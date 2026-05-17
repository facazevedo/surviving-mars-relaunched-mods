-- Force Delete diagnostic scaffold.
-- This main script owns shared helpers, selection monitoring, module loading,
-- and shortcut registration. Object-specific logic lives in fd_* modules.

-- ============================================================================
-- Namespace and constants
-- ============================================================================

ForceDelete = rawget(_G, "ForceDelete") or {}
local FD = ForceDelete
_G.ForceDelete = FD

FD.LVL1_ACTION_ID = "ForceDelete_Level1_CtrlDelete"
FD.LVL2_ACTION_ID = "ForceDelete_Level2_CtrlShiftDelete"
FD.POLL_INTERVAL_MS = 250
FD.shortcuts_patched = FD.shortcuts_patched or false

local unpack_args = table.unpack or unpack

-- ============================================================================
-- Safe engine helpers
-- ============================================================================

-- Return a global value without creating it. This keeps all engine integration
-- defensive because many helpers only exist after specific game/UI phases.
function FD.Global(name)
	return rawget(_G, name)
end

-- Call an arbitrary function safely. Engine objects can assert when touched in
-- the wrong state, so all generic interaction goes through pcall.
function FD.SafeCall(fn, ...)
	if type(fn) ~= "function" then
		return false
	end

	local args = { ... }
	local ok, r1, r2, r3, r4, r5 = pcall(function()
		return fn(unpack_args(args))
	end)

	if not ok then
		return false
	end

	return r1, r2, r3, r4, r5
end

-- Read a field from a Lua table/userdata hybrid without assuming plain-table
-- behavior. This is used heavily by diagnostic modules.
function FD.ReadField(obj, field)
	if obj == nil or field == nil then
		return nil
	end

	local ok, value = pcall(function()
		return obj[field]
	end)

	if ok then
		return value
	end

	return nil
end

-- Write a field defensively. The diagnostic scaffold does not modify selected
-- objects, but this helper is kept here for future force-delete modules.
function FD.WriteField(obj, field, value)
	if obj == nil or field == nil then
		return false
	end

	local ok = pcall(function()
		obj[field] = value
	end)

	return ok
end

-- Invoke an object method safely. This avoids assuming whether a method exists
-- or whether the backing native object is still in a valid state.
function FD.CallMethod(obj, method_name, ...)
	if obj == nil or method_name == nil then
		return false
	end

	local method = FD.ReadField(obj, method_name)
	if type(method) ~= "function" then
		return false
	end

	local args = { ... }
	local ok, r1, r2, r3, r4, r5 = pcall(function()
		return method(obj, unpack_args(args))
	end)

	if not ok then
		return false
	end

	return r1, r2, r3, r4, r5
end

-- Validate an object using the engine helper when available. Plain Lua values
-- fall back to a nil check so diagnostics can still summarize them.
function FD.IsObjectValid(obj)
	if obj == nil or obj == false then
		return false
	end

	local is_valid = FD.Global("IsValid")
	if type(is_valid) == "function" then
		local ok, result = pcall(is_valid, obj)
		if ok then
			return result and true or false
		end
	end

	return true
end

-- Check engine inheritance using IsKindOf when present. The fallback is exact
-- class-name equality; substring matching belongs in ObjectMatches.
function FD.IsKindOf(obj, class_name)
	if obj == nil or class_name == nil then
		return false
	end

	local is_kind_of = FD.Global("IsKindOf")
	if type(is_kind_of) == "function" then
		local ok, result = pcall(is_kind_of, obj, class_name)
		if ok and result then
			return true
		end
	end

	return FD.ClassName(obj) == class_name
end

-- Return the most useful class identifier available for an object-like value.
function FD.ClassName(obj)
	if obj == nil then
		return "nil"
	end

	local class = FD.ReadField(obj, "class")
	if class ~= nil then
		return FD.SafeToString(class)
	end

	local class_name = FD.ReadField(obj, "class_name")
	if class_name ~= nil then
		return FD.SafeToString(class_name)
	end

	local meta_class = FD.CallMethod(obj, "GetClass")
	if meta_class ~= false and meta_class ~= nil then
		return FD.SafeToString(meta_class)
	end

	local value_type = type(obj)
	if value_type == "table" or value_type == "userdata" then
		return value_type
	end

	return value_type
end

