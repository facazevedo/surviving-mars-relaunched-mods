-- Force Delete core.
-- Shared helpers, selection dispatch, and diagnostic shortcut registration.

-- Create the shared namespace used by all Force Delete modules.
ForceDelete = rawget(_G, "ForceDelete") or {}
local FD = ForceDelete
_G.ForceDelete = FD

-- Shortcut ids are stable so repeated loads do not create incompatible actions.
FD.LVL1_ACTION_ID = "ForceDelete_Level1_CtrlDelete"
FD.LVL2_ACTION_ID = "ForceDelete_Level2_CtrlShiftDelete"
FD.MAX_SCAN = FD.MAX_SCAN or 2048

-- Common identity fields shown by object-specific inspector modules.
FD.IDENTITY_FIELDS = { "name", "display_name", "handle", "id", "index", "Index" }

-- Common demolition methods shown by non-unit object modules.
FD.DEMOLISHABLE_METHODS = { "CanDemolish", "DoDemolish", "delete" }

-- Supported object modules are checked in this order for detection and dispatch.
FD.SUPPORTED_TYPES = {
	{ object_type = "colonist", module_name = "Colonist", is_method = "IsColonist" },
	{ object_type = "drone", module_name = "Drone", is_method = "IsDrone" },
	{ object_type = "animal", module_name = "Animal", is_method = "IsAnimal" },
	{ object_type = "shuttle", module_name = "Shuttle", is_method = "IsShuttle" },
	{ object_type = "rover", module_name = "Rover", is_method = "IsRover" },
	{ object_type = "dome", module_name = "Dome", is_method = "IsDome" },
	{ object_type = "deposit", module_name = "Deposit", is_method = "IsDeposit" },
	{ object_type = "decoration", module_name = "Decoration", is_method = "IsDecoration" },
	{ object_type = "infrastructure", module_name = "Infrastructure", is_method = "IsInfrastructure" },
	{ object_type = "internal_building", module_name = "InternalBuilding", is_method = "IsInternalBuilding" },
	{ object_type = "external_building", module_name = "ExternalBuilding", is_method = "IsExternalBuilding" },
}

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

-- Write a field on an engine object without trusting table/userdata behavior.
function FD.WriteField(obj, field, value)
	if not obj then
		return false
	end

	local ok = pcall(function()
		obj[field] = value
	end)

	return ok
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

