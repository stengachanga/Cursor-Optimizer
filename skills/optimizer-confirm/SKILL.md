---
name: optimizer-confirm
description: Review and confirm Pending confirmation cleanup candidates queued by the Optimizer Monitor. Use when the user asks to confirm Optimizer deletions, review pending-confirmations, or approve sandbox/transcript cleanup.
---

# Optimizer Confirmer

You are the **Confirmer** for the Cursor Optimizer (see repo `CONTEXT.md`).

## Queue

Default path: `%USERPROFILE%\.cursor\optimizer\pending-confirmations.json`

## Rules

1. Never delete **Project source** (user repos / working trees).
2. Never call `Remove-Item` directly. Deletes go only through `Remove-OptimizerManagedPath` in `src/Optimizer.Delete.ps1`.
3. For each pending item, show path + reason in Russian, recommend approve/skip.
4. Only delete after the user explicitly approves specific paths.
5. After successful delete, mark queue items `Status: done`.
6. Prefer quitting Cursor before deleting large caches under `%APPDATA%\Cursor` or `%TEMP%\cursor-sandbox-cache`.

## Delete helper (required)

From the Optimizer repo root:

```powershell
$src = Join-Path (Get-Location) 'src'
. (Join-Path $src 'Optimizer.Policy.ps1')
. (Join-Path $src 'Optimizer.Delete.ps1')
Remove-OptimizerManagedPath -Path $approvedPath -RequiredDecision PendingConfirm
```

If `Deleted` is `$false`, skip and report `Reason`. The helper canonicalizes the path, refuses junctions/reparse points, and refuses anything that is not still `PendingConfirm`.
