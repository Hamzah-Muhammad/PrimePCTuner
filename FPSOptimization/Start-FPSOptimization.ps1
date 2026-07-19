# Start-FPSOptimization.ps1 — FPS Optimizer (PrimePCTuner suite)
# Gaming-focused deep optimization: 52 checks across 3 risk levels. DRY RUN —
# auto-scans on launch, green APPLIED / gold PENDING per item, nothing is changed.
#
# Usage:  .\Start-FPSOptimization.ps1            (self-elevates)
#         .\Start-FPSOptimization.ps1 -SelfTest  (build UI headless + exit)

param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\shared\PrimeUI.ps1')
Invoke-PrimeBootstrap -SelfTest:$SelfTest -ScriptPath $PSCommandPath
. (Join-Path $PSScriptRoot 'lib\Catalog.ps1')

$ctx = New-PrimeChecklistApp `
    -Title       'FPS Optimizer' `
    -Eyebrow     'P R I M E P C T U N E R   ·   F O R  G A M I N G  R I G S' `
    -HeadingPlain 'FPS ' -HeadingAccent 'Optimizer' `
    -SubTitle    'Scanned automatically against your system — green means already applied. Uncheck anything you don''t want. Nothing is changed in dry-run mode.' `
    -FooterNote  'FPS Optimizer v0.3 · dry run — no changes applied' `
    -Items       $OptimizationCatalog `
    -LevelMeta   @{
        1 = @{ Title = 'LEVEL 1 · SAFE';       Color = $P.Green }
        2 = @{ Title = 'LEVEL 2 · DEBLOAT';    Color = $P.GoldA }
        3 = @{ Title = 'LEVEL 3 · AGGRESSIVE'; Color = $P.GoldB }
    } `
    -LogDir      (Join-Path $PSScriptRoot 'logs') `
    -ReportTitle 'FPS Optimizer dry run'

if ($SelfTest) {
    Write-Host "SELFTEST OK — FPS Optimizer window built, $($ctx.Rows.Count) rows, specs: $($ctx.Specs.CPU) / $($ctx.Specs.GPU)"
    exit 0
}
$ctx.Window.ShowDialog() | Out-Null
