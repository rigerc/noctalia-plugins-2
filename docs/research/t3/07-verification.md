# 07 — Verification

Claim-by-claim verdicts for the source brief. Snapshot: `2026-10-24T19:44Z`,
`statev2.sqlite`, T3 `0.1.3-nightly.20261024.3630`. Counts drift; the verdict
column is what matters.

## Confirmed

| Claim | Evidence |
|---|---|
| `orchestration_v2_projection_threads` is the v2 thread record | 660 rows; columns as described |
| `payload_json` is the full DTO the app/MCP returns | matches `t3_thread_read` output field-for-field |
| `runs` / `run_attempts` | present, 270 / 270 |
| `messages` and full cleartext message text | `orchestration_v2_projection_messages`, 10,385 rows, `payload_json.text` |
| `turn_items` with the listed type vocabulary | 19 types present, same names; counts shifted |
| Each turn item carries `nativeItemRef`, provider thread/turn ids, parent/child refs, start/complete times | confirmed on all 19 types |
| `nodes` = execution graph, 9,404 → now 9,628 | confirmed, `parent_node_id`/`root_node_id` |
| `subagents` with `child_thread_id` | 70 rows, all `app_owned`, `child_thread_id` populated |
| `plans`, `runtime_requests`, `context_handoffs`, `context_transfers` | 17 / 23 / 3 / 141 |
| `orchestration_v2_message_search*` is an FTS5 index over message text | confirmed; trigram tokenizer, contentless |
| Attachments keyed by thread id | 18 files, prefix = thread id, size matches DTO |
| `logs/provider/events.<threadId>.log`, rotated at ~10 MB | 7 files, all rotations ≈10 MiB |
| `worktrees/` ≈2.4 GB, `scratch/<date>-<title>-<hash>` | confirmed |
| `caches/pull-requests/pr-<hash>` | 29 JSON files |
| Unauthenticated `GET` on `:3773` serves SPA HTML for every path, incl. `/api/threads` and `/threads` | 4 paths probed: identical 19,492-byte `text/html`. **Superseded in part:** `POST /api/auth/websocket-ticket` is a real endpoint, and `/ws` is the orchestration channel (see [05](05-access-paths.md)). |
| `sqlite3` is the only non-app read path | **Corrected:** the orchestration WebSocket (`/ws`, `orchestrationProtocol=2`) exposes the shell read-only; SQLite remains the path for full message bodies. |
| Long item text needs `itemId` + `textOffset` paging **through MCP** | reproduced: `textTruncated: true`, `nextTextOffset: 300` |

## Corrected

| Brief said | Actually |
|---|---|
| `projection_threads` (538) holds current UI state — `pinned_at`, `settled_at`, `snoozed_until`, `pending_approval_count`, `linked_pull_request_json`, `model_selection_json`, `title_state_json` | **Frozen v1.** Last write `2026-09-24T20:41:06Z`. `pinned_at`, `snoozed_until`, `linked_pull_request_json` are 100 % NULL; 0 rows for any thread created after cutover. In v2 that state lives in `orchestration_v2_projection_threads.payload_json` (`pinnedAt`, `pinOrderKey`, `settledAt`, `settledOverride`, `unsettledAt`, `snoozedUntil`, `snoozedAt`, `lastVisitedAt`, `activeOrderKey`, `opens`, `titleRegeneration`, `pullRequests`). |
| `projection_thread_sessions` (530) = live runtime state | **Frozen v1**, same cutover timestamp. Live runtime state is in `orchestration_v2_projection_provider_sessions` / `_provider_threads` / `_provider_turns` plus `runs.status`. Thread "status" shown by MCP is derived, not stored. |
| `messages` (10,357) and `projection_thread_messages` (11,674) both hold cleartext text | Only **one** is live. `projection_thread_messages` (11,313) is a frozen v1 mirror; 11,674 was its count in `state.sqlite`. v2 canonical = `orchestration_v2_projection_messages` (10,385). |
| `creationSource` ∈ `web` / `desktop` / `scratch` | Observed values: `server` (538, with `createdBy: system` = v1 import), `mcp` (68, `agent`), `mobile` (27, `user`), `web` (27, `user`). **No `desktop`, no `scratch`.** The desktop shell is the same SPA, so it reports `web`. |
| `command_receipts` + `thread_launch_workflows` hold idempotency keys | `orchestration_v2_command_receipts` = **0 rows**, `orchestration_v2_thread_launch_workflows` = **0 rows**. The populated receipts table is the v1 `orchestration_command_receipts` (2,712). Do not rely on v2 receipts. |
| `turn_items` counts: 19,100 total, `assistant_message` 8,236, `reasoning` 3,703, … | Same shape, higher counts (live writes): 19,345 / 8,252 / 3,763, and 3 types the brief omitted — `system_notice` (48), `error` (25), `file_search` (5), plus `run_interrupt_result` (23). |
| `nodes` 9,404, `context_transfers` 137, `subagents` 69, threads 656, projects 45 | Growth only: 9,628 / 141 / 70 / 660 / 46. |
| `:3773` returns SPA HTML for `/api/threads` — so no REST | Confirmed for unauthenticated `GET`. **Correction:** the auth-pairing endpoint and the `/ws` orchestration RPC are real; only the SPA routes are a catch-all. The MCP server is a separate channel. |
| MCP read path list | Complete, plus tools the brief did not name: `t3_thread_launch`, `create_threads`, `t3_worktree_*`, `delegate_task`/`task_*`/`orchestrator_capabilities`, `t3_project_*`, `preview_*`, `schedule_task`, `device_*`, PR watch/link tools. |

