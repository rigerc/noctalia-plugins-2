--!nonstrict
local count = noctalia.state.get("count") or 0

local function render()
  local label = noctalia.getConfig("label") or "Details"
  panel.render(ui.column({ padding = 16, gap = 14, fill = "surface" }, {
    ui.label({ text = label, fontSize = 20, fontWeight = "bold", color = "on_surface" }),
    ui.label({ text = "Count: " .. tostring(count), color = "on_surface_variant" }),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ text = "Refresh", variant = "primary", onClick = "refreshPanel" }),
      ui.button({ text = "Close", variant = "outline", onClick = "closePanel" }),
    }),
  }))
end

noctalia.state.watch("count", function(value)
  count = value or 0
  render()
end)

function onOpen(_context) render() end
function refreshPanel() count = noctalia.state.get("count") or 0; render() end
function closePanel() panel.close() end
function onIpc(event, _payload) if event == "refresh" then refreshPanel() end end
