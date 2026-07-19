# Start-StartupOptimization.ps1 — Startup Optimizer (PrimePCTuner suite)
# For everyday PCs, not gaming rigs: lists every startup app / logon task /
# Windows extra on THIS PC as a checkbox. DRY RUN — auto-scans on launch,
# green APPLIED / gold PENDING per item, nothing is changed.
#
# Usage:  .\Start-StartupOptimization.ps1            (self-elevates)
#         .\Start-StartupOptimization.ps1 -SelfTest  (build UI headless + exit)

param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\shared\PrimeUI.ps1')
Invoke-PrimeBootstrap -SelfTest:$SelfTest -ScriptPath $PSCommandPath

# Catalog is now split (§3): static items (Windows Extras/Leftover Toggles —
# several merged with FPS Optimizer's own scripts) come from manifest.json;
# the genuinely PC-specific items (Run keys, startup-folder shortcuts, logon
# tasks) are discovered live each launch via changes\PC Startup\Enumerate.ps1,
# not an in-process dynamic-catalog-build like before.
$RepoRoot = Split-Path -Parent $PSScriptRoot
$static = @(Get-PrimeManifestItems -ManifestPath (Join-Path $PSScriptRoot 'manifest.json') -RepoRoot $RepoRoot)

$enumScript = Join-Path $RepoRoot 'changes\PC Startup\Enumerate.ps1'
$psExe = Get-PrimePSExe
if (-not $psExe) { throw 'No PowerShell host (pwsh or powershell.exe) found on this PC.' }
$discovered = @(& $psExe -NoProfile -NonInteractive -File $enumScript -Json 2>$null | ConvertFrom-Json)

$dynamic = foreach ($d in $discovered) {
    $scriptArgs = switch ($d.Kind) {
        'RunKeyEntry'           { @{ RegPath = $d.RegPath; ValueName = $d.ValueName } }
        'StartupFolderShortcut' { @{ FilePath = $d.FilePath } }
        'ScheduledTask'         { @{ TaskPath = $d.TaskPath; TaskName = $d.TaskName } }
        default                 { @{} }   # "nothing found" placeholder rows (Kind = $null)
    }
    [pscustomobject]@{
        Id = $d.Id; Level = $d.Level; Module = $d.Module; Name = $d.Name
        Desc = $d.Desc; Target = $d.Target; DefaultChecked = [bool]$d.DefaultChecked
        ScriptPath = if ($d.Kind) { Join-Path $RepoRoot "changes\PC Startup\$($d.Kind).ps1" } else { $null }
        ScriptArgs = $scriptArgs
    }
}

$OptimizationCatalog = @($static) + @($dynamic)

$ctx = New-PrimeChecklistApp `
    -Title       'Startup Optimizer' `
    -Eyebrow     'P R I M E P C T U N E R   ·   F O R  E V E R Y D A Y  P C s' `
    -HeadingPlain 'Startup ' -HeadingAccent 'Optimizer' `
    -SubTitle    'Every app, task, and Windows extra that launches itself at logon on this PC. Green means already clean. Unchecked rows are recommended keeps. Nothing is changed in dry-run mode.' `
    -FooterNote  'Startup Optimizer v0.1 · dry run — no changes applied' `
    -Items       $OptimizationCatalog `
    -LevelMeta   @{
        1 = @{ Title = 'STARTUP APPS';   Color = $P.Green }
        2 = @{ Title = 'LOGON TASKS';    Color = $P.GoldA }
        3 = @{ Title = 'WINDOWS EXTRAS'; Color = $P.GoldB }
    } `
    -LogDir      (Join-Path $PSScriptRoot 'logs') `
    -ReportTitle 'Startup Optimizer dry run'

if ($SelfTest) {
    Write-Host "SELFTEST OK — Startup Optimizer window built, $($ctx.Rows.Count) rows, specs: $($ctx.Specs.CPU)"
    exit 0
}
$ctx.Window.ShowDialog() | Out-Null
