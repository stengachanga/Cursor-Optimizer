$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$src = Join-Path $root 'src'
. (Join-Path $src 'Optimizer.Policy.ps1')
. (Join-Path $src 'Optimizer.Delete.ps1')

$script:PolicyRoots = @{
    CursorUserHome = 'C:\Users\x\.cursor'
    CursorAppData  = 'C:\Users\x\AppData\Roaming\Cursor'
    TempRoot       = 'C:\Users\x\AppData\Local\Temp'
}

Describe 'Remove-OptimizerManagedPath' {
    $tempRoot = Join-Path $env:TEMP ("optimizer-delete-tests-" + [guid]::NewGuid().ToString('N'))

    BeforeEach {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $tempRoot) { Remove-Item -Recurse -Force $tempRoot }
    }

    It 'deletes an allow-listed cache directory under Cursor AppData' {
        $cursorRoot = Join-Path $tempRoot 'AppData\Roaming\Cursor'
        $cache = Join-Path $cursorRoot 'Cache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cache 'f.txt') -Value 'x'

        $r = Remove-OptimizerManagedPath -Path $cache -RequiredDecision AllowAuto `
            -CursorUserHome (Join-Path $tempRoot '.cursor') `
            -CursorAppData $cursorRoot `
            -TempRoot (Join-Path $tempRoot 'Temp')
        $r.Deleted | Should Be $true
        (Test-Path -LiteralPath $cache) | Should Be $false
    }

    It 'refuses deny-list paths' {
        $cursorRoot = Join-Path $tempRoot 'AppData\Roaming\Cursor'
        $db = Join-Path $cursorRoot 'User\globalStorage'
        New-Item -ItemType Directory -Path $db -Force | Out-Null
        $file = Join-Path $db 'state.vscdb'
        Set-Content -LiteralPath $file -Value 'x'

        $r = Remove-OptimizerManagedPath -Path $file -RequiredDecision AllowAuto `
            -CursorUserHome (Join-Path $tempRoot '.cursor') `
            -CursorAppData $cursorRoot `
            -TempRoot (Join-Path $tempRoot 'Temp')
        $r.Deleted | Should Be $false
        $r.Reason | Should Match 'decision-mismatch'
        (Test-Path -LiteralPath $file) | Should Be $true
    }

    It 'refuses AllowAuto when RequiredDecision is PendingConfirm' {
        $cursorRoot = Join-Path $tempRoot 'AppData\Roaming\Cursor'
        $cache = Join-Path $cursorRoot 'Cache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null

        $r = Remove-OptimizerManagedPath -Path $cache -RequiredDecision PendingConfirm `
            -CursorUserHome (Join-Path $tempRoot '.cursor') `
            -CursorAppData $cursorRoot `
            -TempRoot (Join-Path $tempRoot 'Temp')
        $r.Deleted | Should Be $false
        (Test-Path -LiteralPath $cache) | Should Be $true
    }

    It 'refuses parent-traversal that leaves Cursor AppData' {
        $cursorRoot = Join-Path $tempRoot 'AppData\Roaming\Cursor'
        $cache = Join-Path $cursorRoot 'Cache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        $escape = Join-Path $cache '..\..\..\secret'
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'secret') -Force -ErrorAction SilentlyContinue | Out-Null

        $r = Remove-OptimizerManagedPath -Path $escape -RequiredDecision AllowAuto `
            -CursorUserHome (Join-Path $tempRoot '.cursor') `
            -CursorAppData $cursorRoot `
            -TempRoot (Join-Path $tempRoot 'Temp')
        $r.Deleted | Should Be $false
    }
}
