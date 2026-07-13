# PCOptimizationServices

A modular PowerShell toolkit that applies a battle-tested Windows 11 gaming-PC optimization baseline — the same set of changes that took a real rig (Ryzen 7 5800X3D + RTX 4070 Ti) from ~100 FPS to ~200 FPS in Call of Duty: Warzone. Portable: it detects hardware and installed software, guards machine-specific steps, and skips what doesn't apply.

> **Status: DESIGN / REVIEW stage.** The full catalog of changes lives in [CHANGES.md](CHANGES.md) and is under review. Scripts are written after the catalog is approved.

## What it does

Windows 11 ships with telemetry, background services, scheduled tasks, power-saving features, and security mitigations that all cost CPU time, I/O, and frame-time consistency. On a gaming PC — especially a CPU-bound one — reclaiming those resources translates directly into higher and more stable FPS. This toolkit applies those reclaims **systematically, reversibly, and with proof**.

Three levels of optimization, plus audit and maintenance modes:

| Level | Name | What it touches | Risk |
|---|---|---|---|
| **1** | Safe | Telemetry, ads/suggestions, bloat scheduled tasks, Edge background containment, filesystem tuning, NIC power saving, USB/PCIe power, mouse acceleration, multimedia scheduler | None — no functionality a gamer uses is lost |
| **2** | Debloat | Background services (with detection guards), preinstalled app removal, Widgets, Delivery Optimization, write caching, hibernation/Fast Startup | Low — removes features *some* people use; every item is guarded by detection or a prompt |
| **3** | Aggressive | Spectre/Meltdown mitigations OFF, VBS/Memory Integrity OFF, Defender scheduled scans OFF, Defender game exclusions, MSI interrupt mode | **Deliberate security/functionality trade-offs.** Requires explicit per-item consent. Read [CHANGES.md](CHANGES.md) §Level 3 before running |

| Mode | What it does |
|---|---|
| **Audit** | Report-only. Compares live system state against the baseline and prints a drift report — *no changes made*. Windows Updates silently revert several tweaks (documented in CHANGES.md §Drift); run this after every major update |
| **Maintenance** | Repeatable cleanups: ghost/non-present device removal (with hard skip-rules), temp cleanup (age-guarded), on-demand Defender quick scan |
| **Revert** | Every change is logged with its previous value to a JSON undo file; revert restores any module or everything |

## Planned architecture

```
PCOptimizationServices/
├── README.md                     ← you are here
├── CHANGES.md                    ← full catalog: every change, why, exact command, revert
├── Start-PCOptimization.ps1      ← orchestrator: interactive menu + CLI flags
├── modules/
│   ├── Optimize-Telemetry.ps1        (L1) telemetry, ads, cross-device, search web content
│   ├── Optimize-ScheduledTasks.ps1   (L1) the 10 bloat tasks
│   ├── Optimize-Edge.ps1             (L1) autolaunch, startup boost, background mode
│   ├── Optimize-Filesystem.ps1       (L1/L2) last-access, NTFS cache, write caching, TRIM check
│   ├── Optimize-Network.ps1          (L1) NIC power-saving cluster off
│   ├── Optimize-Power.ps1            (L1) USB suspend, PCIe ASPM, mouse accel, MMCSS
│   ├── Optimize-Services.ps1         (L2) service debloat with detection guards
│   ├── Optimize-Apps.ps1             (L2) preinstalled app/Widgets removal
│   ├── Optimize-SecurityTradeoffs.ps1(L3) mitigations, VBS, Defender schedule/exclusions
│   ├── Optimize-Interrupts.ps1       (L3) MSI mode for GPU/NIC
│   └── Invoke-Maintenance.ps1        ghost devices, temp, on-demand scan
├── lib/
│   ├── Baseline.ps1                  ← the baseline definition audit mode diffs against
│   └── Undo.ps1                      ← change logging + revert engine
├── logs/                             ← per-run transcript + undo JSON files
└── dist/                             ← ps2exe-compiled .exe (built at release)
```

## Planned usage

```powershell
# Report-only: what would change / what has drifted (safe to run anytime)
.\Start-PCOptimization.ps1 -Audit

# Apply level 1 (safe) only
.\Start-PCOptimization.ps1 -Apply -Level 1

# Apply levels 1+2, prompt through level 3 item by item
.\Start-PCOptimization.ps1 -Apply -Level 3

# Single module
.\Start-PCOptimization.ps1 -Apply -Module Network

# Undo a previous run
.\Start-PCOptimization.ps1 -Revert -RunId <timestamp>
```

No parameters → interactive menu. Requires an elevated (Administrator) PowerShell. A System Restore point is created before any Apply run.

## Safety model

1. **Audit before Apply** — you always get to see the delta first.
2. **Everything is logged** — old value captured before every write; undo JSON per run.
3. **Restore point** created before the first change of a run.
4. **Hard guardrails (never touched, at any level):**
   - Defender real-time protection + tamper protection stay **ON** (Level 3 only disables *scheduled* scans)
   - Bluetooth, audio, `AppXSvc`, `GamingServices` (Game Pass/Store games) services
   - Vendor peripheral software the user actually uses (RGB/mouse/controller apps)
   - EA/anticheat services are set **Manual, never Disabled** (disabling silently breaks game launches)
   - `WAN Miniport*` devices are never removed in ghost-device cleanup (breaks VPN)
   - Windows Update itself, and Edge WebView2 security updates
5. **Game-aware:** modules that reset hardware (NIC) or stop services refuse to run while a known game process is active.

## Honest expectations

- The single biggest FPS win is **eliminating background contention** — services, telemetry, and scheduled tasks stealing CPU time from a CPU-bound game. On the reference rig this (plus closing apps while gaming) roughly doubled Warzone FPS.
- VBS/Memory Integrity off is worth a few percent; Spectre/Meltdown mitigations off ~1–3% CPU-bound — both are Level 3 trade-offs, not free lunches.
- Once the system is clean, **you hit your CPU's ceiling** — further registry tweaks won't move FPS. The catalog includes a "known placebos" section (CHANGES.md §Placebos) documenting tweaks that measurably do nothing on Windows 11, so you don't waste time on them.

## Requirements

- Windows 11 (Home or Pro)
- PowerShell 5.1+ (7+ recommended)
- Administrator elevation
- A willingness to reboot (several changes need one)

## License / disclaimer

Personal tooling, provided as-is. Level 3 deliberately trades security hardening for performance — understand each item before applying it. Not affiliated with Microsoft.
