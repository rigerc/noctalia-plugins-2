# T3 Code thread storage — v2 research

Scope: **v2 only**. Everything here was verified against `~/.t3/` on this machine
(T3 `0.1.3-nightly.20261024.3630`, snapshot measured `2026-10-24T19:44Z`). No T3
source code was read. Row counts drift while the app runs — treat them as
magnitudes, not constants.

## TL;DR

- The single source of truth for threads is **`~/.t3/userdata/statev2.sqlite`**.
  All live data lives in `orchestration_v2_projection_*`.
- Tables named `projection_*` and `orchestration_*` (without `_v2_`) are **v1
  leftovers frozen at the cutover** (`2026-09-24T20:41:06Z`), with one exception:
  `projection_projects` is still live, and `orchestration_events` is still the
  live event log.
- Message and turn-item text is stored **in cleartext, untruncated, inside
  `payload_json`**. Truncation is an artifact of the MCP read tools, not of the
  database.
- There is **no REST API**. `:3773` serves the SPA HTML for every path
  (verified: `/`, `/api/threads`, `/threads`, `/api/v1/threads` all return the
  same 19,492-byte `text/html` document).
- `sqlite3` CLI on this box has **no FTS5 module**, so the message-search index
  is unreadable from the CLI. Use the `python3` `sqlite3` module.

## Documents

| File | Contents |
|---|---|
| [01-storage-layout.md](01-storage-layout.md) | What is on disk, what is live vs frozen, cutover evidence |
| [02-schema.md](02-schema.md) | v2 tables, columns, keys, counts, ID formats, joins |
| [03-payloads.md](03-payloads.md) | Exact `payload_json` shapes: thread, run, node, turn item (all 19 types), subagent, handoff, transfer |
| [04-search.md](04-search.md) | FTS5 index internals and practical query recipes |
| [05-access-paths.md](05-access-paths.md) | MCP tool surface, absence of REST, paging behaviour |
| [06-files-and-artifacts.md](06-files-and-artifacts.md) | Attachments, provider logs, worktrees, scratch, PR cache |
| [07-verification.md](07-verification.md) | Claim-by-claim verdicts on the source brief, incl. corrections |

## Fast start

```bash
DB="file:$HOME/.t3/userdata/statev2.sqlite?mode=ro"

# newest 20 threads
sqlite3 "$DB" "
  SELECT substr(thread_id,1,8), json_extract(payload_json,'\$.runtimeMode'),
         substr(title,1,60), updated_at
  FROM orchestration_v2_projection_threads
  ORDER BY updated_at DESC LIMIT 20;"

# full text of one thread's conversation, in order
sqlite3 "$DB" "
  SELECT p.ordinal, json_extract(t.payload_json,'\$.type'),
         substr(json_extract(t.payload_json,'\$.text'),1,200)
  FROM orchestration_v2_turn_item_positions p
  JOIN orchestration_v2_projection_turn_items t USING (turn_item_id)
  WHERE p.thread_id = '<thread-uuid>'
  ORDER BY p.ordinal;"
```

Always open read-only (`?mode=ro`) — the app holds a WAL and will contend with
you otherwise. Do **not** use `immutable=1`; it ignores the WAL and you will read
stale data.

## Two rules that prevent most mistakes

1. **Ordinals are composite, not indices.** Both
   `orchestration_v2_projection_turn_items.ordinal` and
   `orchestration_v2_turn_item_positions.ordinal` encode
   `runOrdinal × 1_000_000 + itemIndexInRun` (run 1 → `1000001`; v1-imported
   threads start at `1`). They are unique per thread, so `ORDER BY ordinal` works;
   just never read the number as a list position. MCP's `items[].position` is
   derived from the positions table and is 0-based.
2. **`thread_id` is not always a UUID.** Subagent threads use
   `thread:delegated-task:command%3A<command-uuid>%3Adelegate-task%3A<slug>`.
   Never cast or regex thread IDs as UUIDs.
