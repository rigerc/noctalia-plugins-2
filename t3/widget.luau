-- Native Noctalia bar capsule. All data comes from the monitor service.
local snapshot = noctalia.state.get("snapshot")
noctalia.setUpdateInterval(1000)

local function render()
  barWidget.setGlyph("code")
  if type(snapshot) ~= "table" then
    barWidget.setText("T3 · …")
    barWidget.setTooltip("Waiting for T3 monitor")
    return
  end
  if snapshot.health ~= "ok" then
    barWidget.setText("T3 · offline")
    barWidget.setTooltip("T3 Monitor: " .. tostring(snapshot.error or "Disconnected"))
    return
  end

  local parents = tonumber(snapshot.parentCount) or 0
  local children = tonumber(snapshot.childCount) or 0
  local attention = tonumber(snapshot.attentionCount) or 0
  local text = "T3 · " .. parents .. "P " .. children .. "S"
  -- Persistent attention outranks a transient completion highlight.
  if attention > 0 then
    text = text .. " · !" .. attention
  elseif type(snapshot.highlight) == "table"
     and (os.time() - (tonumber(snapshot.highlight.at) or 0)) < 5 then
    text = "T3 · ✓ " .. tostring(snapshot.highlight.title or "Finished")
  end
  barWidget.setText(text)
  barWidget.setTooltip(
    "T3 Code · " .. parents .. " active parents · " .. children .. " active subagents"
      .. (attention > 0 and (" · " .. attention .. " require attention") or "")
  )
end

noctalia.state.watch("snapshot", function(value)
  snapshot = value
  render()
end)

function update()
  render()
end

function onClick()
  noctalia.togglePanel("rigerc/t3:dashboard")
end
