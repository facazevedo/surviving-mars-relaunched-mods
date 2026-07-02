-- mn_debug.lua
-- Centralized, flag-gated debug logging. Output is printed only when the master
-- MN_Config.DEBUG flag is exactly true and (optionally) the scope flag is true.

MN_Debug = {}

local function MN_DebugConfig()
	return rawget(_G, "MN_Config") or {}
end

-- Render a table as readable key=value text (one level deep) for logs.
local function MN_DebugValue(value, depth)
	depth = depth or 0
	if type(value) ~= "table" then
		return tostring(value)
	end
	if depth > 1 then
		return "<table>"
	end
	local parts = {}
	for key, entry in pairs(value) do
		parts[#parts + 1] = tostring(key) .. "=" .. MN_DebugValue(entry, depth + 1)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

-- scope_flag is an optional MN_Config key (e.g. "DEBUG_SUPPRESSION"). When nil,
-- only the master DEBUG flag is required.
function MN_Debug.IsEnabled(scope_flag)
	local cfg = MN_DebugConfig()
	if cfg.DEBUG ~= true then
		return false
	end
	if scope_flag == nil then
		return true
	end
	return cfg[scope_flag] == true
end

function MN_Debug.Log(level, scope, message, data, scope_flag)
	if MN_Debug.IsEnabled(scope_flag) ~= true then
		return
	end
	local suffix = ""
	if data ~= nil then
		suffix = " " .. MN_DebugValue(data)
	end
	local name = MN_DebugConfig().MOD_DISPLAY_NAME or "Mute Notifications"
	print("[" .. tostring(name) .. "][" .. tostring(level) .. "][" .. tostring(scope) .. "] " .. tostring(message) .. suffix)
end

function MN_Debug.Info(scope, message, data, scope_flag)
	MN_Debug.Log("Info", scope, message, data, scope_flag)
end

function MN_Debug.Warn(scope, message, data, scope_flag)
	MN_Debug.Log("Warn", scope, message, data, scope_flag)
end

function MN_Debug.Error(scope, message, data, scope_flag)
	MN_Debug.Log("Error", scope, message, data, scope_flag)
end
