# Manifest, entry contracts, and settings

Source of truth: the uploaded snapshot's `docs/user/plugins/development/manifest.mdx` and `entries.mdx`, also copied to `source-docs/`. This file is a concise implementation guide, not a replacement for the source docs.

## Identity and shape

```toml
id = "acme/flux"
name = "Flux"
version = "1.0.0"
plugin_api = 3
author = "acme"
license = "MIT"
description = "A configurable shell extension."
icon = "puzzle"
tags = ["utility"]
# dependencies = ["some-optional-executable"]

[[setting]]
key = "refresh_seconds"
type = "int"
label_key = "settings.refresh_seconds.label"
default = 30
min = 5
max = 3600

[[widget]]
id = "status"
entry = "widget.luau"

  [[widget.setting]]
  key = "label"
  type = "string"
  label_key = "settings.label.label"
  default = "Flux"

[[panel]]
id = "details"
entry = "panel.luau"
width = 420
height = 280
placement = "floating"
position = "center"

[[service]]
id = "poller"
entry = "service.luau"
```

`translations/en.json`:

```json
{
  "settings.refresh_seconds.label": "Refresh interval (seconds)",
  "settings.label.label": "Widget label"
}
```

Root `id`, `name`, `version`, `plugin_api` are mandatory. Version is exactly `MAJOR.MINOR.PATCH` of non-negative integers without leading zeros; suffixes like `-rc.1` are not valid. `plugin_api` must be a positive integer within the host's supported range. The included snapshot advertises 3–42, with 35–42 not mapped to released versions. `author` is shown in examples but is not listed by the source docs as a mandatory root field.

## Entry kind decision table

| Manifest table | Entry Lua API | Host callbacks | Use when |
| --- | --- | --- | --- |
| `[[widget]]` | `barWidget.*` and optionally `ui.*` | `update`, `onClick`, `onRightClick`, `onMiddleClick`, `onScroll`, `onIpc`, `onExit` | compact bar status/action |
| `[[shortcut]]` | `shortcut.setLabel`, `.setIcon`, `.setActive`, `.setEnabled` | `onClick`, `onRightClick`, `onIpc`, `onExit` | control-center tile |
| `[[launcher_provider]]` | `launcher.setResults`, `.setQuery` | `onQuery`, `onActivate`, `onIpc`, `onExit` | indexed launcher search |
| `[[desktop_widget]]` | `desktopWidget.render`, ticks | `update`, `onFrameTick`, `onIpc`, `onExit` | desktop tile |
| `[[panel]]` | `panel.render`, `.close`, ticks | `onOpen`, `onClose`, `update`, `onFrameTick`, `onKey`, `onIpc`, `onExit` | interactive transient or persistent panel |
| `[[layer]]` | `layer.render`, `.outputName`, frame tick | `update`, `onFrameTick`, `onConfigChanged`, `onIpc`, `onExit` | raw layer-shell surface; API >=36 |
| `[[service]]` | `noctalia.*` (no surface) | `update`, `onEnable`, `onConfigChanged`, `onIpc`, `onExit` | singleton background work |

`onIpc(event, payload)` works for all kinds. `onExit(signal, reason)` works for all kinds; the reason string needs API ≥17. Services start with plugin enable on API ≥17; `onEnable` is for *explicit enable action*, not normal startup or reload. Services defining `onConfigChanged()` preserve memory across a settings change; without it services restart. Widget/panel/desktop entries are rebuilt on settings changes. `noctalia.state` survives service restarts within the plugin process but does not survive the shell process exiting.

## Settings and scopes

