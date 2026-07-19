# 3.1 — Spectre/Meltdown mitigations OFF (Level 3, Security Trade-off). Windows Changes sector.
# TRADE-OFF: ~1-3% CPU-bound gain for disabled speculative-execution hardening.
# Major Windows updates can re-enable — audit re-checks.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$NameA = 'FeatureSettingsOverride'
$NameB = 'FeatureSettingsOverrideMask'

Invoke-PrimeChange -Id '3.1' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $a = Test-RegValue $RegPath $NameA 3 -MissingText '(not set — mitigations ACTIVE, Windows default)'
        $b = Test-RegValue $RegPath $NameB 3 -MissingText '(not set)'
        [pscustomobject]@{ Current = "$($a.Current); $($b.Current)"; Compliant = ($a.Compliant -and $b.Compliant) }
    } `
    -ApplyBlock {
        $a = Set-RegValueTracked $RegPath $NameA 3
        $b = Set-RegValueTracked $RegPath $NameB 3
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue (@{A=$a;B=$b} | ConvertTo-Json -Compress)
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        Undo-RegValueTracked $RegPath $NameA $inner.A.PreviouslyExisted $inner.A.PreviousValue
        Undo-RegValueTracked $RegPath $NameB $inner.B.PreviouslyExisted $inner.B.PreviousValue
    }
