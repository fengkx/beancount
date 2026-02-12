# Pyodide Beancount POC

This is a minimal, browser-only proof of concept that:
- loads Pyodide in a Web page
- installs `beancount` via `micropip`
- provides a multi-file Monaco editor
- writes editor files to Pyodide's in-memory FS and runs `loader.load_file()`

## Run locally

From the repo root:

```sh
python3 -m http.server --directory pyodide-poc 8080
```

Then open `http://localhost:8080` in your browser.

## Notes
- First load is large and slow because Pyodide and packages are fetched.
- `beancount` is not a pure-Python wheel, so Pyodide install may fail unless you provide a Pyodide-compatible wheel.
- `CUSTOM_WHEELS` in `pyodide-poc/main.js` is preconfigured to load the local
  `pyodide-poc/wheels/beancount-3.2.0-cp313-cp313-emscripten_4_0_9_wasm32.whl`.
- The entry file is selected in the UI. `include` directives resolve relative to
  each file because the POC syncs every editor file into `/work` in the
  Pyodide filesystem and calls `loader.load_file()` on the entry file.
