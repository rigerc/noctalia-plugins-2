# 04 — Message search (FTS5)

## What exists

```sql
CREATE VIRTUAL TABLE orchestration_v2_message_search USING fts5(
  text,
  content = '',              -- contentless: stores no copy of the text
  contentless_delete = 1,    -- rows deletable/updatable without the original
  tokenize = 'trigram remove_diacritics 1'
);
```

9889 indexed rows, exactly matching the 9889 eligible source messages — coverage
is complete, not sampled. `rowid` of the FTS row **equals**
`orchestration_v2_projection_messages.rowid`, so a join reconstructs results.

## What gets indexed

From the `orchestration_v2_message_search_insert` trigger, a message is indexed
only when **all** of these hold:

1. `streaming = 0` (partial streamed text is never indexed);
2. `role = 'assistant'`, **or** `role = 'user'` with
   `payload_json.createdBy` absent or `'user'`;
3. its thread is **not** a subagent thread, i.e. no
   `orchestration_v2_projection_threads` row for it with
   `payload_json.lineage.relationshipToParent = 'subagent'`.

Consequences you must design around:

- **Agent-authored `user_message` rows are invisible.** Steering messages injected
  by another agent (`createdBy: "agent"`) are excluded on purpose.
- **Subagent transcripts are invisible.** 68 subagent threads are excluded, so a
  full-corpus search must fall back to `LIKE` on `payload_json` for those.
- `reasoning` and `command_execution` output are **not** in the index at all —
  only `messages` rows are. Turn items are not indexed.
- Two `’`/`‘` characters are normalized to `'`; nothing else is normalized.
- Deletes/updates are maintained by triggers, so the index stays consistent.

## Tokenizer behaviour (trigram) — verified

Findings from probing the live index:

| query | rows | note |
|---|---|---|
| `worktree` | 171 | substring match |
| `mcp` | 967 | |
| `subagent*` | 116 | prefix star is accepted, cheap |
| `"delegate task"` | 1 | phrase query works |
| `NEAR(delegate task)` | 5 | positional operators work |
| `ai` | 0 | **terms shorter than 3 chars cannot match** — returns 0, no error |
| `pi` | 0 | same; `pi` appears everywhere but is unsearchable as a token |

Trigram means *substring* search, so `worktree` also matches `worktrees` and
`git-worktree`. It also means case-insensitive matching only via
`remove_diacritics`, and no stemming — plan queries accordingly (≥3 chars).

## The CLI cannot read it

`sqlite3` CLI here is **3.50.6 without FTS5**:

```
$ sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(a);"
Error: stepping, no such module: fts5
$ sqlite3 "$DB" "SELECT count(*) FROM orchestration_v2_message_search;"
Error: in prepare, no such module: fts5
```

The `python3` `sqlite3` module (SQLite 3.53.0) does have FTS5. Use it.

## Recipes

### Count matches

```python
import sqlite3
con = sqlite3.connect("file:" + __import__("os").path.expanduser(
    "~/.t3/userdata/statev2.sqlite") + "?mode=ro", uri=True)
con.execute("SELECT count(*) FROM orchestration_v2_message_search "
            "WHERE orchestration_v2_message_search MATCH ?", ("subagent*",)).fetchone()
```

### Search with results (the join matters)

`MATCH` requires the **table name**, not an alias, as its left operand:

```python
q = """
SELECT m.thread_id, m.role, m.created_at,
       substr(json_extract(m.payload_json,'$.text'), 1, 240) AS snippet
FROM orchestration_v2_message_search
JOIN orchestration_v2_projection_messages m
  ON m.rowid = orchestration_v2_message_search.rowid
WHERE orchestration_v2_message_search MATCH ?
ORDER BY m.created_at DESC
LIMIT 50
"""
for row in con.execute(q, ('"context handoff"',)):
    print(row)
```

Verified working. `snippet()` and `highlight()` return `NULL` on this contentless
table (there is no stored text to snip), so build snippets from the join instead.

```python
# this returns None, by design:
con.execute("SELECT snippet(orchestration_v2_message_search,0,'[',']','…',8) "
            "FROM orchestration_v2_message_search "
            "WHERE orchestration_v2_message_search MATCH 'worktree' LIMIT 1").fetchone()
```

### Full-corpus fallback (subagents, reasoning, tool output)

```sql
SELECT thread_id, type, substr(json_extract(payload_json,'$.text'),1,200)
FROM orchestration_v2_projection_turn_items
WHERE payload_json LIKE '%delegate_task%'
LIMIT 50;
```

`LIKE '%…%'` over `payload_json` is a full scan of ~19k rows / ~500 MB of JSON —
acceptable interactively (sub-second to a few seconds), not for a tight loop.
For repeated work, materialize an extraction table once:

```sql
CREATE TABLE work_items AS
SELECT turn_item_id, thread_id, type,
       json_extract(payload_json,'$.text')     AS text,
       json_extract(payload_json,'$.input')    AS input,
       json_extract(payload_json,'$.output')   AS output,
       json_extract(payload_json,'$.diffStr')  AS diff
FROM orchestration_v2_projection_turn_items;
```

(Create that in a **copy** of the DB, never in the live one — the app owns it.)

### Ranked search across a project

```sql
SELECT t.title, count(*) AS hits
FROM orchestration_v2_message_search
JOIN orchestration_v2_projection_messages m
  ON m.rowid = orchestration_v2_message_search.rowid
JOIN orchestration_v2_projection_threads t ON t.thread_id = m.thread_id
WHERE orchestration_v2_message_search MATCH ?
  AND t.project_id = ?
GROUP BY t.thread_id
ORDER BY hits DESC;
```
