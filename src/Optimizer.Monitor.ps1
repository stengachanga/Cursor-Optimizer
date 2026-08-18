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

        [int]$AgentArtifactMinAgeDays = 14
    )

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

        if ($idle) {
            $d = Get-OptimizerPathDecision -Path ([string]$c.Path) -AgeDays $age -AgentArtifactMinAgeDays $AgentArtifactMinAgeDays -ProjectFolderIdle
        }
        else {
            $d = Get-OptimizerPathDecision -Path ([string]$c.Path) -AgeDays $age -AgentArtifactMinAgeDays $AgentArtifactMinAgeDays
        }

        $entry = [pscustomobject]@{
            Path     = $d.Path
            Decision = $d.Decision
            Reason   = $d.Reason
            AgeDays  = $age
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

    return [pscustomobject]@{
        GeneratedAt           = (Get-Date).ToString('o')
        Pressure              = $Pressure
        PreferInMemoryReport  = $prefer
        AllowAuto             = $allowAuto
        PendingConfirm        = $pending
        Deny                  = $deny
        Mode                  = 'dry-run'
        CloudOffloadHint      = 'Cloud offload is off by default; prefer Cloud Agents for heavy work.'
    }
}
