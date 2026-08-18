# Optimizer path policy — AllowAuto | PendingConfirm | Deny
# Public seam: Get-OptimizerPathDecision

function Get-OptimizerPathDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [int]$AgeDays = 0,

        [switch]$ProjectFolderIdle,

        [int]$AgentArtifactMinAgeDays = 14
    )

    $normalized = $Path -replace '/', '\'
    $lower = $normalized.ToLowerInvariant()

    $result = {
        param($Decision, $Reason)
        [pscustomobject]@{
            Path     = $Path
            Decision = $Decision
            Reason   = $Reason
        }
    }

    # Never touch project source trees (heuristic: not under .cursor / AppData\Roaming\Cursor / Temp cursor*)
    $isCursorHome = $lower -match '\\\.cursor\\'
    $isCursorAppData = $lower -match '\\appdata\\roaming\\cursor\\'
    $isCursorTemp = $lower -match '\\temp\\cursor' -or $lower -match '\\temp\\vscode-stable-user-'
    if (-not ($isCursorHome -or $isCursorAppData -or $isCursorTemp)) {
        return & $result 'Deny' 'project-source-or-unknown'
    }

    # Deny-list (hard)
    $denyPatterns = @(
        '\\state\.vscdb',
        '\\mcp\.json$',
        '\\settings\.json$',
        '\\\.cursor\\skills\\',
        '\\\.cursor\\skills-cursor\\',
        '\\\.agents\\skills\\',
        '\\user\\history\\'
    )
    foreach ($pat in $denyPatterns) {
        if ($lower -match $pat) {
            return & $result 'Deny' 'deny-list'
        }
    }

    # Pending confirmation
    $pendingPatterns = @(
        '\\agent-transcripts(\\|$)',
        '\\canvases(\\|$)',
        'cursor-sandbox-cache',
        '\\anysphere\.cursor-agent-worker\\',
        '\\agent-cli(\\|$)'
    )
    foreach ($pat in $pendingPatterns) {
        if ($lower -match $pat) {
            return & $result 'PendingConfirm' 'confirm-required'
        }
    }

    # Agent artifacts: terminals / agent-tools — AllowAuto only if idle + old enough
    if ($lower -match '\\.cursor\\projects\\[^\\]+\\(terminals|agent-tools)(\\|$)') {
        if ($ProjectFolderIdle -and $AgeDays -ge $AgentArtifactMinAgeDays) {
            return & $result 'AllowAuto' 'idle-agent-artifact'
        }
        return & $result 'Deny' 'agent-artifact-too-young-or-active'
    }

    # Allow-list caches / logs / temps
    $allowPatterns = @(
        '\\appdata\\roaming\\cursor\\cache(\\|$)',
        '\\appdata\\roaming\\cursor\\gpucache(\\|$)',
        '\\appdata\\roaming\\cursor\\code cache(\\|$)',
        '\\appdata\\roaming\\cursor\\dawngraphitecache(\\|$)',
        '\\appdata\\roaming\\cursor\\dawnwebgpucache(\\|$)',
        '\\appdata\\roaming\\cursor\\cachedextensionvsixs(\\|$)',
        '\\appdata\\roaming\\cursor\\cacheddata\\',
        '\\appdata\\roaming\\cursor\\logs\\',
        '\\temp\\vscode-stable-user-'
    )
    foreach ($pat in $allowPatterns) {
        if ($lower -match $pat) {
            return & $result 'AllowAuto' 'allow-list'
        }
    }

    return & $result 'Deny' 'unclassified'
}
