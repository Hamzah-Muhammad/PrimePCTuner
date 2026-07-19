# Catalog.ps1 — StartupOptimizer catalog. Built DYNAMICALLY at load:
# every startup surface on this PC is enumerated and becomes one checkbox item.
# Check scriptblocks are read-only. Nothing in this file writes to the system.
#
# Levels: 1 = Startup Apps (Run keys + startup folders)
#         2 = Logon Scheduled Tasks
#         3 = Windows Extras (Widgets/Copilot/Edge/AI) + leftovers

Set-StrictMode -Version 2

$Script:OptimizationCatalog = [System.Collections.Generic.List[object]]::new()
function Add-StartupItem {
    param($Id, $Level, $Module, $Name, $Desc, $Target, [bool]$DefaultChecked, [scriptblock]$Check)
    $Script:OptimizationCatalog.Add([pscustomobject]@{
        Id = $Id; Level = $Level; Module = $Module; Name = $Name
        Desc = $Desc; Target = $Target; Check = $Check; DefaultChecked = $DefaultChecked
    })
}

# ---------- annotations for well-known startup entries ----------
# Keep = recommended keep (row starts UNCHECKED so a general client doesn't remove it by accident)
function Get-StartupAnnotation {
    param($Name)
    switch -Regex ($Name) {
        '^SecurityHealth$'        { return @{ Keep = $true;  Note = 'Windows Security tray icon — recommended KEEP.' } }
        'OneDrive'                { return @{ Keep = $false; Note = 'Cloud file sync. UNCHECK if you rely on OneDrive syncing from the moment you log in.' } }
        'Discord'                 { return @{ Keep = $false; Note = 'Chat app — opens fine on demand, not needed at boot.' } }
        'Steam|EpicGames|GOG'     { return @{ Keep = $false; Note = 'Game launcher — start it when you actually game.' } }
        'Spotify'                 { return @{ Keep = $false; Note = 'Music app — not needed at boot.' } }
        'Teams'                   { return @{ Keep = $false; Note = 'Meetings app — starts fast on demand.' } }
        'vgtray|Vanguard|Riot'    { return @{ Keep = $false; Note = 'Game anticheat/launcher tray. Removing from startup may require re-enabling before that game runs.' } }
        'Rtk|Realtek'             { return @{ Keep = $false; Note = 'Audio vendor tray — audio keeps working without it.' } }
        'iTunesHelper|CCleaner|Update' { return @{ Keep = $false; Note = 'Helper/updater — the app updates itself when opened.' } }
        default                   { return @{ Keep = $false; Note = 'Starts at every logon. Removing it speeds up boot; you can still open the app manually.' } }
    }
}

# =====================================================================
# LEVEL 1 — Registry Run entries (each entry found on THIS PC = one item)
# =====================================================================

