-- Reducer contract tests for the T3 monitor.
-- Plain Lua 5.4: run with `lua5.4 .github/workflows/t3_reducer_test.lua`.
-- Fixture timestamps are 2026-10-27T10:0x:00Z; NOW is 10:05:00Z.

local reducer = dofile("t3/reducer.luau")

local NOW = 1793095500
local failures, checks = 0, 0

local function check(condition, message)
  checks = checks + 1
  if not condition then
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
  end
end

local function equal(actual, expected, message)
  check(actual == expected, string.format("%s (expected %s, got %s)", message,
    tostring(expected), tostring(actual)))
end

local function config(over)
  local value = {
    now = NOW,
    excluded = {},
    notifyCompletions = true,
    notifyAttention = true,
    tokenFile = "/tmp/token",
  }
  for key, item in pairs(over or {}) do value[key] = item end
  return value
end

local function project(id, title)
  return { id = id, title = title }
end

local function thread(id, over)
  local value = {
    id = id,
    projectId = "alpha",
    title = id,
    status = "idle",
    provider = "codex",
    model = "gpt",
    parentId = nil,
    relationship = nil,
    pendingRequest = nil,
    latestRunId = nil,
    latestRunStartedAt = nil,
    latestRunCompletedAt = nil,
    updatedAt = "2026-10-27T10:00:00.000Z",
    archivedAt = nil,
  }
  for key, item in pairs(over or {}) do value[key] = item end
  return value
end

local function snapshot(threads, over)
  local value = {
    type = "snapshot",
    scope = "full",
    sequence = 1,
    projects = { project("alpha", "Alpha"), project("beta", "Beta") },
    threads = threads,
  }
  for key, item in pairs(over or {}) do value[key] = item end
  return value
end

local function update(value)
  return { type = "thread.updated", thread = value }
end

