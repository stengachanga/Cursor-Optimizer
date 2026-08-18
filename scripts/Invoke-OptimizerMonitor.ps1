# Discovers Cursor-related candidates and builds a dry-run Monitor report.
# Does not delete unless -ApplyAllowList is passed AND config.applyAllowList is true.

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\optimizer.json'),
    [switch]$ApplyAllowList,
    [switch]$NoEnqueue
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src'
. (Join-Path $src 'Optimizer.Policy.ps1')
. (Join-Path $src 'Optimizer.Pressure.ps1')
. (Join-Path $src 'Optimizer.PendingQueue.ps1')
. (Join-Path $src 'Optimizer.Monitor.ps1')
. (Join-Path $src 'Optimizer.Delete.ps1')

function Expand-EnvPath([string]$p) {
    [Environment]::ExpandEnvironmentVariables($p)
}

function Get-OptimizerPositiveInt($value, [int]$default) {
    if ($null -eq $value -or $value -eq '') { return $default }
    try {
        $n = [int]$value
    }
    catch {
        return $default
    }
    if ($n -le 0) { return $default }
    return $n
}

function Get-OptimizerConfigBool($obj, [string]$name, [bool]$default) {
    if ($obj.PSObject.Properties.Name -notcontains $name) { return $default }
    return [bool]$obj.$name
}

