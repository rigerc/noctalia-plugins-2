# T3 Code monitor for Noctalia v5

Status: accepted design, implementation tracked on `feat/t3-monitor`
Repository: `rigerc/noctalia-plugins-2`
Plugin ID: `rigerc/t3`

## Purpose

Provide local, read-only monitoring of T3 Code parent threads and their subagents from the Noctalia bar. The plugin must not send messages, approve requests, interrupt runs, or mutate T3 state.

## Locked decisions

| Domain | Requirement |
| --- | --- |
| Backend | Local hybrid: official `t3` CLI for parent thread status, read-only SQLite for projects and subagents |
| Installation | No persistent bridge, Node.js process, SSH, or remote MCP connection. Require `t3` and `sqlite3` on PATH; support configurable executable paths |
| Data directory | Default `${T3CODE_HOME:-~/.t3}`; default DB `userdata/statev2.sqlite` |
| Projects | Auto-discover all active projects, include newly created projects, exclude user-selected project IDs |
| UI | Adaptive bar with separate active parent/child counts; single newest-activity-sorted active-thread list; expandable parent rows; nested subagents |
| Visible parents | Preparing, queued, starting, running, or confirmed pending user input; keep idle parent as context if child is still active |
| Visible children | Active and waiting subagents, with independent lifecycle; never infer subagent completion from parent status |
| Child details | Status, progress, provider/model and timing, with graceful missing-field fallbacks |
| Bar attention | Persistent until resolved; separate parent and child counts; event highlight 5 seconds without hiding attention |
| Notifications | Parent completion, *every child completion*, attention requiring human input; child attention attributed to parent + child when verifiable |
| Offline notifications | Persist deduplication ledger and replay only verified missed transitions within 10 minutes; first launch silent |
| Refresh | Target 5 seconds while active; 30 seconds idle; immediate on panel open; exponential backoff and no overlapping refreshes |

## Confirmed upstream interfaces

- `t3 thread list --project <id> --json` lists a single project's threads; it explicitly passes `includeSubagents: false`. The JSON has `threadId`, `title`, `status`, `latestRunId`, `providerInstanceId`, `model`, `createdAt`, `updatedAt`. The CLI opens and revokes a short-lived local MCP session internally.
- `t3 thread show <id> --json` supplies a `thread` object with `pendingRequestCount` and messages. Avoid this expensive call for every historical thread.
- `projection_projects` stores `project_id`, `title`, `workspace_root`, `deleted_at`.
- `orchestration_v2_projection_subagents` stores `subagent_id`, `thread_id`, `run_id`, `child_thread_id`, `origin`, `status`, `started_at`, `completed_at`, `updated_at`, `payload_json`. The subagent payload can contain `title`, `progress`, `driver`, `model` and related metadata.
- `orchestration_v2_projection_runtime_requests` stores `thread_id`, `status` and request metadata; use pending request signals only when clearly attributable.
- `~/.t3/userdata/server-runtime.json` describes the running T3 server.
- Noctalia v5 / plugin API 24 provides `noctalia.runAsync` with argv, `noctalia.json.decode`, `noctalia.state.set/watch`, `noctalia.pluginDataDir`, native panels, and notifications.

References: 
- https://github.com/pingdotgg/t3code/blob/main/apps/server/src/cli/thread.ts
- https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/orchestratorMcp.ts
- https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/orchestrationV2.ts
- https://github.com/pingdotgg/t3code/blob/main/apps/server/src/persistence/Migrations/OrchestrationV2/Subagents.ts
- https://github.com/pingdotgg/t3code/blob/main/apps/server/src/persistence/Migrations/005_Projections.ts

## Design and data flow

