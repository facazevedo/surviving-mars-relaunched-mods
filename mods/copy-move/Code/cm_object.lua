-- Copy Move safe engine-access boundary.
-- Thin, defensive wrappers around engine globals/objects so the rest of the mod
-- never throws when the game returns userdata, nil, or an invalidated object.
-- Patterned on the Force Delete mod's core helpers.

CopyMove = rawget(_G, "CopyMove") or {}
local CM = CopyMove
_G.CopyMove = CM

local Object = CM.Object or {}
CM.Object = Object

-- Return an engine global without creating it.
function Object.Global(name)
	return rawget(_G, name)
end

-- Call an optional engine function safely; returns false on failure/non-function.
function Object.SafeCall(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	local ok, result = pcall(fn, ...)
	return ok and result or false
end

-- Read a field from a table/userdata hybrid without throwing.
function Object.ReadField(obj, field)
	if not obj then
		return nil
	end
	local ok, value = pcall(function()
		return obj[field]
	end)
	return ok and value or nil
end

-- Call a zero-argument object method safely, returning its value or nil.
function Object.CallMethod(obj, method)
	local fn = Object.ReadField(obj, method)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, obj)
	if ok then
		return value
	end
	return nil
end

-- Whether an engine object is still valid (uses the engine IsValid when present).
function Object.IsValid(obj)
	if not obj then
		return false
	end
	local is_valid = rawget(_G, "IsValid")
	if type(is_valid) == "function" then
		return Object.SafeCall(is_valid, obj) and true or false
	end
	return type(obj) == "table" or type(obj) == "userdata"
end

-- Test a class relationship through the engine helper when available.
function Object.IsKindOf(obj, class_name)
	if not Object.IsValid(obj) then
		return false
	end
	return Object.SafeCall(rawget(_G, "IsKindOf"), obj, class_name) and true or false
end

-- Test membership in any of several classes.
function Object.IsKindOfClasses(obj, ...)
	if not Object.IsValid(obj) then
		return false
	end
	return Object.SafeCall(rawget(_G, "IsKindOfClasses"), obj, ...) and true or false
end

-- Return a compact class-like name for display and fallback matching.
function Object.ClassName(obj)
	if obj == nil then
		return "nil"
	end
	local name = Object.ReadField(obj, "class")
		or Object.ReadField(obj, "class_name")
		or Object.CallMethod(obj, "GetClass")
	if name ~= nil then
		return tostring(name)
	end
	return type(obj)
end
