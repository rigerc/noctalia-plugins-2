# T3 Monitor

Local read-only T3 Code monitoring for **Noctalia v5, plugin API 36**.

## What it does

- Shows separate working parent and active subagent counts in the bar.
- Keeps attention indicators visible until verified requests are resolved.
- Shows a unified list of active parent threads, with subagents nested under the parent.
- Keeps idle parent rows visible when their child subagents still work.
- Displays subagent progress, provider/model and timings when present in T3's projections.
- Sends a notification when each parent run or subagent completes; attributes pending-attention requests to a child only when supported by evidence.
- Deduplicates notifications, including a 10-minute restart catch-up window.
- Uses **no remote connection or persistent companion daemon**.

**Read-only:** the plugin does not send prompts, approve tool requests or change T3 project/thread state.

## Requirements

- T3 Code running locally, with the official `t3` command on `PATH`.
- `sqlite3` executable on `PATH` with `-json` support.
- T3 orchestration V2 (`statev2.sqlite`) and Noctalia plugin API 36.

## Install

Register this repository as a Noctalia plugin source if not already registered:

```sh
noctalia msg plugins source add rigerc git git@github.com:rigerc/noctalia-plugins-2.git
noctalia msg plugins enable rigerc/t3
```

Add the **T3 / status** bar widget in Settings → Bar. Click to open the attached panel, or run:

```sh
noctalia msg panel-toggle rigerc/t3:dashboard
```

## Settings

In **Settings → Plugins → T3 Monitor** you can override T3 home, database path,
the `t3` and `sqlite3` executables, exclude individual project IDs, and toggle
completion/attention notifications. Defaults use `T3CODE_HOME` or `~/.t3`.

Polling aims for 5 seconds while work is active and 30 seconds when idle.
A failed poll produces an offline indicator and never treats work as completed.

## Implementation

`service.luau` invokes `t3 thread list --project ID --json` to read parent
thread status and `t3 thread show ID --json` when pending requests need verification.
SQLite read-only queries find projects, subagents and pending-request hints.
The Noctalia service publishes normalized state; the bar and panel subscribe.

The standard T3 CLI excludes subagents, so this plugin reads
`orchestration_v2_projection_subagents` directly. Schema changes are detected as
errors rather than silently showing incorrect information. Subagent completion
is based on the subagent record itself, not parent run completion.

## Known limitations

- SQLite projection schema is internal to T3 Code and may change on upgrade.
- Subagent progress is optional and may be missing for some providers.
- A waiting subagent is *not* automatically proof of a user-actionable request;
  attribution requires request evidence.
- Parent-thread polling through the CLI starts a short-lived local MCP session
  per project on each refresh, so installations with many projects may refresh
  slower than the target interval.
- Unobserved very short-lived work that has already vanished from T3 projections
  cannot be recovered; the plugin does not fabricate events.

## Development

Run repository validation and tests:

```sh
python3 .github/workflows/validate-plugins.py
python3 -m unittest discover -s .github/workflows -p 'test_validate_plugins.py'
```

See [design plan](../docs/plans/t3-monitor.md).
