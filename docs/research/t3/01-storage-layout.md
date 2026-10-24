# 01 — Storage layout

Root: `~/.t3/`. T3 is a desktop shell (Electron) plus a local server; the UI is a
web SPA served by that server, so *all* client kinds write into the same store.

```
~/.t3/
├── bin/t3                          CLI
├── caches/                         provider model catalogs, PR cache, ACP registry
├── runtime/versions/               downloaded runtimes
├── scratch/<date>-<slug>-<hash8>/  project-less thread checkouts
├── tools/{chrome-headless-shell,cloudflared}
├── worktrees/<project-slug>/t3-<hash8>/   per-thread git worktrees (2.4 GB here)
└── userdata/
    ├── statev2.sqlite              1.6 GB  ← v2 authoritative store (WAL active)
    ├── state.sqlite                1.7 GB  v1 store, retained
    ├── server-owner.sqlite         0 B     leader election, single row-owner
    ├── server-runtime.json         live server pid/port/origin/version
    ├── settings.json, client-settings.json, desktop-settings.json, keybindings.json
    ├── model-manifest.json, usage-model-rates.json, usage-scan-cache*.json
    ├── compacted-at                epoch-ms marker of last event compaction
    ├── environment-id, anonymous-id, clerk-tokens.json
    ├── secrets/                    per-provider credentials (mode 0700)
    ├── attachments/                user-uploaded files, 18 here
    ├── browser-artifacts/          preview/download artefacts
    ├── logs/{boot-service.log,desktop-main.log,desktop.trace.ndjson*}
    ├── logs/provider/events.<threadId>.log[.1,.2]   raw provider protocol streams
    └── opencode-servers/           per-session opencode server state
```

`server-runtime.json` (verified) pins the local endpoint:

```json
{"version":1,"pid":4112472,"host":"0.0.0.0","port":3773,
 "origin":"http://127.0.0.1:3773","startedAt":"2026-10-24T18:01:17.262Z",
 "serverVersion":"0.1.3-nightly.20261024.3630","ownerId":"1d71fa2b-…"}
```

`desktop-settings.json` shows `"serverExposureMode":"network-accessible"`, which
is why it binds `0.0.0.0` rather than loopback.

## Live vs frozen — the important distinction

`statev2.sqlite` contains **both** the v2 schema and a copy of the v1 schema.
Naming is actively misleading. Verified last-write timestamps:

| Table | Last write (UTC) | Status |
|---|---|---|
| `orchestration_v2_projection_*` | now | **live v2** |
| `orchestration_v2_turn_item_positions` | now | **live v2** |
| `orchestration_v2_message_search` | now | **live v2** |
| `orchestration_events` | now | **live** — the v2 event log, despite the name |
| `projection_projects` | now | **live** — no v2 replacement exists |
| `projection_threads` | `2026-09-24T20:41:06.027Z` | frozen v1 |
| `projection_thread_messages` | `2026-09-24T20:41:06.004Z` | frozen v1 |
| `projection_thread_sessions` | `2026-09-24T20:41:06.027Z` | frozen v1 |
| `provider_session_runtime` | `2026-09-25T16:32:56.359Z` | frozen v1 |
| `orchestration_v2_events` | never (0 rows) | **empty** — v2 never used it |
| `orchestration_v2_command_receipts` | never (0 rows) | **empty on this machine** |
| `orchestration_v2_thread_launch_workflows` | never (0 rows) | **empty on this machine** |

### Cutover evidence

- All three v1 projection tables stop at the same instant
  (`2026-09-24T20:41:06Z`); nothing has written them since.
- `orchestration_v2_legacy_imports` (538 rows) records the v1→v2 import, with
  import completion timestamps `2026-09-25T16:44–16:45Z`.
- Exactly **538** v2 threads carry `createdBy: "system"`, `creationSource:
  "server"` — the imported set — and those are precisely the 538 rows in
  `projection_threads`. The other 122 v2 threads (`web`, `mobile`, `mcp`) have no
  `projection_threads` row at all.
- `projection_threads` is a subset of v2: 0 orphan rows in either direction for
  the threads it does contain.

**Consequence:** organization state you might expect in `projection_threads`
(pin order, settle/snooze, linked PRs) is all `NULL` there. In v2 that state
moved *into* `orchestration_v2_projection_threads.payload_json` — see
[03-payloads.md](03-payloads.md#thread-dto).

## Event log: `orchestration_events`

Despite the legacy name, this table is the **live v2 event log**. 67,903 rows,
34 distinct event types, written milliseconds ago for the thread in this session.
`orchestration_v2_events` exists but is empty; `userdata/compacted-at` records
the last compaction pass, so old v2 events are pruned.

```sql
-- schema: sequence, event_id, aggregate_kind, stream_id, stream_version,
--         event_type, occurred_at, command_id, causation_event_id,
--         correlation_id, actor_kind, payload_json, metadata_json,
--         application_event_version
SELECT event_type, count(*) FROM orchestration_events GROUP BY 1 ORDER BY 2 DESC;
```

Observed shape: append-only, `aggregate_kind` ∈ {`thread`, `project`},
`stream_id` = thread id, `stream_version` monotonic per stream, `actor_kind` =
`server`, and `payload_json` holds a **complete DTO snapshot** (not a diff) —
so events alone are enough to reconstruct the projection. Recent types:

`turn-item.updated`, `node.updated`, `provider-turn.updated`, `message.updated`,
`run.updated`, `provider-thread.updated`, `thread.visited`, `run-attempt.updated`,
`provider-session.updated`, `checkpoint.captured`, `subagent.updated`,
`checkpoint-scope.created`, plus ~22 more.

## `state.sqlite` (v1)

Kept for rollback/export only. 1.7 GB. Verified contents: 564 threads,
11,674 messages, 160,220 `projection_thread_activities`, 1,763 `projection_turns`,
0 `projection_pending_approvals`, 0 `checkpoint_diff_blobs`. Do not read it for
current data.
