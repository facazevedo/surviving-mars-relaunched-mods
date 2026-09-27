-- dam_debug.lua
-- Structured debug logging gated by explicit boolean configuration flags.

DAM_Debug = {}

local function should_log(scope_flag)
	if DAM_Config.DEBUG_LOGS ~= true then
		return false
	end
	if scope_flag and DAM_Config[scope_flag] ~= true then
		return false
	end
	return true
end

local function format_value(value)
	local value_type = type(value)
	if value_type == "string" then
		return string.format("%q", value)
	end
	if value_type == "table" then
		return string.format("<table:%d>", #value)
	end
	return tostring(value)
end

local function format_data(data)
	if type(data) ~= "table" then
		return data ~= nil and (" {" .. format_value(data) .. "}") or ""
	end

	local keys = {}
	for key in pairs(data) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)

	local values = {}
	for index = 1, #keys do
		local key = keys[index]
		values[#values + 1] = tostring(key) .. "=" .. format_value(data[key])
	end
	return #values > 0 and (" {" .. table.concat(values, ", ") .. "}") or ""
end

local function write(level, scope, message, data, scope_flag)
	if should_log(scope_flag) ~= true then
		return
	end
	ModLog(string.format(
		"[%s][%s][%s] %s%s",
		DAM_Config.MOD_DISPLAY_NAME,
		level,
		scope,
		message,
		format_data(data)
	))
end

function DAM_Debug.Info(scope, message, data, scope_flag)
	write("INFO", scope, message, data, scope_flag)
end

function DAM_Debug.Warn(scope, message, data, scope_flag)
	write("WARN", scope, message, data, scope_flag)
end

function DAM_Debug.Error(scope, message, data, scope_flag)
	write("ERROR", scope, message, data, scope_flag)
end
