#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"

# Optional: force a clean xbuildenv (useful in Docker when host has a different platform).
if [[ "${FORCE_REDOWNLOAD_XBUILDENV:-}" == "1" ]]; then
  rm -rf .pyodide-xbuildenv
fi

# Ensure the xbuild environment exists before Meson config.
python - <<'PY'
from pathlib import Path
from pyodide_build import install_xbuildenv

install_xbuildenv.install(Path(".pyodide-xbuildenv"), download=True)
PY

PY_INSTALL_DIR="$(ls -1 .pyodide-xbuildenv/xbuildenv/pyodide-root/cpython/installs | head -1)"
PY_INSTALL_PATH=".pyodide-xbuildenv/xbuildenv/pyodide-root/cpython/installs/${PY_INSTALL_DIR}"
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

for pc in python-3.11.pc python3.pc python-3.11-embed.pc python3-embed.pc; do
  printf "%s\n" "${PC_CONTENT}" > "${PY_PKGCONFIG_DIR_REL}/${pc}"
done

export PKG_CONFIG_PATH="${PY_PKGCONFIG_DIR_ABS}"

pyodide build . -o dist

# If Meson picked up a build Python tag (cp310) for the wheel, rewrite to cp311.
python - <<'PY'
from __future__ import annotations

import io
import re
import zipfile
from pathlib import Path

dist = Path("dist")
if not dist.exists():
    raise SystemExit(0)

for wheel in dist.glob("beancount-*-emscripten_3_1_46_wasm32.whl"):
    with zipfile.ZipFile(wheel, "r") as zf:
        wheel_name = next((n for n in zf.namelist() if n.endswith("WHEEL")), None)
        if not wheel_name:
            continue
        content = zf.read(wheel_name).decode("utf-8")
        if "Tag: cp310-cp311-emscripten_3_1_46_wasm32" not in content:
            continue
        new_content = content.replace(
            "Tag: cp310-cp311-emscripten_3_1_46_wasm32",
            "Tag: cp311-cp311-emscripten_3_1_46_wasm32",
        )

        tmp_path = wheel.with_suffix(".tmp")
        with zipfile.ZipFile(wheel, "r") as src, zipfile.ZipFile(tmp_path, "w") as dst:
            for name in src.namelist():
                data = src.read(name)
                if name == wheel_name:
                    data = new_content.encode("utf-8")
                dst.writestr(name, data)

        new_name = re.sub(r"cp310-cp311", "cp311-cp311", wheel.name)
        tmp_path.replace(dist / new_name)
        wheel.unlink(missing_ok=True)
PY
