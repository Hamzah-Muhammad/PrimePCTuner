# 1.19 — MMCSS gaming profile. Performance & Hardware sector.
# Network throttling off + games get a fair CPU share from the multimedia
# scheduler. Registry DWORD 0xFFFFFFFF reads back as Int32 -1 — both
# representations are accepted as compliant.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$NameA = 'NetworkThrottlingIndex'
$NameB = 'SystemResponsiveness'

Invoke-PrimeChange -Id '1.19' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $sp = Get-ItemProperty $RegPath -ErrorAction SilentlyContinue
        $nti = if ($sp) { $sp.NetworkThrottlingIndex } else { $null }
        $sr  = if ($sp) { $sp.SystemResponsiveness }  else { $null }
        $ntiOk = ($nti -eq -1 -or $nti -eq 4294967295)
        [pscustomobject]@{ Current = "NetworkThrottlingIndex = $nti; SystemResponsiveness = $sr"; Compliant = ($ntiOk -and ($sr -eq 0 -or $sr -eq 10)) }
    } `
    -ApplyBlock {
        $a = Set-RegValueTracked $RegPath $NameA 0xFFFFFFFF
        $b = Set-RegValueTracked $RegPath $NameB 0
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue (@{A=$a;B=$b} | ConvertTo-Json -Compress)
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        Undo-RegValueTracked $RegPath $NameA $inner.A.PreviouslyExisted $inner.A.PreviousValue
        Undo-RegValueTracked $RegPath $NameB $inner.B.PreviouslyExisted $inner.B.PreviousValue
    }
