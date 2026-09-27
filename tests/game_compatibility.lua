-- Run in a disposable game session after loading the mods to be checked.
-- Exercises reversible runtime state; never invokes deletion or the disable-all action.
local function CheckShortcutRouting(shortcuts, id, key)
    local host = XShortcutsTarget
    local previous_mode, can_run, run = host.ActionsMode, shortcuts.CanRun, shortcuts.Run
    local fired = 0
    shortcuts.CanRun = function() return true end
    shortcuts.Run = function() fired = fired + 1 end
    host:SetActionsMode("Game")
    local ok, result = pcall(function()
        local action = host:ActionById(id)
        local routed = host:ActionByShortcut(key, "keyboard") == action
        host:OnShortcut(key, "keyboard")
        shortcuts.CanRun = function() return false end
        local falls_through = host:ActionByShortcut(key, "keyboard") ~= action
        return routed and fired == 1 and falls_through
    end)
    shortcuts.CanRun, shortcuts.Run = can_run, run
    host:SetActionsMode(previous_mode)
    if not ok then return false end
    return result
end

local checks = {
    TForTracks = function()
        local s = TFT_Shortcuts; local id = "TForTracks_T"
        s.ApplyModBehavior(); s.ApplyModBehavior()
        local count = 0; for _,a in ipairs(XShortcutsTarget.actions) do if a.ActionId == id then count=count+1 end end
        local registered = count == 1 and XShortcutsTarget:ActionById(id).ActionShortcut == "T"
        s.RestoreVanillaBehavior(); s.RestoreVanillaBehavior()
        local removed = not XShortcutsTarget:ActionById(id)
        TFT_Config.ENABLE_MOD = false; s.ApplyModBehavior()
        local disabled = not XShortcutsTarget:ActionById(id)
        TFT_Config.ENABLE_MOD = true; s.ApplyModBehavior()
        return registered and removed and disabled and CheckShortcutRouting(s, id, "T")
    end,
    SalvageToolShortcut = function()
        local s = STS_Shortcuts; local id = "SalvageToolShortcut_Delete"
        s.ApplyModBehavior(); s.ApplyModBehavior()
        local count = 0; for _,a in ipairs(XShortcutsTarget.actions) do if a.ActionId == id then count=count+1 end end
        local registered = count == 1 and XShortcutsTarget:ActionById(id).ActionShortcut == "Delete"
        s.RestoreVanillaBehavior(); s.RestoreVanillaBehavior()
        local removed = not XShortcutsTarget:ActionById(id)
        STS_Config.ENABLE_MOD = false; s.ApplyModBehavior()
        local disabled = not XShortcutsTarget:ActionById(id)
        STS_Config.ENABLE_MOD = true; s.ApplyModBehavior()
        return registered and removed and disabled and CheckShortcutRouting(s, id, "Delete")
    end,
    SelectMixedRovers = function()
        local s = SMR_Shortcuts; local id = "SelectMixedRovers_CtrlR"
        local startup = debug.getinfo(SelectionModeDialog.OnMouseButtonUp, "S").short_src:find("smr_selection.lua", 1, true) ~= nil
        SMR_Selection.RestoreVanillaBehavior(); local original = SelectionModeDialog.OnMouseButtonUp
        SMR_Selection.ApplyModBehavior(); local patched = SelectionModeDialog.OnMouseButtonUp
        SMR_Selection.ApplyModBehavior(); local stable = SelectionModeDialog.OnMouseButtonUp == patched and patched ~= original
        SMR_Selection.RestoreVanillaBehavior(); SMR_Selection.RestoreVanillaBehavior()
        local restored = SelectionModeDialog.OnMouseButtonUp == original
        SMR_Config.ENABLE_MOD = false; SMR_Selection.ApplyModBehavior()
        local disabled = SelectionModeDialog.OnMouseButtonUp == original
        SMR_Config.ENABLE_MOD = true; SMR_Selection.ApplyModBehavior()
        s.ApplyModBehavior(); s.ApplyModBehavior()
        local count=0; for _,a in ipairs(XShortcutsTarget.actions) do if a.ActionId == id then count=count+1 end end
        return startup and stable and restored and disabled and count == 1 and CheckShortcutRouting(s, id, "Ctrl-R")
    end,
    AttributeInspector = function()
        return type(AttributeInspectorPanel) == "table"
        and type(AttributeInspector_EnsurePanel) == "function"
        and type(AttributeInspector_ClosePanel) == "function"
    end,
    ForceDelete = function()
        ForceDelete.PatchGameShortcuts(); ForceDelete.PatchGameShortcuts()
        local counts = {}; for _,a in ipairs(XShortcutsTarget.actions) do counts[a.ActionId]=(counts[a.ActionId] or 0)+1 end
        return counts[ForceDelete.LVL1_ACTION_ID] == 1 and counts[ForceDelete.LVL2_ACTION_ID] == 1
        and ForceDelete.Colonist ~= nil and ForceDelete.Dome ~= nil and ForceDelete.Train ~= nil
    end,
    MuteNotifications = function()
        local active = MN_VoiceSuppression.applied == true and MN_AudioPatch.prop_added == true
        local catalog = MN_Catalog.Build("compatibility_test")
        local disabled = MN_Disable("compatibility_test")
        local original_queue = QueueVoice; local original_play = PlayVoicedText
        MN_Disable("compatibility_test_twice")
        local restored = QueueVoice == original_queue and PlayVoicedText == original_play and not MN_AudioPatch.prop_added
        MN_Enable("compatibility_test"); MN_Enable("compatibility_test_twice")
        local count = 0; for _,p in ipairs(OptionsObject.properties) do if p.id == MN_Config.AUDIO_OPTION_ID then count=count+1 end end
        return active and disabled and restored and count == 1 and MN_VoiceSuppression.applied == true
    end,
    FlexiblePassages = function()
        local f = Mods.FlexiblePassages.env.FlexiblePassages
        local startup = f.State.active == true and GridConstructionController.Activate == f.State.patched_activate
        local available = f.Validation.CheckRuntimeApi("compatibility_test")
        f.Lifecycle.Disable("compatibility_test")
        local original_activate = GridConstructionController.Activate
        local original_cursor = GridConstructionController.UpdateCursor
        local enabled = f.Lifecycle.Enable("compatibility_test")
        f.Lifecycle.Enable("compatibility_test_twice")
        local active = GridConstructionController.Activate ~= original_activate
        f.Lifecycle.Disable("compatibility_test"); f.Lifecycle.Disable("compatibility_test_twice")
        local restored = GridConstructionController.Activate == original_activate and GridConstructionController.UpdateCursor == original_cursor
        f.Lifecycle.Enable("compatibility_test")
        f.Config.ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION = false; f.Lifecycle.Enable("feature_disabled")
        local disabled = not f.State.active and GridConstructionController.Activate == original_activate
        f.Config.ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION = true; f.Lifecycle.Enable("compatibility_test")
        return startup and available and enabled and active and restored and disabled
    end,
    DisableAllMods = function()
        local function count(root)
            if type(root) ~= "table" then return 0 end
            local n = root.Id == DAM_Config.BUTTON_ID and 1 or 0
            for _,child in ipairs(root) do n=n+count(child) end
            return n
        end
        local applied = DAM_Lifecycle.ApplyModBehavior()
        DAM_Lifecycle.ApplyModBehavior()
        local once = count(XTemplates.ModsUIMainContent) == 1
        DAM_UI.RestoreVanillaBehavior(); DAM_UI.RestoreVanillaBehavior()
        local removed = count(XTemplates.ModsUIMainContent) == 0
        DAM_UI.ApplyModBehavior()
        DAM_DisableGuard.RestoreVanillaBehavior(); local original = TurnModOff
        DAM_DisableGuard.ApplyModBehavior(); local patched = TurnModOff
        DAM_DisableGuard.ApplyModBehavior(); local stable = TurnModOff == patched and patched ~= original
        DAM_DisableGuard.RestoreVanillaBehavior(); DAM_DisableGuard.RestoreVanillaBehavior()
        local restored = TurnModOff == original
        DAM_DisableGuard.ApplyModBehavior()
        return applied and once and removed and stable and restored
    end,
}
local results = {}
for _, mod in ipairs(ModsLoaded) do
    local check = checks[mod.id]
    if check then
        local ok, result = pcall(check)
        results[#results + 1] = mod.id .. ": " .. (ok and result == true and "PASS" or "FAIL: " .. tostring(result))
    end
end
return table.concat(results, "\n")
