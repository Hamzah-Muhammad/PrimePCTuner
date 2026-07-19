# 2B.1 — Disk write caching ON for all fixed disks. Performance & Hardware sector.
# Found silently OFF on the reference rig — a large invisible I/O penalty.
# Missing value = Windows default (on). Needs reboot; re-verify after
# driver/Windows updates.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

function Get-DiskCacheRegPath {
    param($Disk)
    "HKLM:\SYSTEM\CurrentControlSet\Enum\$($Disk.PNPDeviceID)\Device Parameters\Disk"
}

Invoke-PrimeChange -Id '2B.1' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $bad = [System.Collections.Generic.List[string]]::new(); $seen = 0
        foreach ($disk in Get-CimInstance Win32_DiskDrive) {
            $seen++
            $v = (Get-ItemProperty -Path (Get-DiskCacheRegPath $disk) -Name UserWriteCacheSetting -ErrorAction SilentlyContinue).UserWriteCacheSetting
            if ($v -eq 0) { $bad.Add(($disk.Model -replace '\s+', ' ').Trim()) }
        }
        if ($bad.Count) { [pscustomobject]@{ Current = "write cache OFF: $($bad -join ', ')"; Compliant = $false } }
        else { [pscustomobject]@{ Current = "write cache on/default for all $seen disks"; Compliant = $true } }
    } `
    -ApplyBlock {
        $results = @{}
        foreach ($disk in Get-CimInstance Win32_DiskDrive) {
            $results[$disk.PNPDeviceID] = Set-RegValueTracked (Get-DiskCacheRegPath $disk) 'UserWriteCacheSetting' 1
        }
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($results | ConvertTo-Json -Compress -Depth 4)
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        foreach ($pnp in $inner.PSObject.Properties.Name) {
            $r = $inner.$pnp
            $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnp\Device Parameters\Disk"
            Undo-RegValueTracked $reg 'UserWriteCacheSetting' $r.PreviouslyExisted $r.PreviousValue | Out-Null
        }
        New-TrackedResult -Success $true -Note 'reboot required to take effect'
    }
