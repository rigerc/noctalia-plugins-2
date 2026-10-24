# Plugin API compatibility — source-snapshot feature ledger

A plugin declares the **oldest** level it requires. The source snapshot supports levels 3–42; levels 35–42 are listed without a released Noctalia version, so treat them as **unreleased at snapshot time**. Keep the plugin level as low as practical.

| API level | Noctalia release mapping | Feature |
| ---: | --- | --- |
| 3 | v5.0.0-beta.3 | Mandatory `plugin_api` compatibility declaration, replacing `min_noctalia`. |
| 4 | v5.0.0-beta.4 | `noctalia.httpStream()` for streaming HTTP responses. |
| 5 | v5.0.0-beta.4 | `ui.dragSource()` and `ui.dropZone()` for declarative panel drag and drop. |
| 6 | v5.0.0-beta.4 | The `string_map` plugin setting type. |
| 7 | v5.0.0-beta.4 | The `allow_insecure_tls` HTTP request option. |
| 8 | v5.0.0-beta.4 | The `dismiss_on_outside_click` panel entry option. |
| 9 | v5.0.0-beta.5 | Luau closures directly in UI tree callback props. |
| 10 | v5.0.0-beta.5 | The `keyboard_focus` panel entry option. |
| 11 | v5.0.0-beta.5 | The `persistent` panel entry option. |
| 12 | v5.0.0-beta.5 | `noctalia.systemStats()`, `noctalia.cpuCores()`, and `noctalia.nowMs()`. |
| 13 | v5.0.0-beta.5 | The `capture_keys` panel entry option and the `onKey` callback. |
| 14 | v5.0.0-beta.5 | The `[widget.actions]` entry table, declaring bar gesture defaults. |
| 15 | v5.0.0-beta.6 | `noctalia.openSettings()`, opening the settings window at the plugin's own settings. |
| 16 | v5.0.0-beta.6 | Per-interface network rates, sample timestamps, and disk mount/stat APIs. |
| 17 | v5.0.0-beta.7 | Service entries start when the plugin is enabled instead of only at launch, and `onExit(signal, reason)` reports `reload`, `disable`, `uninstall`, or `shutdown`. |
| 18 | v5.0.0-beta.7 | `panel.setNeedsFrameTick(bool)`, delivering `onFrameTick(deltaMs)` to an open panel. |
| 19 | v5.0.0-beta.7 | Timezone support on `noctalia.formatTime`, `noctalia.isValidTimezone(name)`, and `noctalia.timeFormat()` / `noctalia.dateFormat()` mirroring `[shell].time_format` / `date_format`. |
| 20 | v5.0.0-beta.7 | `noctalia.sound.load()` and `noctalia.sound.play()` for plugin audio. |
| 21 | v5.0.0-beta.8 | The `ui.markdown` node, `submitOnEnter` on `ui.input`, and `stickToBottom` / `onScroll` / `scrollToBottomRev` on `ui.scroll`. |
| 22 | v5.0.0-beta.8 | `require("./path.luau")` loads relative `.luau` modules with entry-local caches and hot reload for loaded modules. |
| 23 | v5.0.0-beta.8 | `noctalia.readFileAsync(path, callback)` for bounded filesystem reads outside plugin VM workers. |
| 24 | v5.0.0-beta.9 | Argument-array form of `noctalia.runAsync()` for direct process execution without shell parsing. |
| 25 | v5.0.0-beta.9 | `noctalia.wallpaperPath(connector)` and `noctalia.setWallpaperMask(connector, mask)` for source-aligned desktop-widget occlusion masks. |
| 26 | v5.0.0-beta.9 | `noctalia.getSetting(path)` for reading any effective shell config value by TOML dotted path. |
| 27 | v5.0.0-beta.9 | `frameVisible` on `ui.input` for hiding the native input background and border. |
| 28 | v5.0.0-beta.9 | `panel.openContextMenu(request)` for native context menus in regular and persistent plugin panels. |
| 29 | v5.0.1 | `onPointerMove` and `onPointerLeave` callbacks on `ui.graph` nodes. |
| 30 | v5.0.1 | The `layer` panel entry option for choosing the layer-shell layer of a floating plugin panel. |
| 31 | v5.2.0 | `noctalia.getColor(role)` for reading colors from the active theme palette. |
| 32 | v5.2.0 | The `tooltip` prop on `ui.box`, `ui.row`, `ui.column`, and `ui.image`, shown on hover. |
| 33 | v5.3.0 | The `revealKey` prop on `ui.scroll` for scrolling a keyed child into view. |
| 34 | v5.3.0 | The `hover_highlight` widget entry option for opting out of the bar's whole-widget hover highlight. |
| 35 | **Unreleased in snapshot** | `noctalia.idle.watch` and `noctalia.idle.unwatch` for compositor idle notifications, available to every entry kind. |
| 36 | **Unreleased in snapshot** | `[[layer]]` entries for plugin-owned layer-shell surfaces, with `layer.*` and `noctalia.layer.show`, `hide`, and `configure`. |
| 37 | **Unreleased in snapshot** | `noctalia.calendarEvents()` for reading the shell's synced calendar events. |
| 38 | **Unreleased in snapshot** | `ui.dragSource()` and `ui.dropZone()` in bar widgets (`barWidget.render`), not only panels; `dragSource.grabCursor` and `dragSource.onClick` for a source that wraps a whole clickable item; `expandOnDrag` grows a zone along its thin axis. |
| 39 | **Unreleased in snapshot** | `noctalia.osd.show(icon, value, opts)` for showing the shell OSD from plugins. |
| 40 | **Unreleased in snapshot** | `ui.pixelStream` for showing frames from a companion process over a shared-memory socket protocol, with pointer, scroll, and keyboard callbacks. |
| 41 | **Unreleased in snapshot** | `ui.colorPicker` for an inline color picker with optional alpha, hex-only or hidden inputs, swatches, and `onChange` / `onChangeEnd` callbacks. |
| 42 | **Unreleased in snapshot** | `height = "content"` and `max_height` on `[[panel]]` entries: the panel follows the height of its rendered tree. |

## Recipe

1. Identify each capability from actual code and manifest, not from what Noctalia might support.
2. Set `plugin_api = max(required levels)` with minimum 3.
3. If the target Noctalia installation is older than that level, remove the feature or ship a separate compatible release; do not lower the number to silence a gate.
4. Explicitly mention unreleased-in-snapshot API features and test against the exact target build.

## Script validator limitations

`scripts/validate_plugin.py` scans common manifest keys and recognizable Lua calls/properties. It is not a full Luau parser and cannot infer all data-driven calls or custom module behavior. Treat its output as **preflight diagnostics**, not a guarantee of API compatibility.
