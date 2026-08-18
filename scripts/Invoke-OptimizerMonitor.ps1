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

function Expand-EnvPath([string]$p) {
    [Environment]::ExpandEnvironmentVariables($p)
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
    $letter = $driveLetter.TrimEnd(':')
    $vol = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$letter`:'"
    if (-not $vol) { throw "Volume $driveLetter not found" }
    return @{ Total = [long]$vol.Size; Free = [long]$vol.FreeSpace }
}

function Get-AvailableRamBytes {
    $m = Get-CimInstance -ClassName Win32_OperatingSystem
    return [long]$m.FreePhysicalMemory * 1KB
}

$configRaw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$queuePath = Expand-EnvPath $configRaw.queuePath
$reportPath = Expand-EnvPath $configRaw.reportPath

$drive = @($configRaw.volumes)[0]
$vol = Get-VolumeBytes $drive
$ram = Get-AvailableRamBytes

$pressure = Get-OptimizerPressure `
    -TotalBytes $vol.Total `
    -FreeBytes $vol.Free `
    -AvailableRamBytes $ram `
    -WarnFreePercent ([double]$configRaw.warnFreePercent) `
    -CriticalFreePercent ([double]$configRaw.criticalFreePercent) `
    -CriticalFreeGB ([double]$configRaw.criticalFreeGB) `
    -MinAvailableRamGB ([double]$configRaw.minAvailableRamGB)

$cursorRunning = Test-CursorRunning
$candidates = @()

$roaming = Join-Path $env:APPDATA 'Cursor'
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
        if ($age -ge [int]$configRaw.logRetentionDays) {
            $candidates += [pscustomobject]@{ Path = $_.FullName; AgeDays = $age; ProjectFolderIdle = $false }
        }
    }
}

$cachedData = Join-Path $roaming 'CachedData'
if (Test-Path -LiteralPath $cachedData) {
    $versions = @(Get-ChildItem -LiteralPath $cachedData -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($versions.Count -gt 2) {
        $versions | Select-Object -Skip 2 | ForEach-Object {
            $candidates += [pscustomobject]@{ Path = $_.FullName; AgeDays = (Get-DirAgeDays $_.FullName); ProjectFolderIdle = $false }
        }
    }
}

$projectsRoot = Join-Path $env:USERPROFILE '.cursor\projects'
if (Test-Path -LiteralPath $projectsRoot) {
    Get-ChildItem -LiteralPath $projectsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $projAge = Get-DirAgeDays $_.FullName
        $idle = $projAge -ge [int]$configRaw.agentArtifactMinAgeDays
        foreach ($name in @('terminals', 'agent-tools', 'agent-transcripts', 'canvases')) {
            $p = Join-Path $_.FullName $name
            if (Test-Path -LiteralPath $p) {
                $candidates += [pscustomobject]@{
                    Path              = $p
                    AgeDays           = (Get-DirAgeDays $p)
                    ProjectFolderIdle = $idle
                }
            }
        }
    }
}

$sandbox = Join-Path $env:TEMP 'cursor-sandbox-cache'
if (Test-Path -LiteralPath $sandbox) {
    $candidates += [pscustomobject]@{ Path = $sandbox; AgeDays = (Get-DirAgeDays $sandbox); ProjectFolderIdle = $false }
}

$agentCli = Join-Path $roaming 'User\globalStorage\anysphere.cursor-agent-worker'
if (Test-Path -LiteralPath $agentCli) {
    $candidates += [pscustomobject]@{ Path = $agentCli; AgeDays = (Get-DirAgeDays $agentCli); ProjectFolderIdle = $false }
}

$enqueue = -not [bool]$NoEnqueue
$report = New-OptimizerMonitorReport `
    -Pressure $pressure `
    -Candidates $candidates `
    -QueuePath $queuePath `
    -EnqueuePending:$enqueue `
    -AgentArtifactMinAgeDays ([int]$configRaw.agentArtifactMinAgeDays)

$report | Add-Member -NotePropertyName CursorRunning -NotePropertyValue $cursorRunning -Force
$report | Add-Member -NotePropertyName CandidateCount -NotePropertyValue $candidates.Count -Force

# User-facing console lines (ASCII). Russian copy lives in skills/README (ADR 0004).
Write-Host ("Optimizer Monitor | disk: {0} | free: {1}% ({2} GB) | avail RAM ~{3} GB" -f `
    $pressure.Level, $pressure.FreePercent, $pressure.FreeGB, $pressure.AvailableRamGB)
Write-Host ("AllowAuto: {0} | PendingConfirm: {1} | Deny: {2} | mode: {3}" -f `
    @($report.AllowAuto).Count, @($report.PendingConfirm).Count, @($report.Deny).Count, $report.Mode)
if ($report.PreferInMemoryReport) {
    Write-Host 'RAM-first: skipping report file write while disk is critical and RAM is available.'
}

$shouldWriteReport = -not ($report.PreferInMemoryReport -and [bool]$configRaw.preferInMemoryReport)
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

# Deletes require BOTH -ApplyAllowList and config.applyAllowList=true (scheduled tasks stay dry-run otherwise).
$doApply = $ApplyAllowList -and ([bool]$configRaw.applyAllowList)
if ($doApply) {
    if ([bool]$configRaw.requireCursorQuit -and $cursorRunning) {
        Write-Host 'AllowAuto delete skipped: Cursor is running (requireCursorQuit).'
    }
    else {
        foreach ($item in @($report.AllowAuto)) {
            if (Test-Path -LiteralPath $item.Path) {
                Remove-Item -LiteralPath $item.Path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Deleted: $($item.Path)"
            }
        }
    }
}
else {
    Write-Host 'Dry-run: no deletes. Pending items go through the Confirmer skill.'
}

if ($queuePath -and (Test-Path -LiteralPath $queuePath)) {
    Write-Host "Pending queue: $queuePath"
}

return $report
