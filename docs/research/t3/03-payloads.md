# 03 — `payload_json` reference

Every v2 projection table stores a full DTO in `payload_json`. The scalar columns
are a denormalized subset used for indexing. These shapes were read directly from
the database, not from source.

## Thread DTO

`orchestration_v2_projection_threads.payload_json` — key coverage across all 660
rows (count of rows carrying the key):

```
createdBy 660   creationSource 660   id 660   projectId 660   title 660
providerInstanceId 660   modelSelection 660   runtimeMode 660
interactionMode 660   branch 660   worktreePath 660
activeProviderThreadId 660   lineage 660   forkedFrom 660
createdAt 660   updatedAt 660   archivedAt 660
settledOverride 660   settledAt 660   snoozedUntil 660   snoozedAt 660
lastVisitedAt 660   deletedAt 660
pullRequests 654   linkedPullRequest 618   activeOrderKey 616
pinnedAt 592   pinOrderKey 592   unsettledAt 585
branchPullRequest 547   historyOrigin 538
titleRegeneration 120   opens 31   limitRecovery 29
```

Verbatim example (a fresh `web` thread in `full-access` mode):

```json
{
  "createdBy": "user",
  "creationSource": "web",
  "id": "c7504a0c-1d54-476d-b931-af0ffc93e87a",
  "projectId": "68d08718-02f7-4c4a-9227-e3b0af1a9450",
  "title": "**This is research for T3 code's exposure of threa...",
  "providerInstanceId": "pi",
  "modelSelection": {
    "instanceId": "pi",
    "model": "opencode-go/deepseek-v4.1-flash",
    "options": [ { "id": "thinking", "value": "high" } ]
  },
  "runtimeMode": "full-access",
  "interactionMode": "default",
  "branch": "master",
  "worktreePath": null,
  "pullRequests": [],
  "activeProviderThreadId": "provider-thread:provider:pi:native-thread:pending%3Arun%3Athread%3Ac7504a0c-…%3Aordinal%3A1",
  "lineage": {
    "parentThreadId": null,
    "relationshipToParent": null,
    "rootThreadId": "c7504a0c-1d54-476d-b931-af0ffc93e87a"
  },
  "forkedFrom": null,
  "createdAt": "2026-10-24T19:39:56.796Z",
  "updatedAt": "2026-10-24T19:40:20.481Z",
  "archivedAt": null,
  "settledOverride": null,
  "settledAt": null,
  "snoozedUntil": null,
  "snoozedAt": null,
  "lastVisitedAt": "2026-10-24T19:39:56.868Z",
  "opens": { "openedAt": 1792870796930, "score": 1, "picks": [] },
  "titleRegeneration": null,
  "deletedAt": null
}
```

Notes:

- `modelSelection.options` is an **array of `{id, value}`** (e.g.
  `{"id":"thinking","value":"high"}`), not an object. Provider/model ids come from
  the live catalog; `providerInstanceId` is the instance (e.g. `pi`, `codex`,
  `opencode_2`, `claudeAgent`).
- `lineage.relationshipToParent` ∈ {`null`, `fork`, `subagent`}.
- `opens.openedAt` is **epoch milliseconds** while every other timestamp is ISO
  Zulu. Mixing these up silently breaks recency sorts.
- UI/organization state that v1 kept in `projection_threads` columns lives here:
  `pinnedAt`, `pinOrderKey`, `settledAt`, `settledOverride`, `unsettledAt`,
  `snoozedUntil`, `snoozedAt`, `lastVisitedAt`, `activeOrderKey`, `opens`,
  `titleRegeneration`, `linkedPullRequest`, `branchPullRequest`, `pullRequests`,
  `limitRecovery`, `historyOrigin`.
- `historyOrigin` (538 rows) marks the v1-imported threads.

## Run DTO

```json
{
  "id": "run:thread:0bee9927-…:ordinal:1",
  "threadId": "0bee9927-…",
  "ordinal": 1,
  "providerInstanceId": "pi",
  "modelSelection": { "instanceId": "pi", "model": "opencode-go/glm-5.3" },
  "providerThreadId": "provider-thread:provider:pi:native-thread:pending%3A…",
  "userMessageId": "138d60c3-…",
  "rootNodeId": "node:run:run%3Athread%3A0bee9927-…%3Aordinal%3A1:root",
  "activeAttemptId": "run-attempt:run:run%3A…:attempt:1",
  "status": "completed",
  "queuePosition": null,
  "requestedAt": "2026-10-24T19:41:27.580Z",
  "startedAt": "2026-10-24T19:41:31.146Z",
  "completedAt": "2026-10-24T19:42:14.789Z",
  "checkpointId": "checkpoint:scope:checkpoint-scope%3Athread%3A0bee9927-…%3Aname%3Aroot:name:1",
  "contextHandoffId": null,
  "workspacePreparation": { "type": "root", "branch": "master" }
}
```

