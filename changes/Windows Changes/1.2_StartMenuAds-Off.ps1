# 1.2 — Start-menu ads & suggestions off. Windows Changes sector.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$NameA = 'SubscribedContent-338388Enabled'
$NameB = 'SubscribedContent-338389Enabled'

Invoke-PrimeChange -Id '1.2' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $a = Test-RegValue $RegPath $NameA 0
        $b = Test-RegValue $RegPath $NameB 0
        [pscustomobject]@{ Current = "$($a.Current); $($b.Current)"; Compliant = ($a.Compliant -and $b.Compliant) }
    } `
    -ApplyBlock {
        $a = Set-RegValueTracked $RegPath $NameA 0
        $b = Set-RegValueTracked $RegPath $NameB 0
        New-TrackedResult -Success $true -PreviousValue (@{A=$a;B=$b} | ConvertTo-Json -Compress) -PreviouslyExisted $true
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        Undo-RegValueTracked $RegPath $NameA $inner.A.PreviouslyExisted $inner.A.PreviousValue
        Undo-RegValueTracked $RegPath $NameB $inner.B.PreviouslyExisted $inner.B.PreviousValue
    }
