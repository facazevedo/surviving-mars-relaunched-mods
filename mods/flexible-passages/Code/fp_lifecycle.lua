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
		if validation.CheckRuntimeApi(reason) ~= true then
			return false, "required construction API unavailable"
		end
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
		return rules.RestoreVanillaBehavior(reason)
	end
	return true
end

function Lifecycle.Enable(reason)
	local st = State()
	if FlexiblePassages.Config.ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION ~= true then
		return Lifecycle.Disable(reason or "feature_disabled")
	end
	if st.active == true then
		return Lifecycle.ApplyModBehavior(reason or "enable_already_active")
	end

	local ok, err = Lifecycle.ApplyModBehavior(reason or "enable")
	st.active = ok == true

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
	st.active = false
	local restored = Lifecycle.RestoreVanillaBehavior(reason or "disable")

	local log = FlexiblePassages.DebugLog
	if log then
		log.Info("Lifecycle", "Disabled", {
			reason = reason,
			restored = restored,
		})
	end

	return restored
end

FlexiblePassages.Lifecycle = Lifecycle
