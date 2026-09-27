-- Register through the engine's Shortcuts event, including already-created hosts.
-- No vanilla shortcut or raw keyboard handler is replaced.
TFT_Shortcuts = {}
local owned_actions = setmetatable({}, { __mode = "k" })
local action_id = "TForTracks_T"

function TFT_Shortcuts.Log(operation, reason)
    if TFT_Config.DEBUG_LOGS == true then
        print("[T for tracks][Shortcuts] " .. operation .. " reason=" .. tostring(reason))
    end
end

function TFT_Shortcuts.ApplyModBehavior(host)
    if TFT_Config.ENABLE_MOD ~= true then
        TFT_Shortcuts.RestoreVanillaBehavior()
        return false
    end
    host = host or rawget(_G, "XShortcutsTarget")
    if not host or type(host.ActionById) ~= "function" or type(host.RemoveAction) ~= "function"
        or type(XAction) ~= "table" or type(XAction.new) ~= "function" then
        TFT_Shortcuts.Log("Registration deferred", "shortcut_host_or_XAction_unavailable")
        return false
    end
    local existing = host:ActionById(action_id)
    if existing then
        if existing ~= owned_actions[host] then
            TFT_Shortcuts.Log("Registration skipped", "action_id_owned_by_other_code")
            return false
        end
        return true
    end
    owned_actions[host] = XAction:new({
        ActionId = action_id,
        -- XActionsHost resolves shared keys in ActionSortKey order. Prefer this
        -- enabled toggle to vanilla T rotation without altering the vanilla action.
        ActionSortKey = "-100",
        ActionMode = "Game",
        ActionTranslate = false,
        ActionName = "T for tracks",
        ActionShortcut = "T",
        ActionBindable = true,
        IgnoreRepeated = true,
        ActionState = function()
            return TFT_Config.ENABLE_MOD == true and TFT_Shortcuts.CanRun() and "enabled" or "disabled"
        end,
        OnAction = function()
            if TFT_Config.ENABLE_MOD == true and TFT_Shortcuts.CanRun() then
                TFT_Shortcuts.Run()
                return "break"
            end
        end,
    }, host)
    TFT_Shortcuts.Log("Registered", action_id)
    return true
end

function TFT_Shortcuts.RestoreVanillaBehavior()
    for host, action in pairs(owned_actions) do
        if host.window_state ~= "destroying" and host:ActionById(action_id) == action then
            host:RemoveAction(action)
        end
        owned_actions[host] = nil
    end
    TFT_Shortcuts.Log("Removed owned actions", action_id)
    return true
end

-- Verified in GameShortcuts.generated.lua: tracks use track_grid, not construction.
function TFT_Shortcuts.CanRun()
    local igi = GetInGameInterface and GetInGameInterface()
    local hud = GetHUD and GetHUD()
    if not igi or not igi:GetVisible() or not hud or not hud:GetVisible() then return false end
    if igi.Mode == "track_grid" then return true end
    if type(BMIsConstructionEnabled) ~= "function" or type(GetBuildingTechsStatus) ~= "function"
        or type(IsBuildingAllowedIn) ~= "function" or type(GetEnvironment) ~= "function"
        or type(IsOverviewMode) ~= "function" or not CurrentMap then
        TFT_Shortcuts.Log("Action unavailable", "construction_API_or_map_unavailable")
        return false
    end
    local _, researched = GetBuildingTechsStatus("Track")
    return not IsOverviewMode() and BMIsConstructionEnabled("Track") and researched
        and IsBuildingAllowedIn("Track", GetEnvironment(CurrentMap))
end

function TFT_Shortcuts.Run()
    local igi = GetInGameInterface()
    if igi.Mode == "track_grid" then
        CloseModeDialog("track_grid")
        TFT_Shortcuts.Log("Exited track placement", "shortcut")
        return
    end
    CloseXBuildMenu()
    CloseXInfopanel()
    SelectObj(false)
    FocusInfopanel = false
    g_LastBuildItem = "Track"
    igi:SetMode("track_grid", { template = "Track" })
    TFT_Shortcuts.Log("Entered track placement", "shortcut")
end
