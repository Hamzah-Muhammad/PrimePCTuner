# PrimePCTuner — Python Rewrite: Structure & Design (v2 planning doc)

Status: **approved 2026-07-19 — decisions locked, no Python code written yet.**
Scope: replace the PowerShell/WPF UI layer with a FastAPI + pywebview app,
while keeping the proven PowerShell check catalogs as the scan engine.

## 0. Decisions (confirmed 2026-07-19)

1. **Process model:** single pywebview window, client-side SPA routing
   between hub and tool views. One elevated Python process for the whole
   app — no per-tool sibling processes, no `pwsh.exe`-resolution code.
2. **Bridge approach:** subprocess + JSON over stdout to the existing
   PowerShell catalogs is the **permanent** architecture, not a migration
   shim. PowerShell stays the check engine indefinitely.
3. **Old PS entry points:** kept indefinitely as a standalone/no-Python
   fallback (`PrimePCTuner.ps1`, `Start-FPSOptimization.ps1`,
   `Start-StartupOptimization.ps1`) — nothing gets retired.
4. **Report location:** scan reports keep writing to the existing
   `FPSOptimization\logs` / `StartupOptimization\logs` folders — same
   history, whether triggered from PS-standalone or Python.

## 1. Recap of the decision already on record

- FastAPI backend, shelling out to the existing PowerShell catalogs via
  subprocess, reading the JSON they emit.
- pywebview + HTML/CSS frontend, pixel-matching the current dark/green
  Prime theme.
- Packaged with PyInstaller (more mature single-file exe story than ps2exe).
- Written and reviewed **before** any Python code.

## 2. Why keep PowerShell as the engine (not reimplement checks in Python)

The 52 FPS checks + the fully dynamic Startup catalog are proven and already
debugged (registry reads, `Get-CimInstance`, scheduled tasks, `powercfg`,
`fsutil`). Porting all of that to Python would mean `pywin32`/`wmi` calls
that are strictly worse for touching Windows-native surfaces, for no
behavioral gain — pure risk of regressions with zero user-visible benefit.
Python's job in this rewrite is orchestration, UI, and packaging — not
re-deriving `Test-RegValue`/`Test-ServiceStartMode` in a different language.

## 3. Gap to close: today's engine is welded to the WPF UI

`Invoke-PrimeScan` in `shared\PrimeUI.ps1` currently updates live WPF row
objects (`$r.CheckBox.IsChecked`, `$r.PillText`, `$r.Detail`) while it scans
— catalog evaluation and UI painting are one function. That has to be split
before anything can be driven headlessly from Python.

**Proposal — new `shared\PrimeHeadless.ps1`:**
- `Invoke-PrimeCatalogScan -Items $catalog -CheckedIds <string[]|'all'>` —
  pure function, no UI, returns the same result shape already used for the
  JSON reports (`Id, Name, Status, Current, Target`).
- `Invoke-PrimeScan` (WPF path) becomes a thin wrapper: call
  `Invoke-PrimeCatalogScan` per row, then paint pills from the result —
  behavior-identical, so the existing PowerShell app still works standalone.
- A headless bootstrap (no `Add-Type PresentationFramework`, no STA
  relaunch, no self-elevation prompt) — the Python host elevates itself once
  and subprocess children inherit that elevation, so PS re-elevating would
  just be a redundant UAC prompt.

**New per-tool headless entry points** (thin, mirrors existing
`Start-FPSOptimization.ps1`):
```
Start-FPSOptimization.ps1 -Headless -ListCatalog -Json
Start-FPSOptimization.ps1 -Headless -Scan -Json -Checked "1.1,1.2,1.T,..."
```
- `-ListCatalog`: dumps catalog metadata only (`Id/Level/Module/Name/Desc/
  Target/DefaultChecked`) — fast, no checks run. Lets the frontend render
  checkboxes immediately, same as the WPF app building rows before the
  first scan finishes.
