# 05 — How thread data is exposed

## Two read paths, no third

1. **The desktop UI** (the app's own SPA).
2. **The T3-owned MCP server**, which is injected into agent sessions launched by
   T3 and exposes thread data as MCP tools.

Anything else has to read `statev2.sqlite` directly.

## There is no REST API — verified

The server on `:3773` returns the SPA shell for every path, including paths that
look like API routes:

```
/                -> 200 text/html 19492 bytes
/api/threads     -> 200 text/html 19492 bytes
/threads         -> 200 text/html 19492 bytes
/api/v1/threads  -> 200 text/html 19492 bytes
```

Identical byte counts and `content-type: text/html; charset=utf-8` in all four
cases; body is the same `<!doctype html>` document. So the HTTP surface is a
catch-all SPA fallback, not an API. (`GET`-only probe; no auth attempt was made.)

Endpoint details come from `~/.t3/userdata/server-runtime.json`
(`host: 0.0.0.0`, `port: 3773`, `origin: http://127.0.0.1:3773`,
`serverVersion: 0.1.3-nightly.20261024.3630`).

> Practical consequence: to read threads outside the app, `sqlite3` (read-only) is
> the only option. There is no documented HTTP or IPC interface to query.

## MCP tool surface

The T3 MCP server (registered as `t3-code`) exposes, by group:

**Threads**
`t3_thread_list`, `t3_thread_read`, `t3_thread_search`, `t3_thread_fork`,
`t3_thread_merge_back`, `t3_thread_transfers`, `t3_thread_configuration`,
`t3_thread_configure`, `t3_thread_update`, `t3_thread_organize`,
`t3_thread_interrupt`, `t3_thread_wait`, `t3_thread_send`,
`t3_thread_send_attachments`.

**Creation / workspace**
`t3_thread_launch` (binds a new or existing worktree *before* the agent starts),
`create_threads` (batch, inherits caller's checkout), `t3_worktree_handoff`,
`t3_worktree_status`, `t3_worktree_list`.

**Queue**: `t3_queue_list`, `t3_queue_read`, `t3_queue_edit`, `t3_queue_cancel`,
`t3_queue_reorder`, `t3_queue_promote_to_steer`.

**Pending input**: `t3_pending_request_list`, `t3_pending_request_read`,
`t3_pending_request_respond` (answers questions only — it cannot grant an
approval).

**Delegation**: `delegate_task`, `task_status`, `task_cancel`,
`orchestrator_capabilities`.

**Projects**: `t3_project_list`, `t3_project_read`, `t3_project_create`,
`t3_project_update`, `t3_project_delete`, `t3_project_clone`.

**PRs / previews / scheduling / devices**: `link_pull_request`,
`unlink_pull_request`, `list_thread_pull_requests`, `watch_pull_request`,
`unwatch_pull_request`, `write_pull_request_guides`,
`read_pull_request_guide`, `t3_preview_list`, `t3_preview_close`,
`preview_*` (browser automation), `schedule_task`, `list_scheduled_tasks`,
`update_scheduled_task`, `delete_scheduled_task`, `run_scheduled_task_now`,
`device_list`, `device_open`, `device_close`, `device_screenshot`.

Note the asymmetry: MCP can read threads, but there is **no MCP tool that returns
subagent prompt/result bodies for an arbitrary thread** the way the DB does — for
corpus-level analysis, go to SQL.

## `t3_thread_read` — paging and truncation

Two views: `view: "messages"` (user/assistant messages + proposed plans) and
`view: "activity"` (all summarized timeline items, i.e. every turn item type).

Response shape:

```json
{ "thread": { "threadId", "projectId", "title", "createdBy", "creationSource",
              "status", "latestRunId", "activeRunId", "providerInstanceId",
              "model", "runtimeMode", "interactionMode", "linkedPullRequest",
              "pullRequests", "titleRegeneration", "branch", "worktreePath",
              "parentThreadId", "relationshipToParent", "runCount", "itemCount",
              "pendingRequestCount", "archived", "settled", "settledAt",
              "snoozed", "snoozedUntil", "createdAt", "updatedAt" },
  "recentRuns": [],
  "items": [ { "position", "visibility", "sourceThreadId", "itemId",
               "runId", "messageId", "createdBy", "creationSource", "type",
               "status", "title", "text", "textTruncated", "nextTextOffset",
               "updatedAt" } ],
  "nextPosition": 2,
  "hasMore": true }
```

Truncation is per item and explicit. Verified against a 83,864-char
`user_message` with `maxCharsPerItem: 300`:

```json
{ "itemId": "migration:v1:turn-item:09592bc7-…",
  "text": "Apply this patch to @go-sense-4 : diff -ruN a/internal/detect/…",
  "textTruncated": true,
  "nextTextOffset": 300 }
```

To read the whole item: call `t3_thread_read` with `itemId` and
`textOffset: nextTextOffset`, repeating while `nextTextOffset != null`. Default
token budget `maxCharsPerItem` caps at 50,000 characters (tool schema: 1–50,000). **The database has the full text unbroken** — paging
is only needed when going through MCP.

Statuses surfaced by MCP (`status`, `settled`, `snoozed`, …) are *derived*
on read from the v2 tables; there is no `status` column on
`orchestration_v2_projection_threads`.

## Correlating MCP output with SQL

| MCP field | Source |
|---|---|
| `thread.threadId` | `orchestration_v2_projection_threads.thread_id` |
| `thread.title`, `branch`, `worktreePath`, `model`, `providerInstanceId` | thread `payload_json` |
| `thread.settled` / `settledAt` / `snoozed` / `archived` | `payload_json.settledAt` / `snoozedUntil` / `archivedAt` |
| `items[].itemId` | `orchestration_v2_projection_turn_items.turn_item_id` |
| `items[].position` | index into `orchestration_v2_turn_item_positions` ordering (0-based; the SQL `ordinal` is composite, see [02-schema.md](02-schema.md)) |
| `items[].text` | `payload_json.text` (or `.output`/`.diffStr` for non-message types) |
| `recentRuns[]` | `orchestration_v2_projection_runs` |

`items[].position` starting at `0` while `turn_item_positions.ordinal` starts at
`1` is the one off-by-one to watch.
