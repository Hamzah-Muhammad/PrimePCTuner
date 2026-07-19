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

## 3.5 Elevation flow (Python side)

Mirrors `Invoke-PrimeBootstrap`'s behavior, adapted for a single-elevation-
at-startup model (no per-tool relaunch, no STA/WPF concerns).

1. On `app.py` start — before the uvicorn thread starts or the pywebview
   window opens — check `ctypes.windll.shell32.IsUserAnAdmin()`.
2. If not elevated, relaunch self via `ShellExecuteW(None, "runas", target,
   params, None, 1)`:
   - Frozen (PyInstaller onefile): `target = sys.executable` (the exe
     itself).
   - Dev mode: `target = sys.executable` (python.exe), `params` includes
     the script path — same frozen-vs-dev dual resolution as PS's
     `$PSScriptRoot` fallback (§3), just the Python version of it.
   - On success: `sys.exit(0)` immediately — the elevated child is now the
     real app.
   - On decline/failure (`ShellExecuteW` returns an error handle, e.g. the
     user clicked "No" on the UAC prompt): **do not exit** — warn and
     continue unelevated, exactly like PS's try/catch-and-continue. The app
     still opens; some scan items will read REVIEW/ERROR instead of a clean
     result, which is already how the PS app behaves today under the same
     condition.
