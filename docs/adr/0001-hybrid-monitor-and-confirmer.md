# ADR 0001: Hybrid Monitor + Confirmer

## Status

Accepted (2026-08-18)

## Context

We need a Cursor resource optimizer that watches disk/RAM, reclaims safe space, and does not interfere with active project work. Research shows Cursor Automations are cloud-only and cannot own local `%APPDATA%\Cursor` cleanup; mechanical allow-list deletes fit a script better than an LLM.

## Decision

1. **Monitor** — local PowerShell (or Python) scheduled script: inventory, dry-run, safe allow-list deletes, RAM-first reporting when disk is critical.
2. **Confirmer** — Cursor Agent skill invoked only for gray-area / confirm-required paths (not for routine cache prune).
3. **Boundary** — never touch project source trees; agent artifacts under `~\.cursor\projects\` are in scope for cleanup policy.

## Consequences

- Two components to maintain (script + skill).
- Cloud offload remains optional for heavy compute; it does not replace local cleanup.
- Deny-list and path roots are enforced in code (`Get-OptimizerPathDecision` + `Remove-OptimizerManagedPath`). The Confirmer skill must call that helper; a prompt alone cannot bypass Deny.
