# T3 Monitor

Local read-only T3 Code monitoring for **Noctalia v5, plugin API 24**.

## Plugin

| Field | Value |
| --- | --- |
| ID | `rigerc/t3` |
| Bar widget | `status` |
| Panel | `dashboard` |
| Service | `monitor` |

## What it does

- Shows separate working parent and active subagent counts in the bar.
- Keeps attention indicators visible until the pending request is resolved.
- Shows a unified list of active parent threads, with subagents nested under the parent.
- Keeps idle parent rows visible when their child subagents still work.
- Displays subagent provider, model and timings when T3 exposes them.
- Sends a notification when each parent run or subagent completes; attributes
  pending-attention requests to a child only when the request sits on that child.
- Deduplicates notifications across restarts, with a 10-minute catch-up window
  and a silent first launch.
- Streams updates over T3 Code's local WebSocket; there is no polling interval
  and no persistent daemon beyond the small bridge process.

**Read-only:** the plugin requests the `orchestration:read` scope, subscribes to
the orchestration shell, and never sends prompts, approves tool requests or
changes T3 project/thread state.

## Requirements

- T3 Code running locally. The bridge reads `~/.t3/userdata/server-runtime.json`
  for the server origin.
- **Node 22 or newer** on `PATH` (or set `node_executable`). The bridge uses the
  built-in `fetch` and global `WebSocket`; it has no npm dependencies.
- A read-only T3 token. See [Token setup](#token-setup).
- Noctalia plugin API 24 or newer (Noctalia v5.0.0-beta.9+).

No `sqlite3` executable and no `t3 thread` CLI calls are used.

## Token setup

The monitor needs a token with the `orchestration:read` scope. Mint one and
write it to the plugin data directory:

```sh
t3 auth session issue --scope orchestration:read --ttl 30d --token-only > "<plugin data dir>/token" && chmod 600 "<plugin data dir>/token"
```

The panel shows this exact command with the resolved path and a **Copy command**
button the first time it runs. Run it in a terminal, then the monitor connects by
itself; there is no restart needed.

The command also restricts the file to your user. If the token file is readable
by other users, the panel shows a warning with the `chmod` fix. Set `token_file`
to use a different location.

## Usage

Install and add the bar widget to watch local T3 activity. Click the widget to
show the panel. Rows expand to reveal provider, model, timings and subagents;
the panel is otherwise read-only.

## Install

Register this repository as a Noctalia plugin source if not already registered:

```sh
noctalia msg plugins source add rigerc git git@github.com:rigerc/noctalia-plugins-2.git
noctalia msg plugins enable rigerc/t3
```

Add the **T3 / status** bar widget in Settings → Bar. Click to open the attached
panel, or run:

```sh
noctalia msg panel-toggle rigerc/t3:dashboard
```

## Settings

| Key | Default | Purpose |
| --- | --- | --- |
| `t3_home` | `T3CODE_HOME` or `~/.t3` | T3 data directory; the bridge reads `userdata/server-runtime.json` from it. |
| `token_file` | `<plugin data dir>/token` | Read-only token file. |
| `node_executable` | `node` | Node 22+ binary or absolute path. |
| `excluded_projects` | empty | T3 project IDs to leave out of counts, rows and notifications. |
| `notify_completions` | on | Notify when a parent run or subagent completes. |
| `notify_attention` | on | Notify when a pending request needs a human. |

## How it works

```
T3 Code ── /ws (orchestrationProtocol=2) ──▶ bridge.mjs ── NDJSON ──▶ service.luau
                                                                        │
                                                        reducer.luau ───┤
                                                                        ▼
                                                         noctalia.state "snapshot"
                                                              │              │
                                                          widget.luau   panel.luau
```

1. `bridge.mjs` reads the server origin from `server-runtime.json`, mints a
   short-lived WebSocket ticket from the token (`POST
   /api/auth/websocket-ticket`), and subscribes with
   `orchestration.subscribeShell`.
2. It projects the shell snapshot and stream deltas into small NDJSON events
   (`snapshot`, `thread.updated`, `thread.removed`, `project.updated`,
   `project.removed`, `health`, `heartbeat`).
3. `service.luau` runs the bridge with `noctalia.runStream`, feeds every line to
   `reducer.luau`, persists its notification ledger, and publishes one snapshot
   for the widget and panel.

The shell snapshot already includes subagent threads, so the monitor does not
open a session per parent project.

### Connection handling

- The bridge reconnects with exponential backoff (5 s to 2 min) and takes a
  fresh full snapshot each time; it never resumes with a stale sequence.
- A heartbeat every 15 s lets the service detect a stalled bridge: 45 s while it
  is healthy, or 3 min while it is already retrying (longer than the backoff
  cap), then it restarts it.
- A dropped connection never counts as completion or disappearance: the
  notification ledger is kept and the view switches to offline until a new
  snapshot arrives.
- Changing settings restarts the bridge. The new process stops the previous one
  through a shared lock file (`bridge.lock`) in the plugin data directory, so a
  restart never leaves two streams running.

### Notifications

- Parent completion key: `threadId + runId`.
- Subagent completion key: `childThreadId + latestRunCompletedAt`.
- Keys are stored in `monitor-ledger.json` and pruned after 7 days, so a restart
  does not repeat a notification.
- The first launch after install records the baseline silently.
- Completed work up to 10 minutes old is reported as a catch-up; older work is
  not.

## Known limitations

- `progress` is not part of the orchestration shell, so the panel shows
  `Unavailable` for it.
- A waiting subagent is *not* automatically proof of a user-actionable request;
  attention requires a non-async pending request on that thread.
- Work that starts and finishes while the bridge is disconnected and has already
  left T3's projections cannot be recovered; the plugin does not fabricate
  events.
- The token expires after its TTL (30 days in the command above). The panel then
  shows the same token hint so a new one can be minted.
- The bridge needs Node 22+; an older `node` shows an offline hint instead of
  silently failing.

## Development

Run repository validation and the contract tests:

```sh
python3 .github/workflows/validate-plugins.py
python3 -m unittest discover -s .github/workflows -p 'test_validate_plugins.py'
python3 -m unittest discover -s .github/workflows -p 'test_t3_monitor.py'
```

The contract tests replay recorded WebSocket frames through the real bridge and
reducer, so they need no T3 installation. They need `node` (the bridge) and
`lua5.4` (the reducer).

Inspect the bridge directly:

```sh
node t3/bridge.mjs --home ~/.t3 --token-file /path/to/token --once
node t3/bridge.mjs --replay t3/fixtures/ws-shell.ndjson
```

`--once` makes a single connection attempt and exits instead of reconnecting;
use it to check the token and the runtime file. `--replay` feeds recorded frames
through the same projection and prints deterministic `at: 0` events for golden
comparisons.

See the [design plan](../docs/plans/t3-monitor.md) and the
[access-path research](../docs/research/t3/05-access-paths.md).
