-- Register through the engine's Shortcuts event, including already-created hosts.
-- No vanilla shortcut or raw keyboard handler is replaced.
SMR_Shortcuts = {}
local owned_actions = setmetatable({}, { __mode = "k" })
local action_id = "SelectMixedRovers_CtrlR"

function SMR_Shortcuts.Log(operation, reason)
    if SMR_Config.DEBUG_LOGS == true then
        print("[Select mixed rovers][Shortcuts] " .. operation .. " reason=" .. tostring(reason))
    end
end

function SMR_Shortcuts.ApplyModBehavior(host)
    if SMR_Config.ENABLE_MOD ~= true then
        SMR_Shortcuts.RestoreVanillaBehavior()
        return false
    end
    host = host or rawget(_G, "XShortcutsTarget")
    if not host or type(host.ActionById) ~= "function" or type(host.RemoveAction) ~= "function"
        or type(XAction) ~= "table" or type(XAction.new) ~= "function" then
        SMR_Shortcuts.Log("Registration deferred", "shortcut_host_or_XAction_unavailable")
        return false
    end
    local existing = host:ActionById(action_id)
    if existing then
        if existing ~= owned_actions[host] then
            SMR_Shortcuts.Log("Registration skipped", "action_id_owned_by_other_code")
            return false
        end
        return true
    end
    owned_actions[host] = XAction:new({
        ActionId = action_id,
        ActionMode = "Game",
        ActionTranslate = false,
        ActionName = "Select mixed rovers",
        ActionShortcut = "Ctrl-R",
        ActionBindable = true,
        IgnoreRepeated = true,
        ActionState = function()
            return SMR_Config.ENABLE_MOD == true and SMR_Shortcuts.CanRun() and "enabled" or "disabled"
        end,
        OnAction = function()
            if SMR_Config.ENABLE_MOD == true and SMR_Shortcuts.CanRun() then
                SMR_Shortcuts.Run()
                return "break"
            end
        end,
    }, host)
    SMR_Shortcuts.Log("Registered", action_id)
    return true
end

function SMR_Shortcuts.RestoreVanillaBehavior()
    for host, action in pairs(owned_actions) do
        if host.window_state ~= "destroying" and host:ActionById(action_id) == action then
            host:RemoveAction(action)
        end
        owned_actions[host] = nil
    end
    SMR_Shortcuts.Log("Removed owned actions", action_id)
    return true
end

function SMR_Shortcuts.CanRun()
    local hud = GetHUD and GetHUD()
    return hud and hud:GetVisible() and #SMR_Selection.GetRovers() > 0
end

function SMR_Shortcuts.Run()
    local rovers = SMR_Selection.GetRovers()
    FocusInfopanel = false
    if #rovers == 1 then
        ViewAndSelectObject(rovers[1])
    else
        SMR_Selection.SelectRovers(rovers)
    end
end
