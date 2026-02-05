#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"

# Optional: force a clean xbuildenv (useful in Docker when host has a different platform).
PYODIDE_VERSION="0.29.3"
PYODIDE_BUILD_VERSION="$(python -c 'import pyodide_build; print(pyodide_build.__version__)')"
XBUILDENV_BASE=".pyodide-xbuildenv-${PYODIDE_BUILD_VERSION}"

if [[ "${FORCE_REDOWNLOAD_XBUILDENV:-}" == "1" ]]; then
  rm -rf "${XBUILDENV_BASE}"
fi

# Clean old build artifacts for this target.
mkdir -p dist
rm -f dist/beancount-*wasm32*.whl

# Ensure the xbuild environment exists before Meson config.
pyodide xbuildenv install "${PYODIDE_VERSION}" --path "${XBUILDENV_BASE}" --force
XBUILDENV_ROOT="${XBUILDENV_BASE}/xbuildenv/xbuildenv"

PY_INSTALL_DIR="$(ls -1 ${XBUILDENV_ROOT}/pyodide-root/cpython/installs | head -1)"
PY_INSTALL_PATH="${XBUILDENV_ROOT}/pyodide-root/cpython/installs/${PY_INSTALL_DIR}"
PY_VERSION="${PY_INSTALL_DIR#python-}"
PY_MAJOR_MINOR="${PY_VERSION%.*}"
PY_INC_SUBDIR="$(ls -1 "${PY_INSTALL_PATH}/include" | head -1)"
PY_PKGCONFIG_DIR_REL="${PY_INSTALL_PATH}/lib/pkgconfig"
PY_PKGCONFIG_DIR_ABS="${ROOT_DIR}/${PY_PKGCONFIG_DIR_REL}"
mkdir -p "${PY_PKGCONFIG_DIR_REL}"

PC_CONTENT=$(cat <<EOF
prefix=${ROOT_DIR}/${PY_INSTALL_PATH}
exec_prefix=\${prefix}
includedir=\${prefix}/include/${PY_INC_SUBDIR}
libdir=\${prefix}/lib

Name: python
Description: Pyodide Python (cross build)
Version: ${PY_INSTALL_DIR#python-}
Cflags: -I\${includedir}
Libs:
EOF
)

for pc in "python-${PY_MAJOR_MINOR}.pc" python3.pc "python-${PY_MAJOR_MINOR}-embed.pc" python3-embed.pc; do
  printf "%s\n" "${PC_CONTENT}" > "${PY_PKGCONFIG_DIR_REL}/${pc}"
done

# Install emsdk under /work (bind-mounted) to avoid bloating the Docker image.
# Match the Emscripten version expected by the installed cross-build environment.
EMSCRIPTEN_VERSION="$(grep -E '^export PYODIDE_EMSCRIPTEN_VERSION' "${XBUILDENV_ROOT}/pyodide-root/Makefile.envs" | head -1 | sed -E 's/.*= *//')"
EMSDK_DIR=".pyodide-emsdk"
EMSDK_REPO="${EMSDK_DIR}/emsdk"
if [[ "${FORCE_REDOWNLOAD_EMSDK:-}" == "1" ]]; then
  rm -rf "${EMSDK_DIR}"
fi
if [[ ! -d "${EMSDK_REPO}/.git" ]]; then
  mkdir -p "${EMSDK_DIR}"
  git clone --depth 1 https://github.com/emscripten-core/emsdk.git "${EMSDK_REPO}"
fi

# Work around a GNU tar + macOS/colima bind mount interaction where extracting
# tarballs containing symlinks into /work fails. emsdk uses `tar --strip 1` to
# unpack downloads, so patch it to use Python's tarfile module instead.
EMSDK_PY="${EMSDK_REPO}/emsdk.py"
export EMSDK_PY
python - <<'PY'
from __future__ import annotations

import os
import sys

path = os.environ.get("EMSDK_PY")
if not path:
    raise SystemExit(0)

with open(path, "r", encoding="utf-8") as fh:
    lines = fh.readlines()

marker = "BEANCOUNT_PATCH_UNTARGZ"
if any(marker in line for line in lines):
    raise SystemExit(0)

try:
    start = next(i for i, line in enumerate(lines) if line.startswith("def untargz("))
except StopIteration:
    print(f"error: emsdk.py untargz() not found: {path}", file=sys.stderr)
    raise SystemExit(1)

try:
    end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("def "))