`workspacePreparation.type` ∈ {`root`, `worktree`, `existing_worktree`} — this is
how you tell whether a run wrote into the project checkout or into
`~/.t3/worktrees/…`.

## Run attempt DTO

```json
{
  "id": "run-attempt:run:run%3Athread:0bee9927-…:attempt:1",
  "nativeThreadId": "/home/bond/.pi/agent/sessions/--mnt-…--/2026-10-24T19-41-27-929Z_01a16…",
  "runId": "run:thread:0bee9927-…:ordinal:1",
  "attemptOrdinal": 1,
  "rootNodeId": "node:run:…:root",
  "providerInstanceId": "pi",
  "providerThreadId": "provider-thread:provider:pi:native-thread:pending%3A…",
  "providerTurnId": null,
  "reason": "initial",
  "status": "completed",
  "startedAt": "…",
  "completedAt": "…"
}
```

## Node DTO

Keys present on all 9628 rows:
`id, threadId, runId, parentNodeId, rootNodeId, kind, status, countsForRun,
providerThreadId, providerTurnId, nativeItemRef, runtimeRequestId,
checkpointScopeId, startedAt, completedAt`.

```json
{
  "id": "node:provider:codex:native-item:exec-9b187618-…",
  "threadId": "f9af912a-…",
  "runId": "run:thread:f9af912a-…:ordinal:1",
  "parentNodeId": "node:run:run%3Athread%3Af9af912a-…%3Aordinal%3A1:root",
  "rootNodeId": "node:run:run%3Athread%3Af9af912a-…%3Aordinal%3A1:root",
  "kind": "tool_call",
  "status": "completed",
  "countsForRun": false,
  "providerThreadId": "provider-thread:provider:codex:native-thread:pending%3A…",
  "nativeItemRef": { "driver": "codex", "nativeId": "exec-9b187618-…", "strength": "strong" }
}
```

## Turn item DTOs

Common to all 19 types: `id, threadId, runId, nodeId, providerThreadId,
providerTurnId, nativeItemRef, parentItemId, ordinal, status, title, type,
startedAt, completedAt, updatedAt`.

`nativeItemRef` = `{driver, nativeId, strength}` or `null`. Distribution:
`null` 10,053; `codex|strong` 7,026; `pi|strong` 1,360; `opencode|strong` 876.

Type-specific fields:

| type | extra fields |
|---|---|
| `user_message` | `text`, `messageId`, `attachments[]`, `context`, `createdBy`, `creationSource`, `senderThreadId`, `inputIntent` |
| `assistant_message` | `text`, `messageId`, `streaming` |
| `reasoning` | `text`, `streaming` |
| `command_execution` | `input`, `output`, `exitCode` |
| `file_change` | `fileName`, `changes`, `diffStr`, `oldStr`, `newStr` |
| `dynamic_tool` | `toolName`, `toolSource`, `input`, `output` |
| `checkpoint` | `checkpointId`, `scopeId`, `files` |
| `subagent` | `subagentId`, `childThreadId`, `origin`, `driver`, `providerInstanceId`, `prompt`, `result` |
| `handoff` | `contextHandoffId`, `strategy`, `summary`, `fromProviderInstanceIds`, `fromProviderThreadIds`, `fromModelSelections`, `toProviderInstanceId`, `toProviderThreadId`, `toModel` |
| `notification` | `source`, `summary`, `detail`, `outcome` |
| `todo_list` | `planId`, `steps`, `explanation` |
| `user_input_request` | `requestId`, `questions`, `questionAnswer`, `responseMode` |
| `web_search` | `patterns`, `results` |
| `file_search` | `pattern`, `results` |
| `error` | `failure`, `retry` |
| `run_interrupt_request` / `run_interrupt_result` | `message` |
| `system_notice` | `message` |
| `compaction` | `driver` |

### Text is complete — measured maxima

`max(length(json payload))` = 592,320 bytes; the largest single text values are
`user_message` 83,864 chars, `assistant_message` 33,770, `reasoning` 32,496, and
`command_execution` output in the tens of KB. **The database does not truncate.**

### Attachment references

`user_message.attachments[]` entries look like:

```json
{ "type": "file",
  "id": "0b83c89f-d600-4dfd-bb35-225c263e8fe2-1540c9c2-290b-4063-b084-40e78b4acf54-md",
  "name": "registry-template-rebuild-revised.md",
  "mimeType": "text/markdown", "sizeBytes": 67264 }
```

`id` is exactly the on-disk basename minus the final extension:
`~/.t3/userdata/attachments/<id>.md` (verified: 67,264 bytes on disk). The
prefixed UUID is the **thread id**. `user_message.context` additionally carries
`{version:1, records:[{contextId, label, kind, attachmentId, name, mimeType,
sizeBytes}]}`.

## Subagent DTO

