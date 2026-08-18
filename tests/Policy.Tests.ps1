# Requires Pester 3.x (Windows built-in)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path (Split-Path -Parent $here) 'src'
. (Join-Path $src 'Optimizer.Policy.ps1')

Describe 'Get-OptimizerPathDecision' {
    It 'denies state.vscdb' {
        $r = Get-OptimizerPathDecision -Path 'C:\Users\x\AppData\Roaming\Cursor\User\globalStorage\state.vscdb'
        $r.Decision | Should Be 'Deny'
    }

    It 'allows Cursor Cache under AppData' {
        $r = Get-OptimizerPathDecision -Path 'C:\Users\x\AppData\Roaming\Cursor\Cache'
        $r.Decision | Should Be 'AllowAuto'
    }

    It 'requires confirm for agent-transcripts' {
        $r = Get-OptimizerPathDecision -Path 'C:\Users\x\.cursor\projects\foo\agent-transcripts'
        $r.Decision | Should Be 'PendingConfirm'
    }

    It 'allows idle project terminals older than 14 days' {
        $r = Get-OptimizerPathDecision -Path 'C:\Users\x\.cursor\projects\foo\terminals' -AgeDays 20 -ProjectFolderIdle
        $r.Decision | Should Be 'AllowAuto'
    }

    It 'does not auto-clean young terminals' {
        $r = Get-OptimizerPathDecision -Path 'C:\Users\x\.cursor\projects\foo\terminals' -AgeDays 3 -ProjectFolderIdle
        $r.Decision | Should Be 'Deny'
    }

    It 'requires confirm for cursor-sandbox-cache' {
        $r = Get-OptimizerPathDecision -Path 'C:\Users\x\AppData\Local\Temp\cursor-sandbox-cache\abc'
        $r.Decision | Should Be 'PendingConfirm'
    }

    It 'denies paths that look like project source' {
        $r = Get-OptimizerPathDecision -Path 'C:\Users\example\Projects\DemoApp\src\index.ts'
        $r.Decision | Should Be 'Deny'
    }
}