function Test-CursorRunning {
    return $null -ne (Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-DirAgeDays([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    $item = Get-Item -LiteralPath $path -Force
    return [int]((Get-Date) - $item.LastWriteTime).TotalDays
}

function Get-VolumeBytes([string]$driveLetter) {
    $letter = ($driveLetter.TrimEnd(':')).ToUpperInvariant()
    if ($letter -notmatch '^[A-Z]$') {
        throw "Invalid volume '$driveLetter'"
    }
    $vol = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$letter`:'"
    if (-not $vol) { throw "Volume $driveLetter not found" }
    return @{ Total = [long]$vol.Size; Free = [long]$vol.FreeSpace }
}

function Get-AvailableRamBytes {
    try {
        if (-not ('OptimizerNativeMemory' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class OptimizerNativeMemory {
  [StructLayout(LayoutKind.Sequential)]
  public struct MEMORYSTATUSEX {
    public uint dwLength;
    public uint dwMemoryLoad;
    public ulong ullTotalPhys;
    public ulong ullAvailPhys;
    public ulong ullTotalPageFile;
    public ulong ullAvailPageFile;
    public ulong ullTotalVirtual;
    public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
  }
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
}
"@
        }
        $ms = New-Object OptimizerNativeMemory+MEMORYSTATUSEX
        $ms.dwLength = 64
        if ([OptimizerNativeMemory]::GlobalMemoryStatusEx([ref]$ms)) {
            return [long]$ms.ullAvailPhys
        }
    }
    catch {
        # fall through
    }
    $m = Get-CimInstance -ClassName Win32_OperatingSystem
    return [long]$m.FreePhysicalMemory * 1KB
}

$configRaw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$queuePath = Expand-EnvPath $configRaw.queuePath
$reportPath = Expand-EnvPath $configRaw.reportPath
$logRetentionDays = Get-OptimizerPositiveInt $configRaw.logRetentionDays 14
$artifactMinAge = Get-OptimizerPositiveInt $configRaw.agentArtifactMinAgeDays 14
$preferInMemory = Get-OptimizerConfigBool $configRaw 'preferInMemoryReport' $true
$useCloud = Get-OptimizerConfigBool $configRaw 'useCloudAgentsForHeavyWork' $false
$applyAllowListCfg = Get-OptimizerConfigBool $configRaw 'applyAllowList' $false
$requireCursorQuit = Get-OptimizerConfigBool $configRaw 'requireCursorQuit' $true

$drive = @($configRaw.volumes)[0]
$vol = Get-VolumeBytes $drive
$ram = Get-AvailableRamBytes

$pressure = Get-OptimizerPressure `
    -TotalBytes $vol.Total `
    -FreeBytes $vol.Free `
    -AvailableRamBytes $ram `
    -WarnFreePercent ([double](Get-OptimizerPositiveInt $configRaw.warnFreePercent 15)) `
    -CriticalFreePercent ([double](Get-OptimizerPositiveInt $configRaw.criticalFreePercent 10)) `
    -CriticalFreeGB ([double](Get-OptimizerPositiveInt $configRaw.criticalFreeGB 5)) `
    -MinAvailableRamGB ([double](Get-OptimizerPositiveInt $configRaw.minAvailableRamGB 2))

$cursorRunning = Test-CursorRunning
$candidates = @()
$roots = Get-OptimizerDefaultRoots

$roaming = $roots.CursorAppData
$allowRoots = @(
    (Join-Path $roaming 'Cache'),
    (Join-Path $roaming 'GPUCache'),
    (Join-Path $roaming 'Code Cache'),
    (Join-Path $roaming 'DawnGraphiteCache'),
    (Join-Path $roaming 'DawnWebGPUCache'),
    (Join-Path $roaming 'CachedExtensionVSIXs')
)
foreach ($p in $allowRoots) {
    if (Test-Path -LiteralPath $p) {
        $candidates += [pscustomobject]@{ Path = $p; AgeDays = (Get-DirAgeDays $p); ProjectFolderIdle = $false }
    }
}

$logsRoot = Join-Path $roaming 'logs'
if (Test-Path -LiteralPath $logsRoot) {
    Get-ChildItem -LiteralPath $logsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $age = Get-DirAgeDays $_.FullName
        $candidates += [pscustomobject]@{ Path = $_.FullName; AgeDays = $age; ProjectFolderIdle = $false }
    }
}

$cachedData = Join-Path $roaming 'CachedData'
if (Test-Path -LiteralPath $cachedData) {
    $versions = @(Get-ChildItem -LiteralPath $cachedData -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $i = 0
    foreach ($ver in $versions) {
        $eligible = $i -ge 2
        $candidates += [pscustomobject]@{
            Path                       = $ver.FullName
            AgeDays                    = (Get-DirAgeDays $ver.FullName)
            ProjectFolderIdle          = $false
            CachedDataEligibleForPrune = $eligible
        }
        $i++
    }
}

$projectsRoot = Join-Path $roots.CursorUserHome 'projects'
if (Test-Path -LiteralPath $projectsRoot) {
    Get-ChildItem -LiteralPath $projectsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($name in @('terminals', 'agent-tools', 'agent-transcripts', 'canvases')) {
            $p = Join-Path $_.FullName $name
            if (Test-Path -LiteralPath $p) {
                $artAge = Get-DirAgeDays $p
                $candidates += [pscustomobject]@{
                    Path              = $p
                    AgeDays           = $artAge
                    ProjectFolderIdle = ($artAge -ge $artifactMinAge)
                }
            }
        }
    }
}

$sandbox = Join-Path $roots.TempRoot 'cursor-sandbox-cache'
if (Test-Path -LiteralPath $sandbox) {
    $candidates += [pscustomobject]@{ Path = $sandbox; AgeDays = (Get-DirAgeDays $sandbox); ProjectFolderIdle = $false }
}

$agentCli = Join-Path $roaming 'User\globalStorage\anysphere.cursor-agent-worker'
if (Test-Path -LiteralPath $agentCli) {
    $candidates += [pscustomobject]@{ Path = $agentCli; AgeDays = (Get-DirAgeDays $agentCli); ProjectFolderIdle = $false }
}

$ramFirst = [bool]$pressure.PreferInMemoryReport -and $preferInMemory
$enqueue = (-not [bool]$NoEnqueue) -and (-not $ramFirst)
$cloudSwitch = @{ }
if ($useCloud) { $cloudSwitch['UseCloudAgentsForHeavyWork'] = $true }

$report = New-OptimizerMonitorReport `
    -Pressure $pressure `
    -Candidates $candidates `
    -QueuePath $queuePath `
    -EnqueuePending:$enqueue `
    -AgentArtifactMinAgeDays $artifactMinAge `
    -LogRetentionDays $logRetentionDays `
    -CursorUserHome $roots.CursorUserHome `
    -CursorAppData $roots.CursorAppData `
    -TempRoot $roots.TempRoot `
    @cloudSwitch

$report | Add-Member -NotePropertyName CursorRunning -NotePropertyValue $cursorRunning -Force
$report | Add-Member -NotePropertyName CandidateCount -NotePropertyValue $candidates.Count -Force

Write-Host ("Optimizer Monitor | disk: {0} | free: {1}% ({2} GB) | avail RAM ~{3} GB" -f `
    $pressure.Level, $pressure.FreePercent, $pressure.FreeGB, $pressure.AvailableRamGB)
Write-Host ("AllowAuto: {0} | PendingConfirm: {1} | Deny: {2} | mode: {3}" -f `
    @($report.AllowAuto).Count, @($report.PendingConfirm).Count, @($report.Deny).Count, $report.Mode)
if ($ramFirst) {
    Write-Host 'RAM-first: skipping report and pending-queue writes while disk is critical and RAM is available.'
}

$shouldWriteReport = -not $ramFirst
if ($shouldWriteReport) {
    $reportDir = Split-Path -Parent $reportPath
    if (-not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    ($report | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host "Report: $reportPath"
}
else {
    Write-Host 'Report not written to disk (RAM-first).'
}

$doApply = $ApplyAllowList -and $applyAllowListCfg
$deleted = 0
if ($doApply) {
    if ($requireCursorQuit -and $cursorRunning) {
        Write-Host 'AllowAuto delete skipped: Cursor is running (requireCursorQuit).'
    }
    else {
        foreach ($item in @($report.AllowAuto)) {
            $delParams = @{
                Path                    = $item.Path
                RequiredDecision        = 'AllowAuto'
                AgeDays                 = [int]$item.AgeDays
                AgentArtifactMinAgeDays = $artifactMinAge
                LogRetentionDays        = $logRetentionDays
                CursorUserHome          = $roots.CursorUserHome
                CursorAppData           = $roots.CursorAppData
                TempRoot                = $roots.TempRoot
            }
            if ($item.ProjectFolderIdle) { $delParams['ProjectFolderIdle'] = $true }
            if ($item.CachedDataEligibleForPrune) { $delParams['CachedDataEligibleForPrune'] = $true }
            $result = Remove-OptimizerManagedPath @delParams
            if ($result.Deleted) {
                $deleted++
                Write-Host "Deleted: $($result.Path)"
            }
            else {
                Write-Host "Skipped $($result.Path) ($($result.Reason))"
            }
        }
    }
}
else {
    Write-Host 'Dry-run: no deletes. Pending items go through the Confirmer skill.'
}

if ($doApply -and $deleted -gt 0) {
    $report.Mode = 'delete-safe'
}

if ($queuePath -and (Test-Path -LiteralPath $queuePath)) {
    Write-Host "Pending queue: $queuePath"
}

return $report
