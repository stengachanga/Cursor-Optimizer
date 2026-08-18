# Cursor disk resource optimizer — research

**Date:** 2026-08-10 (inventory); **Addendum:** 2026-08-18 (RAM-aware policy + cloud offload)  
**Machine:** Windows 10/11, user `<local>`  
**Scope:** How to build a Cursor resource-optimization script/agent that monitors disk usage and safely deletes unnecessary data (caches, old copies, stale artifacts). Extended 2026-08-18 to cover **RAM-before-disk** behavior under low free space and **cloud offload** for heavy regenerable work.  
**Method:** Primary sources only — Cursor docs, VS Code / Electron docs, Microsoft Windows APIs, and local filesystem inspection on this machine.

## Verdict

Cursor already documents **one first-party local disk cleanup mechanism**: automatic Git **worktree** retention (`cursor.worktreeMaxCount` default 25, interval hours). There is **no official Cursor doc** describing a general “clear caches / reclaim disk” product feature for `%APPDATA%\Cursor` or `~/.cursor`. **Cursor Automations run cloud agents** and therefore **cannot** safely own *local* disk cleanup on this PC. On this machine, C: is critically low (**~5.6 GB free / ~4.8%**). The single largest measured Cursor-related consumer is **`%TEMP%\cursor-sandbox-cache` (~13.8 GB)**, followed by **`User\globalStorage\state.vscdb` (~798 MB)**, **`anysphere.cursor-agent-worker\agent-cli` (~524 MB)**, and **`logs` (~453 MB)** — not the small Chromium `Cache`/`GPUCache` folders. The recommended architecture is a **hybrid**: a **local PowerShell (or Python) scheduled monitor** (Task Scheduler) that inventories + dry-runs safe deletes, plus an optional **local Cursor Agent skill** for human-in-the-loop review before irreversible removals.

