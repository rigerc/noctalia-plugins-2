# 02 — v2 schema

All tables below are in `~/.t3/userdata/statev2.sqlite`. Counts measured
`2026-10-24T19:44Z`; they grow while the app runs.

## Table map

```
projection_projects  (live, v1-named)
   └── orchestration_v2_projection_threads        660
         ├── orchestration_v2_projection_runs                270
         │     ├── orchestration_v2_projection_run_attempts   270
         │     ├── orchestration_v2_projection_provider_turns 261
         │     └── orchestration_v2_projection_nodes         9628
         ├── orchestration_v2_projection_turn_items         19345
         │     └── orchestration_v2_turn_item_positions     19346
         ├── orchestration_v2_projection_messages           10385
         │     └── orchestration_v2_message_search (fts)     9889
         ├── orchestration_v2_projection_plans                 17
         ├── orchestration_v2_projection_runtime_requests      23
         ├── orchestration_v2_projection_subagents             70
         ├── orchestration_v2_projection_checkpoint_scopes    122
         │     └── orchestration_v2_projection_checkpoints    379
         └── orchestration_v2_projection_provider_threads     124
               ├── orchestration_v2_projection_provider_sessions 20
               └── orchestration_v2_projection_provider_session_bindings 112

cross-thread:
  orchestration_v2_projection_context_handoffs      3
  orchestration_v2_projection_context_transfers   141
  orchestration_events (live event log)         67903
  orchestration_v2_legacy_imports                 538
  orchestration_v2_effect_outbox                  663
  orchestration_v2_command_receipts                 0
  orchestration_v2_thread_launch_workflows          0
```

## ID formats (verified)

IDs are strings, and several are nested/percent-encoded digests rather than
UUIDs. Patterns seen:

| Entity | Format |
|---|---|
| thread | bare UUID, **or** `thread:delegated-task:command%3A<uuid>%3Adelegate-task%3A<slug>` for subagent threads |
| project | bare UUID |
| run | `run:thread:<threadId>:ordinal:<n>` |
| run attempt | `run-attempt:<runId>:attempt:<n>` |
| node | `node:run:<percent-encoded runId>:root`, or `node:provider:<driver>:native-item:<nativeId>` |
| provider thread | `provider-thread:provider:<driver>:native-thread:<percent-encoded ref>` |
| provider turn | `provider-turn:provider:<driver>:native-turn:<percent-encoded ref>` |
| turn item | `turn-item:provider:<driver>:native-item:<nativeId>` (migrated v1 items: `migration:v1:turn-item:<v1-id>`) |
| checkpoint | `checkpoint:scope:<percent-encoded scopeId>:name:<n>` |
| checkpoint scope | `checkpoint-scope:thread:<threadId>:name:root` |
| message | plain UUID, or `assistant:<nativeId>` |

Encoding nests up to 4 levels deep (`%25253A`), so never `LIKE`-match on decoded
substrings — join by column equality instead.

## Core tables

### `orchestration_v2_projection_threads` — 660 rows

Authoritative thread record. Scalar columns are convenience denormalizations of
`payload_json`.

```sql
thread_id TEXT PRIMARY KEY, project_id TEXT NOT NULL, title TEXT NOT NULL,
default_provider TEXT NOT NULL, runtime_mode TEXT NOT NULL,
interaction_mode TEXT NOT NULL, active_provider_thread_id TEXT,
created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
archived_at TEXT, deleted_at TEXT, provider_instance_id TEXT,
payload_json TEXT NOT NULL          -- full DTO, see 03-payloads.md
```

Distribution: `default_provider` = `opencode` 309, `codex` 301, `claudeAgent` 20,
`pi` 18, `opencode_2` 12. `runtime_mode|interaction_mode` = `full-access|default`
657, `full-access|plan` 3.

`createdBy|creationSource` — only four combinations exist on this machine:
`system|server` 538 (v1 import), `agent|mcp` 68, `user|mobile` 27, `user|web` 27.
There is **no `desktop` and no `scratch` value in this data**; the desktop shell
is the same web SPA, so it reports `web`.

### `orchestration_v2_projection_nodes` — 9628 rows

The execution graph. One `root_turn` node per run; everything else hangs off it
via `parent_node_id`.

```sql
node_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, run_id TEXT,
parent_node_id TEXT, root_node_id TEXT NOT NULL, kind TEXT NOT NULL,
status TEXT NOT NULL, provider_thread_id TEXT, provider_turn_id TEXT,
runtime_request_id TEXT, checkpoint_scope_id TEXT,
started_at TEXT, completed_at TEXT, payload_json TEXT NOT NULL
```