-- Match an object by engine kind first, then by compact class-name substring.
-- This supports mods across engine revisions with slightly different class IDs.
function FD.ObjectMatches(obj, kind_names, class_patterns)
	if not FD.IsObjectValid(obj) then
		return false
	end

	for _, kind_name in ipairs(kind_names or {}) do
		if FD.IsKindOf(obj, kind_name) then
			return true
		end
	end

	local class_name = FD.ClassName(obj)
	for _, pattern in ipairs(class_patterns or {}) do
		if type(pattern) == "string" and class_name:find(pattern, 1, true) then
			return true
		end
	end

	return false
end

-- Convert simple values to text without recursively dumping object graphs.
function FD.SafeToString(value)
	if value == nil then
		return "nil"
	end

	local value_type = type(value)
	if value_type == "string" then
		return value
	end

	if value_type == "number" or value_type == "boolean" then
		return tostring(value)
	end

	local ok, text = pcall(tostring, value)
	if ok and text ~= nil then
		return text
	end

	return value_type
end

-- Produce a compact one-line summary for object-like values. This is the core
-- formatting helper used by modules to avoid large recursive dumps.
function FD.ObjectSummary(obj)
	if obj == nil then
		return "nil"
	end

	local value_type = type(obj)
	if value_type == "string" or value_type == "number" or value_type == "boolean" then
		return FD.SafeToString(obj)
	end

	if value_type ~= "table" and value_type ~= "userdata" then
		return value_type
	end

	local class_name = FD.ClassName(obj)
	local name = FD.ReadField(obj, "display_name")
	if name == nil then
		name = FD.ReadField(obj, "name")
	end
	if name == nil then
		name = FD.CallMethod(obj, "GetDisplayName")
	end
	if name == false or name == nil then
		name = FD.CallMethod(obj, "GetName")
	end

	local ids = {}
	local handle = FD.ReadField(obj, "handle")
	if handle ~= nil then
		ids[#ids + 1] = "handle=" .. FD.SafeToString(handle)
	end
	local id = FD.ReadField(obj, "id")
	if id ~= nil then
		ids[#ids + 1] = "id=" .. FD.SafeToString(id)
	end
	local index = FD.ReadField(obj, "index")
	if index == nil then
		index = FD.ReadField(obj, "Index")
	end
	if index ~= nil then
		ids[#ids + 1] = "index=" .. FD.SafeToString(index)
	end

	local text = class_name
	if name ~= nil and name ~= false and FD.SafeToString(name) ~= "" then
		text = text .. " / " .. FD.SafeToString(name)
	end
	if #ids > 0 then
		text = text .. " [" .. table.concat(ids, ", ") .. "]"
	end

	return text
end

-- ============================================================================
-- Selection helpers
-- ============================================================================

-- Resolve UI contexts to the actual selected object when the game wraps it in
-- an infopanel or property object.
function FD.ResolveContext(context)
	if context == nil or context == false then
		return false
	end

	local resolve_prop_obj = FD.Global("ResolvePropObj")
	if type(resolve_prop_obj) == "function" then
		local resolved = FD.SafeCall(resolve_prop_obj, context)
		if FD.IsObjectValid(resolved) then
			return resolved
		end
	end

	for _, field in ipairs({ "context", "obj", "object", "selected_obj", "SelectedObj" }) do
		local value = FD.ReadField(context, field)
		if FD.IsObjectValid(value) then
			return value
		end
	end

	if FD.IsObjectValid(context) then
		return context
	end

	return false
end

-- Extract a context object from a dialog without assuming a specific UI tree.
function FD.ContextObjectFromDialog(dialog)
	if dialog == nil then
		return false
	end

	local context = FD.ReadField(dialog, "context")
	local resolved = FD.ResolveContext(context)
	if resolved then
		return resolved
	end

	context = FD.CallMethod(dialog, "GetContext")
	resolved = FD.ResolveContext(context)
	if resolved then
		return resolved
	end

	for _, child_id in ipairs({ "idInfopanel", "idSelection", "idContent", "idList" }) do
		local child = FD.ReadField(dialog, child_id)
		resolved = FD.ResolveContext(FD.ReadField(child, "context"))
		if resolved then
			return resolved
		end
	end

	return false
end

-- Return only valid object-like values from an array-style selection list.
function FD.ValidObjectsFromArray(list)
	local objects = {}
	if type(list) ~= "table" then
		return objects
	end

	for _, obj in ipairs(list) do
		if FD.IsObjectValid(obj) then
			objects[#objects + 1] = obj
		end
	end

	return objects
end

-- Gather selected objects from the common game/editor selection sources.
function FD.SelectedObjects()
	local objects = {}
	local seen = {}

	-- Add a selected object once while preserving selection-source priority.
	local function add(obj)
		if FD.IsObjectValid(obj) and not seen[obj] then
			seen[obj] = true
			objects[#objects + 1] = obj
		end
	end

	add(FD.Global("SelectedObj"))

	for _, obj in ipairs(FD.ValidObjectsFromArray(FD.Global("Selection"))) do
		add(obj)
	end

	local get_dialog = FD.Global("GetDialog")
	if type(get_dialog) == "function" then
		add(FD.ContextObjectFromDialog(FD.SafeCall(get_dialog, "Infopanel")))
		add(FD.ContextObjectFromDialog(FD.SafeCall(get_dialog, "InGameInterface")))
	end

	local editor = FD.Global("editor")
	local get_sel = FD.ReadField(editor, "GetSel")
	if type(get_sel) == "function" then
		local editor_selection = FD.SafeCall(function()
			return get_sel(editor)
		end)
		for _, obj in ipairs(FD.ValidObjectsFromArray(editor_selection)) do
			add(obj)
		end
	end

	local selo = FD.Global("selo")
	if type(selo) == "function" then
		local obj = FD.SafeCall(selo)
		add(obj)
	end

	return objects
end

-- Return the primary selected object, if any.
function FD.SelectedObject()
	local objects = FD.SelectedObjects()
	return objects[1] or false
end

-- ============================================================================
-- Message chaining
-- ============================================================================

-- Chain an OnMsg handler without discarding handlers installed by the game or
-- other mods. Keys make repeated module loads idempotent.
function FD.ChainOnMsg(message_name, key, handler)
	local on_msg = FD.Global("OnMsg")
	if type(on_msg) ~= "table" or type(handler) ~= "function" then
		return false
	end

	FD.onmsg_chained = FD.onmsg_chained or {}
	FD.onmsg_chained[message_name] = FD.onmsg_chained[message_name] or {}
	if FD.onmsg_chained[message_name][key] then
		return true
	end

	local previous = on_msg[message_name]

	-- Wrap the previous handler and the new handler so one failing hook does not
	-- take down later diagnostic refreshes.
	on_msg[message_name] = function(...)
		if type(previous) == "function" then
			pcall(previous, ...)
		end
		pcall(handler, ...)
	end

	FD.onmsg_chained[message_name][key] = true
	return true
end

-- ============================================================================
-- Module loading
-- ============================================================================

-- Normalize a mod folder path so module file names can be appended safely.
function FD.NormalizeModPath(path)
	if type(path) ~= "string" or path == "" then
		return false
	end

	local last = path:sub(-1)
	if last == "/" or last == "\\" then
		return path
	end

	return path .. "/"
end

-- Build possible mod root paths from the globals commonly available while mod
-- code is loading. This avoids depending on CurrentModPath alone.
function FD.ModPathCandidates()
	local candidates = {}

	local function add(path)
		path = FD.NormalizeModPath(path)
		if path then
			candidates[#candidates + 1] = path
		end
	end

	add(rawget(_G, "CurrentModPath"))

	local debug_lib = rawget(_G, "debug")
	if type(debug_lib) == "table" and type(debug_lib.getinfo) == "function" then
		local info = debug_lib.getinfo(1, "S")
		local source = info and info.source
		if type(source) == "string" and source:sub(1, 1) == "@" then
			local file_path = source:sub(2)
			add(file_path:gsub("[/\\]Code[/\\]ForceDelete%.lua$", ""))
		end
	end

	local current_mod = rawget(_G, "CurrentModDef")
	if type(current_mod) == "table" then
		add(FD.ReadField(current_mod, "path"))
		add(FD.ReadField(current_mod, "content_path"))
		add(FD.ReadField(current_mod, "env_path"))
	end

	local mods_loaded = rawget(_G, "ModsLoaded")
	if type(mods_loaded) == "table" then
		for _, mod in ipairs(mods_loaded) do
			if FD.ReadField(mod, "id") == "ForceDelete" then
				add(FD.ReadField(mod, "path"))
				add(FD.ReadField(mod, "content_path"))
				add(FD.ReadField(mod, "env_path"))
			end
		end
	end

	return candidates
end

-- Load a support module by trying every known mod path. The function is safe to
-- retry because each support file has its own double-load guard.
function FD.LoadSupportModule(file_name)
	for _, path in ipairs(FD.ModPathCandidates()) do
		local ok = pcall(dofile, path .. "Code/" .. file_name)
		if ok then
			return true
		end
	end

	return false
end

-- Load support modules in deterministic order. This can be retried from OnMsg
-- hooks in case the mod path globals appear later than the main script.
function FD.LoadSupportModules()
	FD.LoadSupportModule("fd_config.lua")
	FD.LoadSupportModule("fd_display_attributes.lua")
	FD.LoadSupportModule("fd_colonist.lua")

	if FD.DisplayAttributes and FD.DisplayAttributes.ShowInitialMessage then
		FD.DisplayAttributes.ShowInitialMessage()
	end
end

FD.LoadSupportModules()

-- ============================================================================
-- Selection monitoring and dispatch
-- ============================================================================

-- Dispatch the selected object to the first module that supports it. The main
-- script stays generic so future fd_drone/fd_dome modules can plug in cleanly.
function FD.DispatchSelectedObject(obj)
	if not FD.DisplayAttributes then
		return
	end

	if FD.Config and FD.Config.ShouldDisplayAttributes and not FD.Config.ShouldDisplayAttributes() then
		FD.DisplayAttributes.Hide()
		return
	end

	if not FD.IsObjectValid(obj) then
		FD.DisplayAttributes.ShowMessage("No object selected.")
		return
	end

	if FD.Colonist and FD.Colonist.IsColonist and FD.Colonist.IsColonist(obj) then
		FD.Colonist.OnSelected(obj)
		return
	end

	FD.DisplayAttributes.ShowMessage("Selected object is not supported yet.")
end

-- React to a selection change and refresh diagnostics only when the object
-- actually changes. This prevents periodic polling from redrawing constantly.
function FD.OnSelectionChanged(obj, force)
	if not force and obj == FD.last_selected_object then
		if FD.DisplayAttributes and FD.DisplayAttributes.RefreshPanelIfMissing then
			FD.DisplayAttributes.RefreshPanelIfMissing()
		end
		return
	end

	FD.last_selected_object = obj
	FD.DispatchSelectedObject(obj)
end

-- Start lightweight selection monitoring. Message hooks catch normal UI
-- changes, while polling covers engine paths that do not broadcast reliably.
function FD.StartSelectionMonitor()
	if FD.selection_monitor_started then
		FD.OnSelectionChanged(FD.SelectedObject(), true)
		return
	end

	FD.selection_monitor_started = true

	-- Refresh from the current selection source and let OnSelectionChanged decide
	-- whether the panel actually needs to update.
	local function refresh()
		FD.OnSelectionChanged(FD.SelectedObject())
	end

	-- Force a redraw after UI rebuilds because earlier attempts may have fallen
	-- back to the log before the in-game parent window existed.
	local function refresh_force()
		FD.OnSelectionChanged(FD.SelectedObject(), true)
	end

	for _, message_name in ipairs({
		"SelectedObjChange",
		"SelectionChange",
		"SelectionAdded",
		"SelectionRemoved",
		"GameEnterEditor",
		"GameExitEditor",
	}) do
		FD.ChainOnMsg(message_name, "selection_monitor", refresh)
	end

	FD.ChainOnMsg("InGameInterfaceCreated", "selection_monitor", refresh_force)

	local create_thread = FD.Global("CreateGameTimeThread") or FD.Global("CreateRealTimeThread")
	if type(create_thread) == "function" then
		-- Poll as a fallback for selection paths that do not emit a reliable UI
		-- message. The polling is intentionally slow and change-gated.
		create_thread(function()
			local sleep = FD.Global("Sleep")
			while true do
				refresh()
				if type(sleep) == "function" then
					sleep(FD.POLL_INTERVAL_MS)
				else
					break
				end
			end
		end)
	end

	FD.OnSelectionChanged(FD.SelectedObject(), true)
end

-- ============================================================================
-- Shortcut registration
-- ============================================================================

-- Check whether an action is already present on a shortcut target. A local
-- registry is used as a fallback when the target does not expose ActionById.
local function action_exists(parent, action_id)
	if parent == nil then
		return false
	end

	FD.shortcut_actions_by_parent = FD.shortcut_actions_by_parent or {}
	local local_actions = FD.shortcut_actions_by_parent[parent]
	if local_actions and local_actions[action_id] then
		return true
	end

	local action_by_id = FD.ReadField(parent, "ActionById")
	if type(action_by_id) == "function" then
		local action = FD.SafeCall(function()
			return action_by_id(parent, action_id)
		end)
		return action ~= nil and action ~= false
	end

	return false
end

-- Remember actions created by this module so retries stay idempotent even on
-- shortcut containers without a query API.
local function mark_action_registered(parent, action_id)
	if parent == nil then
		return
	end

	FD.shortcut_actions_by_parent = FD.shortcut_actions_by_parent or {}
	FD.shortcut_actions_by_parent[parent] = FD.shortcut_actions_by_parent[parent] or {}
	FD.shortcut_actions_by_parent[parent][action_id] = true
end

-- Add the diagnostic shortcuts to a shortcut target. Level 2 is registered
-- first so Ctrl+Shift+Delete does not get consumed by Ctrl+Delete.
function FD.AddForceDeleteActions(parent, context)
	local x_action = FD.Global("XAction")
	if parent == nil or type(x_action) ~= "table" or type(x_action.new) ~= "function" then
		return false
	end

	if not action_exists(parent, FD.LVL2_ACTION_ID) then
		x_action:new({
			ActionId = FD.LVL2_ACTION_ID,
			ActionName = "Force Delete Level 2 Diagnostic",
			ActionShortcut = "Ctrl-Shift-Delete",
			ActionGamepad = "LeftShoulder-RightShoulder-ButtonY",
			ActionMode = "Game",
			ActionBindable = true,
			IgnoreRepeated = true,
			-- Diagnostic shortcuts are always enabled because they only show
			-- feedback and never touch selected game objects.
			ActionState = function()
				return "enabled"
			end,
			-- Show shortcut feedback only and consume the input so no base-game
			-- delete behavior runs afterward.
			OnAction = function()
				if FD.DisplayAttributes then
					FD.DisplayAttributes.ShowMessage("Ctrl+Shift+Delete pressed.")
				end
				return "break"
			end,
		}, parent, context)
		mark_action_registered(parent, FD.LVL2_ACTION_ID)
	end

	if not action_exists(parent, FD.LVL1_ACTION_ID) then
		x_action:new({
			ActionId = FD.LVL1_ACTION_ID,
			ActionName = "Force Delete Level 1 Diagnostic",
			ActionShortcut = "Ctrl-Delete",
			ActionGamepad = "LeftShoulder-RightShoulder-ButtonX",
			ActionMode = "Game",
			ActionBindable = true,
			IgnoreRepeated = true,
			-- Level 1 is enabled in diagnostics for the same reason as Level 2:
			-- this action is read-only and exists to verify input routing.
			ActionState = function()
				return "enabled"
			end,
			-- Show shortcut feedback only and consume the input.
			OnAction = function()
				if FD.DisplayAttributes then
					FD.DisplayAttributes.ShowMessage("Ctrl+Delete pressed.")
				end
				return "break"
			end,
		}, parent, context)
		mark_action_registered(parent, FD.LVL1_ACTION_ID)
	end

	return true
end

-- Patch GameShortcuts.Init once and also try the live shortcut target when it
-- exists. This makes reloads and late UI initialization more forgiving.
function FD.PatchGameShortcuts()
	local live_target = FD.Global("XShortcutsTarget")
	if live_target then
		FD.AddForceDeleteActions(live_target)
	end

	if FD.shortcuts_patched then
		return true
	end

	local game_shortcuts = FD.Global("GameShortcuts")
	if type(game_shortcuts) ~= "table" or type(game_shortcuts.Init) ~= "function" then
		return false
	end

	local original_init = game_shortcuts.Init

	-- Extend the engine shortcut initialization while preserving its original
	-- behavior. Actions are added after the base container is ready.
	game_shortcuts.Init = function(self, parent, context, ...)
		local result = original_init(self, parent, context, ...)
		FD.AddForceDeleteActions(parent, context)
		return result
	end

	FD.shortcuts_patched = true
	return true
end

-- Retry shortcut registration at common data/UI lifecycle points.
function FD.InstallShortcutRetryHandlers()
	-- ClassesPostprocess is a common point where XAction classes become usable.
	FD.ChainOnMsg("ClassesPostprocess", "shortcut_retry", function()
		FD.LoadSupportModules()
		FD.PatchGameShortcuts()
	end)

	-- DataLoaded catches reloads where the shortcut target appears later.
	FD.ChainOnMsg("DataLoaded", "shortcut_retry", function()
		FD.LoadSupportModules()
		FD.PatchGameShortcuts()
	end)
end

-- Bootstrap the read-only diagnostic infrastructure.
FD.InstallShortcutRetryHandlers()
FD.PatchGameShortcuts()
FD.StartSelectionMonitor()
