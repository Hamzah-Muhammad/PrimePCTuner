# StartupOptimization

**Status: PLANNED — scope documented, not yet built.** The startup-junk tool of the [PCOptimizationServices](../README.md) suite. Same pattern as FPSOptimization: detect, list every removal as a checkbox, dry-run first, undo logging.

## Planned scope

Everything that launches without being asked, across all the places Windows hides them:

| Surface | What the tool will do |
|---|---|
| **Run keys** (`HKLM`/`HKCU ...\CurrentVersion\Run`, RunOnce) | List every entry with its publisher/target; checkbox removal. Detects vendor drift — apps that re-add themselves after updates (audio drivers, VPN clients, Edge autolaunch) |
| **Startup folders** (user + common) | Enumerate and offer removal of shortcuts |
| **Logon scheduled tasks** | The hidden startup surface most tools miss: Office logon tasks (re-enabled by every Office update), updater tasks, vendor helpers. Distinguishes logon-triggered tasks (startup cost) from periodic ones (keep — e.g. WebView2 security updates) |
| **StartupApproved leftovers** | Purge inert toggle entries whose backing Run entry is gone. Gotcha handled: value names can have trailing spaces — the tool matches exact registry names, not trimmed ones |
| **Services set to Automatic that don't need to be** | Report-only cross-reference with FPSOptimization's service catalog |

## Planned guardrails

- **Keep-list first:** security tray (SecurityHealth), the user's actual peripherals' software (mouse/RGB/fan control), and anything the user marks keep — never suggested for removal twice after a "keep" decision.
- **Anticheat aware:** kernel-level anticheat startup entries (e.g. Riot Vanguard) are flagged with an explanation, not silently removed — disabling them breaks game launches and needs a reboot-aware toggle, not deletion.
- **Updater tasks:** logon-triggered updater tasks can be disabled, but periodic security-update tasks (Edge/WebView2 UA task) are kept by default with a warning if unchecked.
- **Drift re-audit:** vendors re-add their entries on every update — the tool's audit mode diffs against the last approved state and reports only what came back.

## Why a separate tool from FPSOptimization

Startup cleanup is about **boot time, idle RAM, and background processes at logon**; FPSOptimization is about **frame rate while gaming**. They overlap (a lean startup helps FPS), but the decision model differs: startup entries are per-app user choices that change often and need re-auditing after every app update, while the FPS catalog is a mostly-stable system baseline.
