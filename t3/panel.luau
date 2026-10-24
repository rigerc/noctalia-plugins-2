-- Read-only T3 activity panel. Interactive rows only expand/collapse.
local snapshot = noctalia.state.get("snapshot")
local expandedParent = nil
local expandedChild = nil

local function text(value)
  if value == nil or value == "" then return "Unavailable" end
  return tostring(value)
end

local function statusColor(status, attention)
  if attention then return "error" end
  if status == "running" or status == "starting" then return "primary" end
  if status == "completed" then return "secondary" end
  return "on_surface_variant"
end

local function detail(label, value)
  return ui.row({ gap = 6 }, {
    ui.label({ text = label, color = "on_surface_variant", fontSize = 11 }),
    ui.label({ text = text(value), fontSize = 11, flexGrow = 1 }),
  })
end

local function childEntry(child)
  local children = {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "corner-down-right", color = "on_surface_variant", size = 13 }),
      ui.button({
        text = text(child.title),
        variant = "ghost",
        flexGrow = 1,
        contentAlign = "start",
        onClick = function()
          expandedChild = expandedChild == child.id and nil or child.id
          onRender()
        end,
      }),
      ui.label({
        text = child.attention and "Attention" or text(child.status),
        color = statusColor(child.status, child.attention),
        fontSize = 11,
      }),
    }),
  }
  if expandedChild == child.id then
    table.insert(children, ui.column({ gap = 3, paddingL = 22 }, {
      detail("Provider", child.provider),
      detail("Model", child.model),
      detail("Progress", child.progress),
      detail("Started", child.startedAt),
      detail("Updated", child.updatedAt),
    }))
  end
  return ui.column({ gap = 4 }, children)
end

local function parentEntry(parent)
  local rows = {
    ui.row({ gap = 8, align = "center" }, {
      ui.button({
        text = text(parent.title),
        flexGrow = 1,
        variant = "ghost",
        contentAlign = "start",
        onClick = function()
          expandedParent = expandedParent == parent.id and nil or parent.id
          expandedChild = nil
          onRender()
        end,
      }),
      ui.label({
        text = parent.attention and "Attention" or (parent.working and text(parent.status) or "Context"),
        color = statusColor(parent.status, parent.attention),
        fontSize = 11,
      }),
    }),
    ui.label({
      text = text(parent.projectTitle) .. " · " .. #parent.children .. " subagent(s)",
      color = "on_surface_variant",
      fontSize = 11,
    }),
  }

  if expandedParent == parent.id then
    table.insert(rows, detail("Provider", parent.provider))
    table.insert(rows, detail("Model", parent.model))
    table.insert(rows, detail("Updated", parent.updatedAt))
    if #parent.children > 0 then
      table.insert(rows, ui.label({
        text = "Subagents",
        color = "on_surface_variant",
        fontWeight = "medium",
      }))
      for _, child in ipairs(parent.children) do
        table.insert(rows, childEntry(child))
      end
    end
  end
  return ui.column({
    gap = 6, padding = 10, radius = 10, fill = "surface_container",
  }, rows)
end

function onRender()
  local rows = {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "T3 Monitor", fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "refresh", tooltip = "Refresh now", variant = "ghost", onClick = function()
        local value = tonumber(noctalia.state.get("refresh_request")) or 0
        noctalia.state.set("refresh_request", value + 1)
      end }),
      ui.button({ glyph = "settings", tooltip = "Plugin settings", variant = "ghost",
        onClick = function() noctalia.openSettings() end }),
      ui.button({ glyph = "close", tooltip = "Close", variant = "ghost",
        onClick = function() panel.close() end }),
    }),
  }

  if type(snapshot) ~= "table" then
    table.insert(rows, ui.label({ text = "Loading local T3 Code activity…" }))
  elseif snapshot.health ~= "ok" then
    table.insert(rows, ui.label({ text = "Disconnected: " .. text(snapshot.error), color = "error" }))
    table.insert(rows, ui.label({ text = "Check T3, sqlite3, CLI and plugin paths.", color = "on_surface_variant" }))
  else
    table.insert(rows, ui.label({
      text = tostring(snapshot.parentCount or 0) .. " working parents · "
        .. tostring(snapshot.childCount or 0) .. " active subagents · "
        .. tostring(snapshot.attentionCount or 0) .. " attention",
      color = "on_surface_variant",
      fontSize = 11,
    }))
    local active = snapshot.parents or {}
    if #active == 0 then
      table.insert(rows, ui.label({ text = "No active T3 threads or subagents." }))
    else
      local items = {}
      for _, parent in ipairs(active) do
        table.insert(items, parentEntry(parent))
      end
      table.insert(rows, ui.scroll({ flexGrow = 1, gap = 8 }, items))
    end
    table.insert(rows, ui.label({
      text = "Last sync: " .. text(snapshot.lastSyncText),
      color = "on_surface_variant", fontSize = 10,
    }))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 10 }, rows))
end

function onOpen(_context)
  local value = tonumber(noctalia.state.get("refresh_request")) or 0
  noctalia.state.set("refresh_request", value + 1)
  onRender()
end

noctalia.state.watch("snapshot", function(value)
  snapshot = value
  onRender()
end)
