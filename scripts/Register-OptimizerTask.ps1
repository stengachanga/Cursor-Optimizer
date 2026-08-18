# Registers Task Scheduler jobs: at logon + daily.
[CmdletBinding()]
param(
    [string]$TaskNamePrefix = 'CursorOptimizer',
    [string]$DailyTime = '09:00'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$monitor = Join-Path $PSScriptRoot 'Invoke-OptimizerMonitor.ps1'
if (-not (Test-Path -LiteralPath $monitor)) {
    throw "Monitor script not found: $monitor"
}

$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$monitor`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

$logonTrigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName "$TaskNamePrefix-AtLogon" -Action $action -Trigger $logonTrigger -Settings $settings -Force | Out-Null

$dailyTrigger = New-ScheduledTaskTrigger -Daily -At $DailyTime
Register-ScheduledTask -TaskName "$TaskNamePrefix-Daily" -Action $action -Trigger $dailyTrigger -Settings $settings -Force | Out-Null

Write-Host "Registered: $TaskNamePrefix-AtLogon, $TaskNamePrefix-Daily ($DailyTime)"
Write-Host "Monitor: $monitor"
