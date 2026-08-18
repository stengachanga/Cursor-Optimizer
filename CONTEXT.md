# Optimizer

Keeps a Windows Cursor machine usable by reclaiming safe space without touching project source trees.

## Language

**Monitor**:
The local scheduled process that measures disk and RAM and applies allow-listed cleanup.
_Avoid_: daemon, watcher, cleaner (alone)

**Confirmer**:
The Cursor Agent skill used only when a cleanup target requires explicit confirmation.
_Avoid_: reviewer, approver, agent (alone)

**Project source**:
Files inside the user's working trees and repositories. Out of scope for cleanup.
_Avoid_: codebase, workspace files (ambiguous with Cursor project folders)

**Agent artifact**:
Session or tool metadata under `~\.cursor\projects\<id>\` (for example terminals and agent-tools). Not project source.
_Avoid_: cache (too broad), project folder

**Allow-list**:
Paths the Monitor may delete automatically after policy checks (age, Cursor quit, dry-run rules).
_Avoid_: safe list, whitelist

**Deny-list**:
Paths the Monitor must never delete automatically (settings, MCP, skills, state DB, and confirm-only artifacts).
_Avoid_: blocklist, blacklist

**RAM-first mode**:
Operating mode when free disk is critical and available RAM is above a floor: reports stay in memory and large disk writes are avoided.
_Avoid_: in-memory mode, swap-avoidance

**Cloud offload**:
Sending heavy regenerable compute to Cursor Cloud Agents or Automations so local resources stay freer. Does not reclaim local Cursor app data.
_Avoid_: cloud cleanup, remote delete

**Pending confirmation**:
A queued cleanup candidate the Monitor will not apply until the Confirmer records approval.
_Avoid_: todo, ticket, approval request