- `-Scan`: runs `Invoke-PrimeCatalogScan` for the given ids, prints one JSON
  array to stdout. This is the slow call (today's auto-scan-on-launch).

## 4. Data contracts (already ~90% defined by the existing JSON logs)

```jsonc
// CatalogItem
{ "Id": "1.1", "Level": 1, "Module": "Telemetry & Privacy",
  "Name": "...", "Desc": "...", "Target": "...", "DefaultChecked": true }

// ScanResult (unchanged from today's DryRun_*.json)
{ "Id": "1.1", "Name": "...", "Status": "APPLIED|PENDING|REVIEW|SKIPPED|ERROR",
  "Current": "...", "Target": "..." }
```
Pydantic models in `python/backend/models.py` mirror these 1:1.

## 5. FastAPI backend responsibilities

- `GET /api/tools` — static tool list (mirrors `$Tools` in the hub) + cached
  PC specs (`Get-PCSpecs`, called headlessly once at startup).
- `GET /api/{tool}/catalog` — subprocess → `-ListCatalog -Json`.
- `POST /api/{tool}/scan {checked: [ids]}` — subprocess → `-Scan -Json
  -Checked ...`; backend writes the `.md`/`.json` report (port the report
  section of `Invoke-PrimeScan` into Python — simple string/JSON writing,
  no reason to keep it PS-side).
- `GET /api/{tool}/report/latest` — serve the last report.
- **Deferred, not in this cut:** `POST /api/{tool}/apply` — the apply
  engine is still undesigned in either language; out of scope here.
- Runs as a single local process — `uvicorn` in a background thread inside
  the same elevated process pywebview opens the window from, bound to
  `127.0.0.1` on a random free port. No network exposure.

## 6. pywebview frontend

- **One** pywebview window with client-side routing (hub view ↔ tool view),
  replacing today's "hub launches a separate elevated sibling process per
  tool" model. Simpler process model, no `pwsh.exe`-resolution/portability
  code needed at all (that whole block in `PrimePCTuner.ps1` goes away).
- Plain HTML/CSS/vanilla JS calling `fetch()` against the local FastAPI
  server — no build step, no Node toolchain, keeps the PyInstaller
  single-file story simple.
- CSS is a mechanical port of `PrimeUI.ps1`'s XAML styles — the palette and
  every component (`PrimeCheck`, `BtnSec`, `BtnPri`, `RowCard`, `Chip`, the
  two radial-gradient glows) are already fully specified as hex values and
  layout rules; translating XAML `Style`/`ControlTemplate` → CSS classes is
  well-defined work, not a design decision.

## 7. Proposed folder structure

```
C:\Apps\PrimePCTuner\
  FPSOptimization\lib\Catalog.ps1        (unchanged — the engine)
  StartupOptimization\lib\Catalog.ps1    (unchanged — the engine)
  shared\PrimeUI.ps1                     (unchanged — WPF app keeps working)
  shared\PrimeHeadless.ps1               (NEW — engine split out, §3)
  FPSOptimization\Start-FPSOptimization.ps1        (+ -Headless flag, §3)
  StartupOptimization\Start-StartupOptimization.ps1 (+ -Headless flag, §3)
  python\
    app.py                  — entry: elevation check, start uvicorn thread, open pywebview window
    backend\
      main.py                — FastAPI app + routes
      ps_bridge.py            — subprocess wrapper: run pwsh headless, parse JSON, timeout/error handling
      reports.py               — write .md/.json reports (ported from Invoke-PrimeScan)
      models.py                 — pydantic: CatalogItem, ScanResult, ToolMeta
    frontend\
      index.html
      css\theme.css           — ported palette/components (§6)
      js\app.js                — fetch calls, hub + checklist rendering, client router
    requirements.txt
    build.spec                — PyInstaller spec, bundles the .ps1 engine folders as data
  docs\
    PYTHON_REWRITE_DESIGN.md   (this file)
```

Old PS entry points stay in place and keep working standalone — nothing
is deleted by this rewrite; Python only adds a new front door.

## 8. Packaging

- PyInstaller onefile build of `python/app.py`; `FPSOptimization/`,
  `StartupOptimization/`, `shared/` bundled via `--add-data`, extracted
  next to the exe at first run (same "ship the sibling folders" lesson
  already learned from the ps2exe zip release — subprocess needs real
  `.ps1` files on disk, not PyInstaller's virtual FS).
- Still only depends on `powershell.exe`/`pwsh.exe` being present, which is
  true of every Windows install — no new runtime dependency introduced.

## 9. Explicitly out of scope for this first cut

- Apply engine (undesigned before this doc, stays undesigned here).
- Anything beyond hub view + one tool's checklist view.

## 10. Next step

Design is approved (§0). Next session's work: implement §3 (`PrimeHeadless.ps1`
+ `-Headless` flags on the two tool entry points) first, verify headless
`-ListCatalog`/`-Scan` output matches the existing JSON shape byte-for-byte
against a real scan, *then* start the `python/` scaffold in §7.
