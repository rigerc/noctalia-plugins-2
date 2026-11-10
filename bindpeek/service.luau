--!nonstrict
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Only this service starts Bindpeek processes. The reader remains privileged
-- in the original systemd socket-activated service; we consume CLI summaries.
local parser = require("./shortcuts.luau")

local held = {}
local heldText = ""
local pressedAt = 0
local shown = false
local manual = false
local refreshing = false
local queued = false
local shortcuts = {}
local backendPresent = noctalia.commandExists("bindpeek")

noctalia.setUpdateInterval(40)
noctalia.state.set("held", held)
noctalia.state.set("shortcuts", shortcuts)
noctalia.state.set("manual", false)
noctalia.state.set("backend", backendPresent and "waiting" or "missing")

local function hide()
  if shown then
    shown = false
    noctalia.layer.hide("overlay")
  end
end

local function show()
  if not shown then
    shown = true
    noctalia.layer.show("overlay")
  end
end

local function refresh()
  if not backendPresent then return end
  if refreshing then
    queued = true
    return
  end
  refreshing = true
  local accepted = noctalia.runAsync({ "bindpeek", "--list" }, function(result)
    refreshing = false
    if result.exitCode == 0 and not result.stdoutTruncated then
      shortcuts = parser.parseList(result.stdout or "")
      noctalia.state.set("shortcuts", shortcuts)
      noctalia.state.set("source_status", "ok")
    else
      noctalia.state.set("source_status", "error")
      noctalia.log("Bindpeek --list failed; see 'bindpeek --list' in a terminal.")
    end
    if queued then
      queued = false
      refresh()
    end
  end)
  if not accepted then
    refreshing = false
    noctalia.state.set("source_status", "error")
  end
end

local function applyHeld(nextHeld)
  local nextText = table.concat(nextHeld, "+")
  if nextText == heldText then return end
  local wasEmpty = #held == 0
  held, heldText = nextHeld, nextText
  noctalia.state.set("held", held)
  if #held == 0 then
    pressedAt = 0
    if not manual then hide() end
    return
  end
  if wasEmpty then
    pressedAt = noctalia.nowMs()
    refresh() -- always read fresh compositor bindings before a new appearance
  end
end

local function handleLine(line)
  if line == "__BINDPEEK_EXIT__" then
    noctalia.state.set("backend", "waiting")
    applyHeld({})
    return
  end
  if line:find("Connected to", 1, true) then
    noctalia.state.set("backend", "ready")
    return
  end
  local modifiers = parser.parseHeld(line)
  if modifiers then
    noctalia.state.set("backend", "ready")
    applyHeld(modifiers)
  end
end

-- Reconnect when the socket-activated service is restarted. The sentinel
-- ensures a dead --keys process never leaves a permanently visible overlay.
if backendPresent then
  local accepted = noctalia.runStream(
    "while :; do bindpeek --keys 2>/dev/null; printf '__BINDPEEK_EXIT__\\n'; sleep 2; done",
    handleLine
  )
  if not accepted then noctalia.state.set("backend", "error") end
end

local function toggleManual()
  manual = not manual
  noctalia.state.set("manual", manual)
  if manual then
    refresh()
    show()
  elseif #held == 0 then
    hide()
  end
end

noctalia.state.watch("toggle_request", function()
  toggleManual()
end)

noctalia.state.watch("refresh_request", function()
  refresh()
end)

function onIpc(event, _payload)
  if event == "toggle" then
    toggleManual()
  elseif event == "refresh" then
    refresh()
  elseif event == "hide" then
    manual = false
    noctalia.state.set("manual", false)
    if #held == 0 then hide() end
  end
end

function update()
  if manual then return end
  if not backendPresent or noctalia.getConfig("auto_show") == false then
    hide()
    return
  end
  if #held == 0 then
    hide()
    return
  end
  if noctalia.getConfig("ignore_lone_shift") ~= false
      and #held == 1 and held[1] == "SHIFT" then
    hide()
    return
  end
  local delay = math.max(0, tonumber(noctalia.getConfig("hold_delay_ms")) or 200)
  if noctalia.nowMs() - pressedAt >= delay then show() end
end

function onConfigChanged()
  if noctalia.getConfig("auto_show") == false and not manual then hide() end
end

function onExit(_signal, _reason)
  hide()
end

refresh()
