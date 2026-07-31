-- dam_state.lua
-- Owns the supported per-mod persistent snapshot of the previous load order.

DAM_State = {}

local STORAGE_SCHEMA_VERSION = 1

local function copy_list(source)
	local result = {}
	if type(source) == "table" then
		for index = 1, #source do
			if type(source[index]) == "string" then
				result[#result + 1] = source[index]
			end
		end
	end
	return result
end

local function copy_table(source)
	local result = {}
	if type(source) == "table" then
		for key, value in pairs(source) do
			result[key] = value
		end
	end
	return result
end

local function replace_table(target, source)
	for key in pairs(target) do
		target[key] = nil
	end
	for key, value in pairs(source) do
		target[key] = value
	end
end

local function storage()
	if type(CurrentModStorageTable) ~= "table" then
		DAM_Debug.Error("State", "Persistent storage table is unavailable", nil, "DEBUG_STATE")
		return nil
	end
	return CurrentModStorageTable
end

local function persist(operation)
	if type(WriteModPersistentStorageTable) ~= "function" then
		DAM_Debug.Error("State", "Persistent storage writer is unavailable", {
			operation = operation,
		}, "DEBUG_STATE")
		return false, "WriteModPersistentStorageTable is unavailable"
	end

	local err = WriteModPersistentStorageTable()
	if err then
		DAM_Debug.Error("State", "Persistent state write failed", {
			error = err,
			operation = operation,
		}, "DEBUG_STATE")
		return false, err
	end
	return true
end

function DAM_State.HasPreviousLoadOrder()
	local data = storage()
	return data ~= nil
		and data.schema_version == STORAGE_SCHEMA_VERSION
		and data.restore_available == true
		and type(data.previous_load_order) == "table"
end

function DAM_State.GetPreviousLoadOrder()
	if DAM_State.HasPreviousLoadOrder() ~= true then
		return {}
	end
	return copy_list(CurrentModStorageTable.previous_load_order)
end

function DAM_State.CapturePreviousLoadOrder(load_order)
	local data = storage()
	if data == nil then
		return false, "persistent storage is unavailable"
	end

	local old_schema_version = data.schema_version
	local old_restore_available = data.restore_available
	local old_previous_load_order = data.previous_load_order

	data.schema_version = STORAGE_SCHEMA_VERSION
	data.restore_available = true
	data.previous_load_order = copy_list(load_order)

	local ok, err = persist("capture_previous_load_order")
	if ok ~= true then
		data.schema_version = old_schema_version
		data.restore_available = old_restore_available
		data.previous_load_order = old_previous_load_order
		return false, err
	end

	DAM_Debug.Info("State", "Captured previous active mod load order", {
		count = #data.previous_load_order,
		schema_version = STORAGE_SCHEMA_VERSION,
	}, "DEBUG_STATE")
	return true
end

function DAM_State.ClearPreviousLoadOrder()
	local data = storage()
	if data == nil then
		return false, "persistent storage is unavailable"
	end

	local old_data = copy_table(data)
	replace_table(data, {})

	local ok, err = persist("clear_previous_load_order")
	if ok ~= true then
		replace_table(data, old_data)
		return false, err
	end

	DAM_Debug.Info("State", "Cleared previous active mod load order", nil, "DEBUG_STATE")
	return true
end

function DAM_State.GetButtonText()
	if DAM_State.HasPreviousLoadOrder() == true then
		return DAM_Config.BUTTON_RESTORE_TEXT
	end
	return DAM_Config.BUTTON_DISABLE_TEXT
end