-- Return whether an object appears to support the game's normal demolition path.
function FD.IsDemolishable(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	if FD.IsKindOf(obj, "Demolishable") then
		return true
	end

	local explicit_flag = FD.ReadField(obj, "demolishable")
	if type(explicit_flag) == "boolean" then
		return explicit_flag
	end

	local can_demolish = FD.ReadField(obj, "CanDemolish")
	if type(can_demolish) == "function" then
		local ok, result = pcall(can_demolish, obj)
		if ok and type(result) == "boolean" then
			return result
		end
	end

	return type(FD.ReadField(obj, "DoDemolish")) == "function"
end

-- Return whether an object looks like a building or demolishable construction.
function FD.IsBuildingLike(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	return FD.IsKindOf(obj, "Building")
		or class:find("Building", 1, true) ~= nil
		or type(FD.ReadField(obj, "DoDemolish")) == "function"
end

-- Return whether an object is already demolished building remains.
function FD.IsDemolishedBuilding(obj)
	return FD.IsBuildingLike(obj)
		and FD.ReadField(obj, "destroyed") == true
		and FD.ReadField(obj, "demolishing") ~= true
end

-- Clear already-demolished building remains before normal delete attempts.
function FD.ClearDemolishedBuilding(obj)
	if not FD.IsDemolishedBuilding(obj) then
		return false
	end

	if FD.CallObjectMethod(obj, "ClearDone") then
		return true
	end

	-- If immediate clearing is unavailable, at least ask the game cleanup path
	-- to mark the remains for clearing before the direct delete fallback runs.
	FD.CallObjectMethod(obj, "DestroyedClear")
	return false
end

-- Return whether an object is one of the live unit types handled separately.
function FD.IsProtectedUnit(obj)
	return (FD.Colonist and FD.Colonist.IsColonist(obj))
		or (FD.Drone and FD.Drone.IsDrone(obj))
		or (FD.Animal and FD.Animal.IsAnimal(obj))
		or (FD.Shuttle and FD.Shuttle.IsShuttle(obj))
		or (FD.Rover and FD.Rover.IsRover(obj))
end

-- Return whether an object is a dome-like building that needs separate logic later.
function FD.IsDomeLikeObject(obj)
	return FD.IsKindOf(obj, "Dome") or FD.ClassName(obj):find("Dome", 1, true) ~= nil
end

-- Convert one inspected value into compact inspector text.
function FD.AttributeText(value)
	local value_type = type(value)
	if value_type == "table" or value_type == "userdata" then
		return FD.ObjectSummary(value)
	end

	return FD.SafeToString(value)
end

-- Append one key/value row to an inspector attribute list.
function FD.AddAttribute(rows, label, value)
	rows[#rows + 1] = { label, FD.AttributeText(value) }
end

-- Append a fixed set of safely read fields to an inspector attribute list.
function FD.AddFieldAttributes(rows, obj, fields)
	for _, field in ipairs(fields or {}) do
		FD.AddAttribute(rows, field, FD.ReadField(obj, field))
	end
end

-- Return a boolean result from an object method, or nil if unavailable.
function FD.MethodBool(obj, method)
	local fn = FD.ReadField(obj, method)
	if type(fn) ~= "function" then
		return nil
	end

	local ok, result = pcall(fn, obj)
	return ok and (result and true or false) or nil
end

-- Return a display-ready boolean method result.
function FD.MethodText(obj, method)
	local result = FD.MethodBool(obj, method)
	return result == nil and "unavailable" or tostring(result)
end

-- Call an object method with arguments and return whether it succeeded.
function FD.CallObjectMethod(obj, method, ...)
	local fn = FD.ReadField(obj, method)
	if type(fn) ~= "function" then
		return false
	end

	local ok = pcall(fn, obj, ...)
	return ok and true or false
end

-- Stop a command object without letting stale command destructors run.
function FD.StopCommandNoDestructors(obj)
	FD.WriteField(obj, "command_destructors", false)
	FD.WriteField(obj, "command_queue", nil)
	FD.WriteField(obj, "forced_cmd_importance", nil)

	for _, thread in ipairs({
		FD.ReadField(obj, "command_thread"),
		FD.ReadField(obj, "thread_running_destructors"),
	}) do
		if FD.SafeCall(FD.Global("IsValidThread"), thread) then
			FD.SafeCall(FD.Global("DeleteThread"), thread)
		end
	end

	FD.WriteField(obj, "command_thread", nil)
	FD.WriteField(obj, "thread_running_destructors", nil)
	FD.WriteField(obj, "command", "Idle")
end

-- Stop an active demolition countdown thread before forcing demolition now.
function FD.StopDemolitionThread(obj)
	local thread = FD.ReadField(obj, "demolishing_thread")

	if FD.SafeCall(FD.Global("IsValidThread"), thread) then
		FD.SafeCall(FD.Global("DeleteThread"), thread)
	end

	FD.WriteField(obj, "demolishing_thread", false)
end

-- Try the game's own demolition transition before using direct deletion.
function FD.DemolishObjectNow(obj)
	if FD.ClearDemolishedBuilding(obj) then
		return true
	end

	if not FD.IsDemolishable(obj) or type(FD.ReadField(obj, "DoDemolish")) ~= "function" then
		return false
	end

	FD.WriteField(obj, "demolishing", true)
	FD.WriteField(obj, "demolishing_countdown", 0)
	FD.StopDemolitionThread(obj)

	return FD.CallObjectMethod(obj, "DoDemolish")
end

-- Demolish an object and clear the ruins when demolition leaves remains.
function FD.DemolishThenClearObject(obj)
	if FD.ClearDemolishedBuilding(obj) then
		return true
	end

	local demolished = FD.DemolishObjectNow(obj)
	if not demolished then
		return false
	end

	if not FD.IsObjectValid(obj) then
		return true
	end

	FD.ClearDemolishedBuilding(obj)
	return true
end

-- Demolish, clear, then direct-delete only if the object still exists.
function FD.DeleteAfterDemolishAndClear(obj)
	local changed = FD.DemolishThenClearObject(obj)

	if not FD.IsObjectValid(obj) then
		return changed
	end

	return FD.DeleteObjectDirect(obj) or changed
end

-- Remove an object directly when the normal demolition path is unavailable.
function FD.DeleteObjectDirect(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	if FD.ClearDemolishedBuilding(obj) then
		return true
	end

	if FD.CallObjectMethod(obj, "delete") then
		return true
	end

	return FD.SafeCall(FD.Global("DoneObject"), obj) and true or false
end

-- Delete one non-unit object through demolition first, then direct fallback.
function FD.DeleteNonUnitObject(obj)
	return FD.DeleteAfterDemolishAndClear(obj)
end

-- Guard engine request cleanup against stale boolean request references.
function FD.PatchRequestUnassignUnit()
	if FD.request_unassign_patched then
		return true
	end

	local original = FD.Global("RequestUnassignUnit")
	if type(original) ~= "function" then
		return false
	end

	_G.RequestUnassignUnit = function(request, ...)
		if type(FD.ReadField(request, "UnassignUnit")) ~= "function" then
			return false
		end

		return original(request, ...)
	end

	FD.request_unassign_patched = true
	return true
end

-- Run only the Level 1-style demolition stage for one non-unit object.
function FD.Level1DemolishObject(obj)
	return FD.DemolishThenClearObject(obj)
end

-- Run the Level 2 sequence: demolish, clear, then direct-delete if needed.
function FD.Level2DeleteObject(obj)
	return FD.DeleteAfterDemolishAndClear(obj)
end

-- Delete a named non-unit type and report a concise result message.
function FD.DeleteNamedNonUnitObject(obj, is_supported, label, invalid_message)
	if not is_supported then
		FD.ShowDeleteMessage("Force delete pressed.\n\n" .. invalid_message)
		return false
	end

	local summary = FD.ObjectSummary(obj)
	if FD.DeleteNonUnitObject(obj) then
		FD.ShowDeleteMessage("Force delete pressed.\n\nDeleted " .. label .. ": " .. summary)
		return true
	end

	FD.ShowDeleteMessage("Force delete pressed.\n\nCould not delete " .. label .. ": " .. summary)
	return false
end

-- Append common identity, level, and validity rows for supported objects.
function FD.AddCommonObjectAttributes(rows, obj, object_type, reason)
	local object_level = FD.ConfiguredLevelForType(object_type, obj)
	local level_1_allowed = FD.CanDeleteAtLevel(object_type, 1, obj)
	local level_2_allowed = FD.CanDeleteAtLevel(object_type, 2, obj)

	FD.AddAttribute(rows, "is_demolishable", FD.IsDemolishable(obj))
	FD.AddAttribute(rows, "Selected", FD.ObjectSummary(obj))
	FD.AddAttribute(rows, "Class", FD.ClassName(obj))
	FD.AddAttribute(rows, "object_type", object_type)
	FD.AddAttribute(rows, "configured level", object_level and ("Level " .. object_level) or "unconfigured")
	FD.AddAttribute(rows, "Level 1 delete", level_1_allowed == true)
	FD.AddAttribute(rows, "Level 2 delete", level_2_allowed == true)

	if reason then
		FD.AddAttribute(rows, "reason", reason)
	end

	FD.AddAttribute(rows, "valid", FD.IsObjectValid(obj))
end

-- Append common lifecycle and method-availability rows.
function FD.AddMethodDiagnostics(rows, obj, methods)
	FD.AddAttribute(rows, "IsDead()", FD.MethodText(obj, "IsDead"))
	FD.AddAttribute(rows, "IsDying()", FD.MethodText(obj, "IsDying"))

	for _, method in ipairs(methods or {}) do
		FD.AddAttribute(rows, method .. " method", type(FD.ReadField(obj, method)) == "function")
	end

	FD.AddAttribute(rows, "DoneObject global", type(FD.Global("DoneObject")) == "function")
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

-- Append a valid object once so multi-selection batches do not duplicate work.
function FD.AddUniqueSelectedObject(objects, seen, obj)
	if not FD.IsObjectValid(obj) or seen[obj] then
		return
	end

	seen[obj] = true
	objects[#objects + 1] = obj
end

-- Append valid objects from an array-style selection table.
function FD.AddSelectedObjectsFromArray(objects, seen, list)
	if type(list) ~= "table" then
		return
	end

	for _, obj in ipairs(list) do
		FD.AddUniqueSelectedObject(objects, seen, obj)
	end
end

-- Return selected objects from common gameplay/editor sources.
function FD.SelectedObjects()
	local objects = {}
	local seen = {}

	-- Multi-selection order should control both batch deletion and inspector focus.
	FD.AddSelectedObjectsFromArray(objects, seen, FD.Global("Selection"))
	if #objects > 0 then
		return objects
	end

	FD.AddUniqueSelectedObject(objects, seen, FD.Global("SelectedObj"))

	local get_dialog = FD.Global("GetDialog")
	local infopanel = FD.SafeCall(get_dialog, "Infopanel")
	FD.AddUniqueSelectedObject(
		objects,
		seen,
		FD.ResolveContext(FD.ReadField(infopanel, "context") or FD.CallMethod(infopanel, "GetContext"))
	)

	local editor = FD.Global("editor")
	if editor and type(editor.GetSel) == "function" then
		FD.AddSelectedObjectsFromArray(objects, seen, FD.SafeCall(editor.GetSel))
	end

	local selo = FD.Global("selo")
	FD.AddUniqueSelectedObject(objects, seen, FD.SafeCall(selo))

	return objects
end

-- Return the first selected object for display-focused operations.
function FD.SelectedObject()
	local objects = FD.SelectedObjects()

	return objects[1] or false
end

-- Return the selected object that should drive the inspector panel.
function FD.SelectedInspectableObject()
	local objects = FD.SelectedObjects()

	for _, obj in ipairs(objects) do
		if FD.ObjectType(obj) then
			return obj
		end
	end

	return objects[1] or false
end

-- Clear active gameplay/editor selection before deleting selected objects.
function FD.ClearSelection()
	FD.SafeCall(FD.Global("SelectObj"), false)

	local editor = FD.Global("editor")
	if editor and type(editor.ClearSel) == "function" then
		pcall(function()
			editor.ClearSel()
		end)
	end

	FD.last_selected_object = false
end

-- Return the Force Delete object type handled by installed modules.
function FD.ObjectType(obj)
	for _, entry in ipairs(FD.SUPPORTED_TYPES) do
		local handler = FD[entry.module_name]
		local detector = handler and handler[entry.is_method]

		if type(detector) == "function" and detector(obj) then
			return entry.object_type
		end
	end

	return false
end

-- Return the module that owns one supported object type.
function FD.HandlerForType(object_type)
	for _, entry in ipairs(FD.SUPPORTED_TYPES) do
		if entry.object_type == object_type then
			return FD[entry.module_name] or false
		end
	end

	return false
end

-- Return the configured force-delete level for one selected object.
function FD.ConfiguredLevelForType(object_type, obj)
	if FD.Config and FD.Config.GetObjectLevel then
		return FD.Config.GetObjectLevel(object_type, obj)
	end

	return false
end

-- Return whether one shortcut level may delete one object type.
function FD.CanDeleteAtLevel(object_type, requested_level, obj)
	if object_type == "dome" and requested_level < 2 then
		return false
	end

	return FD.Config
		and FD.Config.CanForceDeleteAtLevel
		and FD.Config.CanForceDeleteAtLevel(object_type, requested_level, obj)
end

-- Show shortcut feedback without making shortcut handlers know display details.
function FD.ShowShortcutMessage(message)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.ShowMessage(message)
	end
end

-- Show deletion feedback through the inspector panel when it exists.
function FD.ShowDeleteMessage(message)
	FD.ShowShortcutMessage(message)
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
	local handler = FD.HandlerForType(object_type)

	if handler and handler.Delete then
		return handler.Delete(obj)
	end

	return false
end

-- Show one supported object's attributes through its owning module.
function FD.ShowObjectAttributes(obj, object_type)
	local handler = FD.HandlerForType(object_type)

	if handler and handler.OnSelected then
		handler.OnSelected(obj)
		return true
	end

	return false
end

-- Send the selected object to the first diagnostic module that supports it.
function FD.RefreshSelectionDiagnostics()
	if not FD.DisplayAttributes then
		return
	end

	local obj = FD.SelectedInspectableObject()
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

	local object_type = FD.ObjectType(obj)

	if not FD.IsObjectValid(obj) then
		FD.DisplayAttributes.ShowMessage("No object selected.")
	elseif object_type and FD.ShowObjectAttributes(obj, object_type) then
		return
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
	local selected_objects = FD.SelectedObjects()

	if #selected_objects == 0 then
		FD.shortcut_feedback_active = true
		FD.ShowShortcutMessage(shortcut_message .. "\n\nNo object selected.")
		return false
	end

	local delete_plan = {}
	local skipped_unsupported = 0
	local skipped_level = 0

	-- Build the complete batch before clearing selection.
	for _, obj in ipairs(selected_objects) do
		local object_type = FD.ObjectType(obj)

		if not object_type then
			skipped_unsupported = skipped_unsupported + 1
		else
			local object_level = FD.ConfiguredLevelForType(object_type, obj)

			if object_level and FD.CanDeleteAtLevel(object_type, requested_level, obj) then
				delete_plan[#delete_plan + 1] = {
					obj = obj,
					object_type = object_type,
				}
			elseif object_level then
				skipped_level = skipped_level + 1
			else
				skipped_unsupported = skipped_unsupported + 1
			end
		end
	end

	if #delete_plan == 0 then
		FD.shortcut_feedback_active = true
		FD.ShowShortcutMessage(
			shortcut_message
				.. "\n\nNo selected objects are eligible for Level "
				.. FD.SafeToString(requested_level)
				.. " deletion."
		)
		return false
	end

	FD.ClearSelection()
	FD.shortcut_feedback_active = true

	local deleted = 0
	local failed = 0

	-- Run each module-owned delete handler after selection is no longer active.
	for _, item in ipairs(delete_plan) do
		if FD.DeleteObjectByType(item.obj, item.object_type) then
			deleted = deleted + 1
		else
			failed = failed + 1
		end
	end

	FD.ShowShortcutMessage(
		shortcut_message
			.. "\n\nDeleted: "
			.. FD.SafeToString(deleted)
			.. "\nFailed: "
			.. FD.SafeToString(failed)
			.. "\nSkipped unsupported: "
			.. FD.SafeToString(skipped_unsupported)
			.. "\nSkipped level: "
			.. FD.SafeToString(skipped_level)
	)

	return deleted > 0
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

-- Retry shortcut patching and engine guards when classes/data are ready.
function FD.InstallShortcutHooks()
	FD.ChainOnMsg("ClassesPostprocess", "force_delete_shortcuts", FD.PatchGameShortcuts)
	FD.ChainOnMsg("DataLoaded", "force_delete_shortcuts", FD.PatchGameShortcuts)
	FD.ChainOnMsg("ClassesPostprocess", "force_delete_request_guard", FD.PatchRequestUnassignUnit)
	FD.ChainOnMsg("DataLoaded", "force_delete_request_guard", FD.PatchRequestUnassignUnit)
end

-- Install the startup hooks after every module has had a chance to load.
FD.InstallSelectionHooks()
FD.InstallShortcutHooks()
FD.PatchGameShortcuts()
FD.PatchRequestUnassignUnit()
FD.StartAttributeRefreshMonitor()
