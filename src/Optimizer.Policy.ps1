# Optimizer path policy — AllowAuto | PendingConfirm | Deny
# Public seam: Get-OptimizerPathDecision, Get-OptimizerCanonicalPath, Test-OptimizerUnderRoot

function Get-OptimizerCanonicalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    try {
        return [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $null
    }
}

function Test-OptimizerUnderRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullPath,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $pathFull = Get-OptimizerCanonicalPath -Path $FullPath
    $rootFull = Get-OptimizerCanonicalPath -Path $Root
    if (-not $pathFull -or -not $rootFull) {
        return $false
    }

    $prefix = $rootFull.TrimEnd('\') + '\'
    $p = $pathFull.TrimEnd('\')
    return $p.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $p.Equals($rootFull.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-OptimizerDefaultRoots {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        CursorUserHome = Join-Path $env:USERPROFILE '.cursor'
        CursorAppData  = Join-Path $env:APPDATA 'Cursor'
        TempRoot       = $env:TEMP
    }
}

function Get-OptimizerPathDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [int]$AgeDays = 0,

        [switch]$ProjectFolderIdle,

        [int]$AgentArtifactMinAgeDays = 14,

        [int]$LogRetentionDays = 14,

        [switch]$CachedDataEligibleForPrune,

        [string]$CursorUserHome,

        [string]$CursorAppData,

        [string]$TempRoot
    )

    $defaults = Get-OptimizerDefaultRoots
    if ([string]::IsNullOrWhiteSpace($CursorUserHome)) { $CursorUserHome = $defaults.CursorUserHome }
    if ([string]::IsNullOrWhiteSpace($CursorAppData)) { $CursorAppData = $defaults.CursorAppData }
    if ([string]::IsNullOrWhiteSpace($TempRoot)) { $TempRoot = $defaults.TempRoot }

    if ($AgentArtifactMinAgeDays -le 0) { $AgentArtifactMinAgeDays = 14 }
    if ($LogRetentionDays -le 0) { $LogRetentionDays = 14 }

    $canonical = Get-OptimizerCanonicalPath -Path $Path
    $resultPath = if ($canonical) { $canonical } else { $Path }

    $mk = {
        param($Decision, $Reason)
        [pscustomobject]@{
            Path     = $resultPath
            Decision = $Decision
            Reason   = $Reason
        }
    }

    if (-not $canonical) {
        return & $mk 'Deny' 'invalid-path'
    }

    $lower = $canonical.ToLowerInvariant()
    $inHome = Test-OptimizerUnderRoot -FullPath $canonical -Root $CursorUserHome
    $inAppData = Test-OptimizerUnderRoot -FullPath $canonical -Root $CursorAppData
    $inTemp = Test-OptimizerUnderRoot -FullPath $canonical -Root $TempRoot
    if (-not ($inHome -or $inAppData -or $inTemp)) {
        return & $mk 'Deny' 'project-source-or-unknown'
    }

    $denyPatterns = @(
        '\\state\.vscdb',
        '\\mcp\.json$',
        '\\settings\.json$',
        '\\\.cursor\\skills(\\|$)',
        '\\\.cursor\\skills-cursor(\\|$)',
        '\\\.agents\\skills(\\|$)',
        '\\user\\history(\\|$)'
    )
    foreach ($pat in $denyPatterns) {
        if ($lower -match $pat) {
            return & $mk 'Deny' 'deny-list'
        }
    }

    $pendingPatterns = @(
        '\\agent-transcripts(\\|$)',
        '\\canvases(\\|$)',
        '\\cursor-sandbox-cache(\\|$)',
        '\\anysphere\.cursor-agent-worker(\\|$)',
        '\\agent-cli(\\|$)'
    )
    foreach ($pat in $pendingPatterns) {
        if ($lower -match $pat) {
            return & $mk 'PendingConfirm' 'confirm-required'
        }
    }

    if ($lower -match '\\\.cursor\\projects\\[^\\]+\\(terminals|agent-tools)(\\|$)') {
        if ($ProjectFolderIdle -and $AgeDays -ge $AgentArtifactMinAgeDays) {
            return & $mk 'AllowAuto' 'idle-agent-artifact'
        }
        return & $mk 'Deny' 'agent-artifact-too-young-or-active'
    }

    if ($inAppData -and $lower -match '\\logs(\\|$)') {
        if ($AgeDays -ge $LogRetentionDays) {
            return & $mk 'AllowAuto' 'allow-list-logs'
        }
        return & $mk 'Deny' 'logs-too-young'
    }

    if ($inAppData -and $lower -match '\\cacheddata(\\|$)') {
        if ($CachedDataEligibleForPrune) {
            return & $mk 'AllowAuto' 'allow-list-cacheddata'
        }
        return & $mk 'Deny' 'cacheddata-keep-newest'
    }

    $allowPatterns = @(
        '\\appdata\\roaming\\cursor\\cache(\\|$)',
        '\\appdata\\roaming\\cursor\\gpucache(\\|$)',
        '\\appdata\\roaming\\cursor\\code cache(\\|$)',
        '\\appdata\\roaming\\cursor\\dawngraphitecache(\\|$)',
        '\\appdata\\roaming\\cursor\\dawnwebgpucache(\\|$)',
        '\\appdata\\roaming\\cursor\\cachedextensionvsixs(\\|$)'
    )
    foreach ($pat in $allowPatterns) {
        if ($inAppData -and $lower -match $pat) {
            return & $mk 'AllowAuto' 'allow-list'
        }
    }

    if ($inTemp -and $lower -match '\\vscode-stable-user-') {
        return & $mk 'AllowAuto' 'allow-list'
    }

    return & $mk 'Deny' 'unclassified'
}
