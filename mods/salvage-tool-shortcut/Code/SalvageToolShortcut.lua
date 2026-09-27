-- High-level lifecycle and engine message wiring.
local unloaded = false

local function Apply(host)
    if unloaded then return end
    STS_Shortcuts.ApplyModBehavior(host)
end

function OnMsg.Shortcuts(host)
    Apply(host)
end

function OnMsg.ShortcutsReloaded()
    Apply()
end

function OnMsg.ClassesBuilt()
    Apply()
end

function OnMsg.ModUnloadLua(mod_id)
    if mod_id ~= "SalvageToolShortcut" then return end
    unloaded = true
    STS_Config.ENABLE_MOD = false
    STS_Shortcuts.RestoreVanillaBehavior()
end

Apply()
