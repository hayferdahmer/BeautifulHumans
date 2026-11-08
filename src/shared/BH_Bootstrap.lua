-- Beautiful Humans / load entry point.
-- All modules are declared before Boot; actual module initialisation waits for
-- OnGameStart so the game world and player data are available.

BH = BH or {}

if BH._BootstrapLoaded then
    return
end
BH._BootstrapLoaded = true

require "BH/Core"
require "BH/Persistence/Persistence"
require "BH/Anatomy/Zones"
require "BH/Anatomy/Rules"
require "BH/Anatomy/Model"
require "BH/Physiology/Physiology"
require "BH/Medical/Treatments"
require "BH/Medical/Medical"
require "BH/Integration/Commands"
require "BH/Integration/GameEvents"

-- Client presentation is loaded only outside the dedicated server.
local clientRuntime = not (isServer and isServer())
if clientRuntime then
    pcall(require, "BH/UI/MedicalPanel")
    pcall(require, "BH/Integration/MedicalContextMenu")
end

BH.Boot()
