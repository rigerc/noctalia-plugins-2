--!nonstrict
-- T3 Monitor reducer: bridge events in, monitor view and notifications out.
--
-- Pure Lua (no host calls) so the repository tests can replay fixtures through
-- the same code the service runs. The service owns I/O, state and notify calls.

local M = {}

local WORKING = {
  preparing = true,
  queued = true,
  starting = true,
  running = true,
}

local ACTIVE_CHILD = {
  preparing = true,
  queued = true,
  starting = true,
  running = true,
  waiting = true,
}

local TERMINAL = {
  completed = true,
  failed = true,
  cancelled = true,
  interrupted = true,
  rolled_back = true,
}

-- Completed work older than this is not a catch-up event.
M.CATCH_UP_SECONDS = 600
M.EMITTED_TTL_SECONDS = 604800

local function trimmed(value)
  return type(value) == "string" and value ~= "" and value or nil
end

local function isRecent(iso, maxAge, now)
  if type(iso) ~= "string" or #iso < 19 then return false end
  -- T3 stores UTC ISO dates. Compare fixed-width UTC fields, not local time.
  return string.sub(iso, 1, 19) >= os.date("!%Y-%m-%dT%H:%M:%S", now - maxAge)
end

local function maxIso(a, b)
  if type(a) ~= "string" then return b end
  if type(b) ~= "string" then return a end
  return a > b and a or b
end

-- The panel shows a copy-paste shell command, so quote the path and keep the
-- token file private in the same step.
local function shellQuote(value)
  return "'" .. string.gsub(tostring(value), "'", "'\\''") .. "'"
end

function M.newState(ledger)
  if type(ledger) ~= "table" or type(ledger.states) ~= "table" then
    ledger = { initialized = false, lastSync = 0, states = {}, emitted = {} }
  end
  if type(ledger.emitted) ~= "table" then ledger.emitted = {} end
  return {
    projects = {},
    threads = {},
    health = "loading",
    error = nil,
    reason = nil,
    tokenCommand = nil,
    warning = nil,
    sequence = nil,
    synced = false,
    lastSyncAt = 0,
    ledger = ledger,
    highlight = nil,
  }
end

-- The pending request rule: async questions (blocking == false) do not need a
-- human. Older servers omit the field, where every request blocked the run.
local function needsAttention(thread)
  local request = thread.pendingRequest
  if type(request) ~= "table" then return false end
  return request.blocking ~= false
end

local function excluded(projectId, config)
  return type(projectId) == "string" and config.excluded ~= nil and config.excluded[projectId] == true
end

local function projectTitle(state, projectId)
  local project = type(projectId) == "string" and state.projects[projectId] or nil
  return (project and trimmed(project.title)) or tostring(projectId or "Unknown project")
end