- Root `[[setting]]`: plugin-wide, seeded into all entries; belongs in **Settings → Plugins**.
- `[[widget.setting]]`: scoped to a specific widget entry/instance, edited with that widget's settings. Overrides same-named plugin setting in that widget.
- `[[panel.setting]]`: panel-specific and edited under plugin settings.
- Layers do **not** support `[[layer.setting]]`; use root settings.
- A setting needs `key`, `type`, and `label_key`; use translation keys, not literal `label` or `description`. The English translation file must contain the label and any description key.
- Types: `string`, `string_list`, `string_map` (API ≥6), `bool`, `int`, `double`, `select`, `file`, `folder`, `glyph`, `color`. The `default` must match the declared type. Use `min` and `max` for numeric types; `{value, label_key}` choices for `select`; `extensions` on `file`; `{key, values}` for `visible_when`; `advanced = true` to hide a rarely changed option.
- `noctalia.getConfig("key")` resolves declared keys only; missing keys are logged warnings and `nil`. Do not use it to fetch general shell settings; `noctalia.getSetting("shell.offline_mode")` requires API ≥26.

## Panel manifest specifics

- `width`, `height` control host-owned size; use fixed positive logical px or `"fill"` with `placement = "floating"` where applicable.
- `height = "content"` requires API ≥42 and `max_height`; cannot be used with `persistent = true`.
- `placement`: `attached` / `floating`; `position` examples `auto`, `center`, `bottom_center`; `open_near_click` (bool).
- `dismiss_on_outside_click = false` requires API ≥8; useful for forms.
- `keyboard_focus`: `on_demand`, `exclusive`, or `none` (API ≥10).
- `persistent = true` requires API ≥11; must also set `dismiss_on_outside_click = false`, cannot have `keyboard_focus = "exclusive"`, and does not support `ui.select` dropdowns.
- `capture_keys = ["space", "ctrl+r"]` requires API ≥13; cannot be used with `keyboard_focus = "none"` and cannot intercept Escape.
- `layer = "top"` / `"overlay"` applies to floating panels; declaring it requires API ≥30.
- Do not define host-injected panel settings as `[[panel.setting]]` just to expose placement, position, layer, open_near_click: Noctalia already injects those keys. They may be overridden via `[plugin_settings."author/plugin"]`.

## Widget manifest specifics

`[widget.actions]` (API ≥14) declares overridable gesture defaults (e.g. `right = "media toggle"`, `scroll_up = "volume-up"`). A gesture bound by the user does not invoke the equivalent script callback. `onMiddleClick` usually will not run because the built-in middle-click opens settings; to free it declare `middle = "none"`. `hover_highlight = false` at the widget entry level requires API ≥34, and must appear **before** `[widget.actions]` in TOML.

## Layer manifest specifics (API ≥36)

```toml
[[layer]]
id = "overlay"
entry = "overlay.luau"
layer = "overlay"
anchors = ["top", "bottom", "left", "right"]
exclusive_zone = -1
keyboard = "none"
output = "all"
visible = false
```

Valid `layer` is `background`/`bottom`/`top`/`overlay`; anchors are distinct among top/bottom/left/right. `width`/`height` 0 stretches on opposing anchors; margins are a table of integers. `exclusive_zone` can be -1, 0, non-negative integer, or `"auto"`. `keyboard` is `none`/`on_demand`/`exclusive`; `click_through` is boolean; `output` is `all`, `focused`, or a connector. `noctalia.layer.show("overlay")` uses **local** entry id and creates an instance *per output*. Hiding destroys runtime state; screensaver-like overlays should usually be driven by a service.

## Launcher manifest specifics

`prefix = "tr"` (NOT `/tr`), `glyph`, `include_in_global_search` (bool), and `debounce_ms` (nonnegative integer). In `onQuery(text)`, echo the same `text` in `launcher.setResults(text, results)` to guard late async results. Results include `id`, `title`, `subtitle`, `glyph`/`icon`/`badge`, `score`, and optionally `query` to drill in. Selecting a result without drill-in closes the launcher. Avoid remote HTTP calls on every keystroke; use `debounce_ms`.

## Modules (API ≥22)

`local M = require("./lib/helpers.luau")` requires explicit relative path and `.luau` extension. A module must return one non-nil value; each entry has its own module cache. A module edit hot-reloads entries that successfully loaded it; missing modules are not automatically watched. Avoid cross-plugin module dependencies and test the runtime after edits.
