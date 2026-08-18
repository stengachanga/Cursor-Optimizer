# Requires Pester 3.x (Windows built-in)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path (Split-Path -Parent $here) 'src'
. (Join-Path $src 'Optimizer.Policy.ps1')

$script:PolicyRoots = @{
    CursorUserHome = 'C:\Users\x\.cursor'
    CursorAppData  = 'C:\Users\x\AppData\Roaming\Cursor'
    TempRoot       = 'C:\Users\x\AppData\Local\Temp'
}

function Invoke-TestPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$AgeDays = 0,
        [switch]$ProjectFolderIdle,
        [switch]$CachedDataEligibleForPrune
    )
    $p = @{
        Path           = $Path
        AgeDays        = $AgeDays
        CursorUserHome = $script:PolicyRoots.CursorUserHome
        CursorAppData  = $script:PolicyRoots.CursorAppData
        TempRoot       = $script:PolicyRoots.TempRoot
    }
    if ($ProjectFolderIdle) { $p['ProjectFolderIdle'] = $true }
    if ($CachedDataEligibleForPrune) { $p['CachedDataEligibleForPrune'] = $true }
    Get-OptimizerPathDecision @p
}

Describe 'Get-OptimizerPathDecision' {
    It 'denies state.vscdb' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\AppData\Roaming\Cursor\User\globalStorage\state.vscdb'
        $r.Decision | Should Be 'Deny'
    }

    It 'allows Cursor Cache under AppData' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\AppData\Roaming\Cursor\Cache'
        $r.Decision | Should Be 'AllowAuto'
    }

    It 'requires confirm for agent-transcripts' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\.cursor\projects\foo\agent-transcripts'
        $r.Decision | Should Be 'PendingConfirm'
    }

    It 'allows idle project terminals older than 14 days' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\.cursor\projects\foo\terminals' -AgeDays 20 -ProjectFolderIdle
        $r.Decision | Should Be 'AllowAuto'
    }

    It 'does not auto-clean young terminals' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\.cursor\projects\foo\terminals' -AgeDays 3 -ProjectFolderIdle
        $r.Decision | Should Be 'Deny'
    }

    It 'requires confirm for cursor-sandbox-cache' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\AppData\Local\Temp\cursor-sandbox-cache\abc'
        $r.Decision | Should Be 'PendingConfirm'
    }

    It 'denies paths that look like project source' {
        $r = Invoke-TestPolicy -Path 'C:\Users\example\Projects\DemoApp\src\index.ts'
        $r.Decision | Should Be 'Deny'
    }

    It 'denies Cache parent-traversal after canonicalization' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\AppData\Roaming\Cursor\Cache\..\..\..\Projects\DemoApp'
        $r.Decision | Should Be 'Deny'
        $r.Reason | Should Be 'project-source-or-unknown'
    }

    It 'denies young log folders' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\AppData\Roaming\Cursor\logs\2026-08-01'
        $r.Decision | Should Be 'Deny'
    }

    It 'allows old log folders' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\AppData\Roaming\Cursor\logs\2026-08-01' -AgeDays 20
        $r.Decision | Should Be 'AllowAuto'
    }

    It 'denies live CachedData unless marked prunable' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\AppData\Roaming\Cursor\CachedData\abc'
        $r.Decision | Should Be 'Deny'
    }

    It 'allows prunable CachedData hashes' {
        $r = Invoke-TestPolicy -Path 'C:\Users\x\AppData\Roaming\Cursor\CachedData\abc' -CachedDataEligibleForPrune
        $r.Decision | Should Be 'AllowAuto'
    }

    It 'denies project temp path that only matches substring cursor' {
        $r = Invoke-TestPolicy -Path 'C:\Users\example\Projects\app\temp\cursor-sandbox-cache\x'
        $r.Decision | Should Be 'Deny'
    }
}
