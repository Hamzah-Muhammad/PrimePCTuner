# CHANGES — FPSOptimization Full Catalog

Every change FPSOptimization will apply, organized by level and module. Each entry lists **What / Why / How (exact implementation) / Revert**. This catalog is derived from a real, verified optimization pass on a Ryzen 7 5800X3D + RTX 4070 Ti Windows 11 Home rig (~100 → ~200 FPS in Warzone), generalized to be portable to any Windows 11 gaming PC.

Legend: 🟢 = no functional loss · 🟡 = removes a feature some users need (guarded by detection or prompt) · 🔴 = deliberate security/functionality trade-off (explicit consent required)

---

## LEVEL 1 — SAFE

### Module: Telemetry & Privacy

| # | Change | Why (perf rationale) |
|---|---|---|
| 1.1 🟢 | Telemetry to minimum: `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` → `AllowTelemetry=1` (Required — the floor on Home/Pro non-Enterprise) | Less background data collection/upload by `DiagTrack` and friends |
| 1.2 🟢 | Start-menu ads/suggestions off: `HKCU\...\ContentDeliveryManager` → `SubscribedContent-338388Enabled=0`, `SubscribedContent-338389Enabled=0` | Kills content-delivery background fetches |
| 1.3 🟢 | Search web content off: `HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings` → `IsDynamicSearchBoxEnabled=0` | Search box stops phoning home for suggestions |
| 1.4 🟢 | Cross-device experiences off: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CDP` → `EnableCdp=0` (recreate key if missing — Windows deletes it) | Stops Connected Devices Platform chatter |
| 1.5 🟢 | Teams taskbar button hidden: `HKCU\...\Explorer\Advanced` → `TaskbarMn=0` | Removes preloaded taskbar surface |
| 1.6 🟢 | Delivery Optimization P2P off: `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` → `DODownloadMode=0` | Your PC stops seeding Windows updates to strangers (upload bandwidth + disk I/O) |
| 1.7 🟢 | Widgets/News feed off by policy: `HKLM\SOFTWARE\Policies\Microsoft\Dsh` → `AllowNewsAndInterests=0` | Disables the news/widgets pipeline (removal of the underlying apps is Level 2, #2A.3) |

**Revert:** each value's prior state is logged; revert restores it (or deletes the value if it didn't exist).

### Module: Bloat Scheduled Tasks (disable 10)

🟢 All are telemetry/compat-census tasks that wake up on triggers and burn CPU/disk:

```
\Microsoft\Windows\Application Experience\MareBackup
\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp
\Microsoft\Windows\Application Experience\PcaPatchDbTask
\Microsoft\Windows\Customer Experience Improvement Program\Consolidator
\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip
\Microsoft\Windows\Feedback\Siuf\DmClient
\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload
\Microsoft\Windows\Windows Error Reporting\QueueReporting
\Microsoft\Windows\Maps\MapsToastTask
\Microsoft\Windows\CloudExperienceHost\CreateObjectTask
```

**How:** `Disable-ScheduledTask`. **Known quirks (from the reference pass):**
- `SdbinstMergeDbTask` is TrustedInstaller-protected (Access Denied even elevated) — **skip it**, trivial impact.
- `\Microsoft\Windows\Shell\CreateObjectTask` is a *different*, legitimate shell task — **never touch it**; only the CloudExperienceHost one.
- Office updates re-enable Office logon tasks; Windows updates re-enable some of these. Audit mode re-checks (§Drift).

**Revert:** `Enable-ScheduledTask` per task.

### Module: Edge Containment

🟢 Edge re-adds itself to startup and keeps background processes alive even if you never open it:

| # | Change | How |
|---|---|---|
| 1.8 | Remove Edge autolaunch | Delete any `MicrosoftEdgeAutoLaunch_*` value in `HKCU\...\CurrentVersion\Run` |
| 1.9 | Block startup boost | `HKLM\SOFTWARE\Policies\Microsoft\Edge` → `StartupBoostEnabled=0` |
| 1.10 | Block background mode | same key → `BackgroundModeEnabled=0` |

**Guardrail:** `MicrosoftEdgeUpdateTaskMachineUA` (the periodic updater) is **left enabled** — Edge WebView2 is a system component embedded in many apps and must keep getting security updates. **Revert:** delete the two policy values.

### Module: Filesystem (safe half)

| # | Change | Why | How |
|---|---|---|---|
| 1.11 🟢 | Disable NTFS last-access timestamp updates | One less metadata write per file read | `fsutil behavior set disablelastaccess 1` |
| 1.12 🟢 | Larger NTFS metadata cache | Fewer metadata disk hits (needs reboot) | `fsutil behavior set memoryusage 2` |
| 1.13 🟢 | Verify TRIM is on (report-only) | SSD health/perf | `fsutil behavior query DisableDeleteNotify` should be 0 |

**Revert:** `disablelastaccess 2` (system-managed default), `memoryusage 1`.

### Module: Network Adapter Power Saving

🟢 NIC power-saving features cause micro-stutter and latency spikes (verified fix on Realtek GbE; applies broadly):

| # | Change | How |
|---|---|---|
| 1.14 | Disable the power-saving property cluster on the active physical adapter: *Energy-Efficient Ethernet, Green Ethernet, Power Saving Mode, Gigabit Lite, Wake on pattern match* | `Set-NetAdapterAdvancedProperty` — only for properties that exist on the detected adapter (vendor-dependent; skip silently if absent) |
| 1.15 | "Allow the computer to turn off this device to save power" → OFF | **The method that actually works:** `Get-CimInstance -Namespace root/wmi MSPower_DeviceEnable`, match the adapter's `InstanceName`, → `Set-CimInstance -Property @{Enable=$false}`. Belt-and-suspenders: `PnPCapabilities=24` in the adapter's registry key. ⚠️ **Verify via `Get-NetAdapterPowerManagement`** — the CIM object's own re-read lies and still reports True |

**Portability/safety notes (hard-won):**
- Applying resets the adapter for ~2s — the module **refuses to run while a known game process is active** (checks a game-process list first).
- Registry `PnPCapabilities` alone does NOT flip the checkbox even after reboot; `Set-NetAdapterPowerManagement -AllowComputerToTurnOffDevice` is not a real parameter. The CIM method is the only reliable one.
- Verify connectivity afterward via **gateway ping or TCP 443** — not ping to 1.1.1.1 (it often drops ICMP).

**Revert:** re-enable the same properties / `Enable=$true`.

### Module: Power & Input

| # | Change | Why | How |
|---|---|---|---|
| 1.16 🟢 | USB selective suspend OFF | Prevents input-device latency/wake hitches | `powercfg /setacvalueindex` on active scheme, USB subgroup |
| 1.17 🟢 | PCIe Link State Power Management OFF | GPU link never down-clocks into a latency penalty | `powercfg /setacvalueindex` PCIe ASPM = Off |
| 1.18 🟢 | Mouse acceleration OFF | Raw 1:1 aim (every FPS player wants this) | `HKCU\Control Panel\Mouse` → `MouseSpeed=0`, `MouseThreshold1=0`, `MouseThreshold2=0` |
| 1.19 🟢 | MMCSS gaming profile | Network throttling off + more CPU share for games | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile` → `NetworkThrottlingIndex=0xFFFFFFFF`, `SystemResponsiveness=0` (10 also accepted) |

