-- dam_mod_control.lua
-- Captures, disables, and restores the ordered active-mod set using the
-- Installed Mods UI's own ModUI_Entry:SetEnabledAndSync engine path.
-- AccountStorage is intentionally unavailable to mod sandboxes, so enabled
-- state is read through ModUI_Entry and changed through its vanilla method.

DAM_ModControl = {}

local operation_thread = false

local function contains(list, value)
	for index = 1, #list do
		if list[index] == value then
			return true
		end
	end
	return false
end

local function validate_runtime()
	local missing = {}
	if type(Mods) ~= "table" then
		missing[#missing + 1] = "Mods"
	end
	if type(ModUI_Entry) ~= "table" or type(ModUI_Entry.FromModDef) ~= "function" then
		missing[#missing + 1] = "ModUI_Entry:FromModDef"
	end
	if type(CreateRealTimeThread) ~= "function" then
		missing[#missing + 1] = "CreateRealTimeThread"
	end

	local available = #missing == 0
	DAM_Debug.Info("Control", "Runtime API availability checked", {
		available = available,
		missing_count = #missing,
	}, "DEBUG_CONTROL")
	if available ~= true then
		DAM_Debug.Error("Control", "Required runtime API is unavailable", {
			missing = table.concat(missing, ", "),
		}, "DEBUG_CONTROL")
	end
	return available
end

local function get_mod_entry(mod_id)
	local mod_def = Mods[mod_id]
	if mod_def == nil then
		return nil
	end
	return ModUI_Entry:FromModDef(mod_def)
end

local function get_enabled_mod_order()
	local result = {}
	local seen = {}

	local function append_if_enabled(value)
		local mod_id = type(value) == "table" and value.id or value
		if type(mod_id) ~= "string" or seen[mod_id] == true then
			return
		end

		local entry = get_mod_entry(mod_id)
		if entry and entry.Enabled == true then
			seen[mod_id] = true
			result[#result + 1] = mod_id
		end
	end

	-- g_InitialMods is the vanilla Installed Mods dialog's ordered snapshot.
	if type(g_InitialMods) == "table" then
		for index = 1, #g_InitialMods do
			append_if_enabled(g_InitialMods[index])
		end
	end

	-- ModsLoaded preserves the active load order if the dialog snapshot is absent.
	if type(ModsLoaded) == "table" then
		for index = 1, #ModsLoaded do
			append_if_enabled(ModsLoaded[index])
		end
	end

	-- Include mods enabled after the dialog opened. Sorting makes the fallback
	-- deterministic; existing active mods retain their vanilla order above.
	local remaining_ids = {}
	for mod_id in pairs(Mods) do
		if type(mod_id) == "string" and seen[mod_id] ~= true then
			remaining_ids[#remaining_ids + 1] = mod_id
		end
	end
	table.sort(remaining_ids)
	for index = 1, #remaining_ids do
		append_if_enabled(remaining_ids[index])
	end

	return result
end

local function set_mod_enabled(mod_id, enabled)
	local entry = get_mod_entry(mod_id)
	if entry == nil then
		DAM_Debug.Warn("Control", "Skipped unavailable mod", {
			enabled = enabled,
			mod_id = mod_id,
		}, "DEBUG_CONTROL")
		return false
	end

	if type(entry.SetEnabledAndSync) ~= "function" then
		DAM_Debug.Error("Control", "Installed Mods entry cannot synchronize state", {
			enabled = enabled,
			mod_id = mod_id,
		}, "DEBUG_CONTROL")
		return false
	end

	entry:SetEnabledAndSync(enabled, true)
	if type(entry.ObjModified) == "function" then
		entry:ObjModified()
	end
	if entry.Enabled ~= enabled then
		DAM_Debug.Error("Control", "Installed Mods entry rejected requested state", {
			actual = entry.Enabled,
			expected = enabled,
			mod_id = mod_id,
		}, "DEBUG_CONTROL")
		return false
	end
	return true
end

local function refresh_installed_mods(host)
	local context = g_ParadoxModsContextObj
	if context and type(context.GetInstalledMods) == "function" then
		context:GetInstalledMods()
		ObjModified(context)
	end
	if DAM_UI and type(DAM_UI.RefreshButton) == "function" then
		DAM_UI.RefreshButton(host)
	end
end

local function disable_all_other_mods(host)
	local previous_load_order = get_enabled_mod_order()
	if contains(previous_load_order, DAM_Config.MOD_ID) ~= true then
		previous_load_order[#previous_load_order + 1] = DAM_Config.MOD_ID
	end

	local captured, capture_err = DAM_State.CapturePreviousLoadOrder(previous_load_order)
	if captured ~= true then
		return false, capture_err
	end

	local disabled_count = 0
	for index = 1, #previous_load_order do
		local mod_id = previous_load_order[index]
		if mod_id ~= DAM_Config.MOD_ID and set_mod_enabled(mod_id, false) == true then
			disabled_count = disabled_count + 1
		end
	end

	set_mod_enabled(DAM_Config.MOD_ID, true)
	refresh_installed_mods(host)

	DAM_Debug.Info("Control", "Disabled active mods and preserved this mod", {
		disabled_count = disabled_count,
		remembered_count = #previous_load_order,
		self_mod_id = DAM_Config.MOD_ID,
	}, "DEBUG_CONTROL")
	return true
end

local function build_available_restore_order(previous_load_order, keep_self_enabled)
	local restore_order = {}
	local seen = {}
	local missing_count = 0

	for index = 1, #previous_load_order do
		local mod_id = previous_load_order[index]
		if seen[mod_id] ~= true then
			seen[mod_id] = true
			if mod_id == DAM_Config.MOD_ID and keep_self_enabled ~= true then
				-- Vanilla will disable this mod after teardown completes.
			elseif Mods[mod_id] ~= nil then
				restore_order[#restore_order + 1] = mod_id
			else
				missing_count = missing_count + 1
				DAM_Debug.Warn("Control", "Remembered mod is no longer installed", {
					mod_id = mod_id,
				}, "DEBUG_CONTROL")
			end
		end
	end

	if keep_self_enabled == true and seen[DAM_Config.MOD_ID] ~= true then
		restore_order[#restore_order + 1] = DAM_Config.MOD_ID
	end
	return restore_order, missing_count
end

local function restore_previous_mods_impl(host, keep_self_enabled)
	local previous_load_order = DAM_State.GetPreviousLoadOrder()
	if #previous_load_order == 0 then
		return false, "no previous active mod load order is available"
	end

	local restore_order, missing_count = build_available_restore_order(
		previous_load_order,
		keep_self_enabled
	)
	local failed_count = 0
	local current_load_order = get_enabled_mod_order()
	for index = 1, #current_load_order do
		local mod_id = current_load_order[index]
		if mod_id ~= DAM_Config.MOD_ID or keep_self_enabled == true then
			if set_mod_enabled(mod_id, false) ~= true then
				failed_count = failed_count + 1
			end
		end
	end

	local restored_count = 0
	for index = 1, #restore_order do
		local mod_id = restore_order[index]
		if set_mod_enabled(mod_id, true) == true then
			if mod_id ~= DAM_Config.MOD_ID then
				restored_count = restored_count + 1
			end
		else
			failed_count = failed_count + 1
		end
	end

	if failed_count > 0 then
		if keep_self_enabled == true then
			set_mod_enabled(DAM_Config.MOD_ID, true)
		end
		refresh_installed_mods(host)
		return false, string.format("%d mod state changes failed", failed_count)
	end

	local cleared, clear_err = DAM_State.ClearPreviousLoadOrder()
	if cleared ~= true then
		refresh_installed_mods(host)
		return false, clear_err
	end

	refresh_installed_mods(host)
	DAM_Debug.Info("Control", "Restored previous active mod load order", {
		missing_count = missing_count,
		restored_count = restored_count,
		target_count = #restore_order,
	}, "DEBUG_CONTROL")
	return true
end

local function restore_previous_mods(host, keep_self_enabled)
	if keep_self_enabled == true then
		return DAM_DisableGuard.RunWithSelfDisableSuppressed(function()
			return restore_previous_mods_impl(host, keep_self_enabled)
		end)
	end
	return restore_previous_mods_impl(host, keep_self_enabled)
end

function DAM_ModControl.IsBusy()
	return IsValidThread(operation_thread)
end

function DAM_ModControl.Toggle(host)
	if DAM_Config.ENABLE_MOD_CONTROL ~= true then
		DAM_Debug.Warn("Control", "Toggle ignored because mod control is disabled", nil, "DEBUG_CONTROL")
		return false
	end
	if DAM_ModControl.IsBusy() == true then
		DAM_Debug.Warn("Control", "Toggle ignored because an operation is already running", nil, "DEBUG_CONTROL")
		return false
	end
	if validate_runtime() ~= true then
		return false
	end

	operation_thread = CreateRealTimeThread(function()
		local restoring = DAM_State.HasPreviousLoadOrder() == true
		local ok, result, err = pcall(function()
			if restoring then
				return restore_previous_mods(host, true)
			end
			return disable_all_other_mods(host)
		end)

		if ok ~= true then
			DAM_Debug.Error("Control", "Toggle operation raised an engine error", {
				error = result,
				operation = restoring and "restore" or "disable",
			}, "DEBUG_CONTROL")
		elseif result ~= true then
			DAM_Debug.Error("Control", "Toggle operation did not complete", {
				error = err,
				operation = restoring and "restore" or "disable",
			}, "DEBUG_CONTROL")
		end

		if result ~= true then
			set_mod_enabled(DAM_Config.MOD_ID, true)
		end
		operation_thread = false
		refresh_installed_mods(host)
	end)

	refresh_installed_mods(host)
	return true
end

function DAM_ModControl.ValidateRuntime()
	return validate_runtime()
end

function DAM_ModControl.CancelOperation()
	if IsValidThread(operation_thread) and type(DeleteThread) == "function" then
		DeleteThread(operation_thread)
	end
	operation_thread = false
	return true
end

function DAM_ModControl.RestoreForModDisable()
	if DAM_State.HasPreviousLoadOrder() ~= true then
		return true
	end
	return restore_previous_mods(false, false)
end
