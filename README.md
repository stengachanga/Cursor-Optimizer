# Cursor Optimizer

Hybrid **Monitor** (PowerShell) + **Confirmer** (Cursor skill) for reclaiming Cursor caches without touching project source.

## Quick start

```powershell
cd "PLACEHOLDER_REPO"
# dry-run inventory + enqueue pending confirmations
.\scripts\Invoke-OptimizerMonitor.ps1

# register logon + daily tasks
.\scripts\Register-OptimizerTask.ps1
```

Link the Confirmer skill:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.cursor\skills" | Out-Null
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.cursor\skills\optimizer-confirm" `
  -Target "PLACEHOLDER_REPO\skills\optimizer-confirm" -Force
```

(If symlink needs admin, copy the folder instead.)

Then in Cursor: ask the agent to run **optimizer-confirm** against the pending queue.

## Tests

```powershell
Invoke-Pester -Path .\tests
```

## Config

`config\optimizer.json` — thresholds, dry-run, queue/report paths. Deleting allow-listed paths requires **both** `"applyAllowList": true` **and** `-ApplyAllowList` on the script.
