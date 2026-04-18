
function OnModPreInit() 

end

function OnModInit() 

end

function OnModPostInit() 

end

function OnPlayerSpawned( player_entity ) 

end

function OnPlayerDied( player_entity ) 

end

function OnWorldInitialized() 

end

function OnWorldPreUpdate() 

end

function OnWorldPostUpdate() 

end

function OnBiomeConfigLoaded() 

end

function OnMagicNumbersAndWorldSeedInitialized() 

end

function OnPausedChanged( is_paused, is_inventory_pause ) 

end

function OnModSettingsChanged() 

end

function OnPausePreUpdate() 

end

local MOD_ID   = "randomTransmutation"
local MOD_ROOT =  "mods/" .. MOD_ID .. "/files/"

-- Spells
ModLuaFileAppend("data/scripts/gun/gun_actions.lua", MOD_ROOT .. "/actions.lua")
ModLuaFileAppend("data/scripts/gun/gun.lua", MOD_ROOT .. "/scripts/spelldatat.lua")
ModLuaFileAppend("data/scripts/gun/procedural/gun_action_utils.lua", MOD_ROOT .. "/scripts/gun_action_utils_append.lua")

-- Translation
local translations = ModTextFileGetContent("data/translations/common.csv")
local new_translations = ModTextFileGetContent("mods/".. MOD_ID .."/translations.csv")
translations = translations .. "\n" .. new_translations .. "\n"
translations = translations:gsub("\r", ""):gsub("\n\n+", "\n")
ModTextFileSetContent("data/translations/common.csv", translations)