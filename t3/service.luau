--!nonstrict
-- T3 Monitor: local, read-only hybrid CLI/SQLite synchronizer.
-- Only this service launches processes; widget and panel watch shared state.
noctalia.setUpdateInterval(1000)

local PROJECT_SQL = [[
SELECT project_id, title, workspace_root
FROM projection_projects
WHERE deleted_at IS NULL
ORDER BY title, project_id;
]]

local CHILD_SQL = [[
SELECT s.subagent_id AS id, s.thread_id AS parent_id, t.title AS parent_title,
       t.project_id AS project_id, s.child_thread_id AS child_thread_id,
       s.status AS status, s.started_at AS started_at,
       s.completed_at AS completed_at, s.updated_at AS updated_at,
       s.payload_json AS payload_json
FROM orchestration_v2_projection_subagents s
JOIN orchestration_v2_projection_threads t ON t.thread_id = s.thread_id
JOIN projection_projects p ON p.project_id = t.project_id
WHERE t.deleted_at IS NULL AND p.deleted_at IS NULL
ORDER BY s.updated_at DESC;
]]

local REQUEST_SQL = [[
SELECT thread_id, COUNT(*) AS pending_count
FROM orchestration_v2_projection_runtime_requests
WHERE status = 'pending'
GROUP BY thread_id;
]]

local ledgerPath = noctalia.pluginDataDir() .. "/monitor-ledger.json"
local function readLedger()
  local raw = noctalia.readFile(ledgerPath)
  local parsed = type(raw) == "string" and noctalia.json.decode(raw) or nil
  if type(parsed) ~= "table" or type(parsed.states) ~= "table" then
    return { initialized = false, lastSync = 0, states = {}, emitted = {} }
  end
  if type(parsed.emitted) ~= "table" then parsed.emitted = {} end
  return parsed
end
local ledger = readLedger()
local snapshot = { health = "loading", parents = {}, parentCount = 0, childCount = 0, attentionCount = 0 }
local busy = false
local forceRefresh = false
local nextPoll = 0
local failures = 0
local refreshGeneration = 0

local function trimmed(v)
  return type(v) == "string" and v ~= "" and v or nil
end

local function settings()
  local home = trimmed(noctalia.getConfig("t3_home"))
    or trimmed(noctalia.getenv("T3CODE_HOME")) or "~/.t3"
  home = noctalia.expandPath(home)
  local db = trimmed(noctalia.getConfig("sqlite_path")) or (home .. "/userdata/statev2.sqlite")
  local excluded = {}
  for _, id in ipairs(noctalia.getConfig("excluded_projects") or {}) do
    if type(id) == "string" then excluded[id] = true end
  end
  return {
    db = noctalia.expandPath(db),
    sqlite = trimmed(noctalia.getConfig("sqlite_executable")) or "sqlite3",
    cli = trimmed(noctalia.getConfig("t3_executable")) or "t3",
    excluded = excluded,
    notifyCompletions = noctalia.getConfig("notify_completions") ~= false,
    notifyAttention = noctalia.getConfig("notify_attention") ~= false,
  }
end

local function decodeRows(output)
  if type(output) ~= "string" or output == "" then return {} end
  local decoded, err = noctalia.json.decode(output)
  if type(decoded) ~= "table" then return nil, tostring(err or "Invalid JSON response") end
  return decoded
end

local function exec(argv, done)
  local launched = noctalia.runAsync(argv, function(result)
    if type(result) ~= "table" or result.exitCode ~= 0 or result.timedOut
        or result.stdoutTruncated then
      local detail = result and (result.stderr or "") or ""
      if detail == "" then detail = "Command failed or returned truncated output" end
      done(nil, detail)
      return
    end
    local rows, err = decodeRows(result.stdout)
    done(rows, err)
  end)
  if not launched then done(nil, "Unable to launch " .. tostring(argv[1])) end
end

local function sqlRead(config, sql, done)
  -- Fixed statements only. DB is opened read-only; no settings are embedded in SQL.
  exec({ config.sqlite, "-readonly", "-json", config.db, sql }, done)