**Revert:** logged prior values restored.

### Module: Graphics

| # | Change | Why | How |
|---|---|---|---|
| 1.20 🟢 | Hardware-accelerated GPU Scheduling ON | Offloads scheduling to the GPU instead of Windows — recommended for modern GPUs/drivers, small latency win | `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` → `HwSchMode=2`. **Takes effect after reboot.** |

**Revert:** logged prior value restored (still needs a reboot to take effect).

---

## LEVEL 2 — DEBLOAT

### Module: Services (disable / set Manual — with detection guards)

🟡 Each service is checked before touching; the table shows the guard that protects users who need it:

| Service | Action | What it is | Guard |
|---|---|---|---|
| `DiagTrack` | Disable | Telemetry collector | none needed |
| `SysMain` | Disable | Superfetch/prefetch | SSD-only systems don't benefit; skip if OS drive is HDD |
| `WerSvc` | Disable | Error reporting upload | none |
| `Fax` | Disable | Fax | none (it's 2026) |
| `RetailDemo` | Disable | Store-demo mode | none |
| `RemoteRegistry` | Disable | Remote registry editing | none (security win too) |
| `MapsBroker` | Disable | Offline maps sync | none |
| `WMPNetworkSvc` | Disable | Media Player network sharing | none |
| `PhoneSvc` | Disable | Phone Link backend | **prompt** if Phone Link app has been used |
| `lfsvc` | Disable | Geolocation | **prompt** (some apps want location) |
| `Spooler` | Disable | Print spooler | **skip if any real printer is installed** (`Get-Printer` beyond the built-in PDF/XPS) |
| `CDPSvc` | Disable | Connected devices platform | none (pairs with 1.4) |
| `DusmSvc` | Disable | Data usage metering | none |
| `SharedAccess` | Disable | Internet Connection Sharing | **prompt** — needed for Mobile Hotspot & some VPN sharing; offer Manual instead |
| `WSAIFabricSvc` | Disable | Windows AI Fabric | none (no AI features wanted on a gaming rig) |
| `LanmanServer` | Disable | SMB share **hosting** | **prompt** — breaks hosting file shares to other devices (client access to NAS still works) |
| `PcaSvc` | Manual | Program Compatibility Assistant | none — Manual, not Disabled (Windows flips it back; see §Drift) |
| `DoSvc` | Manual | Delivery Optimization | ⚠️ `Set-Service` is **Access Denied** on this one — must set registry `HKLM\SYSTEM\CurrentControlSet\Services\DoSvc` → `Start=3` directly |

**Hard KEEP list (never touched, any level):** Defender services (×3), `AppXSvc`, `GamingServices` (Store/Game Pass games break), Bluetooth services (controllers!), audio services, `WSearch` (prompt-only — most users want search), Windows Update services, vendor peripheral services detected in use (Logitech/Razer/Corsair/SteelSeries RGB & device services).

**⚠️ Anticheat/launcher rule (learned the hard way):** EA `EABackgroundService`/`EAAntiCheatService`, BattlEye `BEService`, EasyAntiCheat, Riot `vgc` → **Manual, never Disabled.** Disabling `EABackgroundService` silently broke EA-published Steam games (launch handoff fails with no useful error). Manual keeps them dormant until their game actually runs. The module detects these and normalizes them to Manual only.

**Revert:** prior `StartType` logged and restored per service.

**⚠️ NVIDIA container services (2R.1, report-only):** `NvContainerLocalSystem` / `NVDisplay.ContainerLocalSystem` look like telemetry/bloat services at a glance (similar naming shape to `DiagTrack`), but they host real NVIDIA Control Panel / driver-settings-persistence functionality — unlike `DiagTrack`, there's no version of disabling these that's safe. This item only **reports** current status/start-type for a human to judge; it's never apply-eligible by design (same pattern as 2A.4 below).

### Module: App / Appx Removal

| # | Change | How |
|---|---|---|
| 2A.1 🟡 | Remove Microsoft `aimgr` (AI Manager) Appx | `Remove-AppxPackage` — Windows Update reinstalls it; audit mode re-flags (§Drift) |
| 2A.2 🟡 | Remove Copilot if present | `Remove-AppxPackage` on the Copilot package |
| 2A.3 🟡 | Fully remove Widgets: uninstall `MicrosoftWindows.Client.WebExperience` + `WidgetsPlatformRuntime` | Pairs with policy 1.7. Note: after removal the Settings "Widgets" toggle disappears entirely — expected, not a bug |
| 2A.4 🟡 | OEM vendor bloat sweep | Detect + **list** known OEM utility leftovers (HP/Lenovo/Dell/ASUS companions, trial AV) and prompt per item — never auto-remove, machines vary |

**Revert:** Appx re-install from Store where possible; OEM apps from vendor.

### Module: Filesystem (level-2 half)

| # | Change | Why | How |
|---|---|---|---|
| 2B.1 🟡 | **Ensure disk write caching is ON for every fixed disk** | Real find on the reference rig: caching was silently OFF on *both* drives — a large, invisible I/O penalty. Unknown cause; worth checking on every PC | Per-disk registry `...\Enum\<disk>\Device Parameters\Disk` → `UserWriteCacheSetting=1`; effective after reboot; **verify post-reboot** |
| 2B.2 🟡 | Hibernation + Fast Startup OFF | Frees `hiberfil.sys` (GBs) and avoids dirty-shutdown driver states | `powercfg /h off` — **prompt**: laptops lose hibernate |
| 2B.3 🟡 | Storage Sense OFF | No surprise background cleanups mid-game; user cleans manually | `HKCU\...\StorageSense\Parameters\StoragePolicy` → `01=0` — prompt (some prefer auto-cleanup) |
| 2B.4 🟡 | Cap System Restore shadow storage at 10 GB | Bounds background VSS disk usage while keeping restore points | `vssadmin resize shadowstorage /for=C: /on=C: /maxsize=10GB` |

**Trade-off note (2B.1):** write caching risks losing the last seconds of writes on power loss — standard Windows default is ON; this just restores the default. Desktop + UPS users: non-issue.

---

## LEVEL 3 — AGGRESSIVE (explicit per-item consent; security trade-offs)

### 3.1 🔴 Spectre/Meltdown mitigations OFF

- **Why:** ~1–3% CPU-bound gain. **Cost:** disables speculative-execution attack hardening — acceptable only on a personal gaming rig, by explicit choice.
- **How:** `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` → `FeatureSettingsOverride=3`, `FeatureSettingsOverrideMask=3`, reboot.
- **Verify:** `Get-SpeculationControlSettings` (SpeculationControl module) → BTI disabled by policy, KVA shadow off.
- **Revert:** delete both values + reboot. **Re-check after major Windows updates** — they can re-enable mitigations (§Drift).

### 3.2 🔴 VBS / Memory Integrity / Hyper-V OFF

- **Why:** VBS costs several % FPS (part of the reference rig's 100→200 jump). **Cost:** loses Memory Integrity (HVCI), Credential Guard, **WSL2, Hyper-V, Windows Sandbox**.
- **How:** `bcdedit /set hypervisorlaunchtype off`; `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard` → `EnableVirtualizationBasedSecurity=0`; `...\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity` → `Enabled=0`; reboot.
- **Guard:** module detects WSL2/Hyper-V/Docker Desktop usage and warns hard before proceeding.
- **Known cosmetic effect:** `Microsoft Hypervisor Service` shows **"Degraded"** in device/service views afterward — benign, it just means "not running on purpose." Audit mode knows this and does not flag it.
- **Revert:** `bcdedit /set hypervisorlaunchtype auto` + set both values to 1, reboot.

### 3.3 🔴 Defender: scheduled scans OFF (real-time protection STAYS ON)

- **Why:** random background full scans tank frame times mid-game. Real-time protection still guards every file on access — the always-on layer is kept.
- **How:** `Set-MpPreference -ScanScheduleDay 8` (8 = Never) + `-DisableCatchupQuickScan $true -DisableCatchupFullScan $true`.
- **Compensation:** Maintenance mode offers on-demand quick scans (`Start-MpScan -ScanType QuickScan`, ~1 min).
- **Hard guardrail:** real-time protection and tamper protection are **never** disabled by this toolkit.
- **Drift:** Windows Update resets Defender preferences back to a daily schedule — audit mode re-checks (§Drift).
- **Revert:** `Set-MpPreference -ScanScheduleDay 0` (0 = Everyday) or any specific day.

### 3.4 🔴 Defender exclusions for game folders + executables

- **Why:** eliminates on-access scan stutter on huge game asset files streaming mid-match.
- **How:** parse `Steam\steamapps\libraryfolders.vdf` to find all Steam libraries; **prompt per detected game folder**; `Add-MpPreference -ExclusionPath <folder> -ExclusionProcess <game exe>`. Also supports manual paths (Riot, Battle.net, Epic).
- **Hard rules:** ⚠️ **NEVER exclude `%TEMP%`, user-profile roots, download folders, or drive roots** — classic malware drop locations with zero FPS value (a Temp exclusion was found and removed on the reference rig — this module refuses such paths outright).
- **Revert:** `Remove-MpPreference` per exclusion (all logged).

### 3.5 🔴 MSI (Message-Signaled Interrupts) mode for GPU + NIC

- **Why:** lower interrupt latency vs legacy line-based interrupts; verified stable on the reference rig.
- **How:** per-device registry `...\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties` → `MSISupported=1` for the display adapter and NIC; reboot.
- **Guard:** most modern GPUs/NICs already run MSI — audit first, only offer the change if actually off. Skip unknown/legacy devices.
- **Revert:** `MSISupported=0` (logged).

---

## MAINTENANCE MODE (repeatable, any time)

### M.1 Ghost / non-present device cleanup

Removes accumulated phantom device entries (the reference rig had 170; 152 were safely removable).

- **How:** enumerate non-present devices via `pnputil`, remove with `pnputil /remove-device`, finish with `pnputil /scan-devices`. **Backup the device list to a file first.**
- **HARD SKIP RULES (breakage otherwise):**
  - Skip classes `System`, `SoftwareDevice`, `Volume`, `VolumeSnapshot`
  - ⚠️ **NEVER remove `WAN Miniport*`** — built-in VPN/PPP drivers that *look* non-present but are live; deleting them breaks VPN
- **Revert:** none needed — Windows re-detects real hardware on `/scan-devices`; the backup list documents what was removed.

### M.2 Temp cleanup (age-guarded)

- **How:** clear `%TEMP%`/`C:\Windows\Temp` items **older than 7 days only**. Reason: installers stage live data in Temp (a game installer's staging was found mid-install on the reference rig — deleting fresh Temp items can corrupt in-progress installs).

### M.3 On-demand Defender quick scan

- `Start-MpScan -ScanType QuickScan` — the manual compensation for 3.3.

---

## DRIFT — what Windows silently reverts (Audit mode re-checks all of these)

Observed regressions on the reference rig; audit mode diffs live state against the baseline and reports:

| Item | Reverted by |
|---|---|
| `PcaSvc` flips back to Automatic | Windows Update (observed 3×) |
| `aimgr` Appx reinstalls | Windows Update |
| `HKLM\...\CurrentVersion\CDP` key deleted entirely (takes `EnableCdp` with it) | Windows Update |
| Edge re-adds `MicrosoftEdgeAutoLaunch_*` to Run | Edge updates (why 1.9/1.10 policies exist) |
| Defender scan schedule resets to daily | Windows Update |
| Disk write caching flips off | Unknown (driver/Windows updates suspected) — re-verify post-update |
| Office logon tasks re-enable | Office updates |
| Spectre mitigations may re-enable | Major Windows updates |
| Realtek audio service/Run entry returns | Audio driver updates |

---

## PLACEBOS & DO-NOTS — documented so nobody wastes time

Tested on the reference rig; these do **nothing** or actively backfire:

| "Tweak" | Verdict |
|---|---|
| Global timer-resolution tools (TimerResolution.exe etc.) | **Placebo on Windows 11** — timer resolution is per-process now; games request 1ms themselves. Unless `GlobalTimerResolutionRequests` policy is set (it isn't by default), the tool does nothing |
| IFEO `CpuPriorityClass=3` (force game High priority) | **Doesn't work on anticheat-protected games** — verified live: the game runs at Normal anyway (anticheat sets its own priority), and external `PriorityClass` writes get Access Denied |
| DLSS Frame Generation for competitive FPS | Adds real input latency — fine for single-player cinematics, wrong tool for competitive shooters. DLSS Super Resolution is fine |
| Disabling memory compression on 16 GB systems | Only sensible at 32 GB+ with pagefile pressure ≈ 0; on smaller RAM it hurts |
| `SvcHostSplitThresholdInKB` consolidation | Marginal, edge-case risk — deliberately not included |
| `DisablePagingExecutive`, `Win32PrioritySeparation` edits | No measurable FPS effect on a clean system — not included |
| `TcpAckFrequency` | Competitive games use UDP — irrelevant |
| Deleting shader caches (`DXCache` etc.) "to clean up" | Causes stutter while they rebuild — never delete as routine cleanup |
| NIC Interrupt Moderation OFF | Real trade (sub-ms latency for CPU cost) — documented but **not applied** by default; only for latency purists on GPU-bound rigs |

---

## Biggest wins, honestly ranked (from the reference pass)

1. **Background contention elimination** (Levels 1+2 + closing apps while gaming) — the bulk of the 100→200 FPS doubling on a CPU-bound rig
2. **VBS off** (3.2) — several %
3. **NIC power saving off** (1.14/1.15) — stutter/latency consistency, not raw FPS
4. **Write caching restored** (2B.1) — system-wide I/O, load times
5. **Mitigations off** (3.1) — 1–3%
6. Everything else — consistency and cleanliness, not headline FPS

After all of this, a CPU-bound rig sits at its CPU's practical ceiling — the remaining lever is hardware, not registry.
