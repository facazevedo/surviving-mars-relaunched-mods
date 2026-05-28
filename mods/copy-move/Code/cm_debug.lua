-- Copy Move debug logging.
-- Centralized logging helper. Info/Warn print only when the relevant debug flag
-- is exactly true (see cm_config.lua). Error follows the master DEBUG_LOGS gate.

CopyMove = rawget(_G, "CopyMove") or {}
local CM = CopyMove
_G.CopyMove = CM

local DebugLog = CM.DebugLog or {}
CM.DebugLog = DebugLog

-- Convert any value to short display-safe text.
local function format_value(value)
	local t = type(value)
	if value == nil then
		return "nil"
	end
	if t == "string" or t == "number" or t == "boolean" then
		return tostring(value)
	end
	local ok, text = pcall(tostring, value)
	return ok and text or t
end

-- Convert structured data into readable "k=v, k=v" text.
local function format_data(data)
	if data == nil then
		return ""
	end
	if type(data) ~= "table" then
		return " | " .. format_value(data)
	end
	local parts = {}
	for k, v in pairs(data) do
		parts[#parts + 1] = format_value(k) .. "=" .. format_value(v)
	end
	if #parts == 0 then
		return ""
	end
	return " | " .. table.concat(parts, ", ")
end

-- Decide whether one log line should print.
local function enabled_for(level, scope)
	local cfg = CM.Config
	if type(cfg) ~= "table" then
		return false
	end
	if level == "ERROR" then
		return cfg.DEBUG_LOGS == true
	end
	return type(cfg.DebugEnabled) == "function" and cfg.DebugEnabled(scope) == true
end

local function emit(level, scope, message, data)
	if not enabled_for(level, scope) then
		return
	end
	local print_fn = rawget(_G, "print")
	if type(print_fn) ~= "function" then
		return
	end
	print_fn("[CopyMove][" .. level .. "][" .. format_value(scope) .. "] "
		.. format_value(message) .. format_data(data))
end

function DebugLog.Info(scope, message, data)
	emit("INFO", scope, message, data)
end

function DebugLog.Warn(scope, message, data)
	emit("WARN", scope, message, data)
end

function DebugLog.Error(scope, message, data)
	emit("ERROR", scope, message, data)
end