end

local function publish(value)
  snapshot = value
  noctalia.state.set("snapshot", snapshot)
end

local function fail(message)
  failures += 1
  nextPoll = os.time() + math.min(120, 5 * (2 ^ math.min(failures - 1, 4)))
  busy = false
  publish({
    health = "offline",
    error = tostring(message),
    parents = {},
    parentCount = 0,
    childCount = 0,
    attentionCount = 0,
    lastSyncText = snapshot.lastSyncText,
  })
end

local function isRecent(iso, maxAge)
  if type(iso) ~= "string" or #iso < 19 then return false end
  -- T3 stores UTC ISO dates. Compare fixed-width UTC fields, not local time.
  return string.sub(iso, 1, 19) >= os.date("!%Y-%m-%dT%H:%M:%S", os.time() - maxAge)
end

local function workingParent(p)
  return p.status == "preparing" or p.status == "queued"
      or p.status == "starting" or p.status == "running"
end

local function activeChild(c)
  return c.status == "pending" or c.status == "running" or c.attention == true
end

local function recordEvents(config, parents, children, result)
  local prior = ledger.states
  local current = {}
  local highlight = nil
  local now = os.time()
  local initial = ledger.initialized ~= true
  -- Completed work older than ten minutes is not a catch-up event.
  for _, p in pairs(parents) do
    local key = "parent:" .. p.id
    local old = prior[key]
    current[key] = { status = p.status, runId = p.runId, attention = p.attention == true }
    local completed = p.status == "completed" and p.runId ~= nil
    local transition = old == nil or old.status ~= "completed" or old.runId ~= p.runId
    if not initial and completed and transition and isRecent(p.updatedAt, 600) then
      local event = "complete:" .. key .. ":" .. p.runId
      if ledger.emitted[event] == nil then
        if config.notifyCompletions then
          noctalia.notify("T3 parent completed", p.projectTitle .. " · " .. p.title)
        end
        ledger.emitted[event] = now
        highlight = { at = now, title = p.projectTitle }
      end
    end
    if not initial and p.attention and (old == nil or old.attention ~= true) then
      local event = "attention:" .. key .. ":" .. tostring(p.runId) .. ":" .. tostring(p.updatedAt)
      if ledger.emitted[event] == nil then
        if config.notifyAttention then
          -- Child-specific attribution, when verified, comes from the child below.
          if p.attributedChild == nil then
            noctalia.notify("T3 needs attention", p.projectTitle .. " · " .. p.title)
          end
        end
        ledger.emitted[event] = now
      end
    end
  end
  for _, c in pairs(children) do
    local key = "child:" .. c.id
    local old = prior[key]
    current[key] = { status = c.status, attention = c.attention == true, completedAt = c.completedAt }
    local completed = c.status == "completed"
    local transition = old == nil or old.status ~= "completed" or old.completedAt ~= c.completedAt
    if not initial and completed and transition and isRecent(c.completedAt, 600) then
      local event = "complete:" .. key .. ":" .. tostring(c.completedAt)
      if ledger.emitted[event] == nil then
        if config.notifyCompletions then
          noctalia.notify("T3 subagent completed", c.projectTitle .. " · " .. c.title)
        end
        ledger.emitted[event] = now
        highlight = { at = now, title = c.title }
      end
    end
    if not initial and c.attention and (old == nil or old.attention ~= true) then
      local event = "attention:" .. key .. ":" .. tostring(c.updatedAt)
      if ledger.emitted[event] == nil then
        if config.notifyAttention then
          noctalia.notify("T3 subagent needs attention",
            c.projectTitle .. " · " .. c.parentTitle .. " → " .. c.title)
        end
        ledger.emitted[event] = now
      end
    end
  end
  for key, timestamp in pairs(ledger.emitted) do
    if type(timestamp) ~= "number" or (now - timestamp) > 604800 then
      ledger.emitted[key] = nil
    end
  end
  ledger.initialized = true
  ledger.states = current
  ledger.lastSync = now
  local encoded = noctalia.json.encode(ledger)
  if encoded then noctalia.writeFile(ledgerPath, encoded) end
  result.highlight = highlight