except StopIteration:
    end = len(lines)

patch = [
    "\n",
    "\n",
    "# --- BEGIN BEANCOUNT_PATCH_UNTARGZ ---\n",
    "# emsdk's default implementation shells out to GNU tar with --strip 1.\n",
    "# On some Docker-for-mac bind mounts, extracting symlinks via tar fails and\n",
    "# leaves broken files behind. A Python-based extractor avoids this.\n",
    "def untargz(source_filename, dest_dir):\n",
    "  print(f\"Unpacking '{source_filename}' to '{dest_dir}'\")\n",
    "  mkdir_p(dest_dir)\n",
    "  source_path = sdk_path(source_filename)\n",
    "  try:\n",
    "    with tarfile.open(source_path, 'r:*') as tf:\n",
    "      for member in tf.getmembers():\n",
    "        name = member.name\n",
    "        while name.startswith('./'):\n",
    "          name = name[2:]\n",
    "        parts = name.split('/', 1)\n",
    "        if len(parts) < 2 or not parts[1]:\n",
    "          continue\n",
    "        rel = os.path.normpath(parts[1])\n",
    "        if rel in ('.', ''):\n",
    "          continue\n",
    "        if os.path.isabs(rel) or rel == '..' or rel.startswith('..' + os.sep):\n",
    "          continue\n",
    "        out_path = os.path.join(dest_dir, rel)\n",
    "        out_dir = os.path.dirname(out_path)\n",
    "        if out_dir:\n",
    "          mkdir_p(out_dir)\n",
    "        if member.isdir():\n",
    "          mkdir_p(out_path)\n",
    "          try:\n",
    "            os.chmod(out_path, member.mode & 0o777)\n",
    "          except Exception:\n",
    "            pass\n",
    "          continue\n",
    "        if os.path.lexists(out_path):\n",
    "          try:\n",
    "            os.remove(out_path)\n",
    "          except IsADirectoryError:\n",
    "            shutil.rmtree(out_path)\n",
    "        if member.issym():\n",
    "          os.symlink(member.linkname, out_path)\n",
    "          continue\n",
    "        if member.islnk():\n",
    "          # Hard link: member.linkname refers to another archive member.\n",
    "          linkname = member.linkname\n",
    "          while linkname.startswith('./'):\n",
    "            linkname = linkname[2:]\n",
    "          link_parts = linkname.split('/', 1)\n",
    "          if len(link_parts) < 2 or not link_parts[1]:\n",
    "            continue\n",
    "          link_rel = os.path.normpath(link_parts[1])\n",
    "          if os.path.isabs(link_rel) or link_rel == '..' or link_rel.startswith('..' + os.sep):\n",
    "            continue\n",
    "          os.link(os.path.join(dest_dir, link_rel), out_path)\n",
    "          continue\n",
    "        extracted = tf.extractfile(member)\n",
    "        if extracted is None:\n",
    "          continue\n",
    "        with extracted:\n",
    "          with open(out_path, 'wb') as out_f:\n",
    "            shutil.copyfileobj(extracted, out_f)\n",
    "        try:\n",
    "          os.chmod(out_path, member.mode & 0o777)\n",
    "        except Exception:\n",
    "          pass\n",
    "  except Exception as e:\n",
    "    errlog(f\"Failed to unpack '{source_filename}' to '{dest_dir}': {e}\")\n",
    "    return False\n",
    "  return True\n",
    "\n",
    "# --- END BEANCOUNT_PATCH_UNTARGZ ---\n",
]

