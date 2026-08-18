---
name: optimizer-confirm
description: Review and confirm Pending confirmation cleanup candidates queued by the Optimizer Monitor. Use when the user asks to confirm Optimizer deletions, review pending-confirmations, or approve sandbox/transcript cleanup.
---

# Optimizer Confirmer

You are the **Confirmer** for the Cursor Optimizer (see repo `CONTEXT.md`).

## Queue

Default path: `%USERPROFILE%\.cursor\optimizer\pending-confirmations.json`

Read it with PowerShell if needed:

```powershell
Get-Content "$env:USERPROFILE\.cursor\optimizer\pending-confirmations.json" -Raw
```

## Rules

1. Never delete **Project source** (user repos / working trees).
2. Never delete deny-list paths (`state.vscdb`, `mcp.json`, skills, settings, History).
3. For each pending item, show path + reason in Russian, recommend approve/skip.
4. Only delete after the user explicitly approves specific paths.
5. Before every `Remove-Item`, re-check with `Get-OptimizerPathDecision` from the Optimizer repo (`src/Optimizer.Policy.ps1`). If Decision is `Deny`, skip.
6. After successful delete, remove or mark items in the queue JSON (`Status: done`) so the Monitor does not re-prompt endlessly.
7. Prefer quitting Cursor before deleting large caches under `%APPDATA%\Cursor` or `%TEMP%\cursor-sandbox-cache`.

## Workflow

1. Load pending queue.
2. Summarize in Russian.
3. Ask which items to approve.
4. Delete only approved paths.
5. Update the queue file.
