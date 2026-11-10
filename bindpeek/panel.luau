--!nonstrict
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Focusable explorer for full shortcut browsing; unlike the passive overlay.
local shortcuts = noctalia.state.get("shortcuts") or {}
local backend = noctalia.state.get("backend") or "waiting"
local sourceStatus = noctalia.state.get("source_status") or "waiting"
local manual = noctalia.state.get("manual") == true
local open = false
local query = ""

local function matchesQuery(item)
  if query == "" then return true end
  local haystack = string.lower(item.combo .. " " .. item.description .. " " .. item.group)
  return haystack:find(string.lower(query), 1, true) ~= nil
end

local function render()
  if not open then return end
  local rows = {}
  local count = 0
  local group = ""
  for _, item in ipairs(shortcuts) do
    if matchesQuery(item) then
      if item.group ~= group then
        group = item.group
        table.insert(rows, ui.label({
          text = group, color = "primary", fontWeight = "bold", fontSize = 12,
        }))
      end
      table.insert(rows, ui.row({ key = "bind-" .. item.combo .. item.description, gap = 9, paddingV = 4 }, {
        ui.label({ text = item.combo, fontWeight = "medium", fontSize = 12, width = 160 }),
        ui.label({ text = item.description, color = "on_surface_variant", fontSize = 12, flexGrow = 1, maxLines = 2 }),
      }))
      count += 1
    end
  end
  if count == 0 then
    table.insert(rows, ui.label({
      text = sourceStatus == "error" and "Bindpeek could not read the compositor bindings."
          or "No matching shortcuts loaded.",
      color = "on_surface_variant", fontSize = 13,
    }))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 13 }, {
    ui.row({ align = "center", gap = 9 }, {
      ui.glyph({ name = "keyboard", color = "primary", size = 24 }),
      ui.label({ text = "Bindpeek", fontWeight = "bold", fontSize = 17, flexGrow = 1 }),
      ui.button({ glyph = "settings", variant = "ghost", onClick = "openSettings" }),
      ui.button({ glyph = "x", variant = "ghost", onClick = "closeViewer" }),
    }),
    ui.label({
      text = "Watch: " .. backend .. " · bindings: " .. #shortcuts,
      fontSize = 12, color = backend == "ready" and "primary" or "on_surface_variant",
    }),
    ui.row({ gap = 9, align = "center" }, {
      ui.button({
        text = manual and "Hide overlay" or "Preview overlay", glyph = "eye",
        onClick = "toggleOverlay",
      }),
      ui.button({ text = "Refresh", glyph = "refresh", variant = "secondary", onClick = "refresh" }),
    }),
    ui.input({ key = "search", placeholder = "Filter by shortcut, action, or group", onChange = "search", value = "" }),
    ui.separator({ color = "outline_variant" }),
    ui.label({ text = tostring(count) .. " shortcuts", color = "on_surface_variant", fontSize = 12 }),
    ui.scroll({ flexGrow = 1, gap = 7, align = "stretch" }, rows),
  }))
end

noctalia.state.watch("shortcuts", function(value)
  shortcuts = value or {}
  render()
end)
noctalia.state.watch("backend", function(value)
  backend = value or "waiting"
  render()
end)
noctalia.state.watch("source_status", function(value)
  sourceStatus = value or "waiting"
  render()
end)
noctalia.state.watch("manual", function(value)
  manual = value == true
  render()
end)

function onOpen(_context)
  open = true
  query = ""
  noctalia.state.set("refresh_request", noctalia.nowMs())
  render()
end

function onClose()
  open = false
end

function search(value)
  query = value or ""
  render()
end

function refresh()
  noctalia.state.set("refresh_request", noctalia.nowMs())
end

function toggleOverlay()
  noctalia.state.set("toggle_request", noctalia.nowMs())
end

function openSettings()
  noctalia.openSettings()
end

function closeViewer()
  panel.close()
end
