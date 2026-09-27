-- dam_lifecycle.lua
-- Idempotent high-level apply/restore lifecycle.

DAM_Lifecycle = {}

local MOD_ID = DAM_Config.MOD_ID
local applied = false
local unloaded = false

local function restore_subsystem(callback)
	local ok, result = pcall(callback)
	return ok == true and result == true
end

function DAM_Lifecycle.ApplyModBehavior()
	local guard_applied = DAM_DisableGuard.ApplyModBehavior()
	if guard_applied ~= true then
		return false
	end

	local ui_applied = DAM_UI.ApplyModBehavior()
	if ui_applied ~= true then
		DAM_DisableGuard.RestoreVanillaBehavior()
		return false
	end

	local was_applied = applied
	applied = true
	if was_applied ~= true then
		DAM_Debug.Info("Lifecycle", "Applied mod behavior", {
			control_enabled = DAM_Config.ENABLE_MOD_CONTROL,
			ui_enabled = DAM_Config.ENABLE_INSTALLED_MODS_BUTTON,
		}, "DEBUG_LOGS")
	else
		DAM_Debug.Info(
			"Lifecycle",
			"Revalidated mod behavior after game lifecycle event",
			nil,
			"DEBUG_LOGS"
		)
	end
	return true
end

function DAM_Lifecycle.RestoreVanillaBehavior()
	local operation_cancelled = restore_subsystem(DAM_ModControl.CancelOperation)
	local mods_restored = restore_subsystem(DAM_ModControl.RestoreForModDisable)
	local ui_restored = restore_subsystem(DAM_UI.RestoreVanillaBehavior)
	local guard_restored = restore_subsystem(DAM_DisableGuard.RestoreVanillaBehavior)
	applied = false
	DAM_Debug.Info("Lifecycle", "Restored vanilla Installed Mods template", nil, "DEBUG_LOGS")
	return operation_cancelled == true
		and mods_restored == true
		and ui_restored == true
		and guard_restored == true
end

function OnMsg.ModsReloaded()
	if unloaded ~= true then
		DAM_Lifecycle.ApplyModBehavior()
	end
end

function OnMsg.ModUnloadLua(mod_id)
	if mod_id ~= MOD_ID or unloaded == true then
		return
	end

	unloaded = true
	DAM_Lifecycle.RestoreVanillaBehavior()

	DAM_Main = nil
	DAM_Lifecycle = nil
	DAM_DisableGuard = nil
	DAM_UI = nil
	DAM_ModControl = nil
	DAM_State = nil
	DAM_Debug = nil
	DAM_Config = nil
end
