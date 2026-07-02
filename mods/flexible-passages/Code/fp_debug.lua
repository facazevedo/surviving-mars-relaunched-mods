-- Flexible Passages -- centralized debug logging.

local FlexiblePassages = rawget(_G, "FlexiblePassages")
if type(FlexiblePassages) ~= "table" then
	FlexiblePassages = {}
	rawset(_G, "FlexiblePassages", FlexiblePassages)
end

local PREFIX = "[Flexible Passages] "

local function GetConfig()
	return FlexiblePassages.Config or {}
end

local function IsEnabled(scope)
	local cfg = GetConfig()
	if cfg.DEBUG_LOGS ~= true then
		return false
	end
	if scope ~= nil and scope ~= "" then
		local scoped = cfg["DEBUG_" .. string.upper(tostring(scope))]
		if scoped == false then
			return false
		end
	end
	return true
end

local function FormatData(data)
	if type(data) ~= "table" then
		return ""
	end

	local keys = {}
	for key in pairs(data) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local parts = {}
	for i = 1, #keys do
		local key = keys[i]
		parts[#parts + 1] = tostring(key) .. "=" .. tostring(data[key])
	end

	if #parts == 0 then
		return ""
	end
	return " {" .. table.concat(parts, ", ") .. "}"
end

local function Emit(level, scope, message, data)
	if IsEnabled(scope) ~= true then
		return
	end

	local print_fn = rawget(_G, "print")
	if type(print_fn) ~= "function" then
		return
	end

	print_fn(PREFIX .. level .. tostring(scope) .. ": " .. tostring(message) .. FormatData(data))
end

local DebugLog = {}

function DebugLog.Info(scope, message, data)
	Emit("", scope, message, data)
end

function DebugLog.Warn(scope, message, data)
	Emit("WARN ", scope, message, data)
end

function DebugLog.Error(scope, message, data)
	Emit("ERROR ", scope, message, data)
end

FlexiblePassages.DebugLog = DebugLog