$runLocations = @(
    @{ Tag = 'HKCU';    Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
    @{ Tag = 'HKCU-RO'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' }
    @{ Tag = 'HKLM';    Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
    @{ Tag = 'HKLM-RO'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
    @{ Tag = 'HKLM32';  Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run' }
)
$rIdx = 0
foreach ($loc in $runLocations) {
    $key = Get-Item -Path $loc.Path -ErrorAction SilentlyContinue
    if (-not $key) { continue }
    foreach ($valName in ($key.GetValueNames() | Where-Object { $_ })) {
        $rIdx++
        $cmd = [string]$key.GetValue($valName)
        if ($cmd.Length -gt 110) { $cmd = $cmd.Substring(0, 107) + '…' }
        $ann = Get-StartupAnnotation $valName
        $regPath = $loc.Path; $vn = $valName   # locals for the closure
        Add-StartupItem "R.$rIdx" 1 'Registry Run Entries' "$valName  [$($loc.Tag)]" `
            "$($ann.Note)  Command: $cmd" `
            'entry removed from startup' $(-not $ann.Keep) `
            {
                $k = Get-Item -Path $regPath -ErrorAction SilentlyContinue
                if ($k -and ($k.GetValueNames() -contains $vn)) {
                    [pscustomobject]@{ Current = 'still starts at logon'; Compliant = $false }
                } else {
                    [pscustomobject]@{ Current = 'no longer in startup'; Compliant = $true }
                }
            }.GetNewClosure()
    }
}
if ($rIdx -eq 0) {
    Add-StartupItem 'R.0' 1 'Registry Run Entries' 'No Run-key startup entries found' `
        'Your registry startup surface is already clean.' 'nothing to remove' $false `
        { [pscustomobject]@{ Current = 'clean'; Compliant = $true } }
}

# =====================================================================
# LEVEL 1 — Startup folder shortcuts
# =====================================================================

$folderLocations = @(
    @{ Tag = 'user';   Path = [Environment]::GetFolderPath('Startup') }
    @{ Tag = 'common'; Path = [Environment]::GetFolderPath('CommonStartup') }
)
$fIdx = 0
foreach ($loc in $folderLocations) {
    if (-not $loc.Path -or -not (Test-Path $loc.Path)) { continue }
    foreach ($file in (Get-ChildItem -Path $loc.Path -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -ne 'desktop.ini' })) {
        $fIdx++
        $ann = Get-StartupAnnotation $file.BaseName
        $fp = $file.FullName
        Add-StartupItem "F.$fIdx" 1 'Startup Folder Shortcuts' "$($file.Name)  [$($loc.Tag)]" `
            "$($ann.Note)  Location: $fp" `
            'shortcut removed from Startup folder' $(-not $ann.Keep) `
            {
                if (Test-Path $fp) { [pscustomobject]@{ Current = 'still starts at logon'; Compliant = $false } }
                else               { [pscustomobject]@{ Current = 'no longer in startup'; Compliant = $true } }
            }.GetNewClosure()
    }
}
if ($fIdx -eq 0) {
    Add-StartupItem 'F.0' 1 'Startup Folder Shortcuts' 'Startup folders are empty' `
        'No shortcuts auto-launch from your Startup folders.' 'nothing to remove' $false `
        { [pscustomobject]@{ Current = 'clean'; Compliant = $true } }
}

# =====================================================================
# LEVEL 2 — Logon/boot scheduled tasks (the startup surface most tools miss)
# Scope: third-party tasks at the root path, Office logon tasks, Edge/Google
# updater logon tasks. \Microsoft\Windows\* system tasks are deliberately
# NOT touched (many are OS-critical).
# =====================================================================

$tIdx = 0
$allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
foreach ($task in $allTasks) {
    $triggers = @($task.Triggers | Where-Object { $_ } | Where-Object {
        $_.CimClass.CimClassName -match 'LogonTrigger|BootTrigger' })
    if (-not $triggers.Count) { continue }

    $inScope = ($task.TaskPath -eq '\') -or
               ($task.TaskPath -like '\Microsoft\Office*') -or
               ($task.TaskName -like 'MicrosoftEdgeUpdate*') -or
               ($task.TaskName -like 'GoogleUpdater*')
    if (-not $inScope) { continue }

    $tIdx++
    $exe = ''
    $action = @($task.Actions | Select-Object -First 1)
    if ($action.Count -and $action[0].PSObject.Properties['Execute']) { $exe = [string]$action[0].Execute }
    if ($exe.Length -gt 80) { $exe = $exe.Substring(0, 77) + '…' }

    $keep = $task.TaskName -match 'FanControl|Afterburner|RTSS'   # user hardware-control tooling
    $note = if ($keep) { 'Hardware control tool — KEEP if it manages your fans/overclock.' }
            elseif ($task.TaskName -like 'MicrosoftEdgeUpdate*') { 'Logon-triggered updater. Edge still updates via its periodic task.' }
            elseif ($task.TaskPath -like '\Microsoft\Office*') { 'Office logon task — Office re-enables these on updates; re-run this tool after Office updates.' }
            else { 'Runs at logon/boot. Disabling speeds up startup; the app itself is untouched.' }

    $tp = $task.TaskPath; $tn = $task.TaskName
    Add-StartupItem "T.$tIdx" 2 'Logon Scheduled Tasks' $tn `
        "$note  Path: $tp  Runs: $exe" `
        'task Disabled' $(-not $keep) `
        {
            $t = Get-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction SilentlyContinue
            if (-not $t) { return [pscustomobject]@{ Current = 'task no longer exists'; Compliant = $true } }
            if ($t.State -eq 'Disabled') { [pscustomobject]@{ Current = 'task disabled'; Compliant = $true } }
            else { [pscustomobject]@{ Current = "task $($t.State) — runs at logon/boot"; Compliant = $false } }
        }.GetNewClosure()
}
if ($tIdx -eq 0) {
    Add-StartupItem 'T.0' 2 'Logon Scheduled Tasks' 'No third-party logon tasks found' `
        'No in-scope tasks trigger at logon/boot.' 'nothing to disable' $false `
        { [pscustomobject]@{ Current = 'clean'; Compliant = $true } }
}

# =====================================================================
# LEVEL 3 — Windows extras (the bloat general clients never asked for)
# =====================================================================

Add-StartupItem 'W.1' 3 'Windows Extras' 'Remove Widgets apps' `
    'News/widgets feed pipeline (WebExperience + WidgetsPlatformRuntime). The Settings "Widgets" toggle disappears after removal — expected.' `
    'both packages absent' $true `
    {
        $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match 'Client\.WebExperience|WidgetsPlatformRuntime' })
        if ($pkg.Count) { [pscustomobject]@{ Current = "installed: $($pkg.Name -join ', ')"; Compliant = $false } }
        else            { [pscustomobject]@{ Current = 'not installed'; Compliant = $true } }
    }

Add-StartupItem 'W.2' 3 'Windows Extras' 'Widgets / news feed off (policy)' `
    'Blocks the widgets/news pipeline by policy so Windows Update can''t quietly bring it back to life.' `
    'AllowNewsAndInterests = 0' $true `
    {
        try { $v = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name AllowNewsAndInterests -ErrorAction Stop).AllowNewsAndInterests
              [pscustomobject]@{ Current = "AllowNewsAndInterests = $v"; Compliant = ($v -eq 0) } }
        catch { [pscustomobject]@{ Current = 'policy not set'; Compliant = $false } }
    }

Add-StartupItem 'W.3' 3 'Windows Extras' 'Remove Copilot' `
    'The AI assistant most people never asked for — removes its background presence.' `
    'package absent' $true `
    {
        $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Copilot' })
        if ($pkg.Count) { [pscustomobject]@{ Current = "installed: $(($pkg.Name | Select-Object -First 2) -join ', ')"; Compliant = $false } }
        else            { [pscustomobject]@{ Current = 'not installed'; Compliant = $true } }
    }

Add-StartupItem 'W.4' 3 'Windows Extras' 'Remove Microsoft AI Manager (aimgr)' `
    'Background AI component. Windows Update reinstalls it — re-run this tool after big updates.' `
    'package absent' $true `
    {
        $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'aimgr|AIManager' })
        if ($pkg.Count) { [pscustomobject]@{ Current = "installed: $($pkg[0].Name)"; Compliant = $false } }
        else            { [pscustomobject]@{ Current = 'not installed'; Compliant = $true } }
    }

Add-StartupItem 'W.5' 3 'Windows Extras' 'Block Edge startup boost + background mode' `
    'Edge preloads at logon and lingers after you close it. Policies stop both. WebView2 security updates are untouched.' `
    'StartupBoostEnabled = 0, BackgroundModeEnabled = 0' $true `
    {
        $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        $sb = try { (Get-ItemProperty $p -Name StartupBoostEnabled -ErrorAction Stop).StartupBoostEnabled } catch { $null }
        $bm = try { (Get-ItemProperty $p -Name BackgroundModeEnabled -ErrorAction Stop).BackgroundModeEnabled } catch { $null }
        [pscustomobject]@{
            Current = "StartupBoost = $sb; BackgroundMode = $bm"
            Compliant = ($sb -eq 0 -and $bm -eq 0) }
    }

Add-StartupItem 'X.1' 3 'Leftover Toggles' 'Purge inert StartupApproved leftovers' `
    'Old enable/disable toggle entries whose actual startup entry is long gone — registry clutter from uninstalled apps. Names are matched exactly (some have trailing spaces).' `
    'no orphaned StartupApproved entries' $true `
    {
        $pairs = @(
            @{ A = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   R = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
            @{ A = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   R = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
            @{ A = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; R = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run' }
        )
        $orphans = [System.Collections.Generic.List[string]]::new()
        foreach ($pair in $pairs) {
            $ak = Get-Item -Path $pair.A -ErrorAction SilentlyContinue
            if (-not $ak) { continue }
            $rk = Get-Item -Path $pair.R -ErrorAction SilentlyContinue
            $live = if ($rk) { $rk.GetValueNames() } else { @() }
            foreach ($n in ($ak.GetValueNames() | Where-Object { $_ })) {
                if ($live -notcontains $n) { $orphans.Add($n.Trim()) }
            }
        }
        if ($orphans.Count) {
            $preview = ($orphans | Select-Object -First 6) -join ', '
            if ($orphans.Count -gt 6) { $preview += " (+$($orphans.Count - 6) more)" }
            [pscustomobject]@{ Current = "$($orphans.Count) orphaned: $preview"; Compliant = $false }
        } else {
            [pscustomobject]@{ Current = 'no orphaned entries'; Compliant = $true }
        }
    }
