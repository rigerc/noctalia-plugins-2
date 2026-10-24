#!/usr/bin/env python3
"""Preflight Noctalia v5 Luau plugin manifests and recognizable API gates.

This is NOT a Luau parser, Noctalia host compatibility check, or replacement for
`noctalia plugins lint`, which checks actual getConfig uses across loaded modules.
Python 3.11+ required (tomllib).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
import tomllib
from typing import Any

ENTRY_TYPES = ("widget", "shortcut", "launcher_provider", "desktop_widget", "panel", "layer", "service")
SETTING_TYPES = {"string", "string_list", "string_map", "bool", "int", "double", "select", "file", "folder", "glyph", "color"}
PLUGIN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$")
VERSION_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
LITERAL_GET_CONFIG_RE = re.compile(r'\bnoctalia\.getConfig\s*\(\s*["\']([^"\']+)["\']')
REL_REQUIRE_RE = re.compile(r'\brequire\s*\(\s*["\']([^"\']+)["\']\s*\)')
# Static Lua patterns, deliberately conservative: an indicator is not a compiler.
SCRIPT_GATES: list[tuple[int, str, str]] = [
    (4, r'\bnoctalia\.httpStream\s*\(', 'HTTP streaming'),
    (7, r'\ballow_insecure_tls\s*=', 'disable TLS validation option'),
    (9, r'\bon(?:Click|RightClick|Hover|Change|Submit|DragEnd)\s*=\s*function\b', 'inline UI callback closure'),
    (12, r'\bnoctalia\.(?:systemStats|cpuCores|nowMs)\s*\(', 'system stats/nowMs'),
    (16, r'\bnoctalia\.(?:diskMounts|diskUsage|networkRates)\s*\(', 'extended system stats'),
    (18, r'\bpanel\.setNeedsFrameTick\s*\(', 'panel frame tick'),
    (19, r'\bnoctalia\.(?:isValidTimezone|timeFormat|dateFormat)\s*\(', 'timezone/time format API'),
    (20, r'\bnoctalia\.sound\.', 'sound API'),
    (21, r'\bui\.markdown\s*\(|\bsubmitOnEnter\s*=|\bstickToBottom\s*=|\bscrollToBottomRev\s*=', 'UI markdown/scroll/input extensions'),
    (22, r'\brequire\s*\(', 'relative Luau module require'),
    (23, r'\bnoctalia\.readFileAsync\s*\(', 'async file reads'),
    (24, r'\bnoctalia\.runAsync\s*\(\s*\{', 'argument-vector process execution'),
    (25, r'\bnoctalia\.(?:wallpaperPath|setWallpaperMask)\s*\(', 'wallpaper mask/source'),
    (26, r'\bnoctalia\.getSetting\s*\(', 'shell setting lookup'),
    (27, r'\bframeVisible\s*=', 'input frameVisible prop'),
    (28, r'\bpanel\.openContextMenu\s*\(', 'panel context menu'),
    (29, r'\bonPointer(?:Move|Leave)\s*=', 'graph pointer tracking'),
    (31, r'\bnoctalia\.getColor\s*\(', 'palette color read'),
    (33, r'\brevealKey\s*=', 'scroll revealKey'),
    (35, r'\bnoctalia\.idle\.(?:watch|unwatch)\s*\(', 'idle watch'),
    (36, r'\bnoctalia\.layer\.(?:show|hide|configure)\s*\(|\blayer\.render\s*\(', 'layer runtime API'),
    (37, r'\bnoctalia\.calendarEvents\s*\(', 'calendar events'),
    (39, r'\bnoctalia\.osd\.show\s*\(', 'plugin OSD'),
    (40, r'\bui\.pixelStream\s*\(', 'pixel stream'),
    (41, r'\bui\.colorPicker\s*\(', 'inline color picker'),
]


class Report:
    def __init__(self, location: str) -> None:
        self.location = location
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.infos: list[str] = []
        self.required: list[tuple[int, str]] = [(3, "native v5 plugin manifest")]

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def gate(self, level: int, reason: str) -> None:
        self.required.append((level, reason))


def validate_setting(setting: Any, label: str, report: Report, used_keys: set[str], translations: dict[str, Any]) -> None:
    if not isinstance(setting, dict):
        report.error(f"{label}: setting must be a TOML table")
        return
    key = setting.get("key")
    if not isinstance(key, str) or not key:
        report.error(f"{label}: missing nonempty setting key")
        return
    if key in used_keys:
        report.error(f"{label}: duplicate setting key {key!r} in same scope")
    used_keys.add(key)
    typ = setting.get("type")
    if typ not in SETTING_TYPES:
        report.error(f"{label}: {key}: unsupported setting type {typ!r}")
    if typ == "string_map":
        report.gate(6, f"{label} setting {key}: string_map")
    for forbidden in ("label", "description"):
        if forbidden in setting:
            report.error(f"{label}: {key}: use label_key/description_key, not literal {forbidden}")
    for field in ("label_key", "description_key"):
        if field == "label_key" and not isinstance(setting.get(field), str):
            report.error(f"{label}: {key}: label_key is required")
        k = setting.get(field)
        if k is not None and (not isinstance(k, str) or not isinstance(translations.get(k), str)):
            report.error(f"{label}: {key}: translation {field}={k!r} missing in translations/en.json")
    if "default" in setting:
        value = setting["default"]
        valid: bool | None = None
        if typ in ("string", "select", "file", "folder", "glyph", "color"):
            valid = isinstance(value, str)
        elif typ == "bool":
            valid = type(value) is bool
        elif typ == "int":
            valid = type(value) is int
        elif typ == "double":
            valid = type(value) in (float, int)
        elif typ == "string_list":
            valid = isinstance(value, list) and all(isinstance(x, str) for x in value)
        elif typ == "string_map":
            valid = isinstance(value, dict) and all(isinstance(k, str) and isinstance(v, str) for k, v in value.items())
        if valid is False:
            report.error(f"{label}: {key}: default type does not match {typ}")
    if typ == "select":
        options = setting.get("options")
        if not isinstance(options, list) or not options:
            report.error(f"{label}: {key}: select requires a nonempty options list")
        else:
            for index, opt in enumerate(options):
                if not isinstance(opt, dict) or "value" not in opt or "label_key" not in opt:
                    report.error(f"{label}: {key}: options[{index}] requires value and label_key")
                elif not isinstance(translations.get(opt['label_key']), str):
                    report.error(f"{label}: {key}: option label translation {opt['label_key']!r} missing")
    if typ in ("int", "double"):
        for bound in ("min", "max"):
            if bound in setting and (type(setting[bound]) not in (int, float)):
                report.error(f"{label}: {key}: {bound} must be numeric")
        if "min" in setting and "max" in setting and setting["min"] > setting["max"]:
            report.error(f"{label}: {key}: min must not exceed max")
    when = setting.get("visible_when")
    if when is not None and (not isinstance(when, dict) or not isinstance(when.get("key"), str)
                             or not isinstance(when.get("values"), list)):
        report.error(f"{label}: {key}: visible_when needs {{ key = ..., values = [...] }}")


def load_manifest(path: Path, report: Report) -> dict[str, Any] | None:
    if not path.is_file():
        report.error("Missing plugin.toml")
        return None
    try:
        with path.open("rb") as fh:
            root = tomllib.load(fh)
        if not isinstance(root, dict):
            report.error("Top-level TOML must be a table")
            return None
        return root
    except (OSError, tomllib.TOMLDecodeError) as exc:
        report.error(f"Failed to read/parse plugin.toml: {exc}")
        return None


def load_translations(plugin: Path, report: Report) -> dict[str, Any]:
    path = plugin / "translations/en.json"
    if not path.exists():
        return {}
    try:
        content = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(content, dict):
            report.error("translations/en.json must be a JSON object")
            return {}
        return content
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        report.error(f"Invalid translations/en.json: {exc}")
        return {}


def validate(plugin: Path) -> Report:
    plugin = plugin.resolve()
    report = Report(str(plugin))
    manifest = load_manifest(plugin / "plugin.toml", report)
    if manifest is None:
        return report
    pid = manifest.get("id")
    if not isinstance(pid, str) or not PLUGIN_ID_RE.fullmatch(pid):
        report.error("Root id must be author/plugin (letters, numbers, ., _, -)")
    if not isinstance(manifest.get("name"), str) or not manifest["name"].strip():
        report.error("Root name is required and must be a nonempty string")
    version = manifest.get("version")
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version):
        report.error("version must be exactly MAJOR.MINOR.PATCH without leading zeroes or suffixes")
    api = manifest.get("plugin_api")
    if type(api) is not int or not 3 <= api <= 42:
        report.error("plugin_api must be an integer in snapshot-supported range 3..42")

    translations = load_translations(plugin, report)
    root_keys: set[str] = set()
    for idx, setting in enumerate(manifest.get("setting", [])):
        validate_setting(setting, f"setting[{idx}]", report, root_keys, translations)
    entry_count = 0
    entry_ids: set[str] = set()
    lua_paths: dict[Path, set[str]] = {}
    entry_decls: list[tuple[str, str, Path, set[str]]] = []
    for kind in ENTRY_TYPES:
        entries = manifest.get(kind, [])
        if not isinstance(entries, list):
            report.error(f"[[{kind}]] must be an array of tables")
            continue
        for index, ent in enumerate(entries):
            entry_count += 1
            where = f"{kind}[{index}]"
            if not isinstance(ent, dict):
                report.error(f"{where}: entry must be a TOML table")
                continue
            entry_id = ent.get("id")
            if not isinstance(entry_id, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", entry_id):
                report.error(f"{where}: missing/invalid entry id")
                continue
            if entry_id in entry_ids:
                report.error(f"{where}: duplicate entry id {entry_id!r} (entry ids share a namespace)")
            entry_ids.add(entry_id)
            source_file = ent.get("entry")
            if not isinstance(source_file, str) or not source_file.endswith(".luau"):
                report.error(f"{where}: entry must point to a .luau file")
                continue
            resolved = (plugin / source_file).resolve()
            if not resolved.is_relative_to(plugin):
                report.error(f"{where}: entry file resolves outside plugin directory")
                continue
            if not resolved.is_file():
                report.error(f"{where}: missing entry file {source_file!r}")
                continue
            keys: set[str] = set()
            for idx, setting in enumerate(ent.get("setting", [])):
                validate_setting(setting, f"{where}.setting[{idx}]", report, keys, translations)
            if kind not in ("widget", "panel") and ent.get("setting"):
                report.error(f"{where}: entry-specific [[{kind}.setting]] is not supported; use root [[setting]]")
            if kind == "widget":
                if "actions" in ent: report.gate(14, f"{where}: widget actions")
                if "hover_highlight" in ent: report.gate(34, f"{where}: widget hover_highlight")
            if kind == "panel":
                if "dismiss_on_outside_click" in ent: report.gate(8, f"{where}: outside-click dismiss option")
                if "keyboard_focus" in ent: report.gate(10, f"{where}: keyboard_focus option")
                if "persistent" in ent: report.gate(11, f"{where}: persistent option")
                if "capture_keys" in ent: report.gate(13, f"{where}: capture_keys option")
                if "layer" in ent: report.gate(30, f"{where}: layer option")
                if ent.get("height") == "content":
                    report.gate(42, f"{where}: content-sized height")
                    if type(ent.get("max_height")) is not int or ent["max_height"] <= 0:
                        report.error(f"{where}: height='content' requires positive integer max_height")
                    if ent.get("persistent") is True:
                        report.error(f"{where}: content-sized panel cannot be persistent")
                if ent.get("persistent") is True:
                    if ent.get("dismiss_on_outside_click", True) is not False:
                        report.error(f"{where}: persistent panel requires dismiss_on_outside_click=false")
                    if ent.get("keyboard_focus") == "exclusive":
                        report.error(f"{where}: persistent panel cannot use exclusive keyboard focus")
                if ent.get("capture_keys") and ent.get("keyboard_focus") == "none":
                    report.error(f"{where}: capture_keys cannot be used with keyboard_focus='none'")
            if kind == "layer":
                report.gate(36, f"{where}: layer entry")
                if ent.get("setting"):
                    report.error(f"{where}: layer-specific settings are unsupported")
                if ent.get("layer", "top") not in {"background", "bottom", "top", "overlay"}:
                    report.error(f"{where}: invalid layer value")
                anchors = ent.get("anchors", [])
                if not isinstance(anchors, list) or len(anchors) != len(set(map(str, anchors))) or any(
                    x not in ("top", "bottom", "left", "right") for x in anchors
                ):
                    report.error(f"{where}: anchors must be distinct top/bottom/left/right strings")
                if ent.get("keyboard", "none") not in {"none", "on_demand", "exclusive"}:
                    report.error(f"{where}: invalid keyboard mode")
            if kind == "launcher_provider":
                prefix = ent.get("prefix")
                if not isinstance(prefix, str) or not prefix or prefix.startswith("/"):
                    report.error(f"{where}: prefix must be nonempty without leading '/' (e.g. 'tr')")
            lua_paths.setdefault(resolved, set()).add(kind)
            entry_decls.append((where, kind, resolved, keys))
    if entry_count == 0:
        report.error("Plugin must declare at least one supported entry kind")

    text_cache: dict[Path, str] = {}

    def scan_file(path: Path, kinds: set[str]) -> None:
        if path in text_cache:
            return
        try:
            src = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            report.error(f"Cannot read Lua file {path.name}: {exc}")
            return
        text_cache[path] = src
        for level, regex, why in SCRIPT_GATES:
            if re.search(regex, src):
                report.gate(level, f"{path.name}: {why}")
        if re.search(r'\bui\.(?:dragSource|dropZone)\s*\(', src):
            report.gate(38 if "widget" in kinds else 5, f"{path.name}: drag and drop")
        if re.search(r'\bbarWidget\.render\s*\(', src) and re.search(r'\bbarWidget\.(?:setText|setGlyph|setImage)\s*\(', src):
            report.warn(f"{path.name}: mixed barWidget.render with imperative glyph/text/image; latter has no effect after render")
        if "widget" in kinds and re.search(r'\bui\.(?:input|select|scroll)\s*\(', src):
            report.warn(f"{path.name}: keyboard-focused controls are skipped in bar widgets")
        for m in REL_REQUIRE_RE.finditer(src):
            req = m.group(1)
            if not (req.startswith("./") or req.startswith("../")) or not req.endswith(".luau"):
                report.error(f"{path.name}: require path must be relative and end in .luau: {req!r}")
                continue
            imported = (path.parent / req).resolve()
            if not imported.is_relative_to(plugin):
                report.warn(f"{path.name}: module {req!r} resolves outside plugin; verify intent and trust")
                continue
            if not imported.is_file():
                report.error(f"{path.name}: missing module {req!r}")
            else:
                scan_file(imported, kinds)

    for path, kinds in lua_paths.items():
        scan_file(path, kinds)
    for where, kind, path, local_keys in entry_decls:
        src = text_cache.get(path, "")
        for key in LITERAL_GET_CONFIG_RE.findall(src):
            if key not in root_keys and key not in local_keys:
                report.error(f"{where} ({path.name}): undeclared getConfig({key!r})")

    min_required = max(level for level, _ in report.required)
    report.infos.append(f"Minimum recognizable required API: {min_required}")
    if type(api) is int and api < min_required:
        reasons = sorted({why for level, why in report.required if level > api})
        report.error(f"plugin_api={api} too low; minimum recognizable level {min_required}; features: {'; '.join(reasons[:10])}")
    if type(api) is int and 35 <= api <= 42:
        report.warn(f"plugin_api={api} is listed as unreleased in the supplied source snapshot; verify the target host supports it")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Plugin directory containing plugin.toml")
    parser.add_argument("--json", action="store_true", help="Machine-readable diagnostics")
    args = parser.parse_args()
    report = validate(args.path)
    if args.json:
        print(json.dumps({"path": report.location, "errors": report.errors, "warnings": report.warnings,
                          "info": report.infos, "ok": not report.errors}, indent=2))
    else:
        print(f"Noctalia native plugin preflight: {report.location}")
        for e in report.errors:
            print(f"ERROR: {e}")
        for w in report.warnings:
            print(f"WARN: {w}")
        for i in report.infos:
            print(f"INFO: {i}")
        print(f"Result: {len(report.errors)} error(s), {len(report.warnings)} warning(s)")
        print("Note: static preflight only; also run `noctalia plugins lint` and test inside Noctalia.")
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
