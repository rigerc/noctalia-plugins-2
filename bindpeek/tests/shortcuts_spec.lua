-- SPDX-License-Identifier: GPL-3.0-or-later
-- Execute from the repository root: lua5.4 bindpeek/tests/shortcuts_spec.lua
local api = dofile("bindpeek/shortcuts.luau")

local function equal(expected, actual, context)
  if expected ~= actual then
    error(string.format("%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
  end
end

local function row(combo, description)
  return "  " .. string.format("%-24s", combo) .. "  " .. description .. "\n"
end

local text = "Hyprland: 5 shortcut(s)\n\nGlobal\n"
  .. row("SUPER+T", "Terminal")
  .. row("SUPER+CTRL+K", "Launcher")
  .. row("SUPER+CTRL+SHIFT+S", "Screenshot")
  .. "\nWindow management\n"
  .. row("CTRL+L", "Move left")
  .. row("Volume Down", "Lower volume")

local entries = api.parseList(text)
equal(5, #entries, "parseList count")
equal("SUPER+CTRL+K", entries[2].combo, "combination")
equal("Launcher", entries[2].description, "description")
equal("Window management", entries[4].group, "group")
equal("Volume Down", entries[5].key, "multiword nonmodifier")
equal(0, #entries[5].modifiers, "unmodified binding")

local held = api.parseHeld("CTRL+SUPER")
equal(2, #held, "held count")
equal("SUPER", held[1], "canonical first modifier")
equal("CTRL", held[2], "canonical second modifier")
equal(0, #api.parseHeld("-"), "release event")
equal(nil, api.parseHeld("Connected to the keyboard service."), "ignore preamble")
equal(nil, api.parseHeld("SUPER+ALT+UNKNOWN"), "reject unknown modifier")

local reachable = api.matches(entries, { "SUPER" }, true)
equal(3, #reachable, "all reachable SUPER shortcuts")
equal(true, reachable[1].exact, "exact SUPER shortcut")
equal(false, reachable[2].exact, "deeper modifier shortcut")
equal("CTRL", reachable[2].missing[1], "missing modifier")
equal("reachable", api.keyState("K", reachable, { "SUPER" }), "reachable keycap")
equal("exact", api.keyState("T", reachable, { "SUPER" }), "exact keycap")
equal("held", api.keyState("SUPER", reachable, { "SUPER" }), "held modifier cap")
equal("off", api.keyState("L", reachable, { "SUPER" }), "unreachable keycap")

local exact = api.matches(entries, { "SUPER" }, false)
equal(1, #exact, "filter deeper shortcuts")
local double = api.matches(entries, { "CTRL", "SUPER" }, true)
equal(2, #double, "order-independent modifier match")
local all = api.matches(entries, {}, true)
equal(5, #all, "pinned preview sees every binding")
equal(0, #api.matches(entries, { "ALT" }, true), "unmatched modifier")
print("Bindpeek shortcut protocol: OK")