1. On startup, resolve paths from environment and plugin config; check `t3` / `sqlite3`, server runtime descriptor and V2 schema compatibility.
2. Execute single read-only `sqlite3 -readonly -json` queries for active project discovery and subagent projections. Use direct argv subprocesses; never interpolate a user value into SQL. Validate database path and enable `PRAGMA query_only=ON` where possible.
3. For each non-excluded project, invoke `t3 thread list --project <project_id> --json` (bounded concurrency / serialized initially). Validate stdout, exit code, truncation, timeout; do not interpret failed polls as empty lists.
4. For applicable active or waiting parent threads, invoke `t3 thread show --json` to confirm pending request count; cache and throttle requests.
5. Join subagents to parent thread IDs and project IDs, not parent run IDs. Children may continue working after a parent run settles. Preserve orphaned-parent context rows while children remain active.
6. Normalize state: `{ health, lastSync, projects, parents, children, parentWorkingCount, childWorkingCount, attentionCount }`. Emit into shared plugin state.
7. Compare the new successful snapshot with a persisted event ledger. Notify only on verified status transitions: unique `threadId + runId + completed` for parents, `subagentId + completion timestamp` for children. Handle terminal statuses separately. Attribute child attention only when a pending request can be tied to it; never fabricate attribution.
8. On restart, replay verified events no older than 10 minutes, with a first-run baseline and capped catch-up. Clear no ledger information on connection failures.

## UI

- `[[widget]] status`: small bar element with T3 glyph, separately counted active parents and children, persistent attention badge, short completion highlight, disconnected/idle fallback. Clicking toggles attached panel.
- `[[panel]] dashboard`: unified active parent list sorted by newest activity in family. Expand parent to see child rows, and child to show progress, provider/model, start/update/finish times. Include connection health, last successful sync, settings/project exclusions, and a refresh control.
- Parent with only active children remains a contextual row but is not counted as actively working. Nested subagents are counted separately. Show unknown fields as unavailable.
- Notifications use host `noctalia.notify`, not a separate daemon. Completion alerts for each child; attention only on confirmed pending requests; persistent attention in bar.

## Reliability and security

- Launch subprocesses with argv arrays, not string shell commands. Never execute dynamic project paths through a shell.
- SQLite always read-only; no writes, migrations, checkpoints or live DB copies.
- Schema guard with `sqlite_master` and the columns required for the adapter; on mismatch, show a clear compatibility error.
- Concurrency cap and poll coalescing. No more than one refresh cycle active; exponential retry after failures.
- Never let a stale, truncated, incomplete or failed snapshot trigger completion, disappearance or notification events.
- Exclusions use stable project IDs, apply to UI and notifications, and new projects automatically qualify.
- Never show a child completion unless its own record reaches completed, regardless of parent status. Distinguish failed/cancelled.
- Keep only metadata and small event keys in plugin persistence; do not persist conversation contents.
- T3 subagent `waiting` is not automatically an actionable prompt; correlate with pending requests.

## Repo layout

```text
t3/
  plugin.toml
  service.luau
  widget.luau
  panel.luau
  translations/en.json
  README.md
  thumbnail.webp
```

Optional small helpers and tests may be added if necessary, but do not introduce a permanent service.

## Delivery stages and acceptance criteria

1. **Adapter**: verify CLI availability and JSON format; query SQLite projects and child records; tolerate schema mismatch.
2. **State engine**: normalize and join data; active parent/child counts; independent child lifecycle and persisted ledger.
3. **Events**: once-only parent/child completions, parent-attributed attention, 10-minute recovery and silent first run.
4. **UI**: adaptive bar; nested, expandable active-only list; connection health; exclusions and settings.
5. **Release**: metadata, translations, 960x540 WebP thumbnail, README, fixtures, validator and tests.

Tests must cover: parent starts, child starts, parent idle/child running, two child completions same tick, parent and child finish, request attribution, attention persistence, restart at 5/30 minutes, exclusions, server loss, schema change, process failures, hot reload and duplicate-notification suppression.

## Implementation notes

Prefer a simpler correct partial feature over incorrect status claims. If native Luau + CLI cannot cheaply confirm an attention state, display waiting without notification until verification succeeds. Keep CLI versus SQLite responsibilities clear to avoid reading mutable SQLite run projections as authoritative parent status.
