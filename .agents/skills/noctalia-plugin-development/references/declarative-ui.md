# Declarative UI design and rendering

Authoritative exhaustive prop table: `source-docs/declarative-ui.mdx` in this skill. All `ui.*` functions accept a props table and applicable children. Sizes are logical pixels, host-scaled.

## Render surface selection

- `barWidget.render(tree)` for compact composite bars. Simple text+glyph bars should use `barWidget.setText` and `barWidget.setGlyph` instead. Once tree rendering activates, imperative text/image/glyph patches are not displayed.
- `panel.render(tree)` in `onOpen(context)` and whenever panel state changes; keep panel size in `plugin.toml`.
- `desktopWidget.render(tree)` in `update()`; host owns widget position and dimensions. Use `desktopWidget.setWantsSecondTicks(true)` for clocks and `desktopWidget.setNeedsFrameTick(true)` for animation.
- `layer.render(tree)` from a layer entry; `layer.setNeedsFrameTick(true)` for animation and `layer.outputName()` for local monitor identity. Requires API ≥36.

## Native UI vocabulary

| Construct | Essential props / notes |
| --- | --- |
| `ui.row`, `ui.column` | `gap`, `padding`, `align`, `justify`, `fill`, `radius`, `border` |
| `ui.scroll` | vertically scrolling, `stickToBottom`, `scrollToBottomRev`, `revealKey` |
| `ui.box` | `fill`, `width`, `height`, `border`, `radius`, `softness` |
| `ui.label` | `text`, `fontSize`, `fontWeight`, `fontFamily`, `color`, `maxLines` |
| `ui.glyph` | `name`, `size`, `color` |
| `ui.image` | local `path`, `width`, `height`, `fit`, `radius` |
| `ui.button` | `text`, `glyph`, `variant`, `tooltip`, `enabled`, `onClick` |
| `ui.input` | `value` (initial only), `placeholder`, `focus`, `onChange`, `onSubmit`, `multiline` |
| `ui.toggle` | `checked`, `onChange` |
| `ui.slider` | `value`, `min`, `max`, `step`, `onChange`, `onDragEnd` |
| `ui.select` | `options`, `selectedIndex`, `onChange` |
| `ui.progress` | `progress` 0..1, `fill`, `track` |
| `ui.graph` | normalized `values`/`values2`, optional pointer callbacks (API ≥29) |
| `ui.markdown` | read-only markdown content; API ≥21 |
| `ui.dragSource`, `ui.dropZone` | DnD in panels ≥5, bar widgets ≥38 |
| `ui.pixelStream` | companion socket-backed frames; API ≥40; specialized protocol required |
| `ui.colorPicker` | inline picker; API ≥41 |

All nodes have `width`, `height`, `flexGrow`, `opacity`, `visible`. Layout defaults stretch children across cross axis. Use `align = "center"` for compact rows. A color can be a palette role (`"on_surface"`), a role with alpha (`"surface/0.6"`), or a hex value; prefer theme-aware roles. Parent `opacity` fades text too; use `fill = "surface/0.6"` if only the background should be translucent.

## Callbacks and state

```lua
local count = 0

local function render()
  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.label({ text = "Count: " .. tostring(count), color = "on_surface" }),
    ui.button({ text = "Increment", variant = "primary", onClick = "increase" }),
    ui.button({ text = "Close", onClick = "closePanel" }),
  }))
end

function onOpen(_context) render() end
function increase() count = count + 1; render() end
function closePanel() panel.close() end
```

Callbacks can be **named global function strings** (baseline) or closures (API ≥9). A toggle `onChange` receives string `"true"`/`"false"`; a slider/select callback receives its value/index as a string. Parse explicitly. `ui.input.value` seeds the input **once**; the host owns subsequent edits. Toggle/slider/select are controlled and must be re-rendered with updated values. Use stable `key` on repeated children to retain identity and input state. `focus = true` is a one-time request when an input is first created, not on later renders.

Use closures for per-row actions only after enabling API ≥9:

```lua
for _, item in ipairs(items) do
  table.insert(rows, ui.button({
    key = item.id,
    text = item.title,
    onClick = function() openItem(item.id) end,
  }))
end
```

## UI constraints and ergonomics

- Bar: one control thick; choose horizontal row or vertical column via `barWidget.isVertical()`. Bar ignores keyboard-dependent `ui.input`, `ui.select`, `ui.scroll`. Pointer controls work; button clicks consume their own pointer events.
- Panel: use `onOpen` for initial render. `width`/`height` are manifest owned; `height="content"` needs API ≥42, `max_height`, and nonpersistent panel. `setNeedsFrameTick` for panel needs API ≥18.
- Persistent panel: cannot be exclusive keyboard focus, must disable outside-click dismiss, does not support `ui.select` dropdowns.
- Layers: UI trees can receive pointer and keyboard if the compositor gives focus. One runtime per shown output; hiding destroys runtime.
- Desktop widget: tooltips for containers may not appear; size, rotation and placement are user-owned.
- Images: remote URLs do **not** work in `ui.image`. Download first to a path inside plugin data and then render that local file; handle loading failure.
- Graph: normalized 0–1 values; pointer data callback values are strings.
- Performance: avoid reconstructing gigantic trees unnecessarily, throttle HTTP/IPC updates, and use keyed lists.

## Advanced feature gates

| Capability | API |
| --- | ---: |
| Closure callbacks | 9 |
| Panel frame ticks | 18 |
| `ui.markdown`, multiline submit-on-enter, scroll follow | 21 |
| `frameVisible` on input | 27 |
| Graph pointer callbacks | 29 |
| Container tooltip | 32 |
| Scroll `revealKey` | 33 |
| Bar drag/drop | 38 |
| Pixel stream | 40 |
| Inline color picker | 41 |
| Panel content height | 42 |

For the full pixel-stream framing protocol and drag/drop data shape, **read `source-docs/declarative-ui.mdx` before implementing**; do not invent wire formats or callback signatures.