## Added findings not in the brief

1. **`orchestration_events` is the live v2 event log** (67,903 rows, 34 event
   types, written seconds ago) even though its name lacks `_v2_`.
   `orchestration_v2_events` exists and is empty. Events carry full DTO snapshots,
   `stream_version` per thread, and `actor_kind: server`.
2. **`projection_projects` is live** (46 rows, updated minutes ago) — there is no
   v2 project table. Both the "legacy" and "live" naming intuitions are wrong here.
3. **`turn_items.ordinal` is a composite key, not a sequence.** Formula:
   `runOrdinal × 1_000_000 + itemIndexInRun` (run 1 → `1000001`; v1 imports start
   at `1`; a 47-run thread reaches `47000005`). It is still unique per thread, so
   `ORDER BY ordinal` is valid — just do not interpret the value as a position.
   `orchestration_v2_turn_item_positions` carries the same formula and is what
   MCP's `position` derives from.
4. **`thread_id` is not always a UUID.** Subagent threads are
   `thread:delegated-task:command%3A<uuid>%3Adelegate-task%3A<slug>`, and they do
   exist as rows in `orchestration_v2_projection_threads`.
5. **The FTS index deliberately excludes** streamed-in-progress messages,
   agent-authored user messages (`createdBy: agent`), all subagent threads, and
   everything that is not a `messages` row (so `reasoning`, `command_execution`
   output, diffs are unsearchable).
6. **`snippet()`/`highlight()` return NULL** on this contentless index; reconstruct
   snippets by joining `rowid` to `orchestration_v2_projection_messages`.
7. **Trigram means no terms under 3 characters.** `pi` and `ai` match 0 rows
   silently.
8. **`sqlite3` CLI 3.50.6 here has no FTS5**; `python3`'s module (3.53.0) does.
9. **`modelSelection.options` is an array** of `{id, value}`, not an object.
10. **`opens.openedAt` is epoch milliseconds** while all other timestamps are ISO
    strings.
11. **`run_attempts.payload_json.nativeThreadId`** leaks the provider's own session
    handle — for the `pi` driver it is an absolute path into
    `~/.pi/agent/sessions/…`.
12. **`orchestration_v2_effect_outbox`** (660 rows) is a per-thread effect ledger,
    not part of the read model.

## Not verified / out of scope

- Whether the UI has any internal IPC to the server (only HTTP was probed).
- Behaviour under a concurrent writer beyond the WAL contention observed while
  reading.
- Anything in `state.sqlite` beyond the four counts checked (it is explicitly
  out of scope for v2).
- Retention policy for `logs/provider/*.log` beyond the observed 7 files.