`kind|status` observed: `tool_call|completed` 4593, `reasoning|completed` 3762,
`assistant_message|completed` 838, `root_turn|completed` 270,
`subagent|completed` 69, `system|completed` 63, `user_input_request|completed` 21,
`todo_list|running` 16, `tool_call|failed` 399, `root_turn|interrupted` 23,
`root_turn|cancelled` 10, `root_turn|failed` 8, `subagent|failed` 1,
`todo_list|cancelled` 1, `tool_call|running` 2, `tool_call|interrupted` 9,
`tool_call|cancelled` 1, `root_turn|running` 1.

`payload_json` adds `countsForRun` (boolean; `true` only for `root_turn`),
`nativeItemRef`, `runtimeRequestId`, `checkpointScopeId`.

### `orchestration_v2_projection_turn_items` — 19345 rows

The itemized timeline: messages, reasoning, tool calls, diffs, checkpoints,
subagent spawns, notifications. This is the table to read for a transcript.

```sql
turn_item_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, run_id TEXT,
node_id TEXT, provider_thread_id TEXT, provider_turn_id TEXT,
parent_item_id TEXT, ordinal INTEGER NOT NULL, type TEXT NOT NULL,
status TEXT NOT NULL, updated_at TEXT NOT NULL, payload_json TEXT NOT NULL
```

19 types observed (counts):

| type | n | | type | n |
|---|---|---|---|---|
| `assistant_message` | 8252 | | `subagent` | 70 |
| `reasoning` | 3763 | | `system_notice` | 48 |
| `command_execution` | 3472 | | `web_search` | 44 |
| `user_message` | 2053 | | `error` | 25 |
| `file_change` | 636 | | `run_interrupt_result` | 23 |
| `dynamic_tool` | 509 | | `user_input_request` | 21 |
| `checkpoint` | 249 | | `todo_list` | 17 |
| `run_interrupt_request` | 82 | | `file_search` | 5 |
| `notification` | 80 | | `compaction` | 3 |
| | | | `handoff` | 2 |

**Ordinals are composite, not 1-based indices.** Both
`orchestration_v2_projection_turn_items.ordinal` and
`orchestration_v2_turn_item_positions.ordinal` encode
`runOrdinal × 1_000_000 + itemIndexInRun`, so run 1 starts at `1000001`, run 47
ends at `47000005`, and 123 threads (the v1 imports) start at `1`. Verified: no
duplicate `(thread_id, ordinal)` in either table, so `ORDER BY ordinal` is safe —
just never treat the value as a position in a list. Use
`orchestration_v2_turn_item_positions` if you want exactly the table the UI/MCP
`position` is derived from.

### `orchestration_v2_turn_item_positions` — 19.4k rows

One row per turn item; the table the UI/MCP `position` is derived from.

```sql
thread_id TEXT NOT NULL, turn_item_id TEXT NOT NULL, ordinal INTEGER NOT NULL,
PRIMARY KEY (thread_id, turn_item_id), UNIQUE (thread_id, ordinal)
```

Ordinal values are the same composite formula used on turn items:
`runOrdinal × 1_000_000 + itemIndexInRun`. Confirmed on threads with many runs —
`0b83c89f…` has 47 runs and ordinals `1000001 … 47000005`; `bac1c99d…` has 15 runs
and `1000001 … 15000009`. Imported v1 threads start at `1` instead (hence 123
threads whose minimum ordinal is not 1). 0 rows without a matching turn item.

### `orchestration_v2_projection_messages` — 10385 rows

Canonical message store, `role` ∈ {`assistant` 8252, `user` 2133}. Full text in
`payload_json.text`. Every row is also mirrored by an `assistant_message` /
`user_message` turn item, but messages carry the clean `role` + `streaming` flags
and are what the FTS index tracks.

```sql
message_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, run_id TEXT, node_id TEXT,
role TEXT NOT NULL, streaming INTEGER NOT NULL,
created_at TEXT NOT NULL, updated_at TEXT NOT NULL, payload_json TEXT NOT NULL
```

### `orchestration_v2_projection_runs` / `_run_attempts` — 270 / 270

```sql
runs:         run_id, thread_id, ordinal, provider, provider_thread_id, status,
              requested_at, completed_at, provider_instance_id, payload_json
run_attempts: attempt_id, thread_id, run_id, attempt_ordinal, root_node_id,
              provider, provider_thread_id, provider_turn_id, status,
              provider_instance_id, payload_json
```

`runs.status` observed: `completed` 227, `interrupted` 19, `cancelled` 10,
`failed` 8, `running` 2. `run_attempts.payload_json.reason` distinguishes
`initial` retries from follow-ups; `nativeThreadId` is the provider's own session
handle (for pi, an absolute path into `~/.pi/agent/sessions/...`).

### `orchestration_v2_projection_provider_*` — sessions 20, threads 124, turns 261, bindings 112

