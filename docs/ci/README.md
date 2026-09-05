# Portable CI template

`portable-check.yml` is an inactive GitHub Actions template. It checks Python
syntax, lists the regression manifest and runs the three independent aggregate
runner fixture tests. It does not simulate RTL.

The current publishing authorization lacks GitHub's `workflow` scope. GitHub
rejected a push containing `.github/workflows/portable-check.yml`; consequently
this release publishes the configuration here as documentation, with no active
workflow or claimed Actions success.

An owner with suitable authorization can later place this file at
`.github/workflows/portable-check.yml` to enable it. Until then, run the same
checks locally:

```powershell
python -m compileall -q scripts tests
python scripts/run_all.py --list
python -m unittest tests/test_run_all.py -v
```

The full eleven-runner Vivado regression is separate and has actual local
evidence in `evidence/results.json`.
