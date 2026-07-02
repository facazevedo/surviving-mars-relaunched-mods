-- Flexible Passages -- high-level enable/disable flow.

local FlexiblePassages = rawget(_G, "FlexiblePassages")
if type(FlexiblePassages) ~= "table" then
	FlexiblePassages = {}
	rawset(_G, "FlexiblePassages", FlexiblePassages)
end

local Lifecycle = {}

local function State()
	FlexiblePassages.State = FlexiblePassages.State or {}
	return FlexiblePassages.State
end

function Lifecycle.IsActive()
	return State().active == true
end

function Lifecycle.ApplyModBehavior(reason)
	local validation = FlexiblePassages.Validation
	if validation and type(validation.CheckRuntimeApi) == "function" then
		validation.CheckRuntimeApi(reason)
	end

	local rules = FlexiblePassages.ConstructionRules
	if rules == nil or type(rules.ApplyModBehavior) ~= "function" then
		return false, "ConstructionRules unavailable"
	end

	return rules.ApplyModBehavior(reason)
end

function Lifecycle.RestoreVanillaBehavior(reason)
	local rules = FlexiblePassages.ConstructionRules
	if rules ~= nil and type(rules.RestoreVanillaBehavior) == "function" then
		rules.RestoreVanillaBehavior(reason)
	end
	return true
end

function Lifecycle.Enable(reason)
	local st = State()
	if st.active == true then
		return Lifecycle.ApplyModBehavior(reason or "enable_already_active")
	end

	st.active = true
	local ok, err = Lifecycle.ApplyModBehavior(reason or "enable")

	local log = FlexiblePassages.DebugLog
	if log then
		log.Info("Lifecycle", "Enable requested", {
			reason = reason,
			ok = ok,
			error = err,
		})
	end

	return ok, err
end

function Lifecycle.Disable(reason)
	local st = State()
	if st.active ~= true then
		return true
	end

	Lifecycle.RestoreVanillaBehavior(reason or "disable")
	st.active = false

	local log = FlexiblePassages.DebugLog
	if log then
		log.Info("Lifecycle", "Disabled", {
			reason = reason,
		})
	end

	return true
end

FlexiblePassages.Lifecycle = Lifecycle
