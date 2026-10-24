--!nonstrict
-- Show and hide with: noctalia msg plugin AUTHOR/NAME:controller all show|hide
function onIpc(event, _payload)
  if event == "show" then
    noctalia.layer.show("overlay")
  elseif event == "hide" then
    noctalia.layer.hide("overlay")
  end
end