end

local function finalize(config, projects, parents, children, pendingHints, done)
  -- A parent request must be confirmed by the official CLI. Pending hints
  -- alone may be stale, especially after an agent/provider disconnects.
  local toVerify = {}
  for _, p in pairs(parents) do
    if p.status == "waiting" or (pendingHints[p.id] or 0) > 0 then
      table.insert(toVerify, p)
    end
  end
  for _, c in pairs(children) do
    if (pendingHints[c.childThreadId or ""] or 0) > 0 then
      local p = parents[c.parentId]
      if p and not p.verifyQueued then
        table.insert(toVerify, p)
        p.verifyQueued = true
      end
    end
  end
  local seen = {}
  local queue = {}
  for _, p in ipairs(toVerify) do
    if not seen[p.id] then
      seen[p.id] = true
      table.insert(queue, p)
    end
  end
  local function renderResult()
    for _, c in pairs(children) do
      local p = parents[c.parentId]
      local pending = pendingHints[c.childThreadId or ""] or 0
      c.attention = c.status == "waiting"
          and pending > 0 and p ~= nil and (p.pendingCount or 0) > 0
      if c.attention and p then p.attributedChild = c.id end
    end
    local rows = {}
    local parentCount, childCount, attentionCount = 0, 0, 0
    for _, p in pairs(parents) do
      p.working = workingParent(p)
      if p.working then parentCount += 1 end
      p.children = {}
    end
    for _, c in pairs(children) do
      if activeChild(c) then
        childCount += 1
        local parent = parents[c.parentId]
        if parent == nil then
          parent = {
            id = c.parentId, title = c.parentTitle, projectId = c.projectId,
            projectTitle = c.projectTitle, status = "idle", working = false,
            updatedAt = c.updatedAt, children = {}, context = true,
          }
          parents[c.parentId] = parent
        end
        table.insert(parent.children, c)
      end
    end
    for _, p in pairs(parents) do
      if p.attention then
        local attributed = 0
        for _, child in ipairs(p.children) do
          if child.attention then attributed += 1 end
        end
        attentionCount += math.max(1, attributed)
      end
      if p.working or p.attention or #p.children > 0 then
        table.sort(p.children, function(a, b)
          return tostring(a.updatedAt or "") > tostring(b.updatedAt or "")
        end)
        p.sortAt = p.updatedAt or ""
        for _, child in ipairs(p.children) do
          if tostring(child.updatedAt or "") > p.sortAt then p.sortAt = child.updatedAt end
        end
        table.insert(rows, p)
      end
    end
    table.sort(rows, function(a, b)
      return tostring(a.sortAt) > tostring(b.sortAt)
    end)
    local result = {
      health = "ok",
      parents = rows,
      parentCount = parentCount,
      childCount = childCount,
      attentionCount = attentionCount,
      lastSyncText = noctalia.formatTime("%H:%M:%S"),
    }
    recordEvents(config, parents, children, result)
    -- Keep highlight while it is in the 5-second display window.
    if not result.highlight and type(snapshot.highlight) == "table"
        and os.time() - (tonumber(snapshot.highlight.at) or 0) < 5 then
      result.highlight = snapshot.highlight
    end
    done(result)
  end

  local index = 1
  local function verifyNext()
    if index > #queue then
      renderResult()
      return
    end
    local p = queue[index]
    index += 1
    exec({ config.cli, "thread", "show", p.id, "--messages", "0", "--json" }, function(response, err)
      if response == nil then
        -- Fail closed: an unverified request is not actionable.
        p.pendingCount = 0
      else
        local detail = response.thread
        p.pendingCount = type(detail) == "table" and (tonumber(detail.pendingRequestCount) or 0) or 0
      end
      p.attention = p.pendingCount > 0
      verifyNext()
    end)
  end
  verifyNext()
end

