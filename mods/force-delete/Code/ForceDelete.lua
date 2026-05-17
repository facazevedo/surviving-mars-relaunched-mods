-- Force Delete diagnostic scaffold.
-- Shared helpers, selection dispatch, and diagnostic shortcut registration.

-- Create the shared namespace used by all Force Delete modules.
ForceDelete = rawget(_G, "ForceDelete") or {}
local FD = ForceDelete
_G.ForceDelete = FD

-- Shortcut ids are stable so repeated loads do not create incompatible actions.
FD.LVL1_ACTION_ID = "ForceDelete_Level1_CtrlDelete"
FD.LVL2_ACTION_ID = "ForceDelete_Level2_CtrlShiftDelete"

-- Return an optional engine global without creating it.
function FD.Global(name)
	return rawget(_G, name)
end

-- Call optional engine functions safely.
function FD.SafeCall(fn, ...)
	if type(fn) ~= "function" then
		return false
	end

	local ok, result = pcall(fn, ...)
	return ok and result or false
end

-- Read a field from a table/userdata hybrid without throwing.
function FD.ReadField(obj, field)
	if not obj then
		return nil
	end

	local ok, value = pcall(function()
		return obj[field]
	end)

	return ok and value or nil
end

-- Call a zero-argument object method safely.
function FD.CallMethod(obj, method)
	local fn = FD.ReadField(obj, method)
	if type(fn) ~= "function" then
		return nil
	end

	local ok, value = pcall(function()
		return fn(obj)
	end)

	return ok and value or nil
end

-- Check whether an engine object can still be inspected.
function FD.IsObjectValid(obj)
	if not obj then
		return false
	end

	local is_valid = FD.Global("IsValid")
	if type(is_valid) == "function" then
		return FD.SafeCall(is_valid, obj) and true or false
	end

	return true
end

-- Test class relationships through the engine helper when available.
function FD.IsKindOf(obj, class_name)
	if not FD.IsObjectValid(obj) then
		return false
	end

	return FD.SafeCall(FD.Global("IsKindOf"), obj, class_name) and true or false
end

-- Return a compact class-like name for display and fallback matching.
function FD.ClassName(obj)
	if obj == nil then
		return "nil"
	end

	return FD.SafeToString(
		FD.ReadField(obj, "class")
			or FD.ReadField(obj, "class_name")
			or FD.CallMethod(obj, "GetClass")
			or type(obj)
	)
end

-- Convert values to short display-safe text.
function FD.SafeToString(value)
	local value_type = type(value)

	if value == nil then
		return "nil"
	end

	if value_type == "string" or value_type == "number" or value_type == "boolean" then
		return tostring(value)
	end

	local ok, text = pcall(tostring, value)
	return ok and text or value_type
end

-- Return one compact object summary without recursively dumping fields.
function FD.ObjectSummary(obj)
	if obj == nil then
		return "nil"
	end

	local value_type = type(obj)
	if value_type ~= "table" and value_type ~= "userdata" then
		return FD.SafeToString(obj)
	end

	local class = FD.ClassName(obj)
	local name = FD.ReadField(obj, "display_name")
		or FD.ReadField(obj, "name")
		or FD.CallMethod(obj, "GetDisplayName")
		or FD.CallMethod(obj, "GetName")
	local handle = FD.ReadField(obj, "handle")
	local id = FD.ReadField(obj, "id")

	local text = class
	if name then
		text = text .. " / " .. FD.SafeToString(name)
	end
	if handle then
		text = text .. " [handle=" .. FD.SafeToString(handle) .. "]"
	elseif id then
		text = text .. " [id=" .. FD.SafeToString(id) .. "]"
	end

	return text
end

-- Chain a game message handler without replacing existing handlers.
function FD.ChainOnMsg(message, key, handler)
	local on_msg = FD.Global("OnMsg")
	if type(on_msg) ~= "table" or type(handler) ~= "function" then
		return false
	end

	FD.onmsg_chained = FD.onmsg_chained or {}
	local chain_key = message .. ":" .. key
	if FD.onmsg_chained[chain_key] then
		return true
	end

	local previous = on_msg[message]
	on_msg[message] = function(...)
		if type(previous) == "function" then
			pcall(previous, ...)
		end
		pcall(handler, ...)
	end

	FD.onmsg_chained[chain_key] = true
	return true
end

-- Resolve a dialog/context wrapper to its underlying object when possible.
function FD.ResolveContext(context)
	if not context then
		return false
	end

	return FD.SafeCall(FD.Global("ResolvePropObj"), context)
		or FD.ReadField(context, "obj")
		or FD.ReadField(context, "object")
		or context
