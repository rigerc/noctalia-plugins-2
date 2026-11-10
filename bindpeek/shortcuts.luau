--!nonstrict
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Helpers for the text-only, read-only Bindpeek CLI protocol. No input devices opened.
local M = {}

local ORDER = { "SUPER", "CTRL", "ALT", "SHIFT" }
local NAMES = { SUPER = true, CTRL = true, ALT = true, SHIFT = true }

local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

function M.parseHeld(line)
  local text = trim(line)
  if text == "-" then return {} end
  if not text:match("^[A-Z+]+$") then return nil end
  local seen = {}
  for part in text:gmatch("[^+]+") do
    if not NAMES[part] then return nil end
    seen[part] = true
  end
  local mods = {}
  for _, mod in ipairs(ORDER) do
    if seen[mod] then table.insert(mods, mod) end
  end
  return #mods > 0 and mods or nil
end

function M.parseList(stdout)
  local out = {}
  local group = "Other"
  -- CLI lines have exactly two spaces of indentation, a padded shortcut
  -- column, at least two spaces, then the description.
  for line in (stdout .. "\n"):gmatch("(.-)\r?\n") do
    if line:match("^  ") then
      local combo, description = line:match("^  (.-)%s%s+(.+)$")
      if combo and description then
        combo, description = trim(combo), trim(description)
        local parts = {}
        for part in combo:gmatch("[^+]+") do
          table.insert(parts, trim(part))
        end
        if #parts > 0 and description ~= "" then
          local key = parts[#parts]
          local modifiers, valid = {}, true
          for i = 1, #parts - 1 do
            local modifier = string.upper(parts[i])
            if not NAMES[modifier] then valid = false end
            if valid then table.insert(modifiers, modifier) end
          end
          if valid and key ~= "" then
            table.insert(out, {
              combo = combo, key = key, modifiers = modifiers,
              group = group, description = description,
            })
          end
        end
      end
    elseif trim(line) ~= "" and not line:find("shortcut(s)", 1, true) then
      group = trim(line)
    end
  end
  return out
end

local function has(list, item)
  for _, v in ipairs(list) do if v == item then return true end end
  return false
end

function M.matches(entries, held, showDeeper)
  local matches = {}
  for _, item in ipairs(entries or {}) do
    local valid = true
    for _, mod in ipairs(held or {}) do
      if not has(item.modifiers, mod) then valid = false; break end
    end
    local missing = {}
    if valid then
      for _, mod in ipairs(ORDER) do
        if has(item.modifiers, mod) and not has(held or {}, mod) then
          table.insert(missing, mod)
        end
      end
      if showDeeper == false and #missing > 0 then valid = false end
    end
    if valid then
      table.insert(matches, {
        combo = item.combo, key = item.key,
        group = item.group, description = item.description,
        missing = missing, exact = #missing == 0,
      })
    end
  end
  return matches
end

function M.keyState(key, items, held)
  local upper = string.upper(key)
  if (upper == "SUPER" or upper == "CTRL" or upper == "ALT" or upper == "SHIFT")
      and has(held or {}, upper) then return "held" end
  local state = "off"
  for _, item in ipairs(items or {}) do
    if string.upper(item.key or "") == upper then
      if item.exact then return "exact" end
      state = "reachable"
    end
  end
  return state
end

return M
