# Tasmota sets wd to the archive prefix while starting a .tapp.
import path
do
  var dir = tasmota.wd
  var conflict = nil
  for name : ["gate.be","gate.bec","hek.be","hek.bec","hekweb.be","hekweb.bec","Hekoverzicht.tapp"]
    if path.exists("/" + name) conflict = name break end
  end
  if conflict != nil
    tasmota.log("CB19: old installation found: /" + conflict + ". See the README migration steps.", 2)
  elif global.contains("Hek") && type(global.Hek) == "instance"
    tasmota.log("CB19: a gate driver is already running.", 2)
  else
    if tasmota.load(dir + "gate.be")
      if !tasmota.load(dir + "hekweb.be") tasmota.log("CB19: dashboard failed to load.", 1) end
    else
      tasmota.log("CB19: gate driver failed to load.", 1)
    end
  end
end
