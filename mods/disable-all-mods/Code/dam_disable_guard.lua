-- dam_disable_guard.lua
-- Restores all mod-owned state before vanilla disables this mod.

DAM_DisableGuard = {}

local MOD_ID = DAM_Config.MOD_ID
local original_turn_mod_off = false
local turn_mod_off_wrapper = false
local teardown_in_progress = false
local internal_self_disable_depth = 0
local guard_active = false

local function prepare_for_disable()
	if teardown_in_progress == true then
		return true
	end

	teardown_in_progress = true
	local restored = DAM_Lifecycle.RestoreVanillaBehavior()
	teardown_in_progress = false
	return restored
end

function DAM_DisableGuard.ApplyModBehavior()
	if turn_mod_off_wrapper and TurnModOff == turn_mod_off_wrapper then
		return true
	end
	if type(TurnModOff) ~= "function" then
		return false
	end

	local captured_turn_mod_off = TurnModOff
	original_turn_mod_off = captured_turn_mod_off
	turn_mod_off_wrapper = function(mod_id, ...)
		if guard_active == true
			and mod_id == MOD_ID
			and internal_self_disable_depth == 0
		then
			prepare_for_disable()
		end
		return captured_turn_mod_off(mod_id, ...)
	end
	guard_active = true
	TurnModOff = turn_mod_off_wrapper
	return true
end

function DAM_DisableGuard.RunWithSelfDisableSuppressed(callback)
	internal_self_disable_depth = internal_self_disable_depth + 1
	local ok, result, err = pcall(callback)
	internal_self_disable_depth = internal_self_disable_depth - 1
	if ok ~= true then
		error(result)
	end
	return result, err
end

function DAM_DisableGuard.RestoreVanillaBehavior()
	guard_active = false
	if turn_mod_off_wrapper and TurnModOff == turn_mod_off_wrapper then
		TurnModOff = original_turn_mod_off
	end
	original_turn_mod_off = false
	turn_mod_off_wrapper = false
	teardown_in_progress = false
	internal_self_disable_depth = 0
	return true
end