local function applyAll(state, events, over)
  local notifications = {}
  for _, event in ipairs(events) do
    for _, notification in ipairs(reducer.apply(state, event, config(over))) do
      notifications[#notifications + 1] = notification
    end
  end
  return notifications
end

local function titles(notifications)
  local out = {}
  for _, notification in ipairs(notifications) do out[#out + 1] = notification.title end
  return table.concat(out, "|")
end

local function runningParent(id, over)
  local value = {
    status = "running", latestRunId = "run-" .. id, latestRunStartedAt = "2026-10-27T10:00:00.000Z",
    updatedAt = "2026-10-27T10:01:00.000Z",
  }
  for key, item in pairs(over or {}) do value[key] = item end
  return thread(id, value)
end

local function subagent(id, parentId, over)
  local value = {
    parentId = parentId, relationship = "subagent", status = "running",
    latestRunId = "run-" .. id, latestRunStartedAt = "2026-10-27T10:00:00.000Z",
    updatedAt = "2026-10-27T10:01:00.000Z",
  }
  for key, item in pairs(over or {}) do value[key] = item end
  return thread(id, value)
end

-- 1. First launch: a baseline snapshot is silent and counted correctly.
do
  local state = reducer.newState()
  local notifications = applyAll(state, {
    snapshot({ runningParent("p1"), subagent("c1", "p1"), thread("p2", { status = "idle" }) }),
  })
  equal(#notifications, 0, "first launch is silent")
  local view = reducer.snapshot(state, config())
  equal(view.health, "ok", "snapshot is healthy")
  equal(view.parentCount, 1, "one working parent")
  equal(view.childCount, 1, "one active subagent")
  equal(view.attentionCount, 0, "no attention")
  equal(#view.parents, 1, "idle parents are hidden")
  equal(view.parents[1].children[1].title, "c1", "child nested under parent")
  equal(view.parents[1].children[1].provider, "codex", "child provider shown")
end

-- 2. Idle parent with a running child stays as a context row.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ thread("p1", { status = "idle" }), subagent("c1", "p1") }) })
  local view = reducer.snapshot(state, config())
  equal(view.parentCount, 0, "idle parent is not working")
  equal(view.childCount, 1, "child still counted")
  equal(#view.parents, 1, "context row kept")
  equal(view.parents[1].working, false, "context row is not working")
end

-- 3. Parent completion fires once, keyed by run id.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1") }) })
  local notifications = applyAll(state, {
    update(runningParent("p1", {
      status = "completed", latestRunCompletedAt = "2026-10-27T10:04:00.000Z",
      updatedAt = "2026-10-27T10:04:00.000Z",
    })),
  })
  equal(#notifications, 1, "parent completion notifies")
  equal(notifications[1].title, "T3 parent completed", "parent completion title")
  equal(notifications[1].body, "Alpha · p1", "parent completion body")
  local again = applyAll(state, {
    update(runningParent("p1", {
      status = "completed", latestRunCompletedAt = "2026-10-27T10:04:00.000Z",
      updatedAt = "2026-10-27T10:04:00.000Z",
    })),
  })
  equal(#again, 0, "duplicate parent completion suppressed")
end

-- 4. Two child completions in one snapshot both notify.
do
  local state = reducer.newState()
  applyAll(state, {
    snapshot({ runningParent("p1"), subagent("c1", "p1"), subagent("c2", "p1") }),
  })
  local notifications = applyAll(state, {
    snapshot({
      runningParent("p1"),
      subagent("c1", "p1", { status = "completed", latestRunCompletedAt = "2026-10-27T10:04:00.000Z", updatedAt = "2026-10-27T10:04:00.000Z" }),
      subagent("c2", "p1", { status = "completed", latestRunCompletedAt = "2026-10-27T10:04:30.000Z", updatedAt = "2026-10-27T10:04:30.000Z" }),
    }),
  })
  equal(#notifications, 2, "two child completions notify twice")
  equal(titles(notifications), "T3 subagent completed|T3 subagent completed", "child completion titles")
end

-- 5. A child completing a second run notifies again.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1"), subagent("c1", "p1") }) })
  applyAll(state, { update(subagent("c1", "p1", { status = "completed", latestRunCompletedAt = "2026-10-27T10:03:00.000Z", updatedAt = "2026-10-27T10:03:00.000Z" })) })
  applyAll(state, { update(subagent("c1", "p1", { status = "running", latestRunId = "run-c1b", latestRunCompletedAt = nil, updatedAt = "2026-10-27T10:03:30.000Z" })) })
  local notifications = applyAll(state, {
    update(subagent("c1", "p1", { status = "completed", latestRunId = "run-c1b", latestRunCompletedAt = "2026-10-27T10:04:00.000Z", updatedAt = "2026-10-27T10:04:00.000Z" })),
  })
  equal(#notifications, 1, "second run completion notifies again")
end

-- 6. Blocking attention notifies once; clearing it does not notify.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1") }) })
  local notifications = applyAll(state, {
    update(runningParent("p1", {
      status = "waiting",
      pendingRequest = { id = "r1", kind = "approval", blocking = true },
      updatedAt = "2026-10-27T10:03:00.000Z",
    })),
  })
  equal(#notifications, 1, "attention notifies")
  equal(notifications[1].title, "T3 needs attention", "attention title")
  local view = reducer.snapshot(state, config())
  equal(view.attentionCount, 1, "attention counted")
  equal(view.parents[1].attention, true, "parent row shows attention")
  local cleared = applyAll(state, {
    update(runningParent("p1", { status = "running", pendingRequest = nil, updatedAt = "2026-10-27T10:04:00.000Z" })),
  })
  equal(#cleared, 0, "clearing attention is silent")
  equal(reducer.snapshot(state, config()).attentionCount, 0, "attention cleared")
end

-- 7. Non-blocking requests are not attention.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1") }) })
  local notifications = applyAll(state, {
    update(runningParent("p1", {
      status = "waiting",
      pendingRequest = { id = "r2", kind = "question", blocking = false },
      updatedAt = "2026-10-27T10:03:00.000Z",
    })),
  })
  equal(#notifications, 0, "async question does not notify")
  equal(reducer.snapshot(state, config()).attentionCount, 0, "async question not counted")
end

-- 8. A child request is attributed to the child and its parent row.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1"), subagent("c1", "p1") }) })
  local notifications = applyAll(state, {
    update(subagent("c1", "p1", {
      status = "waiting",
      pendingRequest = { id = "r3", kind = "approval", blocking = true },
      updatedAt = "2026-10-27T10:03:00.000Z",
    })),
  })
  equal(#notifications, 1, "child attention notifies")
  equal(notifications[1].title, "T3 subagent needs attention", "child attention title")
  equal(notifications[1].body, "Alpha · p1 → c1", "child attention names parent and child")
  local view = reducer.snapshot(state, config())
  equal(view.attentionCount, 1, "one attention item")
  equal(view.parents[1].children[1].attention, true, "child row shows attention")
end

-- 9. Reconnect baseline: the same snapshot twice never duplicates events.
do
  local state = reducer.newState()
  local baseline = snapshot({ runningParent("p1"), subagent("c1", "p1") })
  applyAll(state, { baseline })
  local notifications = applyAll(state, { baseline, baseline })
  equal(#notifications, 0, "repeated baseline is silent")
end

-- 10. Restart within ten minutes replays a missed completion once.
do
  local ledger = { initialized = true, lastSync = NOW - 60, states = {
    ["parent:p1"] = { status = "running", runId = "run-p1", attention = false },
  }, emitted = {} }
  local state = reducer.newState(ledger)
  local notifications = applyAll(state, {
    snapshot({ runningParent("p1", {
      status = "completed", latestRunCompletedAt = "2026-10-27T10:04:00.000Z",
      updatedAt = "2026-10-27T10:04:00.000Z",
    }) }),
  })
  equal(#notifications, 1, "catch-up completion notifies within ten minutes")
end

-- 11. Restart beyond ten minutes stays silent.
do
  local ledger = { initialized = true, lastSync = NOW - 3600, states = {
    ["parent:p1"] = { status = "running", runId = "run-p1", attention = false },
  }, emitted = {} }
  local state = reducer.newState(ledger)
  local notifications = applyAll(state, {
    snapshot({ runningParent("p1", {
      status = "completed", latestRunCompletedAt = "2026-10-27T09:00:00.000Z",
      updatedAt = "2026-10-27T09:00:00.000Z",
    }) }),
  })
  equal(#notifications, 0, "stale completion is not a catch-up event")
end

-- 12. Excluded projects are invisible to the UI and notifications.
do
  local state = reducer.newState()
  local excluded = { alpha = true }
  applyAll(state, { snapshot({ runningParent("p1") }) }, { excluded = excluded })
  local notifications = applyAll(state, {
    update(runningParent("p1", {
      status = "completed", latestRunCompletedAt = "2026-10-27T10:04:00.000Z",
      updatedAt = "2026-10-27T10:04:00.000Z",
    })),
  }, { excluded = excluded })
  equal(#notifications, 0, "excluded project does not notify")
  local view = reducer.snapshot(state, config({ excluded = excluded }))
  equal(#view.parents, 0, "excluded project has no rows")
end

-- 13. A dropped bridge shows offline state and never fabricates completion.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1"), subagent("c1", "p1") }) })
  local notifications = applyAll(state, {
    { type = "health", state = "offline", reason = "disconnected", error = "T3 closed the WebSocket" },
  })
  equal(#notifications, 0, "disconnect is silent")
  local view = reducer.snapshot(state, config())
  equal(view.health, "offline", "offline health")
  equal(#view.parents, 0, "offline snapshot has no rows")
  equal(view.parentCount, 0, "offline snapshot has no parents")
  equal(state.ledger.states["parent:p1"].status, "running", "ledger kept across disconnect")
end

-- 14. A rejected token surfaces the exact recovery command.
do
  local state = reducer.newState()
  applyAll(state, { { type = "health", state = "offline", reason = "unauthorized", error = "T3 rejected the token." } })
  local view = reducer.snapshot(state, config())
  equal(view.health, "offline", "unauthorized is offline")
  check(type(view.tokenCommand) == "string" and view.tokenCommand:find("t3 auth session issue", 1, true) ~= nil,
    "token command is shown")
  check(view.tokenCommand:find("/tmp/token", 1, true) ~= nil, "token command names the token file")
end

-- 15. Malformed events are ignored.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1") }) })
  local notifications = applyAll(state, { {}, { type = "nonsense" }, { type = "thread.updated" } })
  equal(#notifications, 0, "unknown events are ignored")
  equal(reducer.snapshot(state, config()).parentCount, 1, "state survives unknown events")
end

-- 16. Nested subagents group under the nearest real parent.
do
  local state = reducer.newState()
  applyAll(state, {
    snapshot({
      thread("p1", { status = "idle" }),
      subagent("c1", "p1", { status = "running" }),
      subagent("c2", "c1", { status = "running" }),
    }),
  })
  local view = reducer.snapshot(state, config())
  equal(#view.parents, 1, "one row for a nested family")
  equal(#view.parents[1].children, 2, "both subagents listed")
  equal(view.childCount, 2, "both subagents counted")
end

-- 17. Project-metadata snapshots merge instead of clearing threads.
do
  local state = reducer.newState()
  applyAll(state, {
    snapshot({ runningParent("p1") }),
    { type = "snapshot", scope = "projects", projects = { project("gamma", "Gamma") }, sequence = 2 },
  })
  local view = reducer.snapshot(state, config())
  equal(view.parentCount, 1, "projects snapshot keeps threads")
  equal(state.projects.gamma.title, "Gamma", "projects snapshot merges projects")
end

-- 18. Removed threads disappear without a notification.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1"), subagent("c1", "p1") }) })
  local notifications = applyAll(state, { { type = "thread.removed", threadId = "c1" } })
  equal(#notifications, 0, "removal is silent")
  equal(reducer.snapshot(state, config()).childCount, 0, "removed child is gone")
end

-- 19. The completion highlight survives a following event for five seconds.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1"), subagent("c1", "p1") }) })
  applyAll(state, { update(subagent("c1", "p1", { status = "completed", latestRunCompletedAt = "2026-10-27T10:04:00.000Z", updatedAt = "2026-10-27T10:04:00.000Z" })) })
  applyAll(state, { update(runningParent("p2", { updatedAt = "2026-10-27T10:04:10.000Z" })) })
  local view = reducer.snapshot(state, config())
  check(type(view.highlight) == "table", "highlight kept for its display window")
  local later = reducer.snapshot(state, config({ now = NOW + 6 }))
  equal(later.highlight, nil, "highlight expires")
end

-- 20. Notifications disabled still records the event exactly once.
do
  local state = reducer.newState()
  applyAll(state, { snapshot({ runningParent("p1") }) }, { notifyCompletions = false })
  local quiet = applyAll(state, {
    update(runningParent("p1", { status = "completed", latestRunCompletedAt = "2026-10-27T10:04:00.000Z", updatedAt = "2026-10-27T10:04:00.000Z" })),
  }, { notifyCompletions = false })
  equal(#quiet, 0, "disabled completion does not notify")
  local enabled = applyAll(state, {
    update(runningParent("p1", { status = "completed", latestRunCompletedAt = "2026-10-27T10:04:00.000Z", updatedAt = "2026-10-27T10:04:00.000Z" })),
  })
  equal(#enabled, 0, "enabling later does not replay a recorded event")
end

-- 21. Replaying the recorded bridge fixture yields a stable view.
-- The Python contract test converts t3/fixtures/events.ndjson into a Lua chunk
-- and passes its path as the first argument.
do
  local path = arg and arg[1]
  if path == nil then
    io.write("skip: no fixture path argument\n")
  else
    local events = dofile(path)
    local state = reducer.newState()
    local notifications = {}
    for _, event in ipairs(events) do
      for _, notification in ipairs(reducer.apply(state, event, config())) do
        notifications[#notifications + 1] = notification
      end
    end
    local view = reducer.snapshot(state, config())
    equal(view.parentCount, 1, "fixture: one working parent")
    equal(view.childCount, 1, "fixture: one active subagent")
    equal(view.attentionCount, 0, "fixture: attention cleared")
    equal(view.parents[1].projectTitle, "Alpha", "fixture: project title joined")
    equal(view.parents[1].children[1].title, "Re-run the failing suite", "fixture: newest child first")
    equal(titles(notifications), "T3 subagent completed|T3 needs attention", "fixture: notifications")
  end
end

-- 22. A token-file permission warning reaches the panel and clears on reconnect.
do
  local state = reducer.newState()
  applyAll(state, {
    { type = "health", state = "connected", warning = "token file is readable by other users" },
    snapshot({ runningParent("p1") }),
  })
  local view = reducer.snapshot(state, config())
  equal(view.warning, "token file is readable by other users", "warning is surfaced")
  applyAll(state, { { type = "health", state = "connected" } })
  equal(reducer.snapshot(state, config()).warning, nil, "warning clears on reconnect")
end

io.write(string.format("%d checks, %d failure(s)\n", checks, failures))
os.exit(failures == 0 and 0 or 1)