The provider-adapter layer beneath runs. `provider_sessions.status` ∈
{`ready`, `running`, `stopped`}; `provider_threads.status` ∈ {`idle` 121,
`active` 2, `not_loaded` 1} and carries `owner_node_id`, `first_run_ordinal`,
`last_run_ordinal`. These, not the frozen `projection_thread_sessions`, are where
live runtime state lives.

### `orchestration_v2_projection_subagents` — 70 rows

```sql
subagent_id, thread_id, run_id, parent_node_id, provider, provider_thread_id,
child_thread_id, origin, status, driver, provider_instance_id,
started_at, completed_at, updated_at, payload_json
```

`origin` = `app_owned` for all 70; status `completed` 69, `failed` 1.
`child_thread_id` values are `thread:delegated-task:…` synthetic IDs that **do**
exist as rows in `orchestration_v2_projection_threads` with
`lineage.relationshipToParent = "subagent"`.

### `orchestration_v2_projection_plans` — 17 rows

`kind` = `todo_list`, `status` = `active`. Payload carries `steps[]` with
`{id, text, status, durationMs}`.

### `orchestration_v2_projection_runtime_requests` — 23 rows

`kind` = `user_input`, `status` = `resolved`. Payload keys: `id, nodeId,
providerTurnId, nativeRequestRef, kind, status, responseCapability, createdAt,
resolvedAt`, plus `answers` on the 8 answered rows. This is the ask-user /
approval channel; no unresolved rows existed at snapshot time. Question text is
not here — it lives on the paired `user_input_request` turn item (`questions[]`,
`questionAnswer`, `responseMode`).

### `orchestration_v2_projection_context_handoffs` — 3 / `_context_transfers` — 141

The mechanism behind cross-provider and cross-run context transfer (see
[03-payloads.md](03-payloads.md#context-handoff-and-context-transfer)).

```sql
handoffs:  context_handoff_id, thread_id, target_run_id, to_provider_thread_id,
           strategy, status, updated_at, payload_json
transfers: context_transfer_id, source_thread_id, target_thread_id, target_run_id,
           type, status, source_provider, target_provider,
           source_provider_instance_id, target_provider_instance_id, payload_json
```

`transfers.type|status`: `subagent_result|consumed` 70, `subagent_spawn|consumed`
68, `provider_handoff|consumed` 2, `fork|consumed` 1.
`handoffs.strategy`: `delta_since_target_last_seen` ×1, `full_thread_summary` ×2.

### `orchestration_v2_projection_checkpoints` — 379 / `_checkpoint_scopes` — 122

Checkpoints are the fork/rewind points; a scope is a named checkpoint lineage per
thread (`checkpoint-scope:thread:<id>:name:root`).

### `orchestration_v2_effect_outbox` — 663

Per-effect delivery ledger for projection emits: `status` ∈ {`succeeded`,
`cancelled`}. 663 rows across 117 distinct threads, i.e. roughly one row per
projected emit — **not** one row per thread.

### Empty-but-present

`orchestration_v2_command_receipts` (0), `orchestration_v2_thread_launch_workflows`
(0), `orchestration_v2_events` (0). The populated receipts table is the v1
`orchestration_command_receipts` (2712 rows). Idempotency on this machine is thus
**not** observable from v2 receipts — do not build tooling on those tables.

## Objects still on v1 names but required

### `projection_projects` — 46 rows, live

`project_id`, `title`, `workspace_root`, `scripts_json`, `default_model_selection_json`,
`default_thread_env_mode`, `favicon_path`, `project_icon_json`, `auto_pull`,
`created_at`, `updated_at`, `deleted_at`. Every v2 thread's `project_id`
resolves here (0 orphans).

### `orchestration_events` — 67,903 rows, live

See [01-storage-layout.md](01-storage-layout.md#event-log-orchestration_events).

## Useful joins

```sql
-- thread + project + branch/worktree + lineage in one row
SELECT t.thread_id, t.title, p.title AS project, p.workspace_root,
       json_extract(t.payload_json,'$.branch')        AS branch,
       json_extract(t.payload_json,'$.worktreePath')  AS worktree,
       json_extract(t.payload_json,'$.lineage.relationshipToParent') AS rel,
       json_extract(t.payload_json,'$.lineage.parentThreadId')       AS parent
FROM orchestration_v2_projection_threads t
JOIN projection_projects p USING (project_id)
ORDER BY t.updated_at DESC;

-- subagent tree under one parent thread (model lives in the thread payload)
SELECT s.child_thread_id, c.title, s.status, s.provider, s.driver,
       json_extract(c.payload_json,'$.modelSelection.model') AS model
FROM orchestration_v2_projection_subagents s
JOIN orchestration_v2_projection_threads c ON c.thread_id = s.child_thread_id
WHERE s.thread_id = '<parent-thread-id>';
```
