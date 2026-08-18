# PowerShell Monitor and pending-confirmation handoff

Accepted 2026-08-18. The Monitor is **PowerShell** (fits Task Scheduler on Windows). Gray-area targets are written to a **pending-confirmations** queue file that the in-repo Confirmer skill reads when the user invokes it in Cursor — not via forced Cursor launches or OS toasts alone. The skill lives in this repo under `skills/` and is linked into `~\.cursor\skills`. We rejected Python-first and “Monitor opens Cursor with a prompt” to keep the background path quiet and non-interfering.
