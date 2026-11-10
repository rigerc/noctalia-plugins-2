--!nonstrict
-- SPDX-License-Identifier: GPL-3.0-or-later
local status = noctalia.state.get("backend") or "waiting"
local held = noctalia.state.get("held") or {}
local manual = noctalia.state.get("manual") == true

local function render()
  barWidget.setGlyph("keyboard")
  barWidget.setText(#held > 0 and table.concat(held, "+") or "Bindpeek")
  barWidget.setColor(status == "missing" and "error" or "on_surface")
  barWidget.setTooltip({
    { key = "Watch", value = status },
    { key = "Left click", value = "Open shortcut viewer" },
    { key = "Right click", value = manual and "Hide overlay" or "Pin overlay" },
  })
end

noctalia.state.watch("held", function(value)
  held = value or {}
  render()
end)
noctalia.state.watch("backend", function(value)
  status = value or "waiting"
  render()
end)
noctalia.state.watch("manual", function(value)
  manual = value == true
  render()
end)

function onClick()
  noctalia.togglePanel("rigerc/bindpeek:viewer")
end

function onRightClick()
  noctalia.state.set("toggle_request", noctalia.nowMs())
end

render()
