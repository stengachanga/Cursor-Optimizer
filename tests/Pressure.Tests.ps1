$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path (Split-Path -Parent $here) 'src'
. (Join-Path $src 'Optimizer.Pressure.ps1')

Describe 'Get-OptimizerPressure' {
    It 'is Critical when free percent below critical threshold' {
        $r = Get-OptimizerPressure -TotalBytes 100GB -FreeBytes 4GB -AvailableRamBytes 8GB `
            -WarnFreePercent 15 -CriticalFreePercent 10 -CriticalFreeGB 5 -MinAvailableRamGB 2
        $r.Level | Should Be 'Critical'
        $r.PreferInMemoryReport | Should Be $true
    }

    It 'is Warn when between warn and critical percent' {
        $r = Get-OptimizerPressure -TotalBytes 100GB -FreeBytes 12GB -AvailableRamBytes 8GB `
            -WarnFreePercent 15 -CriticalFreePercent 10 -CriticalFreeGB 5 -MinAvailableRamGB 2
        $r.Level | Should Be 'Warn'
        $r.PreferInMemoryReport | Should Be $false
    }

    It 'is Normal when plenty of free space' {
        $r = Get-OptimizerPressure -TotalBytes 100GB -FreeBytes 40GB -AvailableRamBytes 8GB `
            -WarnFreePercent 15 -CriticalFreePercent 10 -CriticalFreeGB 5 -MinAvailableRamGB 2
        $r.Level | Should Be 'Normal'
    }

    It 'is Critical by absolute free GB even if percent looks ok on small disks' {
        # 50GB disk, 4GB free = 8% anyway; use large disk with low absolute free
        $r = Get-OptimizerPressure -TotalBytes 500GB -FreeBytes 4GB -AvailableRamBytes 8GB `
            -WarnFreePercent 15 -CriticalFreePercent 10 -CriticalFreeGB 5 -MinAvailableRamGB 2
        $r.Level | Should Be 'Critical'
    }

    It 'disables PreferInMemoryReport when RAM below floor even if disk critical' {
        $r = Get-OptimizerPressure -TotalBytes 100GB -FreeBytes 4GB -AvailableRamBytes 1GB `
            -WarnFreePercent 15 -CriticalFreePercent 10 -CriticalFreeGB 5 -MinAvailableRamGB 2
        $r.Level | Should Be 'Critical'
        $r.PreferInMemoryReport | Should Be $false
    }
}
