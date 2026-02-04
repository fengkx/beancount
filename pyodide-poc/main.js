const statusEl = document.getElementById('status');
const outputEl = document.getElementById('output');
const inputEl = document.getElementById('input');
const runBtn = document.getElementById('run');

const PYODIDE_VERSION = 'v0.25.1';
const PYODIDE_BASE = `https://cdn.jsdelivr.net/pyodide/${PYODIDE_VERSION}/full/`;
const CUSTOM_WHEELS = [
  './wheels/beancount-3.2.0-cp311-cp311-emscripten_3_1_46_wasm32.whl',
];

let pyodidePromise = null;

function setStatus(text) {
  statusEl.textContent = text;
}

async function initPyodide() {
  if (pyodidePromise) return pyodidePromise;

  pyodidePromise = (async () => {
    setStatus('Loading Pyodide...');
    const { loadPyodide } = await import(`${PYODIDE_BASE}pyodide.mjs`);
    const pyodide = await loadPyodide({ indexURL: PYODIDE_BASE });

    setStatus('Loading micropip...');
    await pyodide.loadPackage('micropip');

    setStatus('Installing beancount (this may take a while)...');
    const installResult = await pyodide.runPythonAsync(`
import json
import micropip

custom_wheels = ${JSON.stringify(CUSTOM_WHEELS)}
result = {"ok": True}
try:
    if custom_wheels:
        await micropip.install(custom_wheels)
    else:
        await micropip.install("beancount", keep_going=True)
except Exception as e:
    result["ok"] = False
    result["error"] = str(e)
    missing = None
    for attr in ("packages", "failed", "errors"):
        if hasattr(e, attr):
            missing = getattr(e, attr)
            break
    result["missing"] = missing

json.dumps(result)
`);
    const installInfo = JSON.parse(installResult);
    if (!installInfo.ok) {
      outputEl.textContent = JSON.stringify(installInfo, null, 2);
      setStatus('Beancount install failed');
      throw new Error(installInfo.error || 'Install failed');
    }

    setStatus('Ready');
    return pyodide;
  })().catch((err) => {
    setStatus(`Init failed: ${err}`);
    throw err;
  });

  return pyodidePromise;
}

async function runBeancheck() {
  outputEl.textContent = '';
  const content = inputEl.value;

  try {
    const pyodide = await initPyodide();
    pyodide.globals.set('content', content);

    setStatus('Running beancount loader...');
    const result = await pyodide.runPythonAsync(`
from beancount import loader
import json

entries, errors, options = loader.load_string(content)

err_list = [
  {
    'file': e.source.get('filename'),
    'line': e.source.get('lineno'),
    'message': e.message,
  }
  for e in errors
]

json.dumps({
  'errors': err_list,
  'entries': len(entries),
})
`);

    outputEl.textContent = result;
    setStatus('Done');
  } catch (err) {
    outputEl.textContent = String(err);
    setStatus('Failed');
  }
}

runBtn.addEventListener('click', () => {
  void runBeancheck();
});
