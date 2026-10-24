--!nonstrict
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
