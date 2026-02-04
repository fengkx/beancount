# Beancount Pyodide/WASM Build (Docker)

This document describes a reproducible Docker-based build for a Pyodide/WASM
wheel of Beancount and how to wire it into `pyodide-poc/`.

## Prereqs
- Docker installed locally.
- Flex/Bison available in the Docker image (provided by the `Dockerfile`).

## Build the Docker image
```sh
docker build -t beancount-pyodide .
```

## Build the WASM wheel (inside Docker)
Use the helper script which:
- downloads the correct xbuildenv,
- creates a minimal `python-3.11.pc` for Meson, and
- invokes `pyodide build`,
- normalizes the wheel tag to `cp311-cp311` if needed.

```sh
docker run --rm -e FORCE_REDOWNLOAD_XBUILDENV=1 -v "$PWD":/work -w /work beancount-pyodide \
  ./tools/build_pyodide_wasm.sh
```

Result:
- `dist/beancount-2.3.6-cp311-cp311-emscripten_3_1_46_wasm32.whl`

## Wire the wheel into the POC
```sh
mkdir -p pyodide-poc/wheels
cp dist/beancount-*-emscripten_3_1_46_wasm32.whl pyodide-poc/wheels/
```

`pyodide-poc/main.js` is already configured to load the local wheel from:
```
pyodide-poc/wheels/beancount-2.3.6-cp311-cp311-emscripten_3_1_46_wasm32.whl
```
If the filename changes, update `CUSTOM_WHEELS` accordingly.

## Run the POC
```sh
python3 -m http.server --directory pyodide-poc 8080
```
Open `http://localhost:8080`, click "Init and Run".

## Notes
- Beancount v2 declares many runtime dependencies not available in Pyodide.
  The POC installs the local wheel with `deps=False` to avoid resolving them.
- If you need a different Pyodide version, update:
  - `pyodide-poc/main.js` (`PYODIDE_VERSION`)
  - `pyodide-build` version in `Dockerfile`
  - the include path under `.pyodide-xbuildenv/` to match that version.
