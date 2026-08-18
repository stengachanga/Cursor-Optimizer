# Public seam: New-OptimizerMonitorReport
# Depends on: Get-OptimizerPathDecision, Add-OptimizerPendingConfirmation

function New-OptimizerMonitorReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Pressure,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Candidates,

        [string]$QueuePath,

        [switch]$EnqueuePending,

        [int]$AgentArtifactMinAgeDays = 14,

        [int]$LogRetentionDays = 14,

        [string]$CursorUserHome,

        [string]$CursorAppData,

        [string]$TempRoot,

        [switch]$UseCloudAgentsForHeavyWork
    )

    if ($AgentArtifactMinAgeDays -le 0) { $AgentArtifactMinAgeDays = 14 }
    if ($LogRetentionDays -le 0) { $LogRetentionDays = 14 }

    $allowAuto = @()
    $pending = @()
    $deny = @()

    foreach ($c in @($Candidates)) {
        if ($null -eq $c) { continue }

        $idle = $false
        if ($c.PSObject.Properties.Name -contains 'ProjectFolderIdle') {
            $idle = [bool]$c.ProjectFolderIdle
        }
        $age = 0
        if ($c.PSObject.Properties.Name -contains 'AgeDays') {
            $age = [int]$c.AgeDays
        }
        $prune = $false
        if ($c.PSObject.Properties.Name -contains 'CachedDataEligibleForPrune') {
            $prune = [bool]$c.CachedDataEligibleForPrune
        }

        $decisionParams = @{
            Path                     = [string]$c.Path
            AgeDays                  = $age
            AgentArtifactMinAgeDays  = $AgentArtifactMinAgeDays
            LogRetentionDays         = $LogRetentionDays
        }
        if ($idle) { $decisionParams['ProjectFolderIdle'] = $true }
        if ($prune) { $decisionParams['CachedDataEligibleForPrune'] = $true }
        if ($CursorUserHome) { $decisionParams['CursorUserHome'] = $CursorUserHome }
        if ($CursorAppData) { $decisionParams['CursorAppData'] = $CursorAppData }
        if ($TempRoot) { $decisionParams['TempRoot'] = $TempRoot }

        $d = Get-OptimizerPathDecision @decisionParams
        $entry = [pscustomobject]@{
            Path                         = $d.Path
            Decision                     = $d.Decision
            Reason                       = $d.Reason
            AgeDays                      = $age
            ProjectFolderIdle            = $idle
            CachedDataEligibleForPrune   = $prune
        }

        switch ($d.Decision) {
            'AllowAuto' { $allowAuto += $entry }
            'PendingConfirm' {
                $pending += $entry
                if ($EnqueuePending -and -not [string]::IsNullOrWhiteSpace($QueuePath)) {
                    Add-OptimizerPendingConfirmation -QueuePath $QueuePath -TargetPath $d.Path -Reason $d.Reason | Out-Null
                }
            }
            default { $deny += $entry }
        }
    }

    $prefer = $false
    if ($null -ne $Pressure -and ($Pressure.PSObject.Properties.Name -contains 'PreferInMemoryReport')) {
        $prefer = [bool]$Pressure.PreferInMemoryReport
    }

    $hint = 'Cloud offload is off by default; prefer Cloud Agents for heavy work.'
    if ($UseCloudAgentsForHeavyWork) {
        $hint = 'Cloud offload is enabled: prefer Cloud Agents for heavy regenerable work.'
    }

    return [pscustomobject]@{
        GeneratedAt           = (Get-Date).ToString('o')
        Pressure              = $Pressure
        PreferInMemoryReport  = $prefer
        AllowAuto             = $allowAuto
        PendingConfirm        = $pending
        Deny                  = $deny
        Mode                  = 'dry-run'
        CloudOffloadHint      = $hint
    }
}
