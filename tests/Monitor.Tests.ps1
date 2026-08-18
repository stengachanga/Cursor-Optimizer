$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$src = Join-Path $root 'src'
. (Join-Path $src 'Optimizer.Policy.ps1')
. (Join-Path $src 'Optimizer.Pressure.ps1')
. (Join-Path $src 'Optimizer.PendingQueue.ps1')
. (Join-Path $src 'Optimizer.Monitor.ps1')

Describe 'New-OptimizerMonitorReport' {
    $tempRoot = Join-Path $env:TEMP ("optimizer-monitor-tests-" + [guid]::NewGuid().ToString('N'))

    BeforeEach {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $tempRoot) { Remove-Item -Recurse -Force $tempRoot }
    }

    It 'groups candidates by policy decision without deleting' {
        $pressure = Get-OptimizerPressure -TotalBytes 100GB -FreeBytes 4GB -AvailableRamBytes 8GB `
            -WarnFreePercent 15 -CriticalFreePercent 10 -CriticalFreeGB 5 -MinAvailableRamGB 2
        $candidates = @(
            [pscustomobject]@{ Path = 'C:\Users\x\AppData\Roaming\Cursor\Cache'; AgeDays = 0; ProjectFolderIdle = $false },
            [pscustomobject]@{ Path = 'C:\Users\x\.cursor\projects\foo\agent-transcripts'; AgeDays = 40; ProjectFolderIdle = $true },
            [pscustomobject]@{ Path = 'C:\Users\example\Projects\DemoApp\src\main.ts'; AgeDays = 0; ProjectFolderIdle = $false }
        )
        $queuePath = Join-Path $tempRoot 'pending-confirmations.json'
        $report = New-OptimizerMonitorReport -Pressure $pressure -Candidates $candidates -QueuePath $queuePath -EnqueuePending `
            -CursorUserHome 'C:\Users\x\.cursor' `
            -CursorAppData 'C:\Users\x\AppData\Roaming\Cursor' `
            -TempRoot 'C:\Users\x\AppData\Local\Temp'

        $report.Pressure.Level | Should Be 'Critical'
        $report.PreferInMemoryReport | Should Be $true
        @($report.AllowAuto).Count | Should Be 1
        @($report.PendingConfirm).Count | Should Be 1
        @($report.Deny).Count | Should Be 1
        @($report.AllowAuto)[0].Path | Should Match 'Cache$'
        @(Get-OptimizerPendingConfirmations -QueuePath $queuePath).Count | Should Be 1
    }

    It 'does not enqueue when EnqueuePending is omitted' {
        $pressure = Get-OptimizerPressure -TotalBytes 100GB -FreeBytes 40GB -AvailableRamBytes 8GB `
            -WarnFreePercent 15 -CriticalFreePercent 10 -CriticalFreeGB 5 -MinAvailableRamGB 2
        $candidates = @(
            [pscustomobject]@{ Path = 'C:\Users\x\AppData\Local\Temp\cursor-sandbox-cache\h'; AgeDays = 10; ProjectFolderIdle = $false }
        )
        $queuePath = Join-Path $tempRoot 'pending-confirmations.json'
        $report = New-OptimizerMonitorReport -Pressure $pressure -Candidates $candidates -QueuePath $queuePath `
            -CursorUserHome 'C:\Users\x\.cursor' `
            -CursorAppData 'C:\Users\x\AppData\Roaming\Cursor' `
            -TempRoot 'C:\Users\x\AppData\Local\Temp'
        @($report.PendingConfirm).Count | Should Be 1
        @(Get-OptimizerPendingConfirmations -QueuePath $queuePath).Count | Should Be 0
    }
}