end

-- Return the first selected object from common gameplay/editor sources.
function FD.SelectedObject()
	local obj = FD.Global("SelectedObj")
	if FD.IsObjectValid(obj) then
		return obj
	end

	local selection = FD.Global("Selection")
	if type(selection) == "table" and FD.IsObjectValid(selection[1]) then
		return selection[1]
	end

	local get_dialog = FD.Global("GetDialog")
	local infopanel = FD.SafeCall(get_dialog, "Infopanel")
	obj = FD.ResolveContext(FD.ReadField(infopanel, "context") or FD.CallMethod(infopanel, "GetContext"))
	if FD.IsObjectValid(obj) then
		return obj
	end

	local editor = FD.Global("editor")
	if editor and type(editor.GetSel) == "function" then
		local selected = FD.SafeCall(editor.GetSel)
		if type(selected) == "table" and FD.IsObjectValid(selected[1]) then
			return selected[1]
		end
	end

	local selo = FD.Global("selo")
	obj = FD.SafeCall(selo)
	return FD.IsObjectValid(obj) and obj or false
end

-- Return the Force Delete object type handled by installed modules.
function FD.ObjectType(obj)
	if FD.Colonist and FD.Colonist.IsColonist(obj) then
		return "colonist"
	end

	return false
end

-- Return the configured force-delete level for one object type.
function FD.ConfiguredLevelForType(object_type)
	if FD.Config and FD.Config.GetObjectLevel then
		return FD.Config.GetObjectLevel(object_type)
	end

	return false
end

-- Show shortcut feedback without making shortcut handlers know display details.
function FD.ShowShortcutMessage(message)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.ShowMessage(message)
	end
end

-- Return the configured attribute refresh interval with a safe fallback.
function FD.AttributeRefreshInterval()
	if FD.Config and FD.Config.GetAttributeRefreshInterval then
		return FD.Config.GetAttributeRefreshInterval()
	end

	return 250
end

-- Delete one object by delegating to the module that owns its type.
function FD.DeleteObjectByType(obj, object_type)
	if object_type == "colonist" and FD.Colonist and FD.Colonist.Delete then
		return FD.Colonist.Delete(obj)
	end

	return false
end

-- Send the selected object to the first diagnostic module that supports it.
function FD.RefreshSelectionDiagnostics()
	if not FD.DisplayAttributes then
		return
	end

	local obj = FD.SelectedObject()
	if obj ~= FD.last_selected_object then
		FD.last_selected_object = obj
		FD.shortcut_feedback_active = false
	end

	if FD.shortcut_feedback_active then
		return
	end

	if FD.Config and FD.Config.ShouldDisplayAttributes and not FD.Config.ShouldDisplayAttributes() then
		FD.DisplayAttributes.Hide()
		return
	end

	if not FD.IsObjectValid(obj) then
		FD.DisplayAttributes.ShowMessage("No object selected.")
	elseif FD.Colonist and FD.Colonist.IsColonist(obj) then
		FD.Colonist.OnSelected(obj)
	else
		FD.DisplayAttributes.ShowMessage("Selected object is not supported yet.")
	end
end

-- Start a lightweight polling thread so changing fields refresh without reselection.
function FD.StartAttributeRefreshMonitor()
	if FD.attribute_refresh_monitor_started then
		return
	end

	local create_thread = FD.Global("CreateRealTimeThread") or FD.Global("CreateGameTimeThread")
	local sleep = FD.Global("Sleep")
	if type(create_thread) ~= "function" or type(sleep) ~= "function" then
		return
	end

	FD.attribute_refresh_monitor_started = true

	-- The monitor only asks the existing dispatcher to refresh; object modules
	-- still own what attributes are read and displayed.
	create_thread(function()
		while true do
			pcall(FD.RefreshSelectionDiagnostics)
			sleep(FD.AttributeRefreshInterval())
		end
	end)
end

