# Pyodide Beancount POC

This is a minimal, browser-only proof of concept that:
- loads Pyodide in a Web page
- installs `beancount` via `micropip`
- runs a tiny `loader.load_string()` check and prints JSON

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
  `pyodide-poc/wheels/beancount-3.2.0-cp311-cp311-emscripten_3_1_46_wasm32.whl`.
- This POC only checks a single in-memory file; it does not support includes yet.
