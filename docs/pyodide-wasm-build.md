# Beancount Pyodide/WASM Build (Docker)

This document describes a reproducible Docker-based build for a Pyodide/WASM
wheel of Beancount and how to wire it into `pyodide-poc/`.

Target runtime:
- Pyodide `0.29.3` (Python 3.13, Emscripten 4.0.9).

## Prereqs
- Docker installed locally.
- Flex/Bison available in the Docker image (provided by the `Dockerfile`).

## Build the Docker image
```sh
docker build -t beancount-pyodide .
```

## Build the WASM wheel (inside Docker)
Use the helper script which:
- downloads the Pyodide xbuildenv for the installed `pyodide-build`,
- creates a minimal `python-3.x.pc` for Meson matching the xbuildenv, and
- invokes `pyodide build`,
- normalizes the wheel tag to match the xbuildenv (e.g. `cp313-cp313`) if needed.

```sh
docker run --rm -e FORCE_REDOWNLOAD_XBUILDENV=1 -v "$PWD":/work -w /work beancount-pyodide \
  ./tools/build_pyodide_wasm.sh
```

Result:
- `dist/beancount-3.2.0-cp313-cp313-emscripten_4_0_9_wasm32.whl`

## Wire the wheel into the POC
```sh
mkdir -p pyodide-poc/wheels
cp dist/beancount-*-emscripten_4_0_9_wasm32.whl pyodide-poc/wheels/
```

`pyodide-poc/main.js` is already configured to load the local wheel from:
```
pyodide-poc/wheels/beancount-3.2.0-cp313-cp313-emscripten_4_0_9_wasm32.whl
```
If the filename changes, update `CUSTOM_WHEELS` accordingly.

## Run the POC
```sh
python3 -m http.server --directory pyodide-poc 8080
```
Open `http://localhost:8080`, click "Init and Run".

## Notes
- Pyodide 0.29.3 includes `regex`, `click`, and `python-dateutil` in its lockfile,
  so no extra wheels are needed for those dependencies.
- If you need a different Pyodide version, update:
  - `pyodide-poc/main.js` (`PYODIDE_VERSION`)
  - `pyodide-build` version in `Dockerfile`
  - the wheel tag in `tools/build_pyodide_wasm.sh`
  - the include path under `.pyodide-xbuildenv/` to match that version.
