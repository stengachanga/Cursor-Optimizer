# Public seam: Get-OptimizerPressure

function Get-OptimizerPressure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [long]$TotalBytes,

        [Parameter(Mandatory = $true)]
        [long]$FreeBytes,

        [Parameter(Mandatory = $true)]
        [long]$AvailableRamBytes,

        [double]$WarnFreePercent = 15,
        [double]$CriticalFreePercent = 10,
        [double]$CriticalFreeGB = 5,
        [double]$MinAvailableRamGB = 2
    )

    if ($TotalBytes -le 0) {
        throw "TotalBytes must be positive"
    }

    $freePercent = ($FreeBytes / [double]$TotalBytes) * 100.0
    $freeGB = $FreeBytes / 1GB
    $ramGB = $AvailableRamBytes / 1GB

    $level = 'Normal'
    if ($freePercent -lt $CriticalFreePercent -or $freeGB -lt $CriticalFreeGB) {
        $level = 'Critical'
    }
    elseif ($freePercent -lt $WarnFreePercent) {
        $level = 'Warn'
    }

    $preferInMemory = ($level -eq 'Critical') -and ($ramGB -ge $MinAvailableRamGB)

    [pscustomobject]@{
        Level                 = $level
        FreePercent           = [math]::Round($freePercent, 2)
        FreeGB                = [math]::Round($freeGB, 2)
        AvailableRamGB        = [math]::Round($ramGB, 2)
        PreferInMemoryReport  = [bool]$preferInMemory
    }
}
