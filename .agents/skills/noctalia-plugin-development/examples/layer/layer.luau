--!nonstrict
layer.render(ui.column({ padding = 16, gap = 8, fill = "surface", radius = 12 }, {
  ui.label({ text = noctalia.getConfig("label") or "Layer", fontSize = 20, color = "primary" }),
  ui.label({ text = "Plugin-owned Wayland layer", color = "on_surface" }),
}))
