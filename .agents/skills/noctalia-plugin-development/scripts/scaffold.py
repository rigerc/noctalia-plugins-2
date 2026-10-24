#!/usr/bin/env python3
"""Create a conservative Noctalia v5 native Luau plugin starter. Python 3.11+."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

KINDS = (
    "starter", "widget", "panel", "service", "shortcut", "launcher_provider",
    "desktop_widget", "layer",
)
PLUGIN_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$")


def lua_string(text: str) -> str:
    # JSON-escaped double-quoted strings are compatible with these ASCII source fields.
    import json
    return json.dumps(text, ensure_ascii=True)


def make_files(plugin_id: str, name: str, kind: str) -> dict[str, str]:
    import json
    owner, slug = plugin_id.split("/", 1)
    is_combo = kind == "starter"
    manifest = [
        f'id = "{plugin_id}"',
        f'name = {json.dumps(name, ensure_ascii=True)}',
        'version = "0.1.0"',
        f'plugin_api = {36 if kind == "layer" else 3}',
        f'author = "{owner}"',
        'license = "MIT"',
        f'description = {json.dumps(name + " native Luau plugin.", ensure_ascii=True)}',
        'icon = "puzzle"',
        '',
        '[[setting]]',
        'key = "label"',
        'type = "string"',
        'label_key = "settings.label.label"',
        f'default = {json.dumps(name, ensure_ascii=True)}',
    ]
    files: dict[str, str] = {}

    def entry(entry_type: str, entry_id: str, filename: str, props: list[str] | None = None) -> None:
        manifest.extend(['', f'[[{entry_type}]]', f'id = "{entry_id}"', f'entry = "{filename}"'])
        manifest.extend(props or [])

    if kind in ("widget", "starter"):
        entry("widget", "status", "widget.luau")
        files["widget.luau"] = '''--!nonstrict
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
''' + (f'  noctalia.togglePanel("{plugin_id}:panel")\n' if is_combo else '  noctalia.notify("Status", noctalia.getConfig("label") or "Hello")\n') + '''end

function onIpc(event, _payload)
  if event == "refresh" then render() end
end
'''
    if kind in ("panel", "starter"):
        entry("panel", "panel", "panel.luau", ["width = 380", "height = 230", 'placement = "floating"', 'position = "center"'])
        files["panel.luau"] = '''--!nonstrict
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
'''
    if kind in ("service", "starter"):
        entry("service", "service", "service.luau")
        files["service.luau"] = '''--!nonstrict
-- Starts on plugin load. No UI: share plain data with other entries.
local count = 0
noctalia.setUpdateInterval(1000)

function update()
  count = count + 1
  noctalia.state.set("count", count)
end

function onIpc(event, _payload)
  if event == "refresh" then update() end
end

function onExit(_signal)
  noctalia.log("Service stopped")
end
'''
    if kind == "shortcut":
        entry("shortcut", "toggle", "shortcut.luau")
        files["shortcut.luau"] = '''--!nonstrict
local enabled = noctalia.state.get("enabled") == true
local function render()
  shortcut.setLabel(noctalia.getConfig("label") or "Toggle")
  shortcut.setIcon(enabled and "check" or "x")
  shortcut.setActive(enabled)
  shortcut.setEnabled(true)
end
render()

function onClick()
  enabled = not enabled
  noctalia.state.set("enabled", enabled)
  render()
end
'''
    if kind == "launcher_provider":
        entry("launcher_provider", "search", "launcher.luau", ['prefix = "demo"', 'glyph = "search"', 'debounce_ms = 200'])
        files["launcher.luau"] = '''--!nonstrict
local choices = { "Apple", "Apricot", "Banana", "Blueberry", "Cherry" }

function onQuery(text)
  local results = {}
  local query = string.lower(text)
  for _, name in ipairs(choices) do
    if query == "" or string.find(string.lower(name), query, 1, true) then
      table.insert(results, { id = name, title = name, subtitle = noctalia.getConfig("label") or "Sample" })
    end
  end
  launcher.setResults(text, results) -- MUST echo onQuery's text.
end

function onActivate(id)
  noctalia.copyToClipboard(id, "text/plain")
end
'''
    if kind == "desktop_widget":
        entry("desktop_widget", "tile", "desktop.luau")
        files["desktop.luau"] = '''--!nonstrict
function update()
  desktopWidget.render(ui.column({ gap = 8, padding = 12, align = "center" }, {
    ui.glyph({ name = "puzzle", size = 28, color = "primary" }),
    ui.label({ text = noctalia.getConfig("label") or "Desktop tile", fontSize = 18 }),
    ui.label({ text = os.date("%H:%M"), color = "on_surface_variant" }),
  }))
end
'''
    if kind == "layer":
        # A lazy layer needs a live controller. Avoid an always-visible or keyboard-grabbing surface.
        entry("service", "controller", "controller.luau")
        entry("layer", "overlay", "layer.luau", [
            'layer = "top"', 'anchors = []', 'width = 340', 'height = 110',
            'keyboard = "none"', 'click_through = true', 'visible = false',
        ])
        files["controller.luau"] = '''--!nonstrict
-- Show and hide with: noctalia msg plugin AUTHOR/NAME:controller all show|hide
function onIpc(event, _payload)
  if event == "show" then
    noctalia.layer.show("overlay")
  elseif event == "hide" then
    noctalia.layer.hide("overlay")
  end
end
'''
        files["layer.luau"] = '''--!nonstrict
layer.render(ui.column({ padding = 16, gap = 8, fill = "surface", radius = 12 }, {
  ui.label({ text = noctalia.getConfig("label") or "Layer", fontSize = 20, color = "primary" }),
  ui.label({ text = "Plugin-owned Wayland layer", color = "on_surface" }),
}))
'''
    manifest.append('')
    files["plugin.toml"] = "\n".join(manifest)
    files["translations/en.json"] = json.dumps({"settings.label.label": "Display label"}, indent=2) + "\n"
    files["README.md"] = f'''# {name}

A minimal **Noctalia v5+ native Luau plugin** (`{kind}` starter).

## Install and test

Copy this plugin directory under `$XDG_DATA_HOME/noctalia/plugins/{slug}/`, or add a `path` source to the **parent repository directory**. Then enable it in Noctalia Settings → Plugins or with:

```sh
noctalia msg plugins enable {plugin_id}
```

Run local checks:

```sh
python3 /path/to/noctalia-plugin-development/scripts/validate_plugin.py .
noctalia plugins lint .   # available in Noctalia builds exposing offline plugin lint
```

''' + (
        f'For a bar widget, place `{plugin_id}:status` on a bar. Click it to open `{plugin_id}:panel`.\n\n' if is_combo else
        f'Place `{plugin_id}:status` on a bar.\n\n' if kind == "widget" else
        f'Open the panel using `noctalia msg panel-toggle {plugin_id}:panel`.\n\n' if kind == "panel" else
        f'Run `noctalia msg plugin {plugin_id}:controller all show` (or `hide`) to control the layer. This example requires plugin API ≥36, unreleased in the bundled source snapshot.\n\n' if kind == "layer" else
        f'Test IPC with `noctalia msg plugin {plugin_id}:service all refresh`.\n\n' if kind == "service" else
        'In the launcher use the `/demo` prefix to see sample results.\n\n' if kind == "launcher_provider" else
        'Enable the plugin and configure its entry through the Noctalia UI.\n\n'
    ) + '''## Notes

- Set `plugin_api` to the *oldest required* feature level, not the latest advertised.
- Files run in isolated Luau entry VMs; cross-entry values use `noctalia.state`.
- Settings labels live under `translations/en.json`.
- This generated plugin was statically scaffolded; verify in a matching live Noctalia/Wayland session.
'''
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--id", required=True, help="Canonical ID, e.g. acme/clock")
    parser.add_argument("--name", help="Display name (default: title-cased plugin slug)")
    parser.add_argument("--kind", choices=KINDS, default="starter")
    parser.add_argument("--output", type=Path, required=True, help="New plugin directory (must not exist)")
    args = parser.parse_args()
    if not PLUGIN_ID.fullmatch(args.id):
        parser.error("--id must match author/plugin with letters, digits, underscore, hyphen or dot")
    if args.output.exists():
        parser.error(f"refusing to overwrite existing path: {args.output}")
    name = args.name or args.id.split("/", 1)[1].replace("-", " ").replace("_", " ").title()
    files = make_files(args.id, name, args.kind)
    for rel, content in files.items():
        path = args.output / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    print(f"Created {args.kind} plugin {args.id} at {args.output}")
    print(f"Validate: python3 {Path(__file__).with_name('validate_plugin.py')} {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
