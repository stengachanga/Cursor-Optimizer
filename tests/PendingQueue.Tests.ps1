$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$src = Join-Path $root 'src'
. (Join-Path $src 'Optimizer.PendingQueue.ps1')

Describe 'Optimizer pending queue' {
    $tempRoot = Join-Path $env:TEMP ("optimizer-queue-tests-" + [guid]::NewGuid().ToString('N'))

    BeforeEach {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $tempRoot) {
            Remove-Item -Recurse -Force $tempRoot
        }
    }

    It 'adds a pending confirmation and reads it back' {
        $queuePath = Join-Path $tempRoot 'pending-confirmations.json'
        Add-OptimizerPendingConfirmation -QueuePath $queuePath -TargetPath 'C:\Temp\cursor-sandbox-cache\a' -Reason 'confirm-required'
        $items = @(Get-OptimizerPendingConfirmations -QueuePath $queuePath)
        $items.Count | Should Be 1
        $items[0].Path | Should Be 'C:\Temp\cursor-sandbox-cache\a'
        $items[0].Reason | Should Be 'confirm-required'
    }

    It 'does not duplicate the same path' {
        $queuePath = Join-Path $tempRoot 'pending-confirmations.json'
        Add-OptimizerPendingConfirmation -QueuePath $queuePath -TargetPath 'C:\Temp\x' -Reason 'r1'
        Add-OptimizerPendingConfirmation -QueuePath $queuePath -TargetPath 'C:\Temp\x' -Reason 'r2'
        $items = @(Get-OptimizerPendingConfirmations -QueuePath $queuePath)
        $items.Count | Should Be 1
        $items[0].Reason | Should Be 'r1'
    }

    It 'returns empty list when file missing' {
        $queuePath = Join-Path $tempRoot 'missing.json'
        $items = @(Get-OptimizerPendingConfirmations -QueuePath $queuePath)
        $items.Count | Should Be 0
    }
}