lines[end:end] = patch
with open(path, "w", encoding="utf-8") as fh:
    fh.writelines(lines)
PY

pushd "${EMSDK_REPO}" >/dev/null
./emsdk install "${EMSCRIPTEN_VERSION}"
./emsdk activate "${EMSCRIPTEN_VERSION}"
source ./emsdk_env.sh
popd >/dev/null

export PKG_CONFIG_PATH="${PY_PKGCONFIG_DIR_ABS}"
export PYODIDE_BUILD=1
CP_TAG="cp${PY_MAJOR_MINOR//./}"
export PYODIDE_WHEEL_TAG="${CP_TAG}-${CP_TAG}-emscripten_${EMSCRIPTEN_VERSION//./_}_wasm32"

pyodide build . -o dist

# If Meson picked up a build Python tag for the wheel, rewrite to the xbuildenv tag.
python - <<'PY'
from __future__ import annotations

import base64
import csv
import io
import hashlib
import os
import re
import zipfile
from pathlib import Path

dist = Path("dist")
if not dist.exists():
    raise SystemExit(0)

expected_tag = os.environ.get("PYODIDE_WHEEL_TAG")
if not expected_tag:
    raise SystemExit(0)
impl, abi, plat = expected_tag.split("-", 2)

for wheel in dist.glob("beancount-*wasm32*.whl"):
    with zipfile.ZipFile(wheel, "r") as zf:
        wheel_name = next((n for n in zf.namelist() if n.endswith("WHEEL")), None)
        record_name = next((n for n in zf.namelist() if n.endswith("RECORD")), None)
        if not wheel_name:
            continue
        content = zf.read(wheel_name).decode("utf-8")
        if f"Tag: {expected_tag}" in content:
            continue
        new_content = re.sub(r"^Tag: .*", f"Tag: {expected_tag}", content, flags=re.MULTILINE)
        if new_content == content:
            continue

        # Keep RECORD hashes/sizes in sync after mutating WHEEL.
        new_record_bytes = None
        if record_name:
            record_rows = []
            with io.StringIO(zf.read(record_name).decode("utf-8")) as fh:
                reader = csv.reader(fh)
                for row in reader:
                    record_rows.append(row)

            def _pad(row):
                return row + [""] * (3 - len(row))

            wheel_bytes = new_content.encode("utf-8")
            wheel_hash = base64.urlsafe_b64encode(hashlib.sha256(wheel_bytes).digest()).decode("ascii").rstrip("=")
            wheel_size = str(len(wheel_bytes))

            updated_rows = []
            for row in record_rows:
                row = _pad(row)
                if row[0] == wheel_name:
                    row[1] = f"sha256={wheel_hash}"
                    row[2] = wheel_size
                elif row[0] == record_name:
                    row[1] = ""
                    row[2] = ""
                updated_rows.append(row)

            if not any(row[0] == wheel_name for row in updated_rows):
                updated_rows.append([wheel_name, f"sha256={wheel_hash}", wheel_size])

            buf = io.StringIO()
            writer = csv.writer(buf, lineterminator="\n")
            writer.writerows(updated_rows)
            new_record_bytes = buf.getvalue().encode("utf-8")

        tmp_path = wheel.with_suffix(".tmp")
        with zipfile.ZipFile(wheel, "r") as src, zipfile.ZipFile(tmp_path, "w") as dst:
            for info in src.infolist():
                name = info.filename
                data = src.read(name)
                if name == wheel_name:
                    data = new_content.encode("utf-8")
                elif new_record_bytes is not None and name == record_name:
                    data = new_record_bytes
                # Preserve original compression + file mode bits (external_attr).
                dst.writestr(info, data)

        parts = wheel.name[:-4].split("-")
        if len(parts) >= 5:
            new_name = "-".join(parts[:-3] + [impl, abi, plat]) + ".whl"
        else:
            new_name = wheel.name
        tmp_path.replace(dist / new_name)
        wheel.unlink(missing_ok=True)
PY
