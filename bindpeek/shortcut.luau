--!nonstrict
-- SPDX-License-Identifier: GPL-3.0-or-later
local manual = noctalia.state.get("manual") == true
local function render()
  shortcut.setLabel(manual and "Hide Bindpeek" or "Show Bindpeek")
  shortcut.setIcon("keyboard")
  shortcut.setActive(manual)
  shortcut.setEnabled(true)
end

noctalia.state.watch("manual", function(value)
  manual = value == true
  render()
end)

function onClick()
  noctalia.state.set("toggle_request", noctalia.nowMs())
end

function onRightClick()
  noctalia.togglePanel("rigerc/bindpeek:viewer")
end

render()
