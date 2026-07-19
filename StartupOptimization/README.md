# StartupOptimization

**Status: v0.1 — dry-run GUI.** The startup-junk tool of the [PrimePCTuner](../README.md) suite, aimed at **everyday PCs, not gaming rigs** — the toned-down cleaner. Same pattern as FPSOptimization: detect, list every removal as a checkbox, auto-scan on launch, dry-run first.

```powershell
.\Start-StartupOptimization.ps1            # self-elevates, opens the GUI
.\Start-StartupOptimization.ps1 -SelfTest  # build the window headless + exit
```

## How it differs from FPSOptimization

The FPS catalog is a **static, verified baseline** (the same 52 checks on every PC). This tool's catalog is **built dynamically at launch** — it enumerates whatever is actually set to start on *this* PC, so the checklist is different on every machine. That's what makes it fit general clients.

## What it scans (3 groups)

| Group | Surface | Behavior |
|---|---|---|
| **STARTUP APPS** | Registry Run/RunOnce entries (HKCU, HKLM, Wow6432Node) + Startup folder shortcuts (user + common) | One checkbox per entry, with its target command shown. Known keeps come annotated and **unchecked** by default |
| **LOGON TASKS** | Logon/boot-triggered scheduled tasks: root-path tasks, Office logon tasks (re-enabled by every Office update), Edge/Google updater tasks | Disabled tasks show green ✓ APPLIED; running/ready logon tasks show PENDING. System tasks under `\Microsoft\Windows\*` are never listed |
| **WINDOWS EXTRAS** | The self-starting Windows bloat: Widgets apps + news-feed policy, Copilot, Microsoft AI Manager (`aimgr`), Edge startup boost / background mode, orphaned StartupApproved leftovers | Same checkbox model; each item explains what it removes |

## Keep-list annotations

Known-good entries are recognized and start **unchecked** with a note explaining why:

- **SecurityHealth** (Defender tray) — keep, it's your security status icon.
- **Hardware control** (FanControl, MSI Afterburner) — keep; they set your fan curves / OC at logon.
- Everything else defaults to **checked** (recommended remove) — the "most if not all of them" model. You can uncheck anything before Start.

## Guardrails

- **Dry run only in v0.1** — the scan shows current state vs. target; nothing is changed. Reports are written to `logs\`.
- **Anticheat aware:** kernel anticheat *services* are out of scope here (that's FPSOptimization's domain, with its Manual-never-Disabled rule); only the tray-app Run entry is listed.
- **StartupApproved gotcha handled:** value names can carry trailing spaces — matching is done on exact registry names, not trimmed ones.
- **Drift-aware by design:** vendors re-add their entries on every update; because the catalog is enumerated fresh each launch, whatever came back simply shows up again as PENDING.

## Why a separate tool from FPSOptimization

Startup cleanup is about **boot time, idle RAM, and background processes at logon**; FPSOptimization is about **frame rate while gaming**. They overlap (a lean startup helps FPS), but the decision model differs: startup entries are per-app user choices that change often and need re-auditing after every app update, while the FPS catalog is a mostly-stable system baseline.