local function sync()
  if busy then
    forceRefresh = true
    return
  end
  busy = true
  refreshGeneration += 1
  local currentGeneration = refreshGeneration
  local config = settings()

  local function reject(message)
    if currentGeneration == refreshGeneration then fail(message) end
  end
  sqlRead(config, PROJECT_SQL, function(projectRows, err)
    if projectRows == nil then reject("Cannot read T3 projects: " .. tostring(err)); return end
    local projects = {}
    local projectList = {}
    for _, row in ipairs(projectRows) do
      if type(row.project_id) == "string" and not config.excluded[row.project_id] then
        local p = { id = row.project_id, title = tostring(row.title or row.project_id) }
        projects[p.id] = p
        table.insert(projectList, p)
      end
    end

    sqlRead(config, CHILD_SQL, function(childRows, childErr)
      if childRows == nil then reject("Cannot read T3 subagents: " .. tostring(childErr)); return end
      local children = {}
      for _, row in ipairs(childRows) do
        local project = projects[row.project_id]
        if project and type(row.id) == "string" and type(row.parent_id) == "string" then
          local payload = type(row.payload_json) == "string" and noctalia.json.decode(row.payload_json) or {}
          if type(payload) ~= "table" then payload = {} end
          children[row.id] = {
            id = row.id, parentId = row.parent_id,
            parentTitle = tostring(row.parent_title or row.parent_id),
            projectId = row.project_id, projectTitle = project.title,
            childThreadId = row.child_thread_id,
            title = trimmed(payload.title) or trimmed(payload.prompt) or row.id,
            status = tostring(row.status or "unknown"),
            progress = trimmed(payload.progress),
            provider = trimmed(payload.driver) or trimmed(payload.providerInstanceId) or "Unknown",
            model = trimmed(payload.model),
            startedAt = row.started_at, completedAt = row.completed_at, updatedAt = row.updated_at,
          }
        end
      end

      sqlRead(config, REQUEST_SQL, function(hintRows, hintErr)
        if hintRows == nil then reject("Cannot read pending request hints: " .. tostring(hintErr)); return end
        local pendingHints = {}
        for _, row in ipairs(hintRows) do
          if type(row.thread_id) == "string" then
            pendingHints[row.thread_id] = tonumber(row.pending_count) or 0
          end
        end
        local parents = {}
        local idx = 1
        local function listNext()
          if idx > #projectList then
            finalize(config, projects, parents, children, pendingHints, function(result)
              if currentGeneration ~= refreshGeneration then return end
              failures = 0
              busy = false
              nextPoll = os.time() + ((result.parentCount > 0 or result.childCount > 0) and 5 or 30)
              publish(result)
              if forceRefresh then
                forceRefresh = false
                nextPoll = 0
              end
            end)
            return
          end
          local project = projectList[idx]
          idx += 1
          exec({ config.cli, "thread", "list", "--project", project.id, "--json" }, function(threads, cliErr)
            if threads == nil then
              reject("T3 CLI (" .. project.title .. "): " .. tostring(cliErr))
              return
            end
            for _, thread in ipairs(threads) do
              if type(thread.threadId) == "string" then
                parents[thread.threadId] = {
                  id = thread.threadId, title = tostring(thread.title or thread.threadId),
                  projectId = project.id, projectTitle = project.title,
                  status = tostring(thread.status or "unknown"),
                  runId = thread.latestRunId, provider = thread.providerInstanceId,
                  model = thread.model, updatedAt = thread.updatedAt,
                  children = {}, pendingCount = 0, attention = false,
                }
              end
            end
            listNext()
          end)
        end
        listNext()
      end)
    end)
  end)
end

noctalia.state.watch("refresh_request", function()
  forceRefresh = true
  nextPoll = 0
end)

function update()
  if not busy and os.time() >= nextPoll then
    forceRefresh = false
    sync()
  end
end

function onConfigChanged()
  -- Re-read all shared manifest settings on the next cycle.
  if busy then forceRefresh = true else nextPoll = 0 end
end

publish(snapshot)