3. A `--self-test` flag (Python's equivalent of `-SelfTest`) skips
   elevation entirely, for CI/verification runs that must not trigger UAC.
4. **No STA/WPF-equivalent relaunch is needed.** That check in
   `Invoke-PrimeBootstrap` exists only because WPF requires an STA thread;
   pywebview has its own threading contract (window creation on the main
   thread), already satisfied by construction — uvicorn runs in a
   background thread, `webview.start()` runs on main.
5. **Key guarantee this whole model leans on:** once `app.py` is running
   elevated, every `subprocess.run([ps_exe, ...])` child inherits that
   elevation token automatically — Windows duplicates the parent's token on
   process creation unless told otherwise. This is exactly why the PS-side
   headless bootstrap can skip self-elevation (§3), and why today's WPF hub
   already launches tool scripts elevated without a second UAC prompt per
   tool. **Subprocess calls must never use `-Verb RunAs` themselves** —
   that would trigger a fresh UAC prompt on every single scan.

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
- `POST /api/{tool}/apply {checked: [ids]}` and `POST /api/{tool}/undo` —
  now designed in §8.5 (was deferred/undesigned as of the previous draft).
- Runs as a single local process — `uvicorn` in a background thread inside
  the same elevated process pywebview opens the window from, bound to
  `127.0.0.1` on a random free port. No network exposure.

## 5.5 Subprocess bridge robustness (`ps_bridge.py` contract)

This is the single highest-risk integration point in the whole rewrite —
every catalog fetch and every scan tunnels through it — so it gets explicit
failure-mode handling, not just a happy-path wrapper.

- **PS host resolution**: resolve once at startup (`shutil.which('pwsh')`,
  fall back to `shutil.which('powershell')`), cache the path. If neither
  exists, fail app startup with a clear fatal state surfaced to the React
  UI as a startup-health banner — the current WPF hub shows a `MessageBox`
  for this same condition; a silently-empty catalog would be worse.
- **Invocation flags**: always `-NoProfile -NonInteractive -ExecutionPolicy
  Bypass -File <script> ...`. `-NonInteractive` is defensive — makes PS
  fail loudly instead of hang if any cmdlet ever tries to prompt.
  `-ExecutionPolicy Bypass` is scoped to this one invocation only, never
  touches the system-wide policy — same "don't change anything beyond
  what's needed" posture as the suite's existing security guardrails.
- **Encoding — a gotcha this codebase has already been bitten by once**:
  the suite needed a UTF-8 BOM fix (see the packaging-bugs history) because
  Windows PowerShell mis-renders its non-ASCII glyphs (`— · → ✓ ◆ ✕`) under
  the console's default codepage. The same failure mode applies to
  subprocess stdout capture — `subprocess.run(..., text=True)` decodes with
  the locale-preferred encoding (often cp1252 on Windows), which will
  mangle those glyphs in `Desc`/`Target`/`Current` strings. Fix on both
  ends: PS headless entry points set `[Console]::OutputEncoding =
  [System.Text.Encoding]::UTF8` before printing JSON; Python passes
  `encoding='utf-8'` explicitly to `subprocess.run(...)`, never relies on
  the default.
- **Timeouts** (two profiles, not one):
  - `-ListCatalog`: 15s ceiling — metadata-only, should return in low
    single-digit seconds even for Startup's live enumeration.
  - `-Scan`: 120s ceiling — 52+ checks, some shelling out per-item to
    `fsutil`/`powercfg`. `subprocess.run(..., timeout=...)` already kills
    the child on expiry; on `TimeoutExpired`, return a structured error —
    never let a hung PS process hang an HTTP request indefinitely (a
    failure mode that couldn't happen in the old synchronous WPF model).
- **Exit-code contract**: headless PS entry points exit `0` whenever they
  produced a JSON payload — including when individual checks errored
  (those surface as per-item `Status: "ERROR"` inside the JSON; that's
  normal). Non-zero exit means the *engine* broke (catalog failed to load,
  unhandled top-level exception) — `ps_bridge.py` treats that as a hard
  `PSBridgeError` and never tries to salvage partial stdout.
- **Never paper over an engine failure**: if `returncode == 0` but
  `json.loads(stdout)` still fails (malformed output), that's also a hard
  `PSBridgeError` surfaced with `stdout`/`stderr`/`returncode` attached —
  not silently defaulted to an empty result. This is a PC-optimization tool
  that will eventually gate real system changes once the apply engine
  exists; a silently-empty "nothing to do" result would be actively
  misleading, worse than a visible error.
- **Concurrency**: one scan in flight per tool at a time — a simple
  per-tool lock in `ps_bridge.py`, not a global lock (the hub can
  plausibly show cached state for both tools independently) and not a
  queueing system (single-user local desktop app — a lock that just
  rejects/waits is enough).
- **Execution model**: plain blocking `subprocess.run()` inside a sync
  FastAPI route handler — FastAPI runs sync `def` routes in a thread pool
  automatically, so no `asyncio.create_subprocess_exec` is needed. This is
  a deliberate simplification: the app has exactly one concurrent user, so
  async subprocess plumbing would be pure ceremony.
- **Frozen-path resolution**: like PS's `$PSScriptRoot` fallback,
  `ps_bridge.py` needs a dual-mode resolver for the target `.ps1` path —
  `Path(__file__).parent` in dev, the PyInstaller-extracted sibling-folder
  location (§8) when frozen.

## 6. pywebview frontend — React

- **One** pywebview window with client-side routing (hub view ↔ tool view),
  replacing today's "hub launches a separate elevated sibling process per
  tool" model. Simpler process model, no `pwsh.exe`-resolution/portability
  code needed at all (that whole block in `PrimePCTuner.ps1` goes away).
- **React 19 + Vite**, built with Claude Code's `frontend-design` skill —
  chosen over vanilla JS specifically so that skill (component-level design
  guidance, not just raw HTML/CSS) is usable for the UI work. Client-side
  routing via a minimal router (react-router or a hand-rolled 2-view
  switch — final call at scaffold time, not a design-doc-level decision).
- **Build step is dev/CI-time only.** `npm run build` emits a static
  `frontend/dist/` (`index.html` + hashed JS/CSS bundles) that pywebview
  loads directly and FastAPI can also serve as static files if needed. The
  shipped exe never runs Node — PyInstaller bundles `dist/`, not the React
  source or `node_modules`. Runtime dependency surface is unchanged from
  the original vanilla-JS plan (§8).
- CSS/theme is still a port of `PrimeUI.ps1`'s XAML styles into React
  components/CSS — the palette and every component (`PrimeCheck`, `BtnSec`,
  `BtnPri`, `RowCard`, `Chip`, the two radial-gradient glows) are already
  fully specified as hex values and layout rules; that translation work is
  unchanged by the React choice, just now done as components instead of
  hand-written DOM/`fetch()` calls.

## 6.5 Tech stack & versions (checked 2026-07-19)

| Layer | Choice | Version | Why |
|---|---|---|---|
| Language | Python | 3.12 or 3.13 | Current safe default for new projects; PyInstaller 6.x supports 3.8–3.15 |
| Web framework | FastAPI | 0.136.x | Pydantic v2 native (5–50x faster validation than v1), current stable |
| ASGI server | uvicorn[standard] | latest | Runs in a background thread inside the same elevated process — not a separate service |
| Validation | pydantic | ≥2.7 | Ships as a FastAPI dependency; models in `python/backend/models.py` (§4) |
| Desktop shell | pywebview | 6.2.x | Windows backend = EdgeChromium (WebView2) — the runtime is preinstalled on Win11 (evergreen), so no extra install for the target PCs per [[pc_setup]] |
| Frontend | React 19.2.x + Vite 8.x | — | Built with Claude Code's `frontend-design` skill for the UI work; `npm run build` emits static `dist/` files that pywebview points at — Node/npm is a **build-time-only** dependency, not a runtime one (§6) |
| Packaging | PyInstaller | 6.21.x | `--onefile`, `--add-data` for the bundled `.ps1` engine folders (§8) |
| PS→Python bridge | `subprocess` (stdlib) | — | No extra package; just `subprocess.run([pwsh_path, '-File', ..., '-Headless', ...], capture_output=True)` and `json.loads()` the stdout |
| Python lint/format | `ruff` | latest | One tool for both (`ruff check` + `ruff format`) instead of flake8+black+isort — fewer moving parts |
| Python types | **skipped for v1** (§8.7a) | — | Pydantic already validates the highest-risk surface (PS↔Python JSON shape) at runtime; mypy would be redundant on that boundary |
| JS/TS lint/format | ESLint (typescript-eslint + react-hooks configs, Vite's default scaffold) + Prettier | latest | Standard for a Vite+React+TS project, not extra ceremony |
| Backend tests | `pytest` + FastAPI `TestClient`, `ps_bridge` mocked | — | Heaviest coverage on `ps_bridge.py` — highest-risk module (§5.5) |
| Frontend tests | Vitest + React Testing Library, smoke-level only | — | A handful of tests (routing, StatusPill variants), not full coverage — matches the app's actual size |
| PS tests | Pester, against a sandboxed `HKCU:\...\_Test\` registry subtree | — | Only way to exercise the apply→undo round-trip (§8.5) without mutating the real CI machine |
| CI | GitHub Actions, `windows-latest` (mandatory — registry/WPF/WebView2/PowerShell are all Windows-only) | — | Full breakdown in §8.7 |

No database, no auth, no external network calls — the whole app talks to
itself on `127.0.0.1` and to `pwsh.exe`/`powershell.exe` as a subprocess.
`requirements.txt` will pin exact versions once `python/` is scaffolded.

## 6.6 React app structure & routing

**Routing — hand-rolled, no react-router.** Only two route "shapes" exist
(Hub, and a single parameterized Tool view for either `fps` or `startup`),
and pywebview's window is chromeless (no address bar, no back/forward
chrome) — there's no browser-history UX to preserve. A dependency-free
state machine in `App.tsx` is simpler and avoids a library that buys
nothing here, the same "don't add abstractions beyond what's needed" logic
that already shaped the bridge design (§5.5):

```ts
type View = { name: 'hub' } | { name: 'tool'; toolKey: 'fps' | 'startup' }
const [view, setView] = useState<View>({ name: 'hub' })
```

Navigation is just `setView(...)` calls: a `ToolCard`'s Launch button →
`{name:'tool', toolKey}`; the topbar/back action in `ToolView` →
`{name:'hub'}`. (If browser-tab dev iteration ever wants URL sync for
convenience, that's a few lines of `history.pushState` — not a reason to
add react-router.)

**Component tree** — maps 1:1 onto the existing XAML resources in
`PrimeUI.ps1` (the `PrimeCheck`/`BtnSec`/`BtnPri`/`RowCard`/`Chip` styles,
the two glow ellipses, the topbar fragment), so the port is mechanical, not
a redesign:

```
src/
  App.tsx                    — owns `view` state, fetches PCSpecs+ToolMeta[] once on mount
  primitives/                — the 5 XAML "Resources" styles, 1:1
    Chip.tsx                  — Border+Text pill (spec chips, stat chips)
    Button.tsx                 — variant='primary'|'secondary' (BtnPri/BtnSec)
    Checkbox.tsx                 — PrimeCheck custom checkbox
    Card.tsx                      — RowCard gradient-bordered container
    StatusPill.tsx                 — APPLIED/PENDING/REVIEW/SKIPPED/ERROR/…SCANNING
  layout/
    BackgroundGlows.tsx        — the two radial-gradient ellipses, rendered once at app root
    Topbar.tsx                  — @Humzeeny branded row, shared by both views
    Footer.tsx                   — @Humzeeny + right-aligned note text (prop: note)
    PageHeading.tsx                — eyebrow/heading/subtitle block, reused by Hub + Tool
    SpecsPanel.tsx                   — WrapPanel of <Chip> from PCSpecs, reused by Hub + Tool
  views/
    HubView.tsx                 — PageHeading + SpecsPanel + ToolCard × 2
      ToolCard.tsx                — Name+Tag+Desc+Meta+Launch Button (onClick → setView)
    ToolView.tsx                — PageHeading + SpecsPanel + StatsPanel + ChecklistPanel + ToolbarBar
      StatsPanel.tsx               — WrapPanel of scan-count Chips (applied/pending/review/skipped/errors)
      ChecklistPanel.tsx            — groups CatalogItem[] by Level+Module (mirrors WPF's Group-Object)
        LevelGroup.tsx                — level/module header + its ChecklistRows
          ChecklistRow.tsx             — Checkbox + id-pill + Name/Desc/Target + StatusPill
      ToolbarBar.tsx                 — Select all/none/Uncheck L3/Open report + status text + Re-scan
  api.ts                      — typed fetch wrappers + the shared TS types below
  theme.css                   — ported palette + primitive styles from PrimeUI.ps1
```

**Shared types in `api.ts`** — hand-mirrored from the Pydantic models (§4),
not code-generated. Only 4 small shapes exist; an OpenAPI-codegen pipeline
would be more tooling than the surface area justifies — the discipline is
just "keep these in sync by hand," low-risk at this size:

```ts
export type PCSpecs = { CPU: string; Cores: string; GPU: string; RAM: string;
  OS: string; Disks: string; NIC: string; Elevated: boolean }
export type ToolMeta = { Key: 'fps' | 'startup'; Name: string; Tag: string;
  Desc: string; Meta: string }
export type CatalogItem = { Id: string; Level: number; Module: string;
  Name: string; Desc: string; Target: string; DefaultChecked: boolean }
export type ScanResult = { Id: string; Name: string;
  Status: 'APPLIED' | 'PENDING' | 'REVIEW' | 'SKIPPED' | 'ERROR';
  Current: string; Target: string }
```

**State management: none beyond `useState`/`useEffect`.** `PCSpecs`/
`ToolMeta[]` are fetched once in `App.tsx` and passed down as props (only 2
levels deep — not worth a Context); each view owns its own loading/error
state locally. No Redux/Zustand, no TanStack Query — a single-user local
app hitting `127.0.0.1` has no caching/pagination/dedup problem those
libraries solve.

**Decided — scan progress UX (confirmed 2026-07-19): ship the v1 regression.**
Today's WPF app scans live — each row flips SCANNING → APPLIED/PENDING/…
as `Invoke-PrimeScan` works through the list, with a running "Checking 12
of 52: 1.13…" status line. §5.5's bridge returns **one JSON array after the
whole scan finishes**, so v1's `ToolbarBar` shows a single "Scanning… (up
to ~2 min)" spinner state and all `ChecklistRow`s paint at once when
`POST /scan` resolves — no per-row live status. Zero changes to the
already-locked bridge contract; fastest to build. Two upgrade paths stay on
the table if this feels too coarse once it's actually running: NDJSON
stdout streaming proxied as SSE (true per-row parity, changes §5.5's output
contract), or a polling `GET /scan/progress` background-task endpoint for
an "N of M" progress bar (middle ground, smaller bridge change). Neither is
in scope now.

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
    frontend\                 — React + Vite source (dev-time only, not shipped)
      src\                      — full component tree in §6.6
        App.tsx                   — owns `view` state (hand-rolled router, §6.6)
        primitives\                — Chip, Button, Checkbox, Card, StatusPill
        layout\                      — BackgroundGlows, Topbar, Footer, PageHeading, SpecsPanel
        views\                          — HubView(+ToolCard), ToolView(+StatsPanel/ChecklistPanel/ToolbarBar)
        api.ts                            — typed fetch wrappers + shared TS types (§6.6, mirrors §4)
        theme.css                          — ported palette from PrimeUI.ps1 (§6)
      package.json
      vite.config.ts
      dist\                    — `npm run build` output; PyInstaller bundles THIS, not src\
    requirements.txt
    build.spec                — PyInstaller spec, bundles frontend\dist\ + the .ps1 engine folders as data
  docs\
    PYTHON_REWRITE_DESIGN.md   (this file)
```

Old PS entry points stay in place and keep working standalone — nothing
is deleted by this rewrite; Python only adds a new front door.

## 8. Packaging

- Build is two stages: (1) `npm run build` in `frontend/` produces
  `frontend/dist/` — a plain static site, no server, no Node needed to run
  it; (2) PyInstaller onefile build of `python/app.py` bundles
  `frontend/dist/`, `FPSOptimization/`, `StartupOptimization/`, `shared/`
  via `--add-data`, extracted next to the exe at first run (same "ship the
  sibling folders" lesson already learned from the ps2exe zip release —
  subprocess needs real `.ps1` files on disk, not PyInstaller's virtual FS).
- End-user runtime dependencies are unchanged from the original vanilla-JS
  plan: `powershell.exe`/`pwsh.exe` (every Windows install has one) +
  WebView2 (preinstalled on Win11). **Node/npm is never required on the
  target PC** — only on the dev machine building the release.

## 8.5 Apply engine design

This is the piece that actually changes the system, so it gets the same
"never paper over a failure" rigor as §5.5, plus real revert capability —
dry-run got the suite this far precisely by promising nothing changes;
apply has to keep that trust by promising every change is undoable.

### Catalog schema change (PS side)

Today `Add-CatalogItem` only carries a read-only `Check` scriptblock. Apply
needs a paired `Apply` scriptblock per item, and — critically — `Check`'s
`Current` field is a **display string** ("AllowTelemetry = 1"), not a typed
value, so it can't be replayed to undo a change. Fix: Apply scriptblocks
are self-contained — they read the old value themselves, write the new
one, and return both:

```powershell
# New sibling helpers alongside the existing Test-RegValue etc.
function Set-RegValueTracked {
    param($Path, $Name, $Value)
    $existed = $false; $prev = $null
    try { $prev = (Get-ItemProperty $Path $Name -EA Stop).$Name; $existed = $true } catch {}
    New-Item -Path $Path -Force -EA SilentlyContinue | Out-Null
    Set-ItemProperty -Path $Path -Name $Name -Value $Value
    [pscustomobject]@{ Success = $true; PreviouslyExisted = $existed; PreviousValue = $prev }
}
```
Same pattern for `Set-ServiceStartModeTracked`, `Disable-ScheduledTaskTracked`,
and — for the Startup Optimizer's file-based items — a
`Remove-StartupEntryTracked` that **copies the shortcut file to a backup
path before deleting it** (a shortcut's binary content can't be
reconstructed from a JSON string the way a registry DWORD can; skipping
this would make those items silently non-revertible, breaking the
"everything is undoable" promise).

### Undo record + log

Every successful Apply call appends one record to a run's undo log:
```jsonc
{ "Id": "1.1", "Kind": "RegistryValue", "Path": "HKLM:\\...", "Name": "AllowTelemetry",
  "PreviouslyExisted": true, "PreviousValue": 3, "BackupFile": null }
```
(`BackupFile` populated only for file-based items, per above.)
**Written incrementally, one record per successful item — not batched at
the end** — so a hard crash or forced kill mid-run still leaves a valid
undo trail for everything that already succeeded; batching to the end
would silently lose that safety net on exactly the failure path it exists
for.

### Restore point (coarse safety net, on top of the undo log)

Before the first item of an apply run, `Checkpoint-Computer -Description
"PrimePCTuner pre-apply <timestamp>"`. **Known gotcha**: Windows throttles
System Restore to one checkpoint per `SystemRestorePointCreationFrequency`
(default 1440 min = 24h) — a second apply run same day won't get a fresh
restore point. Not working around this by touching that registry value
(scope creep, and it's a system-wide setting, not portable-tool territory)
— the granular undo log is the primary safety net; the restore point is a
once-a-day coarse backstop on top of it, not the only line of defense.

### Selection, sequencing, and hard guardrails

- Apply only ever touches ids that are (a) checked in the UI **and** (b)
  scanned `PENDING` on the most recent scan — re-validated server-side,
  never trusted from client state alone, since this mutates the system.
  `REVIEW` items (`Compliant = $null`) are **never** eligible for apply —
  that status exists specifically because the item needs human judgment.
- Sequential, catalog order, one pass — same try/catch-per-item model as
  `Invoke-PrimeCatalogScan` (§3): one item's failure doesn't block the
  other independent items, it's just recorded as `ERROR` and skipped for
  undo purposes (nothing to undo if nothing was written).
- The suite's existing hard guardrails (Defender real-time never touched,
  anticheat services Manual-never-Disabled, no Temp/root Defender
  exclusions, WAN Miniport never touched) are enforced by **catalog
  authorship, not runtime logic** — the catalog is small and human-curated,
  so any future item's `Apply` scriptblock gets manually checked against
  these guardrails before being added, same as today's `Check` scriptblocks
  already are.
- **Game-aware pre-flight, not per-item**: before an apply run starts, a
  `Test-GameRunningTracked` check (known game process names via
  `Get-Process`) — if a game is detected, the **entire apply run is
  refused** with a clear message, not silently skip-just-that-item. FPS
  Optimizer's whole premise is "run this between sessions," so a hard
  pre-flight stop is simpler and safer than per-item judgment calls.

### API + UI (reuses §6.6's already-decided patterns, doesn't reinvent them)

- `POST /api/{tool}/apply {checked: [ids]}` — mirrors `/scan`'s shape.
  Requires an explicit **second confirmation** in the UI before firing
  (modal: "About to apply N changes — a System Restore Point will be
  created first. [Cancel] [Apply N changes]"), the same
  confirm-before-hard-to-reverse-action posture used everywhere else in
  this workflow. If any selected item is Level 3/Aggressive, the modal
  calls that out by count specifically, echoing the existing "AGGRESSIVE"
  labeling already in the catalog/UI.
- Progress UX reuses the **already-decided** §6.6 pattern exactly — single
  blocking spinner, all rows resolve when the request completes. Not
  re-litigating that decision for a second endpoint.
- `POST /api/{tool}/undo` — v1 scope is **undo the most recent apply run
  as a whole**, no partial/single-item undo and no history browser; reads
  the latest `UndoLog_*.json`, reverses each record (write back
  `PreviousValue` or delete the key if `PreviouslyExisted` is false,
  restore the backed-up file, etc.), reports per-item `REVERTED|ERROR`.
- Reports: `ApplyLog_<timestamp>.json`/`.md` in the same `logs/` folder as
  today's dry-run reports (§0 decision #4), same shape as `ScanResult` plus
  `PreviousValue`/`NewValue`. `UndoLog_<timestamp>.json` is a separate,
  machine-oriented file — superset of info needed to programmatically
  revert, not meant for human reading.

### Explicitly out of scope for v1 apply engine

- No scheduled/automatic apply — always user-initiated from the UI.
- No partial undo of a single item from history, no cross-run history
  browser — v1 undo is "revert the most recent run," full stop.
- No override of the Windows restore-point throttle.

## 8.7 Dev/CI tooling

### Python
- **`ruff`** for both lint and format (`ruff check .` / `ruff format .`)
  — one tool instead of flake8+black+isort. Matches the "keep the stack
  thin" posture that's shaped every other tooling call in this doc.
- **mypy — open question, not decided here (see §8.7a below).**

### React/TS
- **ESLint** (typescript-eslint + react-hooks configs — Vite's own
  `--template react-ts` scaffold ships these by default, nothing extra to
  configure) + **Prettier** for formatting. This is the standard, expected
  baseline for a Vite+React+TS project, not additional ceremony the way a
  state library or codegen pipeline would be.
- **`tsc --noEmit`** as the type-check gate — effectively free since
  TypeScript was already chosen for `api.ts` (§6.6); no separate tool to
  add.

### Testing
- **Backend**: `pytest` + FastAPI's `TestClient` (httpx-based). Heaviest
  coverage goes to `ps_bridge.py` (§5.5) with `subprocess.run` mocked —
  it's the highest-risk module in the app, exercising the timeout,
  non-zero-exit, and malformed-JSON error paths specifically.
- **Frontend**: Vitest + React Testing Library, **smoke-level only** — a
  handful of tests (routing switches view on `setView`, `StatusPill`
  renders the right variant per status) rather than full component
  coverage. The app is two views and no state library; exhaustive frontend
  testing would be more ceremony than the surface area justifies.
- **PowerShell — the one genuinely new piece**: introduce **Pester** to
  unit-test the new `Set-*Tracked`/undo helpers from §8.5 against a
  **sandboxed registry subtree** (e.g. `HKCU:\Software\PrimePCTuner\_Test\`,
  created fresh and torn down per test run) instead of real system paths.
  This is the only way to actually exercise the apply→undo round-trip
  (write → capture previous value → undo → assert restored) in CI without
  mutating the CI machine's real settings — and it directly backs the
  "everything is undoable" promise §8.5 makes, rather than just asserting
  it in a design doc. The existing `-SelfTest` convention (headless window
  build + exit) stays for the read-only entry points; Pester is additive,
  specifically for the apply/undo logic that `-SelfTest` was never meant
  to cover.

### CI pipeline
GitHub Actions, `windows-latest` runner — mandatory, not a choice, since
registry access, WebView2, and PowerShell are all Windows-only (no cheaper
`ubuntu-latest` option here). Free for a public repo. Runs on PRs (and
pushes to feature branches, matching the multi-branch git workflow already
in use):
1. **Python**: `ruff check`, `ruff format --check`, `pytest`.
2. **Frontend**: `npm ci` (not `npm install` — reproducible, lockfile-
   pinned), `eslint`, `tsc --noEmit`, `vitest run`, `npm run build` (this
   last step also catches build-breaking errors before merge, for free).
3. **PowerShell**: Pester suite (sandboxed registry) + `-SelfTest`
   invocations of every headless entry point — `-ListCatalog`/`-Scan` can
   run for real in CI since they're read-only; `-Apply`/`-Undo` are only
   exercised via Pester against the sandbox, never via the real entry
   point in CI.
- **Not in v1 CI, deliberately deferred**: a full PyInstaller onefile build
  in CI. Feasible on `windows-latest` but slow, and there's no code to
  build yet — add it once the `python/` scaffold exists and this becomes a
  real question rather than a hypothetical one.

### Local dev loop — no `pre-commit` framework
Your existing git workflow already has Claude run sanity checks *before*
showing a diff and asking to commit — adding a `pre-commit` hooks
framework on top would be a second, overlapping enforcement layer for the
same thing. Instead, the "sanity checks myself" step just becomes these
commands, run manually (by Claude, per that existing rule) before every
commit: `ruff check && ruff format --check && pytest` (Python side),
`npm run lint && npm run typecheck && npm test` (frontend side). No new
automation, just filling in what the existing rule already asks for.

### `.gitattributes`
The repo currently mixes conventions out of necessity — `.ps1` files need
CRLF + a UTF-8 BOM (the packaging-bugs history in this doc explains why).
Python/JS ecosystems conventionally use LF. Rather than let this become
incidental diff noise, add a `.gitattributes` once `python/`/`frontend/`
exist: `*.ps1 text eol=crlf`, `*.py text eol=lf`, `*.ts *.tsx *.css text
eol=lf`.

### 8.7a mypy — decided: skip for v1 (confirmed 2026-07-19)

Pydantic already validates the highest-risk boundary (`ps_bridge.py`'s
parsed JSON vs. the models) at runtime on every request — mypy would catch
the same class of bug a second, redundant way, for the cost of a new
dependency, a new CI step, and annotation overhead, on a stack that's been
kept deliberately thin at every other turn (no react-router, no state
library, no codegen, no async subprocess). Revisit only if `ps_bridge.py`/
`models.py` grow enough that static checking starts pulling its own
weight.

## 8.8 Versioning & release process

### Version scheme — decided: continue the lineage, v2.0.0 (confirmed 2026-07-19)
The PS suite already shipped v1.0.0. The Python rewrite is versioned as
**v2.0.0**, not a reset to v1.0.0 — same product, one coherent release
history on the GitHub Releases page, even though the old PS app (§0
decision #3) keeps working standalone indefinitely. Framing: v2.0.0 is
PrimePCTuner's next major version; the PS app becomes the maintained-but-
not-actively-developed legacy track under that same release history, not a
separately-versioned sibling product.

### One app version, not three per-tool versions
Today's UI shows independent per-tool versions (FPS Optimizer "v0.3",
Startup Optimizer "v0.1") because they're three separate WPF
windows/processes. §6.6 collapses that into one pywebview window/one React
SPA — so there's **one app version** for the whole shipped exe, not three.
Catalog *content* changes (new checks, level changes) keep tracking through
the existing per-tool `CHANGES.md` files (`FPSOptimization/CHANGES.md`
already exists) — that convention doesn't need to change, it's just no
longer tied to an exe-version number of its own.

### Single source of truth for the version string
One value, defined once (`python/backend/__version__.py` or a plain
`python/VERSION` file), consumed three ways — never hand-duplicated:
- `build.spec` reads it for the PyInstaller exe's Windows file-version
  resource (Properties → Details tab — today's ps2exe build likely has
  this blank; low-effort thing to get right this time).
- `GET /api/version` exposes it over the API.
- The React footer **fetches it at runtime** from that endpoint — same
  "fetch, don't bake in" pattern already used for `PCSpecs`/`ToolMeta`
  (§6.6) — rather than injecting it into the JS bundle at build time. This
  is what actually prevents version-string drift between what the exe
  really is and what the UI claims to be, a real bug class otherwise.
- `frontend/package.json`'s own `version` field is cosmetic/irrelevant —
  the frontend isn't published as an npm package, so it's not a second
  source of truth to keep in sync with anything.

### Pre-release checkpoints during the build
This is a multi-session rewrite. Use GitHub pre-release tags
(`v2.0.0-alpha.1`, `-alpha.2`, …, `-beta.1`) for your own in-progress
testing builds as the scaffold comes together, each marked "pre-release"
(not "latest") on GitHub. The **first `v2.0.0` tag** (non-prerelease,
marked latest) only happens once it clears the same verification bar the
v1.0.0 PS release already set: clean zip extraction → `--self-test` →
real launch → hub renders specs + both tool cards → each tool's scan
completes and renders results → apply flow reaches its confirmation modal.
Apply's actual system-mutating path is verified via the §8.7 Pester
sandbox suite, not by manually applying changes to a real machine during
release verification.

### Release assets — same two-asset pattern as today, for the same reason
PyInstaller can embed `frontend/dist/` inside the onefile exe itself
(extracted to `_MEIPASS` at runtime), but the `.ps1` catalog engine still
needs to exist as **real files on disk** next to the exe for `subprocess`
to invoke (§8). So the release keeps shipping: a bare `PrimePCTuner.exe`
(same caveat as today — won't actually run standalone without the sibling
folders) + `PrimePCTuner-v2.0.0-win.zip` containing the exe plus
`FPSOptimization/`, `StartupOptimization/`, `shared/`.

### CHANGELOG.md — new, doesn't exist today
Add one repo-root `CHANGELOG.md` narrating the app-level release train
(`v1.0.0` PS, `v2.0.0` Python, …) with two clearly labeled sections —
"PrimePCTuner (PowerShell/WPF) — legacy, maintained not actively
developed" and "PrimePCTuner (Python) — active development" — since the
repo now genuinely ships two parallel artifacts and there's currently
nowhere that states which one is "current." Per-tool `CHANGES.md` files
keep doing what they already do (catalog-content history); this is a new,
higher-level index above them.

### No new release automation
No semantic-release / conventional-commits / auto-version-bump tooling —
version bumps and tags stay a manual, deliberate act (a human — or Claude,
on explicit request — edits the one version file and creates the git tag),
the same way both PS renames and the v1.0.0 release were already done with
explicit end-to-end verification each time. Consistent with §8.7's "no
pre-commit framework" call: this codebase adds automation for things that
are safe to automate, not for gates that should stay a deliberate human
checkpoint.

### Dependency on the still-open `main` question
None of this can produce a real `v2.0.0` tag until `main` exists — it's
currently **unborn**, and per the standing git rule that's a hard stop
requiring explicit approval, already flagged as pending in §10 and in
memory. Not resolving that here; just noting the release process is
blocked on it, not forgotten.

## 9. Explicitly out of scope for this first cut

- Anything beyond hub view + one tool's checklist view + the apply/undo
  flow specified in §8.5.

## 10. Next step

Design is approved (§0) and now **fully specified end-to-end** — elevation
(§3.5), bridge robustness (§5.5), React structure/routing (§6.6), apply
engine (§8.5), dev/CI tooling (§8.7), and versioning/release (§8.8) are all
locked. Next session's work: implement §3 (`PrimeHeadless.ps1`
+ `-Headless` flags on the two tool entry points) first, verify headless
`-ListCatalog`/`-Scan` output matches the existing JSON shape byte-for-byte
against a real scan, *then* start the `python/` scaffold in §7.
