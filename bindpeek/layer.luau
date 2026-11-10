--!nonstrict
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Passive Noctalia layer. Styles reproduce the animated reachability cues
-- from Bindpeek PR #6, not keypress history or raw key identities.
local parser = require("./shortcuts.luau")

local binds = noctalia.state.get("shortcuts") or {}
local held = noctalia.state.get("held") or {}
local manual = noctalia.state.get("manual") == true
local enter = 0
local pulse = 0

local function animated()
  return noctalia.getConfig("animate_keycaps") ~= false
end

local function ease(x)
  return 1 - (1 - x) * (1 - x) * (1 - x)
end

local function keycap(label, key, width, height, items)
  local state = parser.keyState(key, items, held)
  local lit = state ~= "off"
  local heldKey = state == "held"
  local exact = state == "exact"
  local glow = animated() and pulse or 0
  local fill = heldKey and ("primary/" .. string.format("%.2f", 0.32 + glow * 0.17))
      or exact and ("primary/" .. string.format("%.2f", 0.22 + glow * 0.14))
      or lit and ("secondary/" .. string.format("%.2f", 0.20 + glow * 0.12))
      or "surface_container"
  local border = heldKey and "primary"
      or exact and "primary"
      or lit and "secondary"
      or "outline_variant"
  local color = heldKey and "primary" or "on_surface"
  local detail = ""
  for _, item in ipairs(items) do
    if string.upper(item.key) == string.upper(key) then
      detail = item.description
      break
    end
  end
  if #detail > 15 then detail = detail:sub(1, 14) .. "…" end
  local body = { ui.label({
    text = label, fontSize = width < 52 and 12 or 13,
    fontWeight = lit and "bold" or "medium", color = color,
    textAlign = "center",
  }) }
  if lit and detail ~= "" and height >= 53 then
    table.insert(body, ui.label({
      text = detail, fontSize = 9, textAlign = "center",
      maxLines = 1, color = "on_surface_variant",
    }))
  end
  return ui.column({
    width = width, height = height,
    fill = fill, border = border, borderWidth = lit and (glow > 0.25 and 3 or 2) or 1,
    radius = 9, gap = 2, paddingH = 2, paddingV = 6,
    align = "center", justify = "center",
  }, body)
end

local LAYOUT = {
  {
    {"Esc","Escape",52},{"1","1",45},{"2","2",45},{"3","3",45},
    {"4","4",45},{"5","5",45},{"6","6",45},{"7","7",45},
    {"8","8",45},{"9","9",45},{"0","0",45},{"-","-",45},
    {"=","=",45},{"Backspace","⌫",110}
  },
  {
    {"Tab","⇥",80},{"Q","Q",48},{"W","W",48},{"E","E",48},
    {"R","R",48},{"T","T",48},{"Y","Y",48},{"U","U",48},
    {"I","I",48},{"O","O",48},{"P","P",48},{"[","[",48},
    {"]","]",48},{"\\","\\",52}
  },
  {
    {"Caps","Caps_Lock",94},{"A","A",49},{"S","S",49},
    {"D","D",49},{"F","F",49},{"G","G",49},{"H","H",49},
    {"J","J",49},{"K","K",49},{"L","L",49},
    {";",";",49},{"'","'",49},{"Enter","↵",92}
  },
  {
    {"Shift","SHIFT",115},{"Z","Z",52},{"X","X",52},
    {"C","C",52},{"V","V",52},{"B","B",52},{"N","N",52},
    {"M","M",52},{",",",",52},{".",".",52},{"/","/",52},
    {"Shift","SHIFT",115}
  },
  {
    {"Ctrl","CTRL",84},{"Super","SUPER",84},{"Alt","ALT",84},
    {"Space","␣",270},{"Alt","ALT",84},{"Super","SUPER",84},
    {"Ctrl","CTRL",84}
  }
}

local function keyboard(items, compact)
  local rows = {}
  local count = compact == "two" and 2 or (compact and 3 or #LAYOUT)
  local height = compact and 38 or 55
  for index = 1, count do
    local keys = {}
    for _, spec in ipairs(LAYOUT[index]) do
      local width = compact and math.floor(spec[3] * 0.89) or spec[3]
      table.insert(keys, keycap(spec[1], spec[2], width, height, items))
    end
    table.insert(rows, ui.row({
      key = "keyboard-row-" .. index, gap = 5, align = "center",
      justify = "center",
    }, keys))
  end
  return ui.column({ gap = 6, align = "center" }, rows)
end

local function itemCard(item, width, compact)
  return ui.column({
    key = "item-" .. item.combo .. "-" .. item.description,
    width = width, height = compact and 58 or 66,
    gap = 5, padding = 9, radius = 10,
    fill = "surface_container", border = item.exact and "primary" or "outline_variant",
    borderWidth = item.exact and 2 or 1,
    
  }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({
        text = item.combo, fontSize = 12, fontWeight = "bold",
        color = item.exact and "primary" or "on_surface",
      }),
      ui.spacer({ flexGrow = 1 }),
      ui.label({
        text = item.exact and "READY" or ("+" .. table.concat(item.missing, "+")),
        color = "on_surface_variant", fontSize = 10,
      }),
    }),
    ui.label({
      text = item.description, maxLines = 1,
      fontSize = 12, color = "on_surface_variant",
    }),
  })
end

