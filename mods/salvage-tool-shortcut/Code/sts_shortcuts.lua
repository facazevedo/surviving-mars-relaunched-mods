-- Register through the engine's Shortcuts event, including already-created hosts.
-- No vanilla shortcut or raw keyboard handler is replaced.
STS_Shortcuts = {}
local owned_actions = setmetatable({}, { __mode = "k" })
local action_id = "SalvageToolShortcut_Delete"

function STS_Shortcuts.Log(operation, reason)
    if STS_Config.DEBUG_LOGS == true then
        print("[Salvage tool shortcut][Shortcuts] " .. operation .. " reason=" .. tostring(reason))
    end
end

function STS_Shortcuts.ApplyModBehavior(host)
    if STS_Config.ENABLE_MOD ~= true then
        STS_Shortcuts.RestoreVanillaBehavior()
        return false
    end
    host = host or rawget(_G, "XShortcutsTarget")
    if not host or type(host.ActionById) ~= "function" or type(host.RemoveAction) ~= "function"
        or type(XAction) ~= "table" or type(XAction.new) ~= "function" then
        STS_Shortcuts.Log("Registration deferred", "shortcut_host_or_XAction_unavailable")
        return false
    end
    local existing = host:ActionById(action_id)
    if existing then
        if existing ~= owned_actions[host] then
            STS_Shortcuts.Log("Registration skipped", "action_id_owned_by_other_code")
            return false
        end
        return true
    end
    owned_actions[host] = XAction:new({
        ActionId = action_id,
        -- Prefer this toggle when enabled; selected-object deletion still falls
        -- through to vanilla because our ActionState is disabled in that case.
        ActionSortKey = "-100",
        ActionMode = "Game",
        ActionTranslate = false,
        ActionName = "Salvage tool shortcut",
        ActionShortcut = "Delete",
        ActionBindable = true,
        IgnoreRepeated = true,
        ActionState = function()
            return STS_Config.ENABLE_MOD == true and STS_Shortcuts.CanRun() and "enabled" or "disabled"
        end,
        OnAction = function()
            if STS_Config.ENABLE_MOD == true and STS_Shortcuts.CanRun() then
                STS_Shortcuts.Run()
                return "break"
            end
        end,
    }, host)
    STS_Shortcuts.Log("Registered", action_id)
    return true
end

function STS_Shortcuts.RestoreVanillaBehavior()
    for host, action in pairs(owned_actions) do
        if host.window_state ~= "destroying" and host:ActionById(action_id) == action then
            host:RemoveAction(action)
        end
        owned_actions[host] = nil
    end
    STS_Shortcuts.Log("Removed owned actions", action_id)
    return true
end

-- Salvage is a build-menu action, not a BuildingTemplate. Its verified mode is demolish.
function STS_Shortcuts.CanRun()
    local igi = GetInGameInterface and GetInGameInterface()
    local hud = GetHUD and GetHUD()
    if not igi or not igi:GetVisible() or not hud or not hud:GetVisible() then return false end
    if igi.Mode == "demolish" then return true end
    if type(BMIsConstructionEnabled) ~= "function" then
        STS_Shortcuts.Log("Action unavailable", "BMIsConstructionEnabled_unavailable")
        return false
    end
    return not IsValid(SelectedObj) and BMIsConstructionEnabled("Salvage")
end

function STS_Shortcuts.Run()
    local igi = GetInGameInterface()
    if igi.Mode == "demolish" then
        CloseModeDialog("demolish")
        STS_Shortcuts.Log("Exited salvage mode", "shortcut")
        return
    end
    CloseXBuildMenu()
    CloseXInfopanel()
    SelectObj(false)
    FocusInfopanel = false
    igi:SetMode("demolish")
    STS_Shortcuts.Log("Entered salvage mode", "shortcut")
end