**Addendum (2026-08-18):** When free disk is critical, the monitor should treat **available RAM as the preferred working medium** — inventory/report in memory, avoid large temp/log writes, and skip delete paths that create new temp files — grounded in Windows commit/pagefile needing free disk to grow ([page-file sizing](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows), [`ullAvailPhys`](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex)). Pure-RAM cleanup **cannot** shrink on-disk `state.vscdb`, `agent-cli`, or pagefile growth needs; those remain local FS problems. **Cloud Agents / Automations / SDK `cloud:`** can absorb regenerable compute (clone, build, re-index-like work, agent runs) in isolated VMs so local disk/RAM stay freer, but they **cannot** delete `%APPDATA%\Cursor` or free local logs ([Automations](https://cursor.com/docs/cloud-agent/automations), [Cloud Agents](https://cursor.com/docs/cloud-agent), [SDK](https://cursor.com/docs/sdk/typescript)).

## Inventory (Windows)

Sizes below were measured on this machine via PowerShell recursive `Length` sums (top-level / sampled). They are approximate snapshots as of 2026-08-10 and can change while Cursor is running.

**Volume pressure (primary):** `C:` ≈ **117.29 GB** total, **5.6 GB** free (**4.8%**). Source: local `Get-CimInstance Win32_LogicalDisk` (Win32 API family documented by Microsoft as `GetDiskFreeSpaceExW`).

| Path | Role (inferred + docs) | Size (this machine) | Safety class | Source |
| --- | --- | --- | --- | --- |
| `%USERPROFILE%\.cursor\` | Cursor user home: MCP, skills, projects metadata, extensions | ~43 MB top-level sum | **Mixed** — config irreversible; project caches regenerable | Local listing |
| `%USERPROFILE%\.cursor\mcp.json` | MCP server config | ~0 | **Never auto-delete** | Local; MCP docs |
| `%USERPROFILE%\.cursor\argv.json`, `ide_state.json` | IDE argv / UI state | ~0 | **Settings/state** — do not auto-delete | Local |
| `%USERPROFILE%\.cursor\skills\`, `skills-cursor\`, `%USERPROFILE%\.agents\skills\` | Agent skills | small / user skills present | **Never auto-delete** (user content) | Local; [Skills](https://cursor.com/docs/skills) |
| `%USERPROFILE%\.cursor\extensions\` | User extensions dir (Cursor analogue of VS Code extensions) | ~5.3 MB | **Regenerable** (reinstall) but disruptive | Local; VS Code extensions location pattern |
| `%USERPROFILE%\.cursor\plugins\` | Plugins | ~2.6 MB | **Caution** — may be regenerable via marketplace | Local |
| `%USERPROFILE%\.cursor\ai-tracking\` | AI tracking data | ~8.8 MB | **Caution** — undocumented locally; treat as state | Local only |
| `%USERPROFILE%\.cursor\projects\` | Per-workspace agent artifacts (transcripts, terminals, tools) | ~25.8 MB; **17** project folders; **13** with `agent-transcripts`, **14** with `terminals` | **User data / irreversible** for transcripts; terminals regenerable | Local sample: `...\projects\c-example-project\{agent-transcripts,agent-tools,canvases,mcps,terminals}` |
| `%USERPROFILE%\.cursor\worktrees\` | Documented worktree root (`~/.cursor/worktrees/<repo>/<name>`) | **MISSING** | Built-in cleanup when present | [Worktrees](https://cursor.com/docs/configuration/worktrees); [CLI using](https://cursor.com/docs/cli/using) |
| `%USERPROFILE%\.cursor\cursorfs-clone\` | Speculative clone path | **MISSING** | N/A | Local check |
| `%USERPROFILE%\AppData\Roaming\Cursor\` | Electron/VS Code–style **userData** for app name `Cursor` | ~1.95+ GB dominant children | Mixed | Local; Electron `userData` = `%APPDATA%\<AppName>` |
| `...\Roaming\Cursor\User\globalStorage\state.vscdb` (+ wal/shm/backup) | Primary VS Code/Cursor SQLite state DB (chats/UI state live here in practice) | **~798 MB** + backup **~26 MB** + WAL | **Never auto-delete**; vacuum only with Cursor quit + backup | Local |
| `...\globalStorage\anysphere.cursor-agent-worker\agent-cli` | Agent CLI worker payload/cache | **~524 MB** | **Likely regenerable** but **undocumented** — dry-run + confirm; quit Cursor first | Local only (no Cursor doc naming this path) |
| `...\globalStorage\anysphere.cursor-retrieval\checkpoints` | Retrieval checkpoints | **~11 MB** | **Caution** — regenerable via re-index?, undocumented | Local |
| `...\globalStorage\conversation-search.db*` | Conversation search index | ~7 MB | **Caution** — regenerable search index?, keep if unsure | Local |
| `...\User\workspaceStorage\` | Per-workspace extension/state storage | ~7.7 MB | **Caution** — loses workspace UI state | Local; VS Code extension storage APIs |
| `...\User\History\` | Local file history (Timeline) | ~2.6 MB | **User-recoverable history** — confirm before delete | Local; [VS Code UI / local history](https://code.visualstudio.com/docs/editing/userinterface) |
| `...\User\settings.json`, `snippets\` | User settings / snippets | ~0 | **Never auto-delete** | Local; [VS Code settings](https://code.visualstudio.com/docs/configure/settings) |
| `...\Roaming\Cursor\logs\` | Session logs (dated folders) | **~453 MB**; folders from 2026-05..2026-08 | **Safe after age threshold** if Cursor closed for active folder | Local |
| `...\CachedData\` | Chromium/VS Code versioned cached data | **~56 MB**; **12** version hash dirs (May–Aug 2026) | **Safe to prune old versions**; keep newest / currently used | Local |
| `...\Cache\`, `GPUCache\`, `Code Cache\`, `Dawn*Cache\` | Chromium disk caches | ~10.7 + 5.6 + ~0 + ~1 MB | **Safe regenerable cache** (quit app first) | Local; Electron documents `Cache`/`GPUCache` under `userData`/`sessionData` |
| `...\CachedExtensionVSIXs\` | Cached extension VSIX downloads | ~0 on this machine | **Safe regenerable** | Local |
| `...\Partitions\cursor-browser\` | Browser partition (Cursor browser) | contributes to ~49 MB Partitions | **Caution** — may wipe browser session data | Local |
| `...\Backups\`, `Workspaces\`, `blob_storage\`, `Crashpad\` | Backups / workspace stubs / blobs / crashes | ~0 measured | Backups: **caution**; Crashpad: usually safe | Local |
| `%USERPROFILE%\AppData\Local\Cursor` | Alternate LocalAppData app dir | **MISSING** | N/A | Local |
| `%TEMP%\cursor\` | Temp Cursor screenshots etc. | ~0 MB | **Safe regenerable** when idle | Local |
| `%TEMP%\cursor-sandbox-cache\` | Sandbox cache (hash subdirs) | **~13,786 MB (~13.8 GB)**; 9 hash folders observed | **Likely largest reclaim**; regenerable but **undocumented** — quit Cursor, dry-run, confirm before bulk delete | Local measure 2026-08-10 |
| `%TEMP%\cursor-mcp-*` | MCP Chrome/devtools temp | present | **Safe-ish regenerable** when idle | Local listing |
| `%TEMP%\vscode-stable-user-*` | VS Code/Cursor update extract dirs | **24** dirs observed | **Often safe** if old and unused; verify before bulk delete | Local listing |

### Safety class legend

| Class | Meaning |
| --- | --- |
| **Never auto-delete** | Irreversible user/config data without explicit confirmation |
| **User data / irreversible** | Chats/transcripts/history — delete only with confirmation + age policy |
| **Settings/state** | Breaks IDE continuity if removed |
| **Caution** | May be regenerable but undocumented or disruptive |
| **Safe regenerable cache** | Electron/Chromium/VS Code caches; recreated on next launch |
| **Safe after age threshold** | Logs/temps older than N days |

## Official docs findings

### Cursor (first-party)

- **Worktrees location & cleanup (local disk):** Cursor creates agent worktrees under `~/.cursor/worktrees/<repo>/<name>` (CLI + editor). Cleanup is automatic: `cursor.worktreeCleanupIntervalHours` (example 6) and `cursor.worktreeMaxCount` (**default 25**, machine-wide). Cleanup rediscovers worktrees including those from `/worktree` skills or `git worktree add`. Source: [Worktrees](https://cursor.com/docs/configuration/worktrees), [CLI using — CLI worktrees](https://cursor.com/docs/cli/using).
- **Automations = cloud agents:** “Cursor Automations run **cloud agents** in the background, either on a schedule or in response to events…”. They are billed as cloud agent usage and work against cloned repos / no-repo cloud environments — **not** the user’s local `%APPDATA%\Cursor` tree. Source: [Automations](https://cursor.com/docs/cloud-agent/automations).
- **Cloud retention ≠ local disk:** Cloud conversation history kept indefinitely by default; environment snapshots auto-delete after **90 days** inactivity; Delete Agent API removes conversation artifacts but **not** snapshots. Source: [Secrets & Network — Data retention](https://cursor.com/docs/cloud-agent/security-network).
- **Indexed codebases auto-expiry (server-side):** Enterprise hardening table states indexed codebases expire after **6 weeks inactivity** (links to search + snapshots docs). This is **cloud/index retention**, not a documented local-folder cleanup tool. Source: [Security hardening — Data retention](https://cursor.com/docs/enterprise/security-hardening). Search docs describe embeddings privacy, not local cache paths. Source: [Search](https://cursor.com/docs/agent/tools/search).
- **Skills / hooks / loop:** Skills can package scripts agents run ([Skills](https://cursor.com/docs/skills)). Hooks observe/block agent lifecycle locally via `~/.cursor/hooks.json` or project hooks; **user-level hooks are not available to cloud agents** ([Hooks](https://cursor.com/docs/agent/hooks)). Built-in `/loop` skill is **disabled in cloud** environments (local session recurring only) — local skill file `%USERPROFILE%\.cursor\skills-cursor\loop\SKILL.md`.
- **SDK local runtime:** Cursor SDK can run an agent loop against a **local working tree** (`Agent.create({ local: ... })`) while inference remains hosted — useful for a review agent, not a substitute for OS scheduling. Source: [SDK TypeScript / Python](https://cursor.com/docs/sdk/typescript) (fetched).

### VS Code (inherited patterns)

- User settings live under `%APPDATA%\Code\User\settings.json` on Windows; Cursor mirrors this under `%APPDATA%\Cursor\User\...`. Source: [User and workspace settings](https://code.visualstudio.com/docs/configure/settings).
- Portable mode documents Windows user data at `%APPDATA%\Code` and extensions at `%USERPROFILE%\.vscode\extensions` — Cursor’s analogous paths are `%APPDATA%\Cursor` and `%USERPROFILE%\.cursor\extensions` (observed locally). Source: [Portable mode](https://code.visualstudio.com/docs/setup/portable).
- **Local History** is stored in the user data folder for local files; settings include `workbench.localHistory.enabled`, `maxFileSize` (default 256 KB), `maxFileEntries` (default 50), etc. Commands include delete-all local history. Source: [User interface — Local file history](https://code.visualstudio.com/docs/editing/userinterface), [VS Code 1.66 release notes](https://code.visualstudio.com/updates/v1_66).
- Extension `globalStorageUri` / `storageUri` are the documented APIs behind `User\globalStorage` and `User\workspaceStorage`. Source: [Common Capabilities — Data Storage](https://code.visualstudio.com/api/extension-capabilities/common-capabilities).

### Electron / Chromium

- `app.getPath('userData')` defaults to `%APPDATA%\<AppName>` on Windows; Chromium may create **`Cache`**, **`GPUCache`**, **`Local Storage`**, etc. under that tree. `sessionData` (cookies, disk cache) defaults to `userData` and “Chromium may write **very large disk cache** here.” Source: [Electron `app.getPath`](https://www.electronjs.org/docs/latest/api/app).

### Microsoft Windows (monitoring & scheduling)

- Free space APIs: [`GetDiskFreeSpaceExW`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getdiskfreespaceexw); PowerShell [`Get-Volume`](https://learn.microsoft.com/en-us/powershell/module/storage/get-volume?view=windowsserver2025-ps); WMI/CIM `Win32_LogicalDisk` used in local measurement.
- Memory APIs (2026-08-18 addendum): [`GlobalMemoryStatusEx`](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-globalmemorystatusex) / [`MEMORYSTATUSEX`](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex) (`ullAvailPhys` = standby+free+zero, reusable without writing to disk first); [`SetProcessWorkingSetSize`](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setprocessworkingsetsize); pagefile growth & commit ([page file sizing](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows), [slow page file growth](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/slow-page-file-growth-memory-allocation-errors)); file mapping disk backing ([File Mapping](https://learn.microsoft.com/en-us/windows/win32/memory/file-mapping)).
- Scheduling: [`schtasks /create`](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create), PowerShell [`Register-ScheduledTask`](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps) / [`New-ScheduledTaskAction`](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskaction?view=windowsserver2025-ps).

### Explicit gaps (not found in official docs)

- No Cursor doc found that documents safe deletion of `CachedData`, `logs`, `state.vscdb`, `anysphere.cursor-agent-worker`, or `.cursor/projects/**/agent-transcripts`.
- No Cursor doc found for a product “Disk Cleanup” or log-retention setting for the desktop app.
- No Cursor doc found for in-memory-only Chromium cache mode, relocating `cursor-sandbox-cache`, or recommending RAM-disk `TMP`/`TEMP`.
- Claims about “delete X to free Y” from blogs/Reddit are **out of scope / unverified** per research rules.

## Safe deletion matrix

| Target | When | Risk | Auto? |
| --- | --- | --- | --- |
| `Roaming\Cursor\Cache`, `GPUCache`, `Code Cache`, `Dawn*Cache`, `CachedProfilesData` | Cursor **quit**; free space below threshold | Low — regenerable; may slow next start | Yes (after dry-run) |
| `CachedExtensionVSIXs` | Always when idle | Low — re-download on install | Yes |
| Old `CachedData\<hash>\` except newest / in-use version | Keep ≥1–2 newest hashes; age >14–30d | Medium if wrong hash deleted mid-update | Yes with keep-newest rule |
| `logs\` session folders older than **7–14 days** | Not the active session folder | Low for old logs; high if deleting today’s folder while running | Yes with age + skip-newest |
| `%TEMP%\cursor-sandbox-cache\` (old hash dirs) | Cursor quit; keep newest hash if actively used; age >7d for others | Medium — large reclaim (~13.8 GB here) but undocumented; may slow next sandboxed run | Confirm once, then allowlist age-prune |
| `%TEMP%\cursor*`, old `%TEMP%\vscode-stable-user-*` | Not locked; age >2–7 days | Medium — locked files fail; skip in-use | Yes with `-ErrorAction` + skip locked |
| Worktrees under `~/.cursor/worktrees` | Prefer **Cursor settings** first; manual only if over cap / orphaned | High — may delete uncommitted agent work | Prefer product cleanup; manual confirm |
| `.cursor\projects\<old>\terminals`, `agent-tools` | Project not opened >30–90d | Medium — loses debug context | Confirm / age |
| `.cursor\projects\<old>\agent-transcripts` | Explicit user confirm | **High** — chat history loss | **Never auto** |
| `User\History` | Prefer VS Code local-history settings/commands | High — loses restore points | Confirm |
| `User\workspaceStorage` orphans | Workspace path gone + age | Medium — loses per-workspace state | Confirm |
| `globalStorage\anysphere.cursor-agent-worker\agent-cli` | Cursor quit; after dry-run size report | Medium/undocumented — likely regenerable | Confirm once, then allowlist |
| `state.vscdb` / WAL / backup | Only specialized vacuum/backup procedure | **Critical** — can wipe chats/UI state | **Never auto-delete** |
| `mcp.json`, skills, rules, `settings.json` | Never via optimizer | Critical | Deny-list |

### Detecting “old copies”

1. **Worktrees:** Prefer `cursor.worktreeMaxCount` + product cleanup; optionally `git worktree list` per repo. Path pattern: `~/.cursor/worktrees/<repo>/<name>` ([docs](https://cursor.com/docs/configuration/worktrees)).
2. **CachedData versions:** Multiple hash directories under `CachedData\`; keep newest `LastWriteTime` / currently running Cursor version; delete older hashes.
3. **CachedExtensionVSIXs:** Duplicate/old VSIX files by name+mtime.
4. **Stale `.cursor\projects\*`:** Folder `LastWriteTime` + absence of matching open workspace; never delete transcripts without confirm.
5. **Update leftovers:** `%TEMP%\vscode-stable-user-*` directories with old mtime after successful update.
6. **Duplicate backups:** `state.vscdb.backup` vs live DB — do not delete backup unless live DB healthy and Cursor quit (**unverified** procedure beyond “don’t delete live DB”).

### Recommended thresholds (policy defaults — not Cursor-official)

| Signal | Suggested default |
| --- | --- |
| Warn free % | &lt; 15% |
| Aggressive free % | &lt; 10% |
| Critical free GB | &lt; 5 GB (this machine already here) |
| Log retention | 14 days |
| Temp retention | 7 days |
| CachedData keep | newest 2 versions |
| Projects metadata prune | 90 days, **exclude** transcripts from auto |
| Worktrees | use Cursor defaults (max 25) unless user overrides |

## Memory-aware policy (RAM before disk)

> **Addendum date:** 2026-08-18 — extends the 2026-08-10 inventory; does not replace prior path sizes or safety classes.

### Why disk-full and RAM interact (Windows primary sources)

- **Virtual memory / pagefile needs free disk.** System-managed page files grow with commit charge and crash-dump settings; Microsoft documents that growth assumes “the logical disk that is hosting the page file is large enough to accommodate the growth,” and that when commit charge exceeds ~90% of the commit limit the page file increases (up to 3× RAM or 4 GB, then volume-size limits, and can grow to within **1 GB of free space** for crash-dump settings). Source: [How to determine the appropriate page file size (64-bit Windows)](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows).
- **Slow/automatic pagefile growth → allocation failures.** Apps that allocate frequently can hit OOM when the page file must grow under “automatic” sizing. Source: [Memory allocation errors can be caused by slow page file growth (KB 4055223)](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/slow-page-file-growth-memory-allocation-errors).
- **Available physical RAM is explicitly “ready without writing to disk.”** `MEMORYSTATUSEX.ullAvailPhys` is “the amount of physical memory that can be immediately reused **without having to write its contents to disk first**. It is the sum of the size of the **standby, free, and zero lists**.” `dwMemoryLoad` is approximate % physical memory in use. Source: [`MEMORYSTATUSEX`](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex), [`GlobalMemoryStatusEx`](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-globalmemorystatusex).
- **Working-set trim is RAM pressure tooling, not disk cleanup.** `SetProcessWorkingSetSize` / `EmptyWorkingSet` remove pages from a process working set (optionally with both sizes = `(SIZE_T)-1`). That can increase *system* available RAM but may force dirty pages toward the **pagefile** (disk). Source: [`SetProcessWorkingSetSize`](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setprocessworkingsetsize), [Working Set](https://learn.microsoft.com/en-us/windows/win32/memory/working-set), [Process Working Set](https://learn.microsoft.com/en-us/windows/win32/procthread/process-working-set).
- **Memory-mapped files are still disk-backed.** File mapping associates a file on disk (or the system page file) with a view in memory; when pages are swapped out, changes are written to the backing file. Mapping size for a named file is **limited by disk space**; creating a mapping larger than the file can **expand the file on disk**. Source: [File Mapping](https://learn.microsoft.com/en-us/windows/win32/memory/file-mapping), [Creating a File Mapping Object](https://learn.microsoft.com/en-us/windows/win32/memory/creating-a-file-mapping-object).
- **Crash dumps / pagefile circular dependency.** Crash dump capture requires a page file (or dedicated dump file) large enough for the dump type; system-managed sizing during startup assumes enough free disk. Source: [page file size — Support for system crash dumps](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows).

**Circular failure mode (documented + inference):** Low free disk → pagefile cannot grow → commit/allocation failures and unstable apps → harder to run cleanup tools that themselves allocate or write temps. Prefer reclaiming disk *or* staying within `ullAvailPhys` without new commit that needs pagefile growth. Parts of this loop are **inference / unverified** as a single Microsoft “disk full” article; the pagefile growth + `ullAvailPhys` definitions are primary.

### Cursor / VS Code / Electron — reduce disk writes (documented only)

| Lever | What docs say | Disk-write impact | Source |
| --- | --- | --- | --- |
| **Local History** | `workbench.localHistory.enabled`, `maxFileSize` (default 256 KB), `maxFileEntries` (default 50), exclude/mergeWindow; history stored in user data folder | Disabling or lowering caps reduces `User\History` growth | [VS Code UI — Local file history](https://code.visualstudio.com/docs/editing/userinterface), [1.66 notes](https://code.visualstudio.com/updates/v1_66) |
| **Telemetry / crash reports** | `telemetry.telemetryLevel`: `all` / `error` / `crash` / `off` controls crash reports + error + usage; `off` silences telemetry including crash reporting (restart required per FAQ) | Stops *sending* crash telemetry; **does not document** deleting local `Crashpad` / dump dirs | [Telemetry](https://code.visualstudio.com/docs/configure/telemetry), [FAQ — disable crash reporting](https://code.visualstudio.com/docs/supporting/faq) |
| **Log verbosity** | Command **Developer: Set Log Level** (per channel / extension); CLI `--log` examples in release notes | Higher levels (**Trace**/**Debug**) increase log volume under `%APPDATA%\…\logs` — prefer **Info**/**Warning** when disk is critical | [VS Code 1.73 — Setting log level](https://code.visualstudio.com/updates/v1_73); Copilot troubleshooting documents Trace for diagnosis only ([Troubleshoot AI](https://code.visualstudio.com/docs/agents/agent-troubleshooting/troubleshooting)) |
| **Electron paths** | `userData` → `%APPDATA%\<AppName>`; `sessionData` holds cookies/**disk cache** (defaults to `userData`; Chromium may write **very large disk cache**); `temp`, `crashDumps` are separate `app.getPath` names | App authors can redirect `sessionData` away from `userData`; **no Cursor doc** exposes this to end users | [Electron `app.getPath`](https://www.electronjs.org/docs/latest/api/app) |
| **TMP / TEMP → RAM disk** | Electron exposes `temp`; Windows apps use process/user `TMP`/`TEMP` | **inference / unverified** for Cursor: redirecting TEMP to a RAM disk is not documented by Cursor/VS Code; only cite if the operator configures OS env and accepts RAM volatility | Electron `temp` path name only |

**Not found in official Cursor docs:** settings that switch Cursor’s Chromium disk cache to pure in-memory cache, or that relocate `%TEMP%\cursor-sandbox-cache` into RAM.

### Practical monitor policy (when disk low AND RAM available)

**Signals (primary APIs):**

1. Free disk % / GB — `GetDiskFreeSpaceExW` / `Get-Volume` / `Win32_LogicalDisk` (already in this doc).
2. Memory — `GlobalMemoryStatusEx` → `dwMemoryLoad`, `ullAvailPhys`, `ullAvailPageFile` ([docs](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-globalmemorystatusex)).

**Suggested policy defaults (policy — not OS/Cursor-official):**

| Condition | Behavior |
| --- | --- |
| Disk below `criticalFreePercent` / `criticalFreeGB` **and** `ullAvailPhys` above a floor (e.g. ≥ 2–4 GB) **and** `preferInMemoryReport: true` | Run **inventory / dry-run in memory**; emit summary to console / named pipe / Event Log **or** a tiny report; **do not** write multi-MB reports under `~\.cursor\research\disk-optimizer-reports\` |
| Same + delete mode | Prefer deletes that **free** space without creating temp copies (direct `Remove-Item` on allowlisted idle caches); **skip** tools that stage to `%TEMP%` or expand archives |
| Disk critical + RAM **low** | Do **not** inflate working set or map large files; only minimal inventory; prioritize freeing pagefile-hosting volume |
| Always | Stream / bounded buffers; avoid recursive `Measure-Object` dumps of `%TEMP%\cursor-sandbox-cache` (already noted as hang-prone on this machine) |

### What CANNOT be done purely in RAM

| Asset / mechanism | Why RAM-only fails | Source |
| --- | --- | --- |
| `state.vscdb` (+ WAL/shm/backup) | Lives on disk under `%APPDATA%\Cursor\User\globalStorage\`; never auto-delete | Local inventory (this file); no Cursor vacuum doc |
| `anysphere.cursor-agent-worker\agent-cli` | On-disk payload/cache (~524 MB here) | Local path only |
| `%APPDATA%\Cursor\logs`, Chromium `Cache`/`GPUCache` | Disk directories under Electron `userData`/`sessionData` | [Electron `app.getPath`](https://www.electronjs.org/docs/latest/api/app); local sizes |
| OS pagefile / commit growth | Needs free disk on the hosting volume | [page file sizing](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows) |
| Memory-mapped DB / large files | Views can dirty the backing file; size limited by disk | [File Mapping](https://learn.microsoft.com/en-us/windows/win32/memory/file-mapping) |

## Cloud offload for optimization operations

> **Addendum date:** 2026-08-18 — complements local cleanup; cloud does not replace local FS reclaim.

### What Cloud Agents / Automations CAN do

- Run in **isolated cloud VMs** with cloned repos, dependencies, secrets, builds/tests, desktop/browser computer use — **not** on the user’s laptop disk. Source: [Cloud Agents](https://cursor.com/docs/cloud-agent), [Capabilities](https://cursor.com/docs/cloud-agent/capabilities).
- **Automations** schedule or event-trigger those cloud agents (GitHub/GitLab/Slack/webhooks/Linear/etc.), optionally **no repository** for non-code workflows. Billed as cloud agent usage. Source: [Automations](https://cursor.com/docs/cloud-agent/automations).
- Produce PRs, artifacts (screenshots/videos/logs on cloud storage), remote desktop — so validation need not check out a branch **locally**. Source: [Capabilities](https://cursor.com/docs/cloud-agent/capabilities).
- **SDK:** `Agent.create({ cloud: { repos: [...] } })` or no-repo `cloud: { repos: [] }`; REST **Cloud Agents API** can launch/manage agents programmatically. Local runtime is separate (`local: { cwd }`). Source: [SDK TypeScript](https://cursor.com/docs/sdk/typescript), [Cloud Agents API](https://cursor.com/docs/cloud-agent/api/endpoints), [API v0 (legacy)](https://cursor.com/docs/cloud-agent/api/v0).

### What they CANNOT do (local disk honesty)

- Access **`%APPDATA%\Cursor`**, `~\.cursor` home hooks, or delete local `state.vscdb` / logs / temp sandbox cache. Cloud VMs “don’t have access to your local home directory”; **user-level hooks** from `~/.cursor/hooks.json` are unavailable to cloud agents. Source: [Cloud Agents — Hooks](https://cursor.com/docs/cloud-agent), [Hooks](https://cursor.com/docs/agent/hooks) (also noted in prior inventory).
- Therefore: **cloud cannot free local disk**. It helps by **not creating** local worktrees, local build artifacts, or local agent sandboxes for work that can run remotely.

### Hybrid design (local monitor + cloud compute)

```text
[Local Task Scheduler / PowerShell]
  ├─ measure free disk + GlobalMemoryStatusEx
  ├─ if disk critical: preferInMemoryReport; delete-safe allowlist only
  └─ if useCloudAgentsForHeavyWork: trigger Automation / SDK cloud / API
         for regenerable repo work (build, test, agent coding, re-fetch)
         → results as remote PR/artifacts; avoid local clone/worktree/build

[Cloud Agent VM]
  ├─ clone + build + agent loop + artifacts
  └─ never sees local Roaming\Cursor
```

**inference / unverified:** “Re-index” of a local codebase index is not documented as a cloud substitute for local `anysphere.cursor-retrieval\checkpoints`; official text covers **server-side indexed codebase expiry** (6 weeks inactivity), not relocating desktop index files. Source for expiry: [Security hardening — Data retention](https://cursor.com/docs/enterprise/security-hardening), [Search](https://cursor.com/docs/agent/tools/search).

### Cloud retention (already partially cited; restated)

| Data | Retention | Source |
| --- | --- | --- |
| Cloud conversation history | Indefinite by default; Enterprise can cap (e.g. 90 days) | [Secrets & Network — Data retention](https://cursor.com/docs/cloud-agent/security-network) |
| Environment snapshots | Max **90 days** inactivity (rolling on use); not deleted on demand via Delete Agent API | Same |
| Indexed codebases | Auto-expire after **6 weeks** inactivity | [Security hardening](https://cursor.com/docs/enterprise/security-hardening) |
| Delete Agent API | Removes conversation/artifacts; **not** snapshots | [security-network](https://cursor.com/docs/cloud-agent/security-network), [API endpoints](https://cursor.com/docs/cloud-agent/api/endpoints) |

### Honest limits summary

| Goal | Local script | Cloud Agents |
| --- | --- | --- |
| Free `%TEMP%\cursor-sandbox-cache`, logs, Chromium caches | Yes (with quit/dry-run) | No |
| Shrink `state.vscdb` | Specialized/unsafe; never auto | No |
| Avoid new local worktrees/builds while working | Partial (settings + discipline) | **Yes** — run work in cloud VM |
| Schedule disk inventory | Task Scheduler | Wrong tool |
| Heavy agent coding / CI-style loops | Burns local disk/RAM | Prefer cloud when `useCloudAgentsForHeavyWork` |

## Recommended architecture

### Option comparison

| Option | Feasibility for *local* FS cleanup | Pros | Cons | Primary sources |
| --- | --- | --- | --- | --- |
| **1. Local PowerShell/Python + Task Scheduler** | **Excellent** | Runs offline; cheap; full FS access; dry-run/logging; works when Cursor closed | No LLM judgment unless added | [schtasks](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create), [Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps), disk APIs |
| **2. Cursor Automation (scheduled)** | **Poor / wrong tool** | Good for cloud repo tasks, Slack, PRs | Runs **cloud agents**; no access to local `%APPDATA%\Cursor`; billed as cloud usage | [Automations](https://cursor.com/docs/cloud-agent/automations) |
| **3. Cursor Agent Skill / hook / CLI agent** | **Good as review layer** | Skill can encode allow/deny policy; hooks can block dangerous `rm`; `/loop` can recur in a **local** session; SDK local runtime | Skills need an agent session; hooks don’t schedule disk scans; cloud hooks ≠ home hooks | [Skills](https://cursor.com/docs/skills), [Hooks](https://cursor.com/docs/agent/hooks), loop skill (local-only), SDK |
| **4. Hybrid: monitor script + agent review** | **Best** | Deterministic inventory/delete of safe caches; agent only for gray-area paths; human confirm for transcripts/DB | Two components to maintain | All of the above |
| **5. Hybrid + RAM-aware + cloud offload** (2026-08-18) | **Best under disk pressure** | Local script owns disk+RAM signals and safe deletes; cloud absorbs regenerable compute so local worktrees/builds/sandbox caches grow less | Cloud billed; never frees `state.vscdb`/local logs; needs Git/API setup | [Automations](https://cursor.com/docs/cloud-agent/automations), [Cloud Agents](https://cursor.com/docs/cloud-agent), [SDK](https://cursor.com/docs/sdk/typescript), [GlobalMemoryStatusEx](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-globalmemorystatusex) |

### Recommendation

**Implement option 5 (extension of option 4): PowerShell scheduled script as the core, with RAM-before-disk reporting and optional cloud offload for heavy regenerable work.**

Rationale:

1. Official Automations cannot manage local Roaming/Local Cursor data ([Automations](https://cursor.com/docs/cloud-agent/automations)).
2. The largest reclaimable buckets on this PC (`logs`, Chromium caches, old `CachedData`, temp update dirs, possibly `agent-cli`) are **mechanical** age/hash rules — better as a script than an LLM.
3. Irreversible paths (transcripts, `state.vscdb`, MCP/skills) need a **deny-list** enforced in code, with optional local Agent skill for “review this dry-run report.”
4. Use Cursor’s **built-in worktree cleanup settings** rather than reinventing worktree GC ([Worktrees](https://cursor.com/docs/configuration/worktrees)).
5. **When C: is critical**, prefer `preferInMemoryReport` and avoid pagefile-stressing allocations ([page file sizing](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows), [`ullAvailPhys`](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex)).
6. **Offload** builds/agent coding/re-fetch to Cloud Agents / Automations / SDK `cloud:` so local disk and RAM are not the default compute plane ([Cloud Agents](https://cursor.com/docs/cloud-agent), [SDK](https://cursor.com/docs/sdk/typescript)).

## Concrete agent/script spec

### Inputs / config (`cursor-disk-optimizer.json`)

```json
{
  "volumes": ["C:"],
  "warnFreePercent": 15,
  "criticalFreePercent": 10,
  "criticalFreeGB": 5,
  "minAvailableRamGB": 2,
  "preferInMemoryReport": true,
  "useCloudAgentsForHeavyWork": false,
  "cloudOffloadHint": "When true, emit a structured hint / webhook to start a Cloud Agent or Automation for regenerable repo work instead of local agent/build loops",
  "mode": "dry-run",
  "requireCursorQuit": true,
  "logRetentionDays": 14,
  "tempRetentionDays": 7,
  "cachedDataKeepNewest": 2,
  "allowlist": [
    "%APPDATA%\\Cursor\\Cache",
    "%APPDATA%\\Cursor\\GPUCache",
    "%APPDATA%\\Cursor\\Code Cache",
    "%APPDATA%\\Cursor\\DawnGraphiteCache",
    "%APPDATA%\\Cursor\\DawnWebGPUCache",
    "%APPDATA%\\Cursor\\CachedExtensionVSIXs",
    "%APPDATA%\\Cursor\\logs",
    "%TEMP%\\cursor*",
    "%TEMP%\\cursor-sandbox-cache",
    "%TEMP%\\vscode-stable-user-*"
  ],
  "denylist": [
    "%USERPROFILE%\\.cursor\\mcp.json",
    "%USERPROFILE%\\.cursor\\skills",
    "%USERPROFILE%\\.cursor\\skills-cursor",
    "%USERPROFILE%\\.agents\\skills",
    "%APPDATA%\\Cursor\\User\\settings.json",
    "%APPDATA%\\Cursor\\User\\globalStorage\\state.vscdb*",
    "%USERPROFILE%\\.cursor\\projects\\**\\agent-transcripts",
    "%APPDATA%\\Cursor\\User\\History"
  ],
  "confirmRequired": [
    "%APPDATA%\\Cursor\\User\\globalStorage\\anysphere.cursor-agent-worker",
    "%USERPROFILE%\\.cursor\\projects",
    "%USERPROFILE%\\.cursor\\worktrees",
    "%APPDATA%\\Cursor\\User\\workspaceStorage",
    "%APPDATA%\\Cursor\\Partitions"
  ],
  "reportPath": "%USERPROFILE%\\.cursor\\research\\disk-optimizer-reports\\"
}
```

### Monitoring signals

1. **Free disk % and absolute free GB** via `Get-Volume` / `GetDiskFreeSpaceExW` / `Win32_LogicalDisk`.
2. **Available RAM / memory load / pagefile headroom** via `GlobalMemoryStatusEx` (`ullAvailPhys`, `dwMemoryLoad`, `ullAvailPageFile`) — gate `preferInMemoryReport` and refuse large buffered inventories when RAM is below `minAvailableRamGB`.
3. **Top offenders:** top-level sizes under `.cursor`, `Roaming\Cursor`, selected `%TEMP%\cursor*` (bounded / sampled when disk+RAM critical).
4. **Process gate:** refuse destructive mode if `Cursor.exe` (or related) is running when `requireCursorQuit` is true.
5. **Optional:** count of `CachedData` versions, age of oldest `logs\*` folder, worktree count if `~\.cursor\worktrees` exists.
6. **Optional cloud hint:** when `useCloudAgentsForHeavyWork` is true and disk is below warn/critical, append a report section recommending Cloud Agent / Automation / SDK `cloud:` for upcoming heavy work (does not itself free local disk).

### Actions (state machine)

1. **`inventory`** — measure + classify; write JSON/Markdown report **unless** `preferInMemoryReport` and disk critical (then keep result in memory / Event Log / stdout only).  
2. **`dry-run`** — compute deletion candidates against allowlist + age/hash rules; show bytes reclaimable; never delete.  
3. **`delete-safe`** — apply only allowlisted regenerable paths; skip locked files; log each path; **skip** delete helpers that stage large temps when disk critical.  
4. **`propose-confirm`** — emit a ticket/report for `confirmRequired` paths for human or local Agent skill review.  
5. **`cloud-offload-hint`** (optional) — when configured, fire webhook / print instructions to launch Automations or `Agent.create({ cloud: ... })` for regenerable compute.  
6. **Never** transition denylist paths to delete without an explicit separate CLI flag *and* interactive confirmation.

### Logging / reporting format

Write timestamped report to `~\.cursor\research\disk-optimizer-reports\YYYYMMDD-HHMMSS.md` (and `.json`):

```markdown
# Cursor disk optimizer report
- host, user, utc time
- volume free before/after
- mode: inventory|dry-run|delete-safe
- table: path | class | bytes | action | result
- errors: locked/access denied
```

### Windows-specific notes

- Prefer running scheduled task **at user logon / daily** with `Register-ScheduledTask` as the logged-on user so `%APPDATA%` / `%LOCALAPPDATA%` resolve correctly ([Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps)).
- Quit Cursor before deleting caches under `%APPDATA%\Cursor` to avoid file locks and DB corruption.
- Use `Remove-Item -LiteralPath` with careful handling of junctions; skip files returning sharing violations.
- Robocopy `/L` listing can estimate sizes without deleting; avoid unbounded recursive Measure-Object on `%TEMP%` (can hang — observed on this machine for sandbox cache).
- Configure product worktree GC in Cursor settings instead of scripting worktree deletes first.

### Optional local Agent skill (thin wrapper)

- Skill name e.g. `cursor-disk-optimizer`.
- Invoked manually or via `/loop` in a **local** session when free space critical.
- Reads latest dry-run report; asks user which `confirmRequired` items to approve; then shells the script with `--mode delete-safe` / `--approve path`.
- Do **not** implement this as a Cursor Automation (cloud).

## Open questions / unknowns

1. **Official semantics of `anysphere.cursor-agent-worker\agent-cli` (~524 MB)** — no Cursor doc found; regenerability unverified beyond local path inspection.
2. **Safe vacuum/compaction of `state.vscdb` (~798 MB)** — no first-party procedure found; deleting is unsafe; VACUUM while running is risky.
3. **Whether Cursor writes a separate `%LOCALAPPDATA%\Cursor`** on some installs — absent here; may appear with different update channels.
4. **`cursor-sandbox-cache` official retention** — measured at **~13.8 GB** locally (`%USERPROFILE%\AppData\Local\Temp\cursor-sandbox-cache`); no Cursor doc found on safe pruning of hash subdirs.
5. **Local retention for `.cursor\projects\agent-transcripts`** — no official retention policy found (unlike cloud 90-day snapshots / indefinite conversations).
6. **Exact mapping of chat history → `state.vscdb` vs other stores** — inferred from size/role; not documented in fetched Cursor pages.
7. **Indexed codebase “6 weeks inactivity”** ([security-hardening](https://cursor.com/docs/enterprise/security-hardening)) — clarified as automatic index expiry; relationship to local `anysphere.cursor-retrieval\checkpoints` is **unverified**.
8. **(2026-08-18) Cursor-documented in-memory Chromium / Electron cache mode** — not found; only Electron author APIs for `sessionData` relocation.
9. **(2026-08-18) Official Cursor guidance to put `TMP`/`TEMP` on a RAM disk** — not found; treat as operator OS config (**inference / unverified** for product safety).
10. **(2026-08-18) Whether Automations webhooks are intended as disk-monitor sinks** — Automations document webhook *triggers* into cloud agents ([Automations](https://cursor.com/docs/cloud-agent/automations)); using the local script to call Cloud Agents API is first-party for spawning work, but “disk optimizer → cloud” orchestration is **inference / unverified** as a product pattern.
11. **(2026-08-18) Exact free-disk threshold where Windows fails pagefile growth on this machine** — Microsoft documents growth-to-within-1 GB free and commit-driven growth; machine-specific failure point not measured in this addendum.

## Sources

1. https://cursor.com/docs/configuration/worktrees  
2. https://cursor.com/docs/cli/using  
3. https://cursor.com/docs/cloud-agent/automations  
4. https://cursor.com/docs/cloud-agent/security-network  
5. https://cursor.com/docs/enterprise/security-hardening  
6. https://cursor.com/docs/agent/tools/search  
7. https://cursor.com/docs/skills  
8. https://cursor.com/docs/agent/hooks  
9. https://cursor.com/docs/sdk/typescript  
10. https://cursor.com/docs/reference/ignore-file  
11. https://code.visualstudio.com/docs/configure/settings  
12. https://code.visualstudio.com/docs/setup/portable  
13. https://code.visualstudio.com/docs/editing/userinterface  
14. https://code.visualstudio.com/updates/v1_66  
15. https://code.visualstudio.com/api/extension-capabilities/common-capabilities  
16. https://www.electronjs.org/docs/latest/api/app  
17. https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getdiskfreespaceexw  
18. https://learn.microsoft.com/en-us/powershell/module/storage/get-volume?view=windowsserver2025-ps  
19. https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create  
20. https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps  
21. https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskaction?view=windowsserver2025-ps  
22. Local: `%USERPROFILE%\.cursor\` (listing + sizes)  
23. Local: `%USERPROFILE%\AppData\Roaming\Cursor\` (listing + sizes)  
24. Local: `%USERPROFILE%\AppData\Roaming\Cursor\User\globalStorage\` (state.vscdb, agent-worker, retrieval)  
25. Local: `%USERPROFILE%\.cursor\projects\` (17 folders; transcript/terminal presence)  
26. Local: `%USERPROFILE%\AppData\Local\Cursor` (missing)  
27. Local: `%USERPROFILE%\.cursor\worktrees`, `cursorfs-clone` (missing)  
28. Local: `%USERPROFILE%\AppData\Local\Temp\` (cursor*, vscode-stable-user-*)  
29. Local: `%USERPROFILE%\.cursor\skills-cursor\loop\SKILL.md` (cloud-disabled loop)  
30. Local volume: `Win32_LogicalDisk` DeviceID=`C:` free space snapshot 2026-08-10  
31. https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-globalmemorystatusex  
32. https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex  
33. https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setprocessworkingsetsize  
34. https://learn.microsoft.com/en-us/windows/win32/memory/working-set  
35. https://learn.microsoft.com/en-us/windows/win32/procthread/process-working-set  
36. https://learn.microsoft.com/en-us/windows/win32/memory/file-mapping  
37. https://learn.microsoft.com/en-us/windows/win32/memory/creating-a-file-mapping-object  
38. https://learn.microsoft.com/en-us/windows/win32/memory/memory-management  
39. https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows  
40. https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/slow-page-file-growth-memory-allocation-errors  
41. https://code.visualstudio.com/docs/configure/telemetry  
42. https://code.visualstudio.com/docs/supporting/faq  
43. https://code.visualstudio.com/updates/v1_73  
44. https://code.visualstudio.com/docs/agents/agent-troubleshooting/troubleshooting  
45. https://cursor.com/docs/cloud-agent  
46. https://cursor.com/docs/cloud-agent/capabilities  
47. https://cursor.com/docs/cloud-agent/api/endpoints  
48. https://cursor.com/docs/cloud-agent/api/v0  
49. Addendum research date: 2026-08-18 (RAM-aware + cloud offload sections) 
