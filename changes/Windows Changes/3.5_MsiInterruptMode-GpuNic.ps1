# 3.5 — MSI interrupt mode for GPU + NIC (Level 3, Security Trade-off catalog — hardware tuning, low risk). Windows Changes sector.
# Message-signaled interrupts = lower interrupt latency than legacy line-based.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

function Get-MsiDevices {
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic Display|Remote' } | Select-Object -First 1
    $nic = Get-ActiveNic
    @(
        @{ Label = 'GPU'; Pnp = if ($gpu) { $gpu.PNPDeviceID } else { $null } }
        @{ Label = 'NIC'; Pnp = if ($nic) { $nic.PnpDeviceID } else { $null } }
    )
}

Invoke-PrimeChange -Id '3.5' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $parts = [System.Collections.Generic.List[string]]::new(); $ok = $true
        foreach ($dev in Get-MsiDevices) {
            if (-not $dev.Pnp) { $parts.Add("$($dev.Label): not found"); continue }
            $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Pnp)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $v = (Get-ItemProperty -Path $reg -Name MSISupported -ErrorAction SilentlyContinue).MSISupported
            if ($v -eq 1) { $parts.Add("$($dev.Label): MSI on") } else { $parts.Add("$($dev.Label): MSI off/unset"); $ok = $false }
        }
        [pscustomobject]@{ Current = $parts -join '; '; Compliant = $ok }
    } `
    -ApplyBlock {
        $results = @{}
        foreach ($dev in Get-MsiDevices) {
            if (-not $dev.Pnp) { continue }
            $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Pnp)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $results[$dev.Label] = @{ Reg = $reg; Result = (Set-RegValueTracked $reg 'MSISupported' 1) }
        }
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($results | ConvertTo-Json -Compress -Depth 5)
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        foreach ($label in $inner.PSObject.Properties.Name) {
            $d = $inner.$label
            Undo-RegValueTracked $d.Reg 'MSISupported' $d.Result.PreviouslyExisted $d.Result.PreviousValue | Out-Null
        }
        New-TrackedResult -Success $true -Note 'device reset (~2s) applies the change — never run mid-game'
    }
