# 06 — Files and artifacts keyed by thread

Everything below was verified in `~/.t3/` on this machine.

## Attachments — `userdata/attachments/`

18 files. Filename = `<attachmentId>.<ext>`, and `attachmentId` is exactly the
`id` in `user_message.attachments[]` / `context.records[].attachmentId`:

```
0b83c89f-d600-4dfd-bb35-225c263e8fe2-1540c9c2-290b-4063-b084-40e78b4acf54-md.md
└────── thread id ─────────────┘ └──────────── uuid ───────────┘ └name┘ └ext┘
```

- First segment is the **thread id** (verified: `0b83c89f…` = the "Rebuild
  Registry Templates" thread's attachment, 67,264 bytes = `sizeBytes` in the DTO).
- Second segment is a per-attachment UUID; third is a sanitized name; the trailing
  extension is appended by the store (`.md`, `.mjs`, `.html`, `.png`, `.zip`,
  `.patch`).
- The mid-segment sometimes already encodes the extension token (`-md`, `-mjs`),
  so the visible suffix appears twice — parse the `attachmentId` from the DB, not
  from the filename.

Resolution:

```sql
SELECT json_extract(j.value,'$.id')     AS attachment_id,
       json_extract(j.value,'$.name')   AS name,
       json_extract(j.value,'$.sizeBytes') AS bytes
FROM orchestration_v2_projection_turn_items t,
     json_each(json_extract(t.payload_json,'$.attachments')) j
WHERE t.type = 'user_message';
-- then: ~/.t3/userdata/attachments/<attachment_id>.<ext>
```

## Provider protocol logs — `userdata/logs/provider/`

`events.<threadId>.log`, rotated to `.1`, `.2`, … at ~10 MB (observed:
10,484,127 / 10,471,626 / 10,472,416 / 10,412,028 bytes — all ≈10 MiB). Only 7
files exist here (3 threads), so retention is short/aggressive.

Format: one JSON event per line, prefixed with an ISO timestamp and a tag:

```
[2026-10-24T19:13:02.994Z] NTIVE: {"provider":"codex","protocol":"codex.app-server",
  "kind":"protocol","providerSessionId":"provider-session:provider-instance:codex:shared",
  "event":{"direction":"incoming","stage":"decoded",
           "payload":{"method":"item/completed","params":{...}}}}
```

Fields worth knowing: `provider`, `protocol` (e.g. `codex.app-server`), `kind`,
`providerSessionId`, `event.direction` (`incoming`/`outgoing`), `event.stage`
(`decoded`/…), `event.payload` (raw provider frame). This is the ground truth if a
projection looks wrong.

## Worktrees — `worktrees/<project-slug>/t3-<hash8>/`

2.4 GB total. Layout is **`<project-slug>/t3-<8 hex>/`**, one directory per
worktree-bound thread:

```
worktrees/conduit/                  3
worktrees/my-skills/                2
worktrees/noctalia-plugins/         2
worktrees/nosey/                   14
worktrees/nosey-registry-template/  3
worktrees/takt/                     1
```

A checked-out example is on branch `t3/review-skill-mappings-script` — T3 creates
its own branch namespace (`t3/<slug>`). The corresponding thread row carries
`payload_json.worktreePath` and `payload_json.branch`; `runs.workspacePreparation`
records `{"type":"worktree"}` for these runs.

Worktrees are **not** deleted when a thread is deleted (explicit in the MCP tool
contract). Expect orphans.

## Scratch — `scratch/<date>-<slug>-<hash8>/`

Project-less threads (created with `scratch: true`). Naming verified:

```
2026-10-07-analyze-the-ue5-game-located-5182b112
2026-10-24-hi-1c5da7a9
2026-10-24-hi-2096e8e3
2026-10-24-hi-60ec3f31
2026-10-24-inspect-the-delegate-task-tool-931fb036
```

`<YYYY-MM-DD>-<title-slug>-<8 hex>`. Some are empty (checkout never used).

## PR cache — `caches/pull-requests/`

29 entries, JSON, filename `pr-v2<64-hex-digest>` (69 chars: `pr-` + version tag +
SHA-256). Content is the fetched PR payload, not a thread index — map back through
the thread DTO instead:

```sql
SELECT thread_id,
       json_extract(payload_json,'$.linkedPullRequest') AS linked,
       json_extract(payload_json,'$.pullRequests')      AS all_prs,
       json_extract(payload_json,'$.branchPullRequest') AS branch_pr
FROM orchestration_v2_projection_threads
WHERE json_extract(payload_json,'$.linkedPullRequest') IS NOT NULL;
```

`linkedPullRequest` is the legacy single link and may be `null` while
`pullRequests[]` is non-empty (618 vs 654 rows carrying each key).

Note: `projection_thread_pull_requests`, `pull_request_files_viewed` and
`pull_request_review_guides` (all in `statev2.sqlite`) are **empty** — PR state is
not in those tables on this machine.

## Other caches worth knowing

- `caches/<providerInstance>.json` — per-instance provider config
  (`codex.json`, `opencode_2.json`, `pi.json`, `claudeAgent.json`, `grok.json`,
  `muse.json`, `cursor.json`, `antigravity.json`).
- `caches/acp-registry/` — ACP agent registry.
- `caches/pi-t3-mcp-extension.ts` — an extension file T3 installs for the pi
  driver so that the T3 MCP server reaches the agent.
- `userdata/model-manifest.json` — the model catalog behind
  `orchestrator_capabilities`.
- `userdata/usage-model-rates.json`, `usage-scan-cache-v9.json` — pricing/usage
  scan caches (multi-MB; keyed by model, not thread).

## Disk budget (this machine)

| Path | Size |
|---|---|
| `userdata/state.sqlite` (v1) | 1.7 GB |
| `userdata/statev2.sqlite` (+ ~14 MB WAL) | 1.6 GB |
| `worktrees/` | 2.4 GB |
| `userdata/logs/provider/` | ~55 MB |
| `userdata/attachments/` | 18 files |

`state.sqlite` is the single largest disposable item — it holds only pre-cutover
data.
