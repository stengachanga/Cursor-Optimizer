# Public seam: Remove-OptimizerManagedPath, Test-OptimizerReparsePath

function Test-OptimizerReparsePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path -Force
    $reparse = [System.IO.FileAttributes]::ReparsePoint
    if (($item.Attributes -band $reparse) -eq $reparse) {
        return $true
    }

    if ($item.PSIsContainer) {
        $child = Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { ($_.Attributes -band $reparse) -eq $reparse } |
            Select-Object -First 1
        if ($child) {
            return $true
        }
    }

    return $false
}

function Remove-OptimizerManagedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AllowAuto', 'PendingConfirm')]
        [string]$RequiredDecision,

        [int]$AgeDays = 0,

        [switch]$ProjectFolderIdle,

        [int]$AgentArtifactMinAgeDays = 14,

        [int]$LogRetentionDays = 14,

        [switch]$CachedDataEligibleForPrune,

        [string]$CursorUserHome,

        [string]$CursorAppData,

        [string]$TempRoot
    )

    $policyParams = @{
        Path                    = $Path
        AgeDays                 = $AgeDays
        AgentArtifactMinAgeDays = $AgentArtifactMinAgeDays
        LogRetentionDays        = $LogRetentionDays
    }
    if ($ProjectFolderIdle) { $policyParams['ProjectFolderIdle'] = $true }
    if ($CachedDataEligibleForPrune) { $policyParams['CachedDataEligibleForPrune'] = $true }
    if ($CursorUserHome) { $policyParams['CursorUserHome'] = $CursorUserHome }
    if ($CursorAppData) { $policyParams['CursorAppData'] = $CursorAppData }
    if ($TempRoot) { $policyParams['TempRoot'] = $TempRoot }

    $decision = Get-OptimizerPathDecision @policyParams
    $target = $decision.Path

    if ($decision.Decision -ne $RequiredDecision) {
        return [pscustomobject]@{
            Deleted = $false
            Path    = $target
            Reason  = "decision-mismatch:$($decision.Decision)"
        }
    }

    if (-not (Test-Path -LiteralPath $target)) {
        return [pscustomobject]@{
            Deleted = $false
            Path    = $target
            Reason  = 'missing'
        }
    }

    if (Test-OptimizerReparsePath -Path $target) {
        return [pscustomobject]@{
            Deleted = $false
            Path    = $target
            Reason  = 'reparse-point'
        }
    }

    try {
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{
            Deleted = $false
            Path    = $target
            Reason  = 'delete-failed'
        }
    }

    if (Test-Path -LiteralPath $target) {
        return [pscustomobject]@{
            Deleted = $false
            Path    = $target
            Reason  = 'still-present'
        }
    }

    return [pscustomobject]@{
        Deleted = $true
        Path    = $target
        Reason  = 'ok'
    }
}
