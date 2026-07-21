# FPSOptimization

The gaming-FPS tool of the [PrimePCTuner](../README.md) suite. Detects your PC's specs, lists **52 FPS-related changes as checkboxes** (all pre-checked), and lets you uncheck anything before pressing Start. Covers telemetry and background-contention elimination, service debloat, NIC power saving, filesystem tuning, and the aggressive security trade-offs (Spectre mitigations, VBS, Defender scheduling).

> **Status: v0.3 — DRY-RUN.** The tool auto-scans on launch and re-scans on **Start dry run**, reporting current state vs target for every checked item and saving a Markdown + JSON report to `logs\` — **nothing is changed yet**. The apply engine (with undo JSON + restore point) is v2. As of v0.3 the UI lives in the suite's shared framework (`..\shared\PrimeUI.ps1`); this folder holds the catalog and a thin launcher.

## Run it

```powershell
.\Start-FPSOptimization.ps1        # self-elevates via UAC
```

Or launch it from the suite hub, `..\PrimePCTuner.ps1`. The window shows:
- **Specs bar** — CPU, GPU, RAM, OS build, disks, active NIC, elevation state
- **Checklist** — grouped by level and module, every item with its id, description, and target state
- **Buttons** — Select all / Select none / Uncheck Level 3 / Start dry run / Open last report

Row colors after a run: 🟢 OK (already at target) · 🟠 WOULD CHANGE (with current value) · 🔵 REVIEW (needs human judgement) · ⚪ skipped (unchecked).

## The three levels

| Level | Name | What it touches | Risk |
|---|---|---|---|
| **1** | Safe | Telemetry, ads/suggestions, 10 bloat scheduled tasks, Edge background containment, NTFS tuning, NIC power saving, USB/PCIe power, mouse acceleration, MMCSS | None — no functionality a gamer uses is lost |
| **2** | Debloat | Background services (with detection guards — e.g. Spooler auto-skips if a printer exists), preinstalled app removal, Widgets, write caching, hibernation | Low — removes features *some* people use; guarded by detection or prompts |
| **3** | Aggressive | Spectre/Meltdown mitigations OFF, VBS/Memory Integrity OFF, Defender scheduled scans OFF (real-time stays ON), Defender game exclusions, MSI interrupt mode | **Deliberate security trade-offs** — read [CHANGES.md](CHANGES.md) §Level 3 before leaving these checked |

Full catalog with what/why/exact-command/revert for every item: **[CHANGES.md](CHANGES.md)** — including the drift table (what Windows Update silently reverts) and the placebo list (tweaks that measurably do nothing on Windows 11, documented so you don't waste time).

## Scope boundary

FPSOptimization owns changes that affect **frame rate and frame-time consistency while gaming**. Pure startup-entry cleanup (Run keys, startup folders, logon tasks, autostart drift) belongs to the [StartupOptimization](../StartupOptimization/) tool. The one overlap — Edge autolaunch (item 1.8) — stays here because Edge's background presence costs CPU while gaming; StartupOptimization checks the same surface for everyday PCs.

## Files

| File | Role |
|---|---|
| `Start-FPSOptimization.ps1` | Thin launcher: dot-sources `..\shared\PrimeUI.ps1` (theme, specs detection, checklist window, dry-run engine), loads `manifest.json`, then wires titles/levels |
| `manifest.json` | The 52 items' metadata (id/level/module/name/desc/target/default-checked/script path) — read directly, no subprocess needed just to render the checklist |
| `..\changes\*\*.ps1` | The actual 52 check/apply/undo scripts, one per item, organized by sector (`Windows Changes`, `Services`, `Performance & Hardware`) — each is invoked as its own subprocess via `..\shared\PrimeHeadless.ps1`'s `-Check`/`-Apply`/`-Undo -Json` contract |
| `CHANGES.md` | Human-readable catalog: what / why / exact implementation / revert per item |
| `logs\` | Generated dry-run reports (`DryRun_<timestamp>.md` + `.json`), git-ignored |

`-SelfTest` flag builds the window headless and exits — used for sanity checks.

## Honest expectations

The biggest FPS win is eliminating background contention (Levels 1+2 plus closing apps while gaming) — that's the bulk of the reference rig's doubling. VBS off is worth a few percent, mitigations off ~1–3%. After that, a CPU-bound rig sits at its CPU's practical ceiling — the remaining lever is hardware, not registry.
