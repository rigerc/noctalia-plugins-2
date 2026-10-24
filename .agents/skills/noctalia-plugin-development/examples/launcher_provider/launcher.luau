--!nonstrict
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
