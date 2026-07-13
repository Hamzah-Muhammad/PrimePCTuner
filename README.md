# PCOptimizationServices

A suite of PowerShell optimization tools for Windows 11 gaming PCs. Each tool is its own app in its own folder, but they all share the same DNA: **audit first, checkbox consent for every single change, undo logging, and hard guardrails** — derived from a real, verified optimization pass on a Ryzen 7 5800X3D + RTX 4070 Ti rig that took Warzone from ~100 to ~200 FPS.

## The tools

| Tool | Status | What it does |
|---|---|---|
| **[FPSOptimization](FPSOptimization/)** | **v0.1 — dry-run GUI** | All gaming-related FPS changes: telemetry/background-contention elimination, service debloat, NIC power saving, filesystem tuning, and the aggressive security trade-offs (mitigations, VBS, Defender scheduling). 52 catalog items across 3 risk levels |
| **[StartupOptimization](StartupOptimization/)** | planned | Startup junk removal: Run keys, startup folders, logon scheduled tasks, inert StartupApproved leftovers, vendor autostart drift |

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
PCOptimizationServices/
├── README.md                  ← you are here
├── FPSOptimization/           ← v0.1: dry-run GUI + 52-item change catalog
│   ├── README.md
│   ├── CHANGES.md             ← every change: what / why / exact command / revert
│   ├── Start-FPSOptimization.ps1
│   ├── lib\Catalog.ps1
│   └── logs\                  (generated, git-ignored)
└── StartupOptimization/       ← planned: scope documented in its README
    └── README.md
```

## Requirements

Windows 11, PowerShell 5.1+ (7+ recommended), Administrator elevation (tools self-elevate), and a willingness to reboot for some changes.

## License / disclaimer

Personal tooling, provided as-is. The aggressive tiers deliberately trade security hardening for performance — read each tool's CHANGES.md and understand an item before leaving it checked. Not affiliated with Microsoft.
