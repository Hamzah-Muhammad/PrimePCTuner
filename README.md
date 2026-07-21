# PrimePCTuner

A Windows 11 PC-optimization suite: audit first, checkbox consent for every single change, undo logging, and hard guardrails — derived from a real, verified optimization pass on a Ryzen 7 5800X3D + RTX 4070 Ti rig that took Warzone from ~100 to ~200 FPS.

## Start here: the app

A pywebview desktop app (FastAPI backend + React frontend, `python/`) is the suite's front door — it detects and displays your PC's specs, then lets you launch whichever tool fits the machine. Every tool opens as the same branded checklist — auto-scanned against your system, green ✓ APPLIED for what's already done, a checkbox per change.

```powershell
python\dist\PrimePCTuner.exe        # packaged build (needs shared\/changes\/FPSOptimization\/StartupOptimization\ as sibling folders)
# or, for development:
cd python && .venv\Scripts\python.exe app.py
```

Packaging spec: `python/PrimePCTuner.spec` (PyInstaller onefile). Full architecture: `docs/PYTHON_REWRITE_DESIGN.md`.

## The tools

| Tool | Status | Audience | What it does |
|---|---|---|---|
| **[FPSOptimization](FPSOptimization/)** | **dry-run, 52-item catalog** | Gaming rigs | All gaming-related FPS changes: telemetry/background-contention elimination, service debloat, NIC power saving, filesystem tuning, and the aggressive security trade-offs (mitigations, VBS, Defender scheduling). 52 catalog items across 3 risk levels |
| **[StartupOptimization](StartupOptimization/)** | **dry-run, dynamic catalog** | Everyday PCs | The toned-down cleaner: dynamically enumerates every Run-key entry, startup-folder shortcut, logon scheduled task, and Windows extra (Widgets, Copilot, Edge preload) that launches itself at logon on *this* PC. Known keeps (security tray, fan/hardware control) start unchecked |

More tools may join the suite (candidates: NetworkOptimization for latency tuning, MaintenanceService for the repeatable cleanups).

## Shared principles (every tool in the suite)

1. **The user sees and approves every change.** Each tool opens with your PC's detected specs and a checkbox per change — uncheck anything before pressing Start.
2. **Dry-run before apply.** Current state vs target is always visible first; reports saved to the tool's `logs\` folder.
3. **Everything is reversible.** Old values are logged to undo JSON per run; System Restore point before applying.
4. **Hard guardrails** that no level of aggressiveness crosses: Defender real-time protection stays on, anticheat/launcher services are never Disabled (Manual only), no dangerous Defender exclusions (Temp/roots), `WAN Miniport*` devices never touched, WebView2 security updates keep flowing.
5. **Game-aware:** anything that resets hardware or stops services refuses to run while a game process is active.
6. **Drift-aware:** Windows Updates silently revert many tweaks; each tool's audit mode re-checks its own baseline.

## Repo layout

```
PrimePCTuner/
├── README.md                  ← you are here
├── docs/
│   └── PYTHON_REWRITE_DESIGN.md  ← full architecture/design doc for the Python/React app
├── shared/
│   ├── PrimeChecks.ps1        ← I/O primitives shared by every change script (registry, service,
│   │                             scheduled task, fsutil, power scheme, game-detection, tracked undo)
│   ├── PrimeHeadless.ps1      ← mode-dispatch harness (-Check/-Apply/-Undo -Json) every change
│   │                             script calls into
│   ├── Invoke-SystemScan.ps1  ← "Scan PC" broad inventory (specs + installed software + processes)
│   └── cache\                  (generated, git-ignored)
├── changes/                   ← every individual check/change, one script per item, by sector
│   ├── Windows Changes\        (21 scripts)
│   ├── Services\                (19 scripts)
│   ├── Performance & Hardware\  (13 scripts)
│   └── PC Startup\              (Enumerate.ps1 + 3 parameterized action scripts — dynamic sector)
├── FPSOptimization/            52-item catalog
│   ├── README.md
│   ├── CHANGES.md             ← every change: what / why / exact command / revert
│   ├── manifest.json          ← metadata for all 52 items, pointing at ..\changes\ scripts
│   └── logs\                  (generated, git-ignored)
├── StartupOptimization/        static + live-discovered catalog
│   ├── README.md
│   ├── manifest.json          ← the static items (Windows Extras); dynamic items come from
│   │                             ..\changes\PC Startup\Enumerate.ps1 at launch
│   └── logs\                  (generated, git-ignored)
└── python/                    ← the app: FastAPI backend + React frontend + pywebview launcher
    ├── app.py                  ← desktop entry point (elevation, server, window)
    ├── backend/                ← routes, subprocess bridge to changes\*.ps1, models, reports
    ├── frontend/                ← React SPA (Vite), built to frontend\dist\
    └── PrimePCTuner.spec        ← PyInstaller onefile packaging spec
```

Each catalog item is its own standalone PowerShell script under `changes\`, invoked per-item as a subprocess from the Python backend (via `shared\PrimeHeadless.ps1`'s mode contract) rather than run in-process — isolation over convenience, so one broken/tampered item can only poison its own result. A tool = its `manifest.json` + the shared FastAPI/React app wiring.

## Requirements

Windows 11, WebView2 (preinstalled on Win11), PowerShell 5.1+ (7+ recommended), Administrator elevation (the app self-elevates), and a willingness to reboot for some changes. Building from source additionally needs Python 3.13 + Node/npm (build-time only — the packaged exe never runs Node).

## License / disclaimer

Personal tooling, provided as-is. The aggressive tiers deliberately trade security hardening for performance — read each tool's CHANGES.md and understand an item before leaving it checked. Not affiliated with Microsoft.
