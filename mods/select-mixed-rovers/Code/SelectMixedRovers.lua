-- High-level lifecycle and engine message wiring.
local unloaded = false
local classes_ready = false

local function Apply(host)
    if unloaded then return end
    SMR_Shortcuts.ApplyModBehavior(host)
    if classes_ready then SMR_Selection.ApplyModBehavior() end
end

function OnMsg.Shortcuts(host)
    Apply(host)
end

function OnMsg.ShortcutsReloaded()
    Apply()
end

function OnMsg.ClassesBuilt()
    classes_ready = true
    Apply()
end

function OnMsg.ModUnloadLua(mod_id)
    if mod_id ~= "SelectMixedRovers" then return end
    unloaded = true
    SMR_Config.ENABLE_MOD = false
    SMR_Shortcuts.RestoreVanillaBehavior()
    SMR_Selection.RestoreVanillaBehavior()
end

Apply()
