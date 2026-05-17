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

-- Send the selected object to the first diagnostic module that supports it.
function FD.RefreshSelectionDiagnostics()
	if not FD.DisplayAttributes then
		return
	end

	if FD.Config and FD.Config.ShouldDisplayAttributes and not FD.Config.ShouldDisplayAttributes() then
		FD.DisplayAttributes.Hide()
		return
	end

	local obj = FD.SelectedObject()
	if not FD.IsObjectValid(obj) then
		FD.DisplayAttributes.ShowMessage("No object selected.")
	elseif FD.Colonist and FD.Colonist.IsColonist(obj) then
		FD.Colonist.OnSelected(obj)
	else
		FD.DisplayAttributes.ShowMessage("Selected object is not supported yet.")
	end
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
function FD.AddShortcut(parent, context, id, name, shortcut, gamepad, message)
	if not parent or not XAction then
		return
	end

	if parent.ActionById and parent:ActionById(id) then
		return
	end

	-- XAction owns the actual game shortcut binding and calls our read-only
	-- diagnostic callback when the shortcut is pressed.
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
			if FD.DisplayAttributes then
				FD.DisplayAttributes.ShowMessage(message)
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
		"Ctrl+Shift+Delete pressed."
	)
	FD.AddShortcut(
		parent,
		context,
		FD.LVL1_ACTION_ID,
		"Force Delete Level 1 Diagnostic",
		"Ctrl-Delete",
		"LeftShoulder-RightShoulder-ButtonX",
		"Ctrl+Delete pressed."
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
