# Start-StartupOptimization.ps1 — Startup Optimizer (PCOptimizationServices suite)
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
. (Join-Path $PSScriptRoot 'lib\Catalog.ps1')

$ctx = New-PrimeChecklistApp `
    -Title       'Startup Optimizer' `
    -Eyebrow     'P C  O P T I M I Z E R S   ·   F O R  E V E R Y D A Y  P C s' `
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
