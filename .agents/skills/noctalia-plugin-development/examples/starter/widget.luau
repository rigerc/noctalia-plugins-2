--!nonstrict
-- Each widget placement has its own VM.
local function render()
  local label = noctalia.getConfig("label") or "Status"
  local count = noctalia.state.get("count")
  barWidget.setGlyph("puzzle")
  barWidget.setText(count and (label .. ": " .. tostring(count)) or label)
  barWidget.setTooltip("Click to show details")
end

noctalia.state.watch("count", function(_) render() end)

function update()
  render()
end

function onClick()
  noctalia.togglePanel("acme/demo:panel")
end

function onIpc(event, _payload)
  if event == "refresh" then render() end
end