-- Run one configured force-delete level against the current selection.
function FD.RunForceDeleteLevel(requested_level, shortcut_message)
	local obj = FD.SelectedObject()

	if not FD.IsObjectValid(obj) then
		FD.shortcut_feedback_active = true
		FD.ShowShortcutMessage(shortcut_message .. "\n\nNo object selected.")
		return false
	end

	local object_type = FD.ObjectType(obj)
	local object_level = FD.ConfiguredLevelForType(object_type)

	if not object_type or not object_level then
		FD.shortcut_feedback_active = true
		FD.ShowShortcutMessage(shortcut_message .. "\n\nSelected object is not supported yet.")
		return false
	end

	-- Config decides whether this shortcut level may dispatch deletion.
	if not FD.Config
		or not FD.Config.CanForceDeleteAtLevel
		or not FD.Config.CanForceDeleteAtLevel(object_type, requested_level) then
		FD.shortcut_feedback_active = true
		FD.ShowShortcutMessage(
			shortcut_message
				.. "\n\nSelected "
				.. object_type
				.. " is Level "
				.. FD.SafeToString(object_level)
				.. "."
		)
		return false
	end

	FD.shortcut_feedback_active = true
	return FD.DeleteObjectByType(obj, object_type)
end

-- Level 1 deletes only objects configured for Level 1.
function FD.RunLevel1ForSelection()
	return FD.RunForceDeleteLevel(1, "Ctrl+Delete pressed.")
end

-- Level 2 deletes objects configured for Level 1 or Level 2.
function FD.RunLevel2ForSelection()
	return FD.RunForceDeleteLevel(2, "Ctrl+Shift+Delete pressed.")
end

-- Refresh diagnostics when normal selection messages fire.
function FD.InstallSelectionHooks()
	if FD.selection_hooks_installed then
		return
	end

	FD.selection_hooks_installed = true

	-- Hook the common gameplay/editor selection messages.
	for _, message in ipairs({
		"InGameInterfaceCreated",
		"SelectedObjChange",
		"SelectionChange",
		"SelectionAdded",
		"SelectionRemoved",
		"GameEnterEditor",
		"GameExitEditor",
	}) do
		FD.ChainOnMsg(message, "force_delete_selection", FD.RefreshSelectionDiagnostics)
	end
end

-- Add one shortcut action unless it already exists on the parent.
function FD.AddShortcut(parent, context, id, name, shortcut, gamepad, on_action)
	if not parent or not XAction then
		return
	end

	if parent.ActionById and parent:ActionById(id) then
		return
	end

	-- XAction owns the actual game shortcut binding and calls the matching
	-- force-delete level when the shortcut is pressed.
	XAction:new({
		ActionId = id,
		ActionName = name,
		ActionShortcut = shortcut,
		ActionGamepad = gamepad,
		ActionMode = "Game",
		ActionBindable = true,
		IgnoreRepeated = true,
		ActionState = function()
			return "enabled"
		end,
		OnAction = function()
			if type(on_action) == "function" then
				pcall(on_action)
			end
			return "break"
		end,
	}, parent, context)
end

-- Add both diagnostic shortcuts to a shortcut container.
function FD.AddDiagnosticShortcuts(parent, context)
	FD.AddShortcut(
		parent,
		context,
		FD.LVL2_ACTION_ID,
		"Force Delete Level 2 Diagnostic",
		"Ctrl-Shift-Delete",
		"LeftShoulder-RightShoulder-ButtonY",
		FD.RunLevel2ForSelection
	)
	FD.AddShortcut(
		parent,
		context,
		FD.LVL1_ACTION_ID,
		"Force Delete Level 1 Diagnostic",
		"Ctrl-Delete",
		"LeftShoulder-RightShoulder-ButtonX",
		FD.RunLevel1ForSelection
	)
end

-- Register diagnostic shortcuts by patching the game shortcut initializer once.
function FD.PatchGameShortcuts()
	-- If the shortcut target already exists, add actions immediately too.
	FD.AddDiagnosticShortcuts(rawget(_G, "XShortcutsTarget"))

	if FD.shortcuts_patched or not GameShortcuts or type(GameShortcuts.Init) ~= "function" then
		return
	end

	-- Patch the shortcut initializer once and append our actions after the base
	-- game has created its shortcut container.
	local original_init = GameShortcuts.Init
	GameShortcuts.Init = function(self, parent, context, ...)
		local result = original_init(self, parent, context, ...)
		FD.AddDiagnosticShortcuts(parent, context)
		return result
	end

	FD.shortcuts_patched = true
end

-- Retry shortcut patching when classes/data are ready.
function FD.InstallShortcutHooks()
	FD.ChainOnMsg("ClassesPostprocess", "force_delete_shortcuts", FD.PatchGameShortcuts)
	FD.ChainOnMsg("DataLoaded", "force_delete_shortcuts", FD.PatchGameShortcuts)
end

-- Install the startup hooks after every module has had a chance to load.
FD.InstallSelectionHooks()
FD.InstallShortcutHooks()
FD.PatchGameShortcuts()
FD.StartAttributeRefreshMonitor()
