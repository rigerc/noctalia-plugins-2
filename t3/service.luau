--!nonstrict
-- T3 Monitor: read-only synchronizer driven by T3 Code's orchestration shell.
-- Only this service runs processes; widget and panel watch shared state.
noctalia.setUpdateInterval(1000)

local reducer = require("./reducer.luau")

local STALL_SECONDS = 45 -- three missed bridge heartbeats
local OFFLINE_STALL_SECONDS = 180 -- longer than the bridge's 120 s backoff cap
local LEDGER_SAVE_SECONDS = 5
local RETRY_SECONDS = 15

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

local state = reducer.newState(readLedger())
local config = nil
local stateDirty = false
local ledgerDirty = false
local ledgerUrgent = false
local lastLedgerSave = 0
local malformedLines = 0

local bridge = {
  started = false,
  generation = 0,
  lastLineAt = 0,
  lastStartAt = 0,
  retryAt = 0,
}

local function trimmed(value)
  return type(value) == "string" and value ~= "" and value or nil
end

local function shQuote(value)
  local text = tostring(value)
  local quoted = string.gsub(text, "'", "'\\''")
  return "'" .. quoted .. "'"
end

local function settings()
  local home = trimmed(noctalia.getConfig("t3_home"))
    or trimmed(noctalia.getenv("T3CODE_HOME")) or "~/.t3"
  home = noctalia.expandPath(home)
  local dataDir = noctalia.pluginDataDir() or "."
  local tokenFile = trimmed(noctalia.getConfig("token_file")) or (dataDir .. "/token")
  local excluded = {}
  for _, id in ipairs(noctalia.getConfig("excluded_projects") or {}) do
    if type(id) == "string" then excluded[id] = true end
  end
  return {
    home = home,
    node = trimmed(noctalia.getConfig("node_executable")) or "node",
    bridge = (noctalia.pluginDir() or ".") .. "/bridge.mjs",
    tokenFile = noctalia.expandPath(tokenFile),
    lockFile = dataDir .. "/bridge.lock",
    excluded = excluded,
    notifyCompletions = noctalia.getConfig("notify_completions") ~= false,
    notifyAttention = noctalia.getConfig("notify_attention") ~= false,
  }
end

local function reducerConfig(now)
  return {
    now = now,
    excluded = config.excluded,
    notifyCompletions = config.notifyCompletions,
    notifyAttention = config.notifyAttention,
    tokenFile = config.tokenFile,
  }
end

local function executableExists(command)
  if string.find(command, "/", 1, true) then
    return noctalia.fileExists(noctalia.expandPath(command))
  end
  return noctalia.commandExists(command)
end

local function saveLedger()
  local now = os.time()
  if not ledgerDirty then return end
  if not ledgerUrgent and now - lastLedgerSave < LEDGER_SAVE_SECONDS then return end
  local encoded = noctalia.json.encode(state.ledger)
  if encoded then noctalia.writeFile(ledgerPath, encoded) end
  lastLedgerSave = now
  ledgerDirty = false
  ledgerUrgent = false
end

local function publish()
  local lastSync = tonumber(state.lastSyncAt) or 0
  local snapshot = reducer.snapshot(state, {
    now = os.time(),
    excluded = config.excluded,
    lastSyncText = lastSync > 0 and noctalia.formatTime("%H:%M:%S", lastSync) or nil,
  })
  noctalia.state.set("snapshot", snapshot)
  stateDirty = false
  saveLedger()
end

local function highlightActive(now)
  return type(state.highlight) == "table"
    and now - (tonumber(state.highlight.at) or 0) < 5
end

local function applyEvent(event)
  local notifications = reducer.apply(state, event, reducerConfig(os.time()))
  stateDirty = true
  ledgerDirty = true
  for _, notification in ipairs(notifications) do
    noctalia.notify(notification.title, notification.body)
    ledgerUrgent = true
  end
  if event.type == "health" and event.state == "offline" then
    local reason = event.reason
    if reason == "token-missing" or reason == "node-too-old" or reason == "internal" then
      -- The bridge cannot recover on its own; let update() decide when to retry.
      bridge.started = false
      bridge.retryAt = os.time() + RETRY_SECONDS
    end
  end
end

local function handleLine(generation, line)
  if generation ~= bridge.generation then return end
  bridge.lastLineAt = os.time()
  if line == "" then return end
  local event = noctalia.json.decode(line)
  if type(event) ~= "table" then
    malformedLines += 1
    if malformedLines == 3 then
      applyEvent({
        type = "health",
        state = "offline",
        reason = "protocol",
        error = "T3 sent data this plugin cannot read. Update the plugin or T3 Code.",
      })
      publish()
    end
    return
  end
  applyEvent(event)
end

local function bridgeCommand()
  return table.concat({
    shQuote(config.node),
    shQuote(config.bridge),
    "--home", shQuote(config.home),
    "--token-file", shQuote(config.tokenFile),
    "--lock-file", shQuote(config.lockFile),
  }, " ")
end

local function startBridge()
  if not noctalia.fileExists(config.bridge) then
    applyEvent({
      type = "health", state = "offline", reason = "internal",
      error = "bridge.mjs is missing from the plugin directory.",
    })
    return false
  end
  if not executableExists(config.node) then
    applyEvent({
      type = "health", state = "offline", reason = "node-too-old",
      error = "Node 22 or newer is required. Install node and set node_executable.",
    })
    bridge.retryAt = os.time() + 300
    return false
  end
  bridge.generation += 1
  bridge.lastStartAt = os.time()
  bridge.lastLineAt = os.time()
  local generation = bridge.generation
  local accepted = noctalia.runStream(bridgeCommand(), function(line)
    handleLine(generation, line)
  end)
  if not accepted then
    applyEvent({
      type = "health", state = "offline", reason = "internal",
      error = "Cannot start the T3 bridge process.",
    })
    bridge.retryAt = os.time() + RETRY_SECONDS
    return false
  end
  bridge.started = true
  return true
end

local function ensureBridge()
  if bridge.started then return end
  if not noctalia.fileExists(config.tokenFile) then
    if state.reason ~= "token-missing" then
      applyEvent({
        type = "health", state = "offline", reason = "token-missing",
        error = "No T3 token yet. Run the command below, then the monitor starts by itself.",
      })
    end
    return
  end
  if os.time() < bridge.retryAt then return end
  startBridge()
end

local function restartBridge()
  if not noctalia.fileExists(config.tokenFile) then
    bridge.started = false
    return
  end
  -- The new bridge stops the previous one through the shared lock file.
  bridge.started = false
  bridge.retryAt = 0
  startBridge()
end

noctalia.state.watch("refresh_request", function()
  -- The stream is already live; publish current state immediately.
  stateDirty = true
  publish()
end)

function update()
  local now = os.time()
  -- An offline bridge is retrying on its own, so it gets a longer grace period
  -- than a healthy one. Without the second limit a bridge that died mid-backoff
  -- would never be replaced.
  local limit = state.health == "offline" and OFFLINE_STALL_SECONDS or STALL_SECONDS
  if bridge.started and now - bridge.lastLineAt > limit then
    applyEvent({
      type = "health", state = "offline", reason = "stalled",
      error = "The T3 bridge stopped responding. Restarting it…",
    })
    publish()
    restartBridge()
    return
  end
  ensureBridge()
  if stateDirty or highlightActive(now) then
    publish()
  end
end

function onConfigChanged()
  config = settings()
  if bridge.started then restartBridge() else bridge.retryAt = 0 end
  ensureBridge()
  publish()
end

config = settings()
ensureBridge()
publish()