```json
{
  "id": "node:delegated-task:command%3Amcp%3A88a017ca-…%3Adelegate-task%3Aregistry-rebuild-d01-luna-medium-v1",
  "threadId": "0b83c89f-…",
  "runId": "run:thread:0b83c89f-…:ordinal:3",
  "parentNodeId": "node:run:run%3Athread%3A0b83c89f-…%3Aordinal%3A3:root",
  "origin": "app_owned",
  "createdBy": "agent",
  "driver": "codex",
  "providerInstanceId": "codex",
  "providerThreadId": "provider-thread:provider:codex:native-thread:pending%3A…",
  "childThreadId": "thread:delegated-task:command%3Amcp%3A88a017ca-…%3Adelegate-task%3Aregistry-rebuild-d01-luna-medium-v1",
  "nativeTaskRef": null,
  "prompt": "Act as the implementation sub-agent for this task. …",
  "title": "D01 baseline and committed requirements",
  "model": "gpt-6-luna",
  "completionWake": "always",
  "completionDelivery": { "state": "delivered", "observedByRunId": null },
  "status": "completed",
  "result": "Completed D01 on `feat/registry-template-rebuild`: …",
  "startedAt": "2026-10-24T01:51:37.635Z",
  "completedAt": "2026-10-24T01:53:06.830Z"
}
```

`prompt` and `result` are full text. `completionDelivery.state` records whether
the parent was woken; `observedByRunId` names the run that consumed it.

## Context handoff and context transfer

Handoff (`strategy` = how context is rebuilt for the new provider):

```json
{
  "id": "context-handoff:thread:95773058-…:from-provider-instance:opencode_2:to-provider-instance:pi:e88efb76-…",
  "transferId": "context-transfer:type:provider_handoff:source-thread:95773058-…:target-thread:95773058-…:ae12a6a7-…",
  "threadId": "95773058-…",
  "targetRunId": "run:thread:95773058-…:ordinal:2",
  "fromProviderThreadIds": ["provider-thread:provider:pi:native-thread:pending%3A…"],
  "strategy": "full_thread_summary",
  "status": "ready"
}
```

Transfer (`type` = why context moved), includes the fork source point:

```json
{
  "id": "context-transfer:type:fork:source-thread:af32e5ec-…:target-thread:82ddb4cc-…:bc50e6ed-…",
  "type": "fork",
  "sourceThreadId": "af32e5ec-…",
  "targetThreadId": "82ddb4cc-…",
  "sourcePoint": {
    "threadId": "af32e5ec-…",
    "runId": "run:thread:af32e5ec-…:ordinal:3",
    "checkpointId": "checkpoint:scope:checkpoint-scope%3Athread%3Aaf32e5ec-…%3Aname%3Aroot:name:3",
    "providerThreadRef": { "driver": "codex", "nativeId": "01a16abe-…", "strength": "strong" },
    "providerTurnRef":   { "driver": "codex", "nativeId": "01a16ac0-…", "strength": "strong" }
  },
  "basePoint": null
}
```

Fork → the new thread is a child with
`lineage.relationshipToParent = "fork"` and `forkedFrom` set.

## Plan DTO

Keys: `id, threadId, runId, nodeId, kind, status, steps` (+ `explanation` on 10 of
17 rows).

```json
{ "id": "plan:thread:21a2f581-…:provider:codex:run:…:ecb86865-…",
  "threadId": "21a2f581-…", "runId": "run:thread:21a2f581-…:ordinal:2",
  "nodeId": "node:provider:codex:native-item:turn-plan%3A01a16a68-…",
  "kind": "todo_list", "status": "active",
  "steps": [ { "id": "step-1", "text": "Inspect detection contracts…",
               "status": "completed", "durationMs": 170808 } ] }
```

## Runtime request DTO

Keys: `id, nodeId, providerTurnId, nativeRequestRef, kind, status,
responseCapability, createdAt, resolvedAt` (+ `answers` on answered rows).

```json
{ "id": "runtime-request:provider:pi:provider-turn:provider-turn%3A…:native-request:747c508f-…:33802cd2-…",
  "nodeId": "node:runtime-request:runtime-request%3A…",
  "providerTurnId": "provider-turn:provider:pi:native-turn:…",
  "nativeRequestRef": { "driver": "pi", "nativeId": "747c508f-…", "strength": "strong" },
  "kind": "user_input", "status": "resolved",
  "responseCapability": "…", "createdAt": "…", "resolvedAt": "…" }
```

The **question text** is not here — read the paired `user_input_request` turn
item (`questions[]`, `questionAnswer`, `responseMode`).

## Checkpoint / scope

```json
{ "id": "checkpoint:scope:checkpoint-scope%3Athread%3A4ecd8f09-…%3Aname%3Aroot:name:0",
  "threadId": "4ecd8f09-…",
  "scopeId": "checkpoint-scope:thread:4ecd8f09-…:name:root",
  "runId": null, "nodeId": "node:run:run%3Athread%3A4ecd8f09-…%3Aordinal:1:root" }
```
