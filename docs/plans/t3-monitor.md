# T3 Code monitor for Noctalia v5

Status: accepted design, implemented on `feat/t3-monitor`
Repository: `rigerc/noctalia-plugins-2`
Plugin ID: `rigerc/t3`

## Purpose

Provide local, read-only monitoring of T3 Code parent threads and their subagents
from the Noctalia bar. The plugin must not send messages, approve requests,
interrupt runs, or mutate T3 state.

## Revision: orchestration WebSocket instead of SQLite + CLI

The first implementation read `statev2.sqlite` read-only and shelled out to
`t3 thread list` / `t3 thread show`. That backend was replaced (see
[Revision history](#revision-history)) because T3 Code exposes the same data
through its own orchestration WebSocket, and the hybrid path had three costs:
the SQLite projection schema is internal, every `t3 thread list` opened a
short-lived MCP session per project, and subagent progress was only sometimes
present.

The current backend is a small Node bridge that speaks T3's Effect RPC over
`/ws`, subscribes to `orchestration.subscribeShell`, and streams NDJSON events
to a thin Luau service. No `sqlite3` executable and no `t3 thread` CLI calls
remain.

## Locked decisions

| Domain | Requirement |
| --- | --- |
| Backend | Node 22+ bridge (`t3/bridge.mjs`) speaking T3's orchestration WebSocket RPC (`orchestrationProtocol=2`, `orchestration.subscribeShell`) |
| Authentication | Read-only bearer token with `orchestration:read`, minted with `t3 auth session issue`; exchanged for a short-lived WebSocket ticket |
| Installation | No npm dependencies, no daemon, no SSH or remote MCP. Node 22+ and a local T3 Code are required; `node_executable` and `token_file` are configurable |
| Data directory | Default `${T3CODE_HOME:-~/.t3}`; bridge reads `userdata/server-runtime.json` for the server origin |
| Projects | Auto-discover every project in the shell snapshot, include newly created projects, exclude user-selected project IDs |
| UI | Adaptive bar with separate active parent/child counts; single newest-activity-sorted active-thread list; expandable parent rows; nested subagents |
| Visible parents | Preparing, queued, starting, running, or a confirmed pending request; keep an idle parent as context while a child is still active |
| Visible children | Active and waiting subagents, with independent lifecycle; never infer subagent completion from parent status |
| Child details | Status, provider/model and timing; `progress` is not in the shell and renders as unavailable |
| Bar attention | Persistent until resolved; separate parent and child counts; event highlight 5 seconds without hiding attention |
| Notifications | Parent completion, *every child completion*, attention requiring human input; child attention attributed only when the request sits on that child |
| Offline notifications | Persist deduplication ledger and replay only verified missed transitions within 10 minutes; first launch silent |
| Refresh | Continuous stream; no polling interval. Panel open and refresh publish current state immediately. Reconnect with exponential backoff; a dropped connection never implies completion or disappearance |

## Confirmed upstream interfaces

- `POST /api/auth/websocket-ticket` with `Authorization: Bearer <token>` returns
  `{ ticket }`. A token needs the `orchestration:read` scope.
- `GET /ws?orchestrationProtocol=2&wsTicket=<ticket>` is the orchestration
  WebSocket. The server returns `426` when `orchestrationProtocol` is not `2`.
- Frames are plain JSON Effect RPC, not JSON-RPC and not msgpack. A request is
  `{"_tag":"Request","id":1,"tag":"orchestration.subscribeShell","payload":{},"headers":[]}`
  and replies arrive as `{"_tag":"Chunk","requestId":1,"values":[...]}`. The
  `headers` array is required; omitting it closes the connection with `1011`.
- The `subscribeShell` snapshot includes projects and every thread, including
  subagents (`lineage.relationshipToParent == "subagent"`), with `id`,
  `projectId`, `title`, `status`, `providerInstanceId`, `modelSelection.model`,
  `pendingRuntimeRequest`, `latestRunCompletedAt` and `updatedAt`.
- A cold subscribe sends two `snapshot` items: the authoritative shell followed
  by a project-metadata refresh with `threads: []`. The bridge merges them; it
  treats only the first snapshot on a connection as full.
- `~/.t3/userdata/server-runtime.json` describes the running T3 server
  (`origin`, `serverVersion`, …).
- Noctalia v5 / plugin API 24 provides `noctalia.runStream`, `noctalia.json`,
  `noctalia.state.set/watch`, `noctalia.pluginDataDir`, `noctalia.fileExists`,
  `noctalia.readFile`, `noctalia.writeFile`, native panels, and notifications.

References:

- https://github.com/pingdotgg/t3code/blob/main/apps/server/src/cli/thread.ts
- https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/orchestratorMcp.ts
- https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/orchestrationV2.ts
- [05-access-paths.md](../research/t3/05-access-paths.md)

## Design and data flow

1. On startup, resolve `t3_home`, `token_file`, `node_executable` and the bridge
   path. If the token is missing, publish the token hint instead of spawning.
2. Run `node bridge.mjs --home … --token-file … --lock-file …` through
   `noctalia.runStream`. The bridge takes the lock, which stops a bridge left
   behind by a hot reload.
3. The bridge reads the server origin, mints a ticket, connects, and subscribes
   to the shell. It reconnects with backoff (5 s to 2 min) and takes a fresh
   full snapshot every time.
4. Project each shell item to the fields the monitor renders and print one
   NDJSON event per line: `snapshot` (`full` or `projects`), `thread.updated`,
   `thread.removed`, `project.updated`, `project.removed`, `health`,
   `heartbeat`. Archived threads become `thread.removed`.
5. `service.luau` decodes each line and passes it to `reducer.luau`, which owns
   all state transitions, the view model, attention and notification rules.
6. Publish one snapshot for the widget and panel:
   `{ health, error, reason, tokenCommand, parents, parentCount, childCount,
   attentionCount, lastSyncText, highlight }`. The widget and panel need no
   transport knowledge.
7. Persist only the notification ledger (`monitor-ledger.json`): last states and
   emitted event keys. Notify on verified transitions: `threadId + runId` for
   parents, `childThreadId + latestRunCompletedAt` for children.
8. On restart, report verified events no older than 10 minutes, with a first-run
   baseline and capped catch-up. Connection failures never clear the ledger or
   imply that work finished.

## UI

- `[[widget]] status`: small bar element with T3 glyph, separately counted active
  parents and children, persistent attention badge, short completion highlight,
  disconnected/idle fallback. Clicking toggles the attached panel.
- `[[panel]] dashboard`: unified active parent list sorted by newest activity in
  the family. Expand a parent to see child rows, and a child to show provider,
  model, start/update times. Include connection health, last successful sync,
  settings and a refresh control.
- When offline, the panel shows the failure reason and, for a missing or expired
  token, the exact `t3 auth session issue` command with a copy button.
- A parent with only active children remains a contextual row but is not counted
  as actively working. Nested subagents are counted separately. Unknown fields
  render as unavailable.
- Notifications use host `noctalia.notify`, not a separate daemon.

## Reliability and security

- The bridge never writes to T3: it only mints a ticket and subscribes. The
  token is read from a local file and never printed.
- The token file is expected to be private; the bridge reports a warning when it
  is group- or world-readable.
- Shell-quote every path passed to `noctalia.runStream`; the host runs the
  command through `/bin/sh -c`.
- A heartbeat every 15 s lets the service detect a stalled bridge after 45 s and
  restart it. Retries are bounded and coalesced; there is only one bridge.
- Never let a stale, truncated, incomplete or failed snapshot trigger completion,
  disappearance or notification events. A disconnect only changes health.
- Exclusions use stable project IDs, apply to the UI and notifications, and new
  projects automatically qualify.
- Never show a child completion unless its own record reaches completed,
  regardless of parent status. Distinguish failed/cancelled.
- Keep only metadata and small event keys in plugin persistence; do not persist
  conversation contents.
- T3 subagent `waiting` is not automatically an actionable prompt; attention
  requires a non-async `pendingRuntimeRequest` on that thread.

## Repo layout

```text
t3/
  plugin.toml
  service.luau        # process, stream, ledger, watchdog
  reducer.luau        # pure state machine (testable without the host)
  bridge.mjs          # Node 22+ WebSocket RPC -> NDJSON
  widget.luau
  panel.luau
  translations/en.json
  fixtures/
    ws-shell.ndjson   # recorded, sanitized frames
    ws-defect.ndjson
    events.ndjson     # golden bridge output
  README.md
  thumbnail.webp
```

## Delivery stages and acceptance criteria

1. **Bridge**: token → ticket → `/ws` subscribe; project shell snapshots and
   deltas to NDJSON; reconnect with backoff; lock-file takeover; replay mode.
2. **State engine**: normalize and join threads; active parent/child counts;
   independent child lifecycle and persisted ledger.
3. **Events**: once-only parent/child completions, child-attributed attention,
   10-minute recovery and silent first run.
4. **UI**: adaptive bar; nested, expandable active-only list; connection health,
   token hint, exclusions and settings.
5. **Release**: metadata, translations, 960x540 WebP thumbnail, README, fixtures,
   validator and tests.

Tests must cover: parent starts, child starts, parent idle/child running, two
child completions same tick, parent and child finish, request attribution,
attention persistence, restart at 5/30 minutes, exclusions, server loss, protocol
change, process failures, hot reload and duplicate-notification suppression.

## Implementation notes

Prefer a simpler correct partial feature over incorrect status claims. If the
shell cannot cheaply confirm an attention state, display waiting without a
notification until a pending request appears. Keep transport (bridge) and policy
(reducer) separate so both are testable without a live T3.

## Revision history

- **2026-10-27 — orchestration WebSocket.** Replaced the SQLite + `t3` CLI
  backend with `bridge.mjs` + `reducer.luau`. The published snapshot shape stayed
  the same. Settings lost `sqlite_path`, `sqlite_executable` and
  `t3_executable`; they gained `node_executable` and `token_file`. Live
  verification used T3 Code `0.1.4-nightly` on `http://127.0.0.1:3773`.
- **2026-10-24 — first implementation.** Hybrid `t3 thread list` / `t3 thread
  show` plus read-only `statev2.sqlite` queries.
