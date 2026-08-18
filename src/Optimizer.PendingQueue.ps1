# Public seam: Add-OptimizerPendingConfirmation / Get-OptimizerPendingConfirmations

function Get-OptimizerPendingConfirmations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$QueuePath
    )

    if (-not (Test-Path -LiteralPath $QueuePath)) {
        return @()
    }

    $raw = Get-Content -LiteralPath $QueuePath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $data = $raw | ConvertFrom-Json
    $items = @()
    if ($null -eq $data) {
        return @()
    }
    if ($data -is [System.Array]) {
        $items = @($data)
    }
    elseif ($data.PSObject.Properties.Name -contains 'items') {
        $items = @($data.items)
    }
    else {
        $items = @($data)
    }

    $mapped = @(
        $items | ForEach-Object {
            [pscustomobject]@{
                Path    = [string]$_.Path
                Reason  = [string]$_.Reason
                AddedAt = if ($_.AddedAt) { [string]$_.AddedAt } else { $null }
                Status  = if ($_.Status) { [string]$_.Status } else { 'pending' }
            }
        }
    )
    return , $mapped
}

function Add-OptimizerPendingConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$QueuePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    $dir = Split-Path -Parent $QueuePath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $existing = @(Get-OptimizerPendingConfirmations -QueuePath $QueuePath)
    $normalizedTarget = $TargetPath.ToLowerInvariant()
    foreach ($item in $existing) {
        if ($item.Path.ToLowerInvariant() -eq $normalizedTarget) {
            return $item
        }
    }

    $newItem = [pscustomobject]@{
        Path    = $TargetPath
        Reason  = $Reason
        AddedAt = (Get-Date).ToString('o')
        Status  = 'pending'
    }
    $all = @($existing) + @($newItem)
    $payload = [pscustomobject]@{ items = $all }
    $json = $payload | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $QueuePath -Value $json -Encoding UTF8
    return $newItem
}