local function addChild(parent, child)
  parent.children[#parent.children + 1] = child
  parent.sortAt = maxIso(parent.sortAt, child.updatedAt)
end

-- Subagents can spawn subagents. Group every descendant under the nearest
-- non-subagent ancestor so the panel keeps one row per conversation.
local function rootParentId(state, thread)
  local parentId = thread.parentId
  local guard = 0
  while guard < 16 do
    local parent = state.threads[parentId]
    if parent == nil or parent.relationship ~= "subagent" then break end
    parentId = parent.parentId
    guard = guard + 1
  end
  return parentId
end

-- Group threads into parent rows plus their active subagent children.
local function buildView(state, config)
  local parents, order = {}, {}
  local function parentRow(thread)
    local row = parents[thread.id]
    if row == nil then
      row = {
        id = thread.id,
        title = trimmed(thread.title) or thread.id,
        projectId = thread.projectId,
        projectTitle = projectTitle(state, thread.projectId),
        status = tostring(thread.status or "unknown"),
        provider = trimmed(thread.provider),
        model = trimmed(thread.model),
        updatedAt = thread.updatedAt,
        attention = needsAttention(thread),
        working = WORKING[thread.status] == true,
        children = {},
        sortAt = thread.updatedAt,
      }
      parents[thread.id] = row
      order[#order + 1] = row
    end
    return row
  end

  local children = {}
  for _, thread in pairs(state.threads) do
    if not excluded(thread.projectId, config) and thread.archivedAt == nil then
      if thread.relationship == "subagent" and trimmed(thread.parentId) then
        local attention = needsAttention(thread)
        local active = ACTIVE_CHILD[thread.status] == true or attention
        if active then
          children[#children + 1] = {
            thread = thread,
            attention = attention,
            parentId = thread.parentId,
          }
        end
      else
        parentRow(thread)
      end
    end
  end

  local orphanParents = {}
  for _, entry in ipairs(children) do
    local thread = entry.thread
    local groupId = rootParentId(state, thread)
    entry.directParentTitle = trimmed(state.threads[thread.parentId] and state.threads[thread.parentId].title)
    local parent = parents[groupId]
    if parent == nil then
      -- Keep an orphaned-parent context row while a child is still active.
      parent = orphanParents[groupId]
      if parent == nil then
        parent = {
          id = groupId,
          title = entry.directParentTitle or groupId,
          projectId = thread.projectId,
          projectTitle = projectTitle(state, thread.projectId),
          status = "idle",
          working = false,
          attention = false,
          children = {},
          sortAt = thread.updatedAt,
          context = true,
        }
        orphanParents[groupId] = parent
        order[#order + 1] = parent
      end
    end
    local child = {
      id = thread.id,
      title = trimmed(thread.title) or thread.id,
      status = tostring(thread.status or "unknown"),
      attention = entry.attention,
      provider = trimmed(thread.provider),
      model = trimmed(thread.model),
      progress = nil,
      startedAt = thread.latestRunStartedAt,
      completedAt = thread.latestRunCompletedAt,
      updatedAt = thread.updatedAt,
    }
    addChild(parent, child)
    entry.row = child
    entry.parent = parent
  end

  local rows = {}
  local parentCount, childCount, attentionCount = 0, 0, 0
  for _, parent in ipairs(order) do
    if parent.working then parentCount = parentCount + 1 end
    if parent.attention then attentionCount = attentionCount + 1 end
    if #parent.children > 0 then
      childCount = childCount + #parent.children
      table.sort(parent.children, function(a, b)
        return tostring(a.updatedAt or "") > tostring(b.updatedAt or "")
      end)
      for _, child in ipairs(parent.children) do
        if child.attention then attentionCount = attentionCount + 1 end
      end
    end
    if parent.working or parent.attention or #parent.children > 0 then
      rows[#rows + 1] = parent
    end
  end
  table.sort(rows, function(a, b)
    return tostring(a.sortAt or "") > tostring(b.sortAt or "")
  end)

  return {
    rows = rows,
    parentCount = parentCount,
    childCount = childCount,
    attentionCount = attentionCount,
    children = children,
  }
end

-- Threads whose transitions matter for notifications. Bounded so the ledger
-- stays small: active rows, their children and anything recently finished.
local function trackedThreads(state, view, config, now)
  local tracked = {}
  for _, parent in ipairs(view.rows) do
    tracked[parent.id] = { thread = state.threads[parent.id], parent = parent }
    for _, child in ipairs(parent.children) do
      tracked[child.id] = { thread = state.threads[child.id], parent = parent }
    end
  end
  for id, thread in pairs(state.threads) do
    if tracked[id] == nil and not excluded(thread.projectId, config) and thread.archivedAt == nil then
      if TERMINAL[thread.status] == true
          and isRecent(thread.latestRunCompletedAt or thread.updatedAt, M.CATCH_UP_SECONDS, now) then
        tracked[id] = { thread = thread }
      end
    end
  end
  return tracked
end

local function recordEvents(state, view, config, notifications)
  local ledger = state.ledger
  local now = config.now
  local initial = ledger.initialized ~= true
  local prior = ledger.states
  local current = {}
  local highlight = nil

  local function emit(event, notify, title, body)
    if ledger.emitted[event] ~= nil then return end
    ledger.emitted[event] = now
    if notify then
      notifications[#notifications + 1] = { title = title, body = body }
      highlight = { at = now, title = body }
    end
  end

  local tracked = trackedThreads(state, view, config, now)
  for id, entry in pairs(tracked) do
    local thread = entry.thread
    if thread ~= nil then
      local isChild = thread.relationship == "subagent"
      local key = (isChild and "child:" or "parent:") .. id
      local attention = needsAttention(thread)
      local completedAt = thread.latestRunCompletedAt
      current[key] = {
        status = thread.status,
        runId = thread.latestRunId,
        attention = attention,
        completedAt = completedAt,
      }
      local old = prior[key]
      local parent = entry.parent
      local projectName = parent and parent.projectTitle or projectTitle(state, thread.projectId)
      local parentName = entry.directParentTitle or (parent and parent.title)
      local name = trimmed(thread.title) or id

      if not initial and thread.status == "completed" then
        local completed = isChild or thread.latestRunId ~= nil
        local transition = old == nil
          or old.status ~= "completed"
          or (isChild and old.completedAt ~= completedAt)
          or (not isChild and old.runId ~= thread.latestRunId)
        if completed and transition
            and isRecent(completedAt or thread.updatedAt, M.CATCH_UP_SECONDS, now) then
          if isChild then
            emit("complete:" .. key .. ":" .. tostring(completedAt), config.notifyCompletions,
              "T3 subagent completed", projectName .. " · " .. name)
          else
            emit("complete:" .. key .. ":" .. tostring(thread.latestRunId), config.notifyCompletions,
              "T3 parent completed", projectName .. " · " .. name)
          end
        end
      end

      if not initial and attention and (old == nil or old.attention ~= true) then
        local requestId = type(thread.pendingRequest) == "table" and thread.pendingRequest.id or nil
        local event = "attention:" .. key .. ":" .. tostring(requestId or thread.updatedAt)
        if isChild then
          emit(event, config.notifyAttention, "T3 subagent needs attention",
            projectName .. " · " .. tostring(parentName or thread.parentId) .. " → " .. name)
        else
          emit(event, config.notifyAttention, "T3 needs attention", projectName .. " · " .. name)
        end
      end
    end
  end

  for event, timestamp in pairs(ledger.emitted) do
    if type(timestamp) ~= "number" or (now - timestamp) > M.EMITTED_TTL_SECONDS then
      ledger.emitted[event] = nil
    end
  end
  ledger.initialized = true
  ledger.states = current
  ledger.lastSync = now
  if highlight ~= nil then state.highlight = highlight end
end

local function clearThreads(state)
  state.threads = {}
  state.synced = false
end

-- Apply one bridge event. Returns the notifications to show for this event.
function M.apply(state, event, config)
  config = config or {}
  config.now = config.now or os.time()
  config.excluded = config.excluded or {}
  local notifications = {}
  if type(event) ~= "table" then return notifications end

  local kind = event.type
  if kind == "health" then
    if event.state == "offline" then
      state.health = "offline"
      state.reason = event.reason
      state.error = event.error or "T3 Code is unavailable"
      clearThreads(state)
    elseif event.state == "connected" then
      state.health = "connecting"
      state.reason = nil
      state.error = "Connected to T3 Code; waiting for the shell snapshot…"
    else
      state.health = "connecting"
      state.reason = event.reason
      state.error = event.error or "Connecting to T3 Code…"
    end
    state.tokenCommand = nil
    state.warning = trimmed(event.warning)
    if event.reason == "token-missing" or event.reason == "unauthorized" then
      local path = shellQuote(config.tokenFile or "<plugin data dir>/token")
      state.tokenCommand = "t3 auth session issue --scope orchestration:read --ttl 30d --token-only > "
        .. path .. " && chmod 600 " .. path
    end
    return notifications
  end

  if kind == "snapshot" then
    if event.scope == "projects" then
      for _, project in ipairs(event.projects or {}) do
        if type(project) == "table" and type(project.id) == "string" then
          state.projects[project.id] = project
        end
      end
      state.lastSyncAt = config.now
      return notifications
    end
    state.projects = {}
    state.threads = {}
    for _, project in ipairs(event.projects or {}) do
      if type(project) == "table" and type(project.id) == "string" then
        state.projects[project.id] = project
      end
    end
    for _, thread in ipairs(event.threads or {}) do
      if type(thread) == "table" and type(thread.id) == "string" then
        state.threads[thread.id] = thread
      end
    end
    state.health = "ok"
    state.error = nil
    state.reason = nil
    state.tokenCommand = nil
    state.synced = true
    state.sequence = event.sequence
    state.lastSyncAt = config.now
    recordEvents(state, buildView(state, config), config, notifications)
    return notifications
  end

  if kind == "project.updated" then
    local project = event.project
    if type(project) == "table" and type(project.id) == "string" then
      state.projects[project.id] = project
    end
    return notifications
  end

  if kind == "project.removed" then
    if type(event.projectId) == "string" then state.projects[event.projectId] = nil end
    return notifications
  end

  if kind == "thread.updated" then
    local thread = event.thread
    if type(thread) ~= "table" or type(thread.id) ~= "string" then return notifications end
    state.threads[thread.id] = thread
    state.health = "ok"
    state.error = nil
    state.lastSyncAt = config.now
    if state.synced then
      recordEvents(state, buildView(state, config), config, notifications)
    end
    return notifications
  end

  if kind == "thread.removed" then
    if type(event.threadId) == "string" then state.threads[event.threadId] = nil end
    return notifications
  end

  return notifications
end

-- Published shape consumed by widget.luau and panel.luau.
function M.snapshot(state, config)
  config = config or {}
  local now = config.now or os.time()
  local view = buildView(state, config)

  -- Keep the completion highlight for its five-second display window.
  local highlight = state.highlight
  if type(highlight) == "table" and now - (tonumber(highlight.at) or 0) >= 5 then
    highlight = nil
  end

  if state.health ~= "ok" then
    return {
      health = state.health,
      error = state.error,
      reason = state.reason,
      tokenCommand = state.tokenCommand,
      warning = state.warning,
      parents = {},
      parentCount = 0,
      childCount = 0,
      attentionCount = 0,
      lastSyncText = config.lastSyncText,
      highlight = highlight,
    }
  end

  return {
    health = "ok",
    warning = state.warning,
    parents = view.rows,
    parentCount = view.parentCount,
    childCount = view.childCount,
    attentionCount = view.attentionCount,
    lastSyncText = config.lastSyncText,
    highlight = highlight,
  }
end

return M
