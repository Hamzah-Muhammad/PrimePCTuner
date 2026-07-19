# Catalog.ps1 — the optimization catalog as data.
# Each item: Id, Level, Module, Name, Desc, Target, Check (read-only scriptblock).
# Check returns [pscustomobject] @{ Current = <string>; Compliant = $true|$false|$null; Note = <optional> }
#   Compliant $true  = already at target        → OK
#   Compliant $false = differs from target      → WOULD CHANGE
#   Compliant $null  = needs human judgement    → REVIEW
# Nothing in this file writes to the system.

Set-StrictMode -Version 2

# ---------- shared check helpers ----------

function Test-RegValue {
    param($Path, $Name, $Expected, [switch]$MissingIsCompliant, [string]$MissingText = '(not set)')
    try {
        $val = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        [pscustomobject]@{ Current = "$Name = $val"; Compliant = ($val -eq $Expected) }
    } catch {
        [pscustomobject]@{ Current = "$Name $MissingText"; Compliant = [bool]$MissingIsCompliant }
    }
}

function Test-ServiceStartMode {
    param($Svc, $Expected)   # Expected: 'Disabled' | 'Manual'
    $s = Get-CimInstance Win32_Service -Filter "Name='$Svc'" -ErrorAction SilentlyContinue
    if (-not $s) { return [pscustomobject]@{ Current = 'service not present on this PC'; Compliant = $true } }
    [pscustomobject]@{
        Current   = "StartMode = $($s.StartMode), State = $($s.State)"
        Compliant = ($s.StartMode -eq $Expected)
    }
}

function Get-FsutilNumber {
    param($Query)   # e.g. 'disablelastaccess'
    $out = fsutil behavior query $Query 2>$null
    if ($out -join ' ' -match '=\s*(\d+)') { [int]$Matches[1] } else { $null }
}

function Get-PowerAcValue {
    param($SubGuid, $SettingGuid)
    $out = powercfg /query SCHEME_CURRENT $SubGuid $SettingGuid 2>$null
    $line = @($out) -match 'Current AC Power Setting Index'
    if ($line -and $line[0] -match '0x([0-9a-fA-F]+)') { [Convert]::ToInt32($Matches[1], 16) } else { $null }
}

# NOTE: Get-ActiveNic + Get-PCSpecs live in shared\PrimeUI.ps1 — dot-source it BEFORE this file.

# ---------- catalog ----------

$Script:OptimizationCatalog = [System.Collections.Generic.List[object]]::new()
function Add-CatalogItem {
    param($Id, $Level, $Module, $Name, $Desc, $Target, [scriptblock]$Check)
    $Script:OptimizationCatalog.Add([pscustomobject]@{
        Id = $Id; Level = $Level; Module = $Module; Name = $Name
        Desc = $Desc; Target = $Target; Check = $Check; DefaultChecked = $true
    })
}

# ===== LEVEL 1 — Telemetry & Privacy =====

Add-CatalogItem '1.1' 1 'Telemetry & Privacy' 'Telemetry to minimum (Required)' `
    'Reduces background data collection/upload by DiagTrack and friends.' `
    'AllowTelemetry = 1' `
    { Test-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 `
        -MissingText '(not set — Windows default: Full)' }

Add-CatalogItem '1.2' 1 'Telemetry & Privacy' 'Start-menu ads & suggestions off' `
    'Kills content-delivery background fetches for Start-menu suggestions.' `
    'SubscribedContent-338388/338389Enabled = 0' `
    {
        $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        $a = Test-RegValue $p 'SubscribedContent-338388Enabled' 0
        $b = Test-RegValue $p 'SubscribedContent-338389Enabled' 0
        [pscustomobject]@{ Current = "$($a.Current); $($b.Current)"; Compliant = ($a.Compliant -and $b.Compliant) }
    }

Add-CatalogItem '1.3' 1 'Telemetry & Privacy' 'Search-box web content off' `
    'Search box stops phoning home for web suggestions.' `
    'IsDynamicSearchBoxEnabled = 0' `
    { Test-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0 }

