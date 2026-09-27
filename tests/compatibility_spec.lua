-- Run from the repository root: lua tests/compatibility_spec.lua
-- These regression tests model engine boundaries; live-engine checks are separate.
local checks = 0
local function expect(value, message)
    checks = checks + 1
    assert(value, message)
end

local function environment()
    local env = setmetatable({ OnMsg = {}, empty_table = {}, logs = {} }, { __index = _G })
    env._G = env
    env.print = function(message) env.logs[#env.logs + 1] = message end
    local host = { actions = {} }
    function host:ActionById(id)
        for _, action in ipairs(self.actions) do
            if action.ActionId == id then return action end
        end
    end
    function host:RemoveAction(action)
        for index, existing in ipairs(self.actions) do
            if existing == action then table.remove(self.actions, index); return end
        end
    end
    env.XShortcutsTarget = host
    env.XAction = { new = function(_, action, parent)
        parent.actions[#parent.actions + 1] = action
        return action
    end }
    env.CurrentMap = {}
    env.SelectedObj = false
    env.IsValid = function(obj) return type(obj) == "table" and obj.valid ~= false end
    env.IsValidPos = function(pos) return pos ~= false end
    env.IsKindOf = function(obj, class) return obj.kind == class end
    local igi = { Mode = "selection", GetVisible = function() return true end }
    function igi:SetMode(mode, context) self.Mode, self.context = mode, context end
    env.GetInGameInterface = function() return igi end
    env.GetHUD = function() return igi end
    env.CloseModeDialog = function(mode) if igi.Mode == mode then igi.Mode = "selection" end end
    env.CloseXBuildMenu = function() end
    env.CloseXInfopanel = function() end
    env.SelectObj = function(obj) env.SelectedObj = obj end
    env.ViewAndSelectObject = env.SelectObj
    env.BMIsConstructionEnabled = function() return true end
    env.GetBuildingTechsStatus = function() return nil, true end
    env.IsBuildingAllowedIn = function() return true end
    env.GetEnvironment = function() return "Mars" end
    env.IsOverviewMode = function() return igi.Mode == "overview" end
    env.MultiSelectionWrapper = { new = function(_, value) return value end }
    return env, host, igi
end

local function load(env, folder, file)
    assert(loadfile("mods/" .. folder .. "/Code/" .. file .. ".lua", "t", env))()
end

for _, spec in ipairs({
    { "t-for-tracks", "tft", "TFT", "TForTracks", "TForTracks_T" },
    { "salvage-tool-shortcut", "sts", "STS", "SalvageToolShortcut", "SalvageToolShortcut_Delete" },
    { "select-mixed-rovers", "smr", "SMR", "SelectMixedRovers", "SelectMixedRovers_CtrlR" },
}) do
    local folder, prefix, namespace, main, id = table.unpack(spec)
    local env, host = environment()
    load(env, folder, prefix .. "_config")
    load(env, folder, prefix .. "_shortcuts")
    local config, shortcuts = env[namespace .. "_Config"], env[namespace .. "_Shortcuts"]
    env.SMR_Selection = { ApplyModBehavior = function() end, RestoreVanillaBehavior = function() end }
    load(env, folder, main)
    env.OnMsg.Shortcuts(host)
    env.OnMsg.ShortcutsReloaded()
    expect(#host.actions == 1, main .. ": repeated registration creates one action")
    expect(#env.logs == 0, main .. ": diagnostics off by default")
    config.DEBUG_LOGS = "true"
    shortcuts.Log("test", "string flag")
    expect(#env.logs == 0, main .. ": string true does not enable diagnostics")
    config.DEBUG_LOGS = true
    shortcuts.Log("test", "boolean flag")
    expect(#env.logs == 1, main .. ": boolean true enables diagnostics")
    config.ENABLE_MOD = false
    shortcuts.ApplyModBehavior()
    expect(#host.actions == 0, main .. ": disabling removes owned action")
    config.ENABLE_MOD = true
    shortcuts.ApplyModBehavior()
    env.OnMsg.ModUnloadLua(main)
    env.OnMsg.ModUnloadLua(main)
    env.OnMsg.Shortcuts(host)
    expect(#host.actions == 0, main .. ": unload does not re-register")
    config.ENABLE_MOD = true
    local other = { ActionId = id }
    host.actions[1] = other
    expect(shortcuts.ApplyModBehavior() == false, main .. ": id collision reported")
    shortcuts.RestoreVanillaBehavior()
    expect(host.actions[1] == other, main .. ": other owner's action preserved")
end

do
    local env, host, igi = environment()
    load(env, "t-for-tracks", "tft_config")
    load(env, "t-for-tracks", "tft_shortcuts")
    env.TFT_Shortcuts.ApplyModBehavior()
    local action = host:ActionById("TForTracks_T")
    action.OnAction()
    expect(igi.Mode == "track_grid" and igi.context.template == "Track", "T enters verified track mode")
    action.OnAction()
    expect(igi.Mode == "selection", "T exits track mode")
    igi.Mode = "track_grid"
    action.OnAction()
    expect(igi.Mode == "selection", "T exits track mode entered through the GUI")
    igi.Mode = "demolish"
    action.OnAction()
    expect(igi.Mode == "track_grid", "T switches from another construction tool")
    igi.Mode = "selection"
    env.GetBuildingTechsStatus = function() return nil, false end
    action.OnAction()
    expect(igi.Mode == "selection", "locked track research remains locked")
    env.GetBuildingTechsStatus = function() return nil, true end
    env.IsBuildingAllowedIn = function() return false end
    expect(action.ActionState() == "disabled", "track environment restriction preserved")
    env.TFT_Config.ENABLE_MOD = false
    expect(action.ActionState() == "disabled", "disabled feature cannot invoke retained action")
end

do
    local env, host, igi = environment()
    load(env, "salvage-tool-shortcut", "sts_config")
    load(env, "salvage-tool-shortcut", "sts_shortcuts")
    env.STS_Shortcuts.ApplyModBehavior()
    local action = host:ActionById("SalvageToolShortcut_Delete")
    action.OnAction()
    expect(igi.Mode == "demolish", "Delete enters verified salvage mode")
    action.OnAction()
    expect(igi.Mode == "selection", "Delete exits salvage mode")
    env.SelectedObj = {}
    expect(action.ActionState() == "disabled", "selected-object Delete remains vanilla")
    env.SelectedObj = false
    env.BMIsConstructionEnabled = function() return false end
    expect(action.ActionState() == "disabled", "tutorial restriction preserved")
end

do
    local env = environment()
    local base_calls, vanilla_calls, cancel_calls = 0, 0, 0
    local base_consumes = false
    local gathered = {}
    env.UnitDirectionModeDialog = { OnMouseButtonUp = function()
        base_calls = base_calls + 1
        return base_consumes and "break" or nil
    end }
    local vanilla = function(self, pt, button)
        vanilla_calls = vanilla_calls + 1
        return env.UnitDirectionModeDialog.OnMouseButtonUp(self, pt, button) or "vanilla"
    end
    env.SelectionModeDialog = { OnMouseButtonUp = vanilla }
    env.GatherObjectsInScreenRect = function() return gathered end
    env.UICity = { labels = { Rover = {} } }
    load(env, "select-mixed-rovers", "smr_config")
    load(env, "select-mixed-rovers", "smr_shortcuts")
    load(env, "select-mixed-rovers", "smr_selection")
    load(env, "select-mixed-rovers", "SelectMixedRovers")
    expect(env.SelectionModeDialog.OnMouseButtonUp == vanilla, "selection waits for ClassesBuilt")
    env.OnMsg.ClassesBuilt()
    local patched = env.SelectionModeDialog.OnMouseButtonUp
    expect(patched ~= vanilla, "selection installs after ClassesBuilt")
    local dialog = { drag_start_pos = {}, CancelMultiselection = function() cancel_calls = cancel_calls + 1 end }
    patched(dialog, {}, "L")
    expect(vanilla_calls == 1 and base_calls == 1, "non-rover completion calls base only once")
    local function rover(class, map)
        return { kind = "BaseRover", class = class, GetPos = function() return {} end, GetMap = function() return map end }
    end
    local a, b, other_map = rover("ExplorerRover", env.CurrentMap), rover("RCRover", env.CurrentMap), rover("TransportRover", {})
    env.UICity.labels.Rover = { a, b, other_map }
    gathered = { a, b, other_map, a }
    base_calls, vanilla_calls = 0, 0
    patched(dialog, {}, "L")
    expect(base_calls == 1 and vanilla_calls == 0 and cancel_calls == 1, "mixed completion calls base once")
    expect(#env.SelectedObj.objects == 2 and env.SelectedObj.selection_class == "BaseRover", "mixed selection filters maps and deduplicates")
    base_consumes = true
    patched(dialog, {}, "L")
    expect(cancel_calls == 1, "base-consumed event does not complete a drag")
    env.SMR_Selection.ApplyModBehavior()
    expect(env.SelectionModeDialog.OnMouseButtonUp == patched, "reapplying selection does not stack wrappers")
    env.SMR_Selection.RestoreVanillaBehavior()
    env.SMR_Selection.RestoreVanillaBehavior()
    expect(env.SelectionModeDialog.OnMouseButtonUp == vanilla, "selection restores original handler")
    env.SMR_Selection.ApplyModBehavior()
    local inner = env.SelectionModeDialog.OnMouseButtonUp
    local outer = function(...) return inner(...) end
    env.SelectionModeDialog.OnMouseButtonUp = outer
    env.SMR_Selection.RestoreVanillaBehavior()
    base_consumes = false
    base_calls, vanilla_calls = 0, 0
    outer(dialog, {}, "L")
    expect(env.SelectionModeDialog.OnMouseButtonUp == outer and vanilla_calls == 1 and base_calls == 1,
        "later wrapper remains installed while disabled mod passes through")
end

do
    local env = environment()
    local function controller()
        return { Activate = function() return "vanilla" end, UpdateCursor = function() end,
            UpdateVisuals = function() end }
    end
    local old = controller()
    local old_activate = old.Activate
    env.GridConstructionController = old
    env.HexGetNearestCenter = function(pt) return pt end
    for _, file in ipairs({ "fp_version", "fp_config", "fp_debug", "fp_state",
        "fp_validation", "fp_construction_rules", "fp_lifecycle", "FlexiblePassages" }) do
        load(env, "flexible-passages", file)
    end
    expect(old.Activate == old_activate, "passages do not patch classes during code load")
    local rebuilt = controller()
    local vanilla_activate, vanilla_cursor = rebuilt.Activate, rebuilt.UpdateCursor
    env.GridConstructionController = rebuilt
    env.OnMsg.ClassesBuilt()
    local f = env.FlexiblePassages
    expect(f.State.active and rebuilt.Activate ~= vanilla_activate, "passages patch rebuilt controller")
    expect(f.Lifecycle.Enable("twice"), "passages can reapply without stale ownership")
    f.Lifecycle.Disable("test")
    f.Lifecycle.Disable("twice")
    expect(rebuilt.Activate == vanilla_activate and rebuilt.UpdateCursor == vanilla_cursor, "passages restore both methods")
    f.Config.ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION = false
    f.Lifecycle.Enable("disabled flag")
    expect(not f.State.active and rebuilt.Activate == vanilla_activate, "disabled passages do not install hooks")
    f.Config.ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION = true
    env.HexGetNearestCenter = false
    expect(f.Lifecycle.Enable("missing API") == false and not f.State.active, "missing required API prevents activation")
    env.HexGetNearestCenter = function(pt) return pt end
    f.Lifecycle.Enable("test")
    local inner = rebuilt.Activate
    local outer = function(...) return inner(...) end
    rebuilt.Activate = outer
    expect(f.Lifecycle.Disable("later owner") == false, "incomplete restoration is reported")
    expect(rebuilt.Activate == outer and outer({ mode = "passage_grid" }, {}) == "vanilla",
        "passage wrapper goes dormant without overwriting later owner")
    rebuilt.Activate = inner
    expect(f.Lifecycle.Disable("retry") and rebuilt.Activate == vanilla_activate, "restoration can be retried")
    f.Lifecycle.Enable("test")
    env.OnMsg.ModUnloadLua("FlexiblePassages")
    expect(not f.State.active and rebuilt.Activate == vanilla_activate, "passages restore on unload")
    f.Lifecycle.Enable("before reload")
    load(env, "flexible-passages", "fp_state")
    local reloaded = controller()
    local reloaded_activate = reloaded.Activate
    env.GridConstructionController = reloaded
    env.OnMsg.ClassesBuilt()
    expect(f.State.active and reloaded.Activate ~= reloaded_activate, "reload discards previous class ownership")
    expect(f.Lifecycle.Disable("after reload") and reloaded.Activate == reloaded_activate,
        "reload restores the rebuilt class, not a stale original")
end

print("PASS: " .. checks .. " compatibility regression checks")