local function listView(items)
  local children = {}
  local previous = ""
  local rendered = 0
  for _, item in ipairs(items) do
    if rendered >= 5 then break end
    if item.group ~= previous then
      previous = item.group
      table.insert(children, ui.label({
        text = item.group, color = "primary",
        fontSize = 12, fontWeight = "bold",
      }))
    end
    table.insert(children, itemCard(item, 802, true))
    rendered += 1
  end
  if #items > rendered then
    table.insert(children, ui.label({
      text = "+" .. tostring(#items - rendered) .. " more bindings · open the viewer to see all",
      color = "on_surface_variant", fontSize = 11,
    }))
  end
  if rendered == 0 then
    table.insert(children, ui.label({
      text = "No shortcuts match these modifiers.",
      color = "on_surface_variant", fontSize = 14,
    }))
  end
  return ui.column({ gap = 6, align = "stretch" }, children)
end

local function quickActions(items)
  local cards = {}
  for i = 1, math.min(#items, 6), 2 do
    local pair = { itemCard(items[i], 388, true) }
    if items[i + 1] then table.insert(pair, itemCard(items[i + 1], 388, true)) end
    table.insert(cards, ui.row({ gap = 8, justify = "center" }, pair))
  end
  if #cards == 0 then
    table.insert(cards, ui.label({ text = "No reachable shortcuts", color = "on_surface_variant" }))
  end
  table.insert(cards, ui.separator({ color = "outline_variant", spacing = 4 }))
  table.insert(cards, keyboard(items, true))
  return ui.column({ gap = 7, align = "center" }, cards)
end

local function radial(items)
  local cards = {}
  for i = 1, math.min(5, #items) do
    table.insert(cards, itemCard(items[i], 245, true))
  end
  local function at(index)
    return cards[index] or ui.box({ width = 245, height = 58 })
  end
  local hub = ui.column({
    width = 246, height = 104, radius = 52,
    fill = "primary/0.18", border = "primary", borderWidth = 2,
    align = "center", justify = "center",
    
  }, {
    ui.glyph({ name = "keyboard", size = 28, color = "primary" }),
    ui.label({
      text = #held > 0 and table.concat(held, " + ") or "ALL SHORTCUTS",
      fontSize = 12, fontWeight = "bold",
    })
  })
  return ui.column({ gap = 12, align = "center" }, {
    at(1),
    ui.row({ gap = 12, justify = "center", align = "center" }, {
      at(2), hub, at(3)
    }),
    ui.row({ gap = 20, justify = "center" }, { at(4), at(5) }),
    ui.label({
      text = tostring(math.max(0, #items - 5)) .. " additional bindings",
      color = "on_surface_variant", fontSize = 11,
    }),
    keyboard(items, "two"),
  })
end

local function render()
  local currentView = noctalia.getConfig("view") or "keyboard"
  local items = parser.matches(binds, held, #held == 0 or noctalia.getConfig("show_deeper") ~= false)
  local title = #held > 0 and table.concat(held, " + ") or "Shortcut explorer"
  local opacity = animated() and (0.48 + 0.52 * ease(enter)) or 1

  local main
  if currentView == "list" then
    main = listView(items)
  elseif currentView == "quick-actions" then
    main = quickActions(items)
  elseif currentView == "radial" then
    main = radial(items)
  else
    main = ui.column({ gap = 9, align = "center" }, {
      keyboard(items, false),
      ui.separator({ color = "outline_variant", spacing = 4 }),
      ui.label({
        text = #items .. " reachable shortcuts · brighter keys fire with the current modifiers",
        color = "on_surface_variant", fontSize = 12,
      }),
    })
  end

  layer.render(ui.column({
    width = 856, height = 510, radius = 18, padding = 18,
    fill = "surface/0.97", border = "outline_variant",
    borderWidth = 1, gap = 14, opacity = opacity,
  }, {
    ui.row({ gap = 12, align = "center" }, {
      ui.glyph({ name = "keyboard", size = 25, color = "primary" }),
      ui.column({ gap = 3, flexGrow = 1 }, {
        ui.label({ text = title, fontSize = 18, fontWeight = "bold" }),
        ui.label({
          text = manual and "Pinned preview · toggle again to close"
            or "Hold modifiers to explore · release to dismiss",
          color = "on_surface_variant", fontSize = 11,
        }),
      }),
      ui.label({
        text = string.upper(currentView) .. "  •  " .. #items .. " binds",
        fontSize = 11, color = "on_surface_variant",
      }),
    }),
    ui.separator({ color = "outline_variant", spacing = 2 }),
    main,
  }))
end

local function restartPulse()
  if animated() then
    pulse = 1
    layer.setNeedsFrameTick(true)
  else
    pulse = 0
  end
  render()
end

noctalia.state.watch("held", function(value)
  held = value or {}
  restartPulse()
end)

noctalia.state.watch("shortcuts", function(value)
  binds = value or {}
  render()
end)

noctalia.state.watch("manual", function(value)
  manual = value == true
  render()
end)

function onFrameTick(deltaMs)
  local delta = math.max(0, math.min(80, tonumber(deltaMs) or 16))
  enter = math.min(1, enter + delta / 180)
  pulse = math.max(0, pulse - delta / 190)
  render()
  if enter >= 1 and pulse <= 0 then layer.setNeedsFrameTick(false) end
end

function onConfigChanged()
  if animated() then
    enter = 0
    layer.setNeedsFrameTick(true)
  else
    enter = 1
    pulse = 0
    layer.setNeedsFrameTick(false)
  end
  render()
end

enter = animated() and 0 or 1
layer.setNeedsFrameTick(animated())
render()