Add-CatalogItem '1.4' 1 'Telemetry & Privacy' 'Cross-device experiences off' `
    'Stops Connected Devices Platform chatter. Windows Update deletes this key — audit re-checks.' `
    'EnableCdp = 0' `
    { Test-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDP' 'EnableCdp' 0 `
        -MissingText '(key missing — Windows Update likely removed it)' }

Add-CatalogItem '1.5' 1 'Telemetry & Privacy' 'Teams taskbar button hidden' `
    'Removes the preloaded Chat/Teams taskbar surface.' `
    'TaskbarMn = 0' `
    { Test-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0 }

Add-CatalogItem '1.6' 1 'Telemetry & Privacy' 'Delivery Optimization P2P off' `
    'Your PC stops seeding Windows updates to strangers (upload bandwidth + disk I/O).' `
    'DODownloadMode = 0' `
    { Test-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 }

Add-CatalogItem '1.7' 1 'Telemetry & Privacy' 'Widgets / news feed off (policy)' `
    'Disables the news/widgets pipeline. App removal itself is item 2A.3.' `
    'AllowNewsAndInterests = 0' `
    { Test-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 }

# ===== LEVEL 1 — Bloat Scheduled Tasks =====

Add-CatalogItem '1.T' 1 'Bloat Scheduled Tasks' 'Disable 10 telemetry/compat-census tasks' `
    'CEIP, Compatibility Appraiser, Siuf feedback, WER upload, Maps toast, CloudExperienceHost. Skips TrustedInstaller-protected SdbinstMergeDbTask; never touches \Shell\CreateObjectTask.' `
    'all 10 tasks Disabled' `
    {
        $targets = @(
            @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'MareBackup' }
            @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'Microsoft Compatibility Appraiser Exp' }
            @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'PcaPatchDbTask' }
            @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator' }
            @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'UsbCeip' }
            @{ P = '\Microsoft\Windows\Feedback\Siuf\';                           N = 'DmClient' }
            @{ P = '\Microsoft\Windows\Feedback\Siuf\';                           N = 'DmClientOnScenarioDownload' }
            @{ P = '\Microsoft\Windows\Windows Error Reporting\';                 N = 'QueueReporting' }
            @{ P = '\Microsoft\Windows\Maps\';                                    N = 'MapsToastTask' }
            @{ P = '\Microsoft\Windows\CloudExperienceHost\';                     N = 'CreateObjectTask' }
        )
        $enabled = [System.Collections.Generic.List[string]]::new()
        $missing = 0
        foreach ($t in $targets) {
            $task = Get-ScheduledTask -TaskPath $t.P -TaskName $t.N -ErrorAction SilentlyContinue
            if (-not $task) { $missing++; continue }
            if ($task.State -ne 'Disabled') { $enabled.Add($t.N) }
        }
        if ($enabled.Count -eq 0) {
            [pscustomobject]@{ Current = "all present tasks disabled ($missing not present)"; Compliant = $true }
        } else {
            [pscustomobject]@{ Current = "still enabled: $($enabled -join ', ')"; Compliant = $false }
        }
    }

# ===== LEVEL 1 — Edge Containment =====

Add-CatalogItem '1.8' 1 'Edge Containment' 'Remove Edge autolaunch from startup' `
    'Edge re-adds a MicrosoftEdgeAutoLaunch_* Run entry after updates.' `
    'no MicrosoftEdgeAutoLaunch_* value in HKCU Run' `
    {
        $run = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
        $hits = @($run.GetValueNames() | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch*' })
        if ($hits.Count) { [pscustomobject]@{ Current = "present: $($hits -join ', ')"; Compliant = $false } }
        else             { [pscustomobject]@{ Current = 'no autolaunch entry';          Compliant = $true } }
    }

Add-CatalogItem '1.9' 1 'Edge Containment' 'Block Edge startup boost (policy)' `
    'Stops Edge preloading itself at logon. WebView2 security updates stay enabled.' `
    'StartupBoostEnabled = 0' `
    { Test-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0 }

Add-CatalogItem '1.10' 1 'Edge Containment' 'Block Edge background mode (policy)' `
    'No Edge processes lingering after you close the browser.' `
    'BackgroundModeEnabled = 0' `
    { Test-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0 }

# ===== LEVEL 1 — Filesystem (safe half) =====

Add-CatalogItem '1.11' 1 'Filesystem (safe)' 'NTFS last-access updates off' `
    'One less metadata write per file read.' `
    'disablelastaccess = 1 (user-managed, disabled)' `
    {
        $v = Get-FsutilNumber 'disablelastaccess'
        [pscustomobject]@{ Current = "disablelastaccess = $v"; Compliant = ($v -eq 1 -or $v -eq 3) }
    }

Add-CatalogItem '1.12' 1 'Filesystem (safe)' 'Larger NTFS metadata cache' `
    'Fewer metadata disk hits. Needs a reboot to take effect.' `
    'memoryusage = 2' `
    {
        $v = Get-FsutilNumber 'memoryusage'
        [pscustomobject]@{ Current = "memoryusage = $v"; Compliant = ($v -eq 2) }
    }

Add-CatalogItem '1.13' 1 'Filesystem (safe)' 'SSD TRIM enabled (verify)' `
    'TRIM keeps SSD write performance healthy.' `
    'DisableDeleteNotify = 0' `
    {
        $out = fsutil behavior query DisableDeleteNotify 2>$null
        $ntfs = @($out) -match 'NTFS'
        if ($ntfs -and $ntfs[0] -match '(\d)') {
            [pscustomobject]@{ Current = $ntfs[0].Trim(); Compliant = ($Matches[1] -eq '0') }
        } else { [pscustomobject]@{ Current = ($out -join ' '); Compliant = $null } }
    }

# ===== LEVEL 1 — Network Adapter =====

Add-CatalogItem '1.14' 1 'Network Adapter' 'NIC power-saving property cluster off' `
    'Energy-Efficient Ethernet / Green Ethernet / Power Saving Mode / Gigabit Lite / Wake-on-pattern cause micro-stutter and latency spikes. Only properties that exist on your adapter are touched. Applying resets the adapter ~2s — never runs mid-game.' `
    'all existing power-saving properties Disabled' `
    {
        $nic = Get-ActiveNic
        if (-not $nic) { return [pscustomobject]@{ Current = 'no active physical adapter'; Compliant = $null } }
        $names = 'Energy-Efficient Ethernet', 'Energy Efficient Ethernet', 'EEE', 'Advanced EEE',
                 'Green Ethernet', 'Power Saving Mode', 'Gigabit Lite', 'Wake on pattern match'
        $props = @(Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue |
                   Where-Object { $names -contains $_.DisplayName })
        if (-not $props.Count) {
            return [pscustomobject]@{ Current = "adapter '$($nic.Name)' exposes none of these properties"; Compliant = $true }
        }
        $bad = @($props | Where-Object { $_.DisplayValue -notin 'Disabled', 'Off' })
        $cur = ($props | ForEach-Object { "$($_.DisplayName)=$($_.DisplayValue)" }) -join '; '
        [pscustomobject]@{ Current = $cur; Compliant = ($bad.Count -eq 0) }
    }

Add-CatalogItem '1.15' 1 'Network Adapter' '"Allow computer to turn off this device" off' `
    'OS-initiated NIC power-down causes stutter. Applied via the MSPower_DeviceEnable CIM method (the only one that actually works); verified via Get-NetAdapterPowerManagement, never via the CIM re-read (it lies).' `
    'AllowComputerToTurnOffDevice = Disabled' `
    {
        $nic = Get-ActiveNic
        if (-not $nic) { return [pscustomobject]@{ Current = 'no active physical adapter'; Compliant = $null } }
        $pm = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction SilentlyContinue
        if (-not $pm) { return [pscustomobject]@{ Current = 'power management info unavailable'; Compliant = $null } }
        $v = "$($pm.AllowComputerToTurnOffDevice)"
        [pscustomobject]@{ Current = "AllowComputerToTurnOffDevice = $v"; Compliant = ($v -in 'Disabled', 'Unsupported') }
    }

# ===== LEVEL 1 — Power & Input =====

Add-CatalogItem '1.16' 1 'Power & Input' 'USB selective suspend off' `
    'Prevents input-device latency/wake hitches.' `
    'AC setting = 0 on active power scheme' `
    {
        $v = Get-PowerAcValue '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
        if ($null -eq $v) { return [pscustomobject]@{ Current = 'setting not readable on this scheme'; Compliant = $null } }
        [pscustomobject]@{ Current = "USB selective suspend = $v (0=off,1=on)"; Compliant = ($v -eq 0) }
    }

Add-CatalogItem '1.17' 1 'Power & Input' 'PCIe link-state power management off' `
    'GPU PCIe link never down-clocks into a latency penalty.' `
    'ASPM = 0 (Off) on active power scheme' `
    {
        $v = Get-PowerAcValue '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5'
        if ($null -eq $v) { return [pscustomobject]@{ Current = 'setting not readable on this scheme'; Compliant = $null } }
        [pscustomobject]@{ Current = "PCIe ASPM = $v (0=off)"; Compliant = ($v -eq 0) }
    }

Add-CatalogItem '1.18' 1 'Power & Input' 'Mouse acceleration off' `
    'Raw 1:1 aim — Enhance Pointer Precision disabled.' `
    'MouseSpeed = 0, both thresholds = 0' `
    {
        $m = Get-ItemProperty 'HKCU:\Control Panel\Mouse' -ErrorAction SilentlyContinue
        $cur = "MouseSpeed=$($m.MouseSpeed) T1=$($m.MouseThreshold1) T2=$($m.MouseThreshold2)"
        [pscustomobject]@{ Current = $cur
            Compliant = ($m.MouseSpeed -eq '0' -and $m.MouseThreshold1 -eq '0' -and $m.MouseThreshold2 -eq '0') }
    }

Add-CatalogItem '1.19' 1 'Power & Input' 'MMCSS gaming profile' `
    'Network throttling off + games get a fair CPU share from the multimedia scheduler.' `
    'NetworkThrottlingIndex = 0xFFFFFFFF, SystemResponsiveness = 0 (10 also accepted)' `
    {
        $p = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        $sp = Get-ItemProperty $p -ErrorAction SilentlyContinue
        $nti = if ($sp) { $sp.NetworkThrottlingIndex } else { $null }
        $sr  = if ($sp) { $sp.SystemResponsiveness }  else { $null }
        # registry DWORD 0xFFFFFFFF reads back as Int32 -1 — accept both representations
        $ntiOk = ($nti -eq -1 -or $nti -eq 4294967295)
        [pscustomobject]@{
            Current   = "NetworkThrottlingIndex = $nti; SystemResponsiveness = $sr"
            Compliant = ($ntiOk -and ($sr -eq 0 -or $sr -eq 10)) }
    }

# ===== LEVEL 2 — Services =====

$serviceRows = @(
    @{ Id = '2S.1';  Svc = 'DiagTrack';      Exp = 'Disabled'; Desc = 'Connected User Experiences & Telemetry — the main telemetry collector.' }
    @{ Id = '2S.2';  Svc = 'SysMain';        Exp = 'Disabled'; Desc = 'Superfetch/prefetch — no benefit on SSD-only systems.' }
    @{ Id = '2S.3';  Svc = 'WerSvc';         Exp = 'Disabled'; Desc = 'Windows Error Reporting upload.' }
    @{ Id = '2S.4';  Svc = 'Fax';            Exp = 'Disabled'; Desc = 'Fax. It is not 1996.' }
    @{ Id = '2S.5';  Svc = 'RetailDemo';     Exp = 'Disabled'; Desc = 'Store-shelf demo mode.' }
    @{ Id = '2S.6';  Svc = 'RemoteRegistry'; Exp = 'Disabled'; Desc = 'Remote registry editing — disabling is a security win too.' }
    @{ Id = '2S.7';  Svc = 'MapsBroker';     Exp = 'Disabled'; Desc = 'Offline maps sync.' }
    @{ Id = '2S.8';  Svc = 'WMPNetworkSvc';  Exp = 'Disabled'; Desc = 'Media Player network sharing.' }
    @{ Id = '2S.9';  Svc = 'PhoneSvc';       Exp = 'Disabled'; Desc = 'Phone Link backend. Guard: prompts at apply-time if Phone Link is used.' }
    @{ Id = '2S.10'; Svc = 'lfsvc';          Exp = 'Disabled'; Desc = 'Geolocation. Guard: prompts at apply-time (some apps want location).' }
    @{ Id = '2S.12'; Svc = 'CDPSvc';         Exp = 'Disabled'; Desc = 'Connected Devices Platform service (pairs with 1.4).' }
    @{ Id = '2S.13'; Svc = 'DusmSvc';        Exp = 'Disabled'; Desc = 'Data usage metering.' }
    @{ Id = '2S.14'; Svc = 'SharedAccess';   Exp = 'Disabled'; Desc = 'Internet Connection Sharing. Guard: prompts — Mobile Hotspot/VPN sharing need it (Manual offered instead).' }
    @{ Id = '2S.15'; Svc = 'WSAIFabricSvc';  Exp = 'Disabled'; Desc = 'Windows AI Fabric — no AI features on a gaming rig.' }
    @{ Id = '2S.16'; Svc = 'LanmanServer';   Exp = 'Disabled'; Desc = 'SMB share HOSTING. Guard: prompts — breaks sharing folders to other devices (NAS client access unaffected).' }
    @{ Id = '2S.17'; Svc = 'PcaSvc';         Exp = 'Manual';   Desc = 'Program Compatibility Assistant → Manual. Windows Update flips it back — audit re-checks.' }
)
foreach ($row in $serviceRows) {
    $svc = $row.Svc; $exp = $row.Exp
    Add-CatalogItem $row.Id 2 'Services' "$svc → $exp" $row.Desc "StartMode = $exp" `
        { Test-ServiceStartMode $svc $exp }.GetNewClosure()
}

Add-CatalogItem '2S.11' 2 'Services' 'Spooler → Disabled (printer-guarded)' `
    'Print spooler. Auto-guard: skipped entirely if a real printer is installed.' `
    'StartMode = Disabled (or skip if printer present)' `
    {
        $printers = @(Get-Printer -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -notmatch 'PDF|XPS|OneNote|Fax' })
        if ($printers.Count) {
            return [pscustomobject]@{
                Current = "printer detected ($($printers[0].Name)) — guarded, would SKIP"; Compliant = $true }
        }
        Test-ServiceStartMode 'Spooler' 'Disabled'
    }

Add-CatalogItem '2S.18' 2 'Services' 'DoSvc (Delivery Optimization) → Manual' `
    'Set-Service is Access-Denied on this service — the registry Start value is edited directly (3 = Manual).' `
    'registry Start = 3' `
    { Test-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc' 'Start' 3 }

Add-CatalogItem '2S.19' 2 'Services' 'Anticheat/launcher services → Manual (never Disabled)' `
    'EABackgroundService, EAAntiCheatService, BEService, EasyAntiCheat: Disabled silently breaks game launches (verified with EA titles); Manual keeps them dormant until their game runs. Riot vgc/vgk are deliberately excluded (managed separately).' `
    'present services at Manual' `
    {
        $names = 'EABackgroundService', 'EAAntiCheatService', 'BEService', 'EasyAntiCheat', 'EasyAntiCheat_EOS'
        $found = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
                   Where-Object { $names -contains $_.Name })
        if (-not $found.Count) { return [pscustomobject]@{ Current = 'none present'; Compliant = $true } }
        $bad = @($found | Where-Object { $_.StartMode -ne 'Manual' })
        $cur = ($found | ForEach-Object { "$($_.Name)=$($_.StartMode)" }) -join '; '
        [pscustomobject]@{ Current = $cur; Compliant = ($bad.Count -eq 0) }
    }

# ===== LEVEL 2 — Apps =====

Add-CatalogItem '2A.1' 2 'Apps' 'Remove Microsoft AI Manager (aimgr)' `
    'Background AI component. Windows Update reinstalls it — audit re-flags.' `
    'package absent' `
    {
        $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match 'aimgr|AIManager' })
        if ($pkg.Count) { [pscustomobject]@{ Current = "installed: $($pkg[0].Name)"; Compliant = $false } }
        else            { [pscustomobject]@{ Current = 'not installed';               Compliant = $true } }
    }

Add-CatalogItem '2A.2' 2 'Apps' 'Remove Copilot' `
    'No AI assistant processes on a gaming rig.' `
    'package absent' `
    {
        $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match 'Copilot' })
        if ($pkg.Count) { [pscustomobject]@{ Current = "installed: $(($pkg.Name | Select-Object -First 2) -join ', ')"; Compliant = $false } }
        else            { [pscustomobject]@{ Current = 'not installed'; Compliant = $true } }
    }

