# Cursor Optimizer

Local **resource guardian** for [Cursor](https://cursor.com) on Windows: keeps the machine usable when agent caches, logs, and temp data grow, **without touching your project source trees**.

## Why it exists

Cursor (and its agents) write a lot under `%APPDATA%\Cursor`, `~\.cursor\projects\`, and `%TEMP%`. On a small system drive that quietly becomes “disk full,” which slows Windows (pagefile), breaks installs, and interrupts coding.

Official Cursor cleanup today is mainly **worktree** retention. There is no first-party “clear all Cursor caches” product for local app data. Cloud Automations cannot see or delete files on your PC.

This repo fills that gap with a **hybrid**:

| Piece | Role |
| --- | --- |
| **Monitor** | Scheduled PowerShell script: measures disk/RAM, classifies candidates, dry-runs by default |
| **Confirmer** | Cursor Agent skill: you approve gray-area deletes (sandbox cache, transcripts, …) |

Design goals:

- **Do not interfere with projects** — never delete repo/working-tree source
- **Safe by default** — dry-run; auto-delete only after explicit opt-in
- **RAM-first under disk pressure** — avoid writing large reports when free space is critical
- **Cloud offload is optional** — hint only by default; cloud does not reclaim local Cursor folders

## How it works

1. Monitor runs at Windows logon and daily (or on demand).
2. It inventories Cursor-related paths and labels each as **AllowAuto**, **PendingConfirm**, or **Deny**.
3. Pending items go to `%USERPROFILE%\.cursor\optimizer\pending-confirmations.json`.
4. You open Cursor and run the **optimizer-confirm** skill to review and approve.

### When you are needed

| Situation | User needed? |
| --- | --- |
| Routine dry-run Monitor | No |
| Allow-list cache prune after you opt in | No (quit Cursor first — otherwise deletes are skipped) |
| Sandbox cache, transcripts, canvases, agent-worker | **Yes** (Confirmer) |
| Deny-list / project source | Never deleted by design |
| One-time setup (schedule + skill link) | **Yes** |

## Quick start

```powershell
git clone https://github.com/stengachanga/Cursor-Optimizer.git
cd Cursor-Optimizer

# dry-run inventory (+ enqueue pending confirmations unless -NoEnqueue)
.\scripts\Invoke-OptimizerMonitor.ps1

# optional: logon + daily Task Scheduler jobs
.\scripts\Register-OptimizerTask.ps1
```

Link the Confirmer skill (from the clone directory):

```powershell
$skillSource = Join-Path (Get-Location) 'skills\optimizer-confirm'
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.cursor\skills" | Out-Null
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.cursor\skills\optimizer-confirm" `
  -Target $skillSource -Force
```

If creating a symlink requires elevation, copy the folder instead. Then in Cursor ask the agent to run **optimizer-confirm** against the pending queue.

## Tests

```powershell
Invoke-Pester -Path .\tests
```

## Config

`config\optimizer.json` — thresholds, dry-run, queue/report paths.

Deleting allow-listed paths requires **both** `"applyAllowList": true` **and** `-ApplyAllowList` on the script. Actual deletes go through `Remove-OptimizerManagedPath` (canonical path, Cursor roots only, no reparse points). The Confirmer skill must use that helper with `-RequiredDecision PendingConfirm` — never raw `Remove-Item`.

## Docs

- Domain language: [`CONTEXT.md`](CONTEXT.md)
- Architecture decisions: [`docs/adr/`](docs/adr/)
- Background research (sanitized): [`docs/cursor-disk-optimizer.md`](docs/cursor-disk-optimizer.md)

## Privacy

This repository is public. It must not contain machine-specific usernames, home paths, or secrets. Runtime reports and the pending queue live only on **your** machine under `%USERPROFILE%\.cursor\optimizer\` and are gitignored from this project by design (they are never part of the repo layout).

If you fork or contribute, keep examples generic (`C:\Users\example\...`, `%APPDATA%\Cursor`, …).
