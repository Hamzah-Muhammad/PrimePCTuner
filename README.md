# PrimeFPS

A suite of PowerShell optimization tools for Windows 11 PCs. Each tool is its own app in its own folder, but they all share the same DNA: **audit first, checkbox consent for every single change, undo logging, and hard guardrails** — derived from a real, verified optimization pass on a Ryzen 7 5800X3D + RTX 4070 Ti rig that took Warzone from ~100 to ~200 FPS.

## Start here: the hub

```powershell
.\PrimeFPS.ps1
```

**PrimeFPS** is the suite's main page: it detects and displays your PC's specs, then lets you launch whichever tool fits the machine. Every tool opens as the same branded checklist — auto-scanned against your system, green ✓ APPLIED for what's already done, a checkbox per change.

## The tools

| Tool | Status | Audience | What it does |
|---|---|---|---|
| **[FPSOptimization](FPSOptimization/)** | **v0.3 — dry-run GUI** | Gaming rigs | All gaming-related FPS changes: telemetry/background-contention elimination, service debloat, NIC power saving, filesystem tuning, and the aggressive security trade-offs (mitigations, VBS, Defender scheduling). 52 catalog items across 3 risk levels |
| **[StartupOptimization](StartupOptimization/)** | **v0.1 — dry-run GUI** | Everyday PCs | The toned-down cleaner: dynamically enumerates every Run-key entry, startup-folder shortcut, logon scheduled task, and Windows extra (Widgets, Copilot, Edge preload) that launches itself at logon on *this* PC. Known keeps (security tray, fan/hardware control) start unchecked |

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
PrimeFPS/
├── README.md                  ← you are here
├── PrimeFPS.ps1                ← the hub: specs + pick a tool
├── shared/
│   └── PrimeUI.ps1            ← shared WPF framework: theme, spec detection,
│                                 checklist window builder, dry-run scan engine
├── FPSOptimization/           ← v0.3: dry-run GUI + 52-item change catalog
│   ├── README.md
│   ├── CHANGES.md             ← every change: what / why / exact command / revert
│   ├── Start-FPSOptimization.ps1
│   ├── lib\Catalog.ps1        ← static catalog (the verified gaming baseline)
│   └── logs\                  (generated, git-ignored)
└── StartupOptimization/       ← v0.1: dry-run GUI, dynamic per-PC catalog
    ├── README.md
    ├── Start-StartupOptimization.ps1
    ├── lib\Catalog.ps1        ← enumerates THIS PC's startup surfaces at launch
    └── logs\                  (generated, git-ignored)
```

Both tools are thin shells over `shared\PrimeUI.ps1` — one theme, one checklist window, one scan engine. A tool = its catalog + ~30 lines of wiring.

## Requirements

Windows 11, PowerShell 5.1+ (7+ recommended), Administrator elevation (tools self-elevate), and a willingness to reboot for some changes.

## License / disclaimer

Personal tooling, provided as-is. The aggressive tiers deliberately trade security hardening for performance — read each tool's CHANGES.md and understand an item before leaving it checked. Not affiliated with Microsoft.