Add-CatalogItem '2A.3' 2 'Apps' 'Fully remove Widgets apps' `
    'WebExperience + WidgetsPlatformRuntime. After removal the Settings "Widgets" toggle disappears — expected.' `
    'both packages absent' `
    {
        $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match 'Client\.WebExperience|WidgetsPlatformRuntime' })
        if ($pkg.Count) { [pscustomobject]@{ Current = "installed: $($pkg.Name -join ', ')"; Compliant = $false } }
        else            { [pscustomobject]@{ Current = 'not installed'; Compliant = $true } }
    }

Add-CatalogItem '2A.4' 2 'Apps' 'OEM vendor bloat sweep (report-only)' `
    'Lists known OEM utility leftovers; never auto-removes — each is a per-item prompt at apply-time.' `
    'no known OEM bloat packages' `
    {
        $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match 'HPInc|Hewlett|Lenovo|DellInc|ASUSTeK|AcerIncorporated|McAfee|Norton' })
        if ($pkg.Count) { [pscustomobject]@{ Current = "found: $($pkg.Name -join ', ')"; Compliant = $null } }
        else            { [pscustomobject]@{ Current = 'none found'; Compliant = $true } }
    }

# ===== LEVEL 2 — Filesystem =====

Add-CatalogItem '2B.1' 2 'Filesystem (L2)' 'Disk write caching ON for all fixed disks' `
    'Found silently OFF on the reference rig — a large invisible I/O penalty. Missing value = Windows default (on). Needs reboot; re-verify after driver/Windows updates.' `
    'UserWriteCacheSetting = 1 (or unset) per disk' `
    {
        $bad = [System.Collections.Generic.List[string]]::new()
        $seen = 0
        foreach ($disk in Get-CimInstance Win32_DiskDrive) {
            $seen++
            $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($disk.PNPDeviceID)\Device Parameters\Disk"
            $v = (Get-ItemProperty -Path $reg -Name UserWriteCacheSetting -ErrorAction SilentlyContinue).UserWriteCacheSetting
            if ($v -eq 0) { $bad.Add(($disk.Model -replace '\s+', ' ').Trim()) }
        }
        if ($bad.Count) { [pscustomobject]@{ Current = "write cache OFF: $($bad -join ', ')"; Compliant = $false } }
        else            { [pscustomobject]@{ Current = "write cache on/default for all $seen disks"; Compliant = $true } }
    }

Add-CatalogItem '2B.2' 2 'Filesystem (L2)' 'Hibernation + Fast Startup off' `
    'Frees hiberfil.sys (GBs) and avoids stale-driver Fast Startup states. Guard: prompts on laptops.' `
    'HibernateEnabled = 0' `
    { Test-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' 0 }

Add-CatalogItem '2B.3' 2 'Filesystem (L2)' 'Storage Sense off' `
    'No surprise background cleanups mid-game; clean manually instead.' `
    'StoragePolicy 01 = 0' `
    { Test-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 0 }

Add-CatalogItem '2B.4' 2 'Filesystem (L2)' 'System Restore shadow storage capped at 10 GB' `
    'Bounds background VSS disk usage while keeping restore points. Requires elevation to read.' `
    'MaxSpace <= 10 GB for C:' `
    {
        $out = vssadmin list shadowstorage 2>$null
        if (-not $out) { return [pscustomobject]@{ Current = 'vssadmin unavailable (needs elevation?)'; Compliant = $null } }
        $line = @($out) -match 'Maximum Shadow Copy Storage space'
        if (-not $line) { return [pscustomobject]@{ Current = 'no shadow storage configured'; Compliant = $true } }
        $txt = $line[0].Trim()
        if ($txt -match 'UNBOUNDED') { return [pscustomobject]@{ Current = $txt; Compliant = $false } }
        if ($txt -match '([\d\.]+)\s*GB') { return [pscustomobject]@{ Current = $txt; Compliant = ([double]$Matches[1] -le 10) } }
        if ($txt -match '([\d\.]+)\s*MB') { return [pscustomobject]@{ Current = $txt; Compliant = $true } }
        [pscustomobject]@{ Current = $txt; Compliant = $null }
    }

# ===== LEVEL 3 — Aggressive (security trade-offs) =====

Add-CatalogItem '3.1' 3 'Security Trade-offs' 'Spectre/Meltdown mitigations OFF' `
    'TRADE-OFF: ~1-3% CPU-bound gain for disabled speculative-execution hardening. Personal gaming rig decision only. Major Windows updates can re-enable — audit re-checks.' `
    'FeatureSettingsOverride = 3, Mask = 3' `
    {
        $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        $a = Test-RegValue $p 'FeatureSettingsOverride' 3 -MissingText '(not set — mitigations ACTIVE, Windows default)'
        $b = Test-RegValue $p 'FeatureSettingsOverrideMask' 3 -MissingText '(not set)'
        [pscustomobject]@{ Current = "$($a.Current); $($b.Current)"; Compliant = ($a.Compliant -and $b.Compliant) }
    }

Add-CatalogItem '3.2' 3 'Security Trade-offs' 'VBS / Memory Integrity / Hyper-V OFF' `
    'TRADE-OFF: several % FPS for losing HVCI, Credential Guard, WSL2, Hyper-V, Windows Sandbox. Guard: warns hard if WSL2/Docker detected. Note: "Microsoft Hypervisor Service: Degraded" afterward is benign (= off on purpose).' `
    'VBS status 0, hypervisorlaunchtype Off, HVCI Enabled = 0' `
    {
        $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
        $vbs = if ($dg) { $dg.VirtualizationBasedSecurityStatus } else { $null }
        $hvci = try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' `
                 -Name Enabled -ErrorAction Stop).Enabled } catch { $null }   # key/value absent = HVCI not configured
        $bcd = bcdedit /enum '{current}' 2>$null
        $hvl = if ($bcd) { $l = @($bcd) -match 'hypervisorlaunchtype'
                           if ($l) { ($l[0] -split '\s+')[-1] } else { 'Off (unset)' } } else { 'unreadable (needs elevation)' }
        $cur = "VBS status = $vbs (0=off,2=running); HVCI Enabled = $hvci; hypervisorlaunchtype = $hvl"
        if ($null -eq $vbs) { return [pscustomobject]@{ Current = $cur; Compliant = $null } }
        [pscustomobject]@{ Current = $cur; Compliant = ($vbs -eq 0 -and $hvci -ne 1) }
    }

