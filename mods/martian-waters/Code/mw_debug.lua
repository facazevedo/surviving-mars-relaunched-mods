-- MartianWaters -- centralized debug logging.
--
-- DebugLog.Info/Warn/Error(scope, message, data) print "[MartianWaters] <scope>:
-- <message> {k=v, ...}" only when MartianWaters.Config.DEBUG_LOGS is exactly true
-- (and the optional scoped flag DEBUG_<SCOPE> is not explicitly false). Config
-- is read lazily on each call so log gating always reflects the live config.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	MartianWaters = {}
	rawset(_G, "MartianWaters", MartianWaters)
end

local PREFIX = "[MartianWaters] "

local function current_config()
	return MartianWaters.Config or {}
end

local function enabled(scope)
	local cfg = current_config()
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

local function format_data(data)
	if type(data) ~= "table" then
		return ""
	end
	local keys = {}
	for k in pairs(data) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for i = 1, #keys do
		parts[i] = tostring(keys[i]) .. "=" .. tostring(data[keys[i]])
	end
	if #parts == 0 then
		return ""
	end
	return " {" .. table.concat(parts, ", ") .. "}"
end

local function emit(level, scope, message, data)
	if not enabled(scope) then
		return
	end
	local print_fn = rawget(_G, "print")
	if type(print_fn) ~= "function" then
		return
	end
	print_fn(PREFIX .. level .. tostring(scope) .. ": " .. tostring(message) .. format_data(data))
end

local DebugLog = {}

function DebugLog.Info(scope, message, data)
	emit("", scope, message, data)
end

function DebugLog.Warn(scope, message, data)
	emit("WARN ", scope, message, data)
end

function DebugLog.Error(scope, message, data)
	emit("ERROR ", scope, message, data)
end

MartianWaters.DebugLog = DebugLog