Add-CatalogItem '3.3' 3 'Security Trade-offs' 'Defender scheduled scans OFF (real-time stays ON)' `
    'Background full scans tank frame times mid-game. Real-time + tamper protection are NEVER touched. Windows Update resets the schedule — audit re-checks. Compensation: on-demand quick scans.' `
    'ScanScheduleDay = 8 (Never), catch-up scans disabled' `
    {
        try { $mp = Get-MpPreference -ErrorAction Stop } catch {
            return [pscustomobject]@{ Current = 'Defender preferences unreadable'; Compliant = $null } }
        $cur = "ScanScheduleDay = $($mp.ScanScheduleDay) (8=Never); CatchupQuick disabled = $($mp.DisableCatchupQuickScan); CatchupFull disabled = $($mp.DisableCatchupFullScan)"
        [pscustomobject]@{ Current = $cur
            Compliant = ($mp.ScanScheduleDay -eq 8 -and $mp.DisableCatchupQuickScan -and $mp.DisableCatchupFullScan) }
    }

Add-CatalogItem '3.4' 3 'Security Trade-offs' 'Defender exclusions for game folders (review)' `
    'Eliminates on-access scan stutter on game assets. Steam libraries auto-detected; every folder is a per-item prompt. HARD RULE: never excludes Temp, profile roots, or drive roots.' `
    'game folders excluded, nothing dangerous excluded' `
    {
        try { $mp = Get-MpPreference -ErrorAction Stop } catch {
            return [pscustomobject]@{ Current = 'Defender preferences unreadable'; Compliant = $null } }
        $excl = @($mp.ExclusionPath)
        $danger = @($excl | Where-Object { $_ -match 'Temp|Downloads' -or $_ -match '^[A-Z]:\\?$' })
        $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
        $libs = [System.Collections.Generic.List[string]]::new()
        if ($steam -and (Test-Path "$steam\steamapps\libraryfolders.vdf")) {
            foreach ($m in [regex]::Matches((Get-Content "$steam\steamapps\libraryfolders.vdf" -Raw), '"path"\s+"([^"]+)"')) {
                $libs.Add($m.Groups[1].Value.Replace('\\', '\'))
            }
        }
        $cur = "$($excl.Count) exclusions; Steam libraries: $(if ($libs.Count) { $libs -join ', ' } else { 'none detected' })"
        if ($danger.Count) {
            return [pscustomobject]@{ Current = "$cur — DANGEROUS exclusion present: $($danger -join ', ')"; Compliant = $false }
        }
        [pscustomobject]@{ Current = $cur; Compliant = $null }   # human review: which games to exclude
    }

Add-CatalogItem '3.5' 3 'Security Trade-offs' 'MSI interrupt mode for GPU + NIC' `
    'Message-signaled interrupts = lower interrupt latency than legacy line-based. Most modern devices already use MSI — only offered if actually off.' `
    'MSISupported = 1 for GPU and active NIC' `
    {
        $parts = [System.Collections.Generic.List[string]]::new()
        $ok = $true
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic Display|Remote' } | Select-Object -First 1
        $nic = Get-ActiveNic
        foreach ($dev in @(
            @{ Label = 'GPU'; Pnp = if ($gpu) { $gpu.PNPDeviceID } else { $null } }
            @{ Label = 'NIC'; Pnp = if ($nic) { $nic.PnpDeviceID } else { $null } }
        )) {
            if (-not $dev.Pnp) { $parts.Add("$($dev.Label): not found"); continue }
            $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Pnp)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $v = (Get-ItemProperty -Path $reg -Name MSISupported -ErrorAction SilentlyContinue).MSISupported
            if ($v -eq 1) { $parts.Add("$($dev.Label): MSI on") }
            else { $parts.Add("$($dev.Label): MSI off/unset"); $ok = $false }
        }
        [pscustomobject]@{ Current = $parts -join '; '; Compliant = $ok }
    }
