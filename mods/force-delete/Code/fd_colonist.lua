-- Colonist-specific diagnostics for Force Delete.
-- This module detects colonists and extracts read-only state that will matter
-- later when safe reset/deletion logic is implemented.

-- ============================================================================
-- Module setup
-- ============================================================================

local FD = ForceDelete
if not FD then return end

if FD.colonist_loaded then return end
FD.colonist_loaded = true

FD.Colonist = FD.Colonist or {}

local Colonist = FD.Colonist

-- Convert one attribute value into compact display text without walking nested
-- object graphs or triggering unsafe userdata iteration.
local function value_to_text(value)
	local value_type = type(value)
	if value == nil or value_type == "string" or value_type == "number" or value_type == "boolean" then
		return FD.SafeToString(value)
	end

	if value_type == "table" or value_type == "userdata" then
		return FD.ObjectSummary(value)
	end

	return FD.SafeToString(value)
end

-- Append one formatted key/value row to the attributes payload.
local function add_row(rows, label, value)
	rows[#rows + 1] = { label, value_to_text(value) }
end

-- Append a group of rows returned by one of the focused attribute collectors.
local function add_rows(rows, source)
	for _, row in ipairs(source or {}) do
		rows[#rows + 1] = row
	end
end

-- Call a boolean-style method such as IsDead safely, reporting unavailable
-- instead of asserting or guessing when the method is missing.
local function method_result(obj, method_name)
	local method = FD.ReadField(obj, method_name)
	if type(method) ~= "function" then
		return "unavailable"
	end

	local ok, result = pcall(method, obj)
	if not ok then
		return "unavailable"
	end

	return result and "true" or "false"
end

-- ============================================================================
-- Colonist detection and dispatch entry point
-- ============================================================================

-- Detect colonist/human objects while avoiding common non-human classes.
function Colonist.IsColonist(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class_name = FD.ClassName(obj)
	for _, excluded in ipairs({ "Drone", "Animal", "Pet", "Shuttle", "Hub", "Building", "Dome", "Passage", "Rover" }) do
		if class_name:find(excluded, 1, true) then
			return false
		end
	end

	if FD.IsKindOf(obj, "Colonist") or FD.IsKindOf(obj, "Human") then
		return true
	end

	return class_name:find("Colonist", 1, true) ~= nil
		or class_name:find("Human", 1, true) ~= nil
end

-- Entry point used by the main dispatcher when a colonist is selected.
function Colonist.OnSelected(obj)
	if not FD.DisplayAttributes then
		return
	end

	FD.DisplayAttributes.Show(Colonist.GetRelevantAttributes(obj))
end

-- Report whether a method exists without invoking it. Future reset code needs
-- this to choose safe engine APIs before direct field cleanup.
function Colonist.MethodExists(obj, method_name)
	return type(FD.ReadField(obj, method_name)) == "function"
end

-- ============================================================================
-- Attribute collectors
-- ============================================================================

-- Collect high-level reset/deletion eligibility details for the selected human.
function Colonist.GetResetStateAttributes(colonist)
	local rows = {}
	add_row(rows, "Level 1", true)
	add_row(rows, "Level 2", true)
	add_row(rows, "reason", "colonist/human requires state reset before deletion")
	add_row(rows, "valid", FD.IsObjectValid(colonist))
	return rows
end

-- Collect command and target state that may need to be neutralized later.
function Colonist.GetCommandAttributes(colonist)
	local rows = {}
	for _, field in ipairs({
		"command",
		"command_thread",
		"thread_running_destructors",
		"command_destructors",
		"command_queue",
		"forced_cmd_importance",
		"target",
		"goto_target",
		"fx_moving_target",
		"destination",
		"holder",
		"building",
	}) do
		add_row(rows, field, FD.ReadField(colonist, field))
	end
	return rows
end

-- Collect dome, workplace, residence, and service assignment state.
function Colonist.GetResidenceWorkplaceAttributes(colonist)
	local rows = {}
	for _, field in ipairs({
		"dome",
		"workplace",
		"residence",
		"reserved_residence",
		"assigned_to_service",
		"arriving",
		"emigration_dome",
		"emigration_elevator",
		"leaving_elevator",
	}) do
		add_row(rows, field, FD.ReadField(colonist, field))
	end
	return rows
end

-- Collect traversal and transport references that can keep a colonist attached
-- to a passage, dome, or building scheduled for future force deletion.
function Colonist.GetTransportAttributes(colonist)
	local rows = {}
	for _, field in ipairs({
		"transport_ticket",
		"work_route",
		"lead_in_out",
		"lead_interrupted",
		"visit_end_time",
		"visit_spot_end_time",
		"path",
		"passage",
		"passage_obj",
		"tunnel",
		"entering_tunnel",
		"leaving_tunnel",
	}) do
		add_row(rows, field, FD.ReadField(colonist, field))
	end
	return rows
end

-- Collect death/dying state using method calls only when they are available.
-- Future deletion code must not send idle commands to dead or dying units.
function Colonist.GetHealthStateAttributes(colonist)
	local rows = {}
	add_row(rows, "dead", FD.ReadField(colonist, "dead"))
	add_row(rows, "IsDead()", method_result(colonist, "IsDead"))
	add_row(rows, "IsDying()", method_result(colonist, "IsDying"))
	return rows
end

-- Build the full structured attribute payload consumed by the display module.
-- All values are compact strings or simple scalars; nested objects are summarized.
function Colonist.GetRelevantAttributes(colonist)
	local rows = {}

	add_row(rows, "Selected", FD.ObjectSummary(colonist))
	add_row(rows, "Class", FD.ClassName(colonist))
	add_row(rows, "name", FD.ReadField(colonist, "name"))
	add_row(rows, "display_name", FD.ReadField(colonist, "display_name"))
	add_row(rows, "handle", FD.ReadField(colonist, "handle"))
	add_row(rows, "id", FD.ReadField(colonist, "id"))
	add_row(rows, "index", FD.ReadField(colonist, "index") or FD.ReadField(colonist, "Index"))

	add_rows(rows, Colonist.GetResetStateAttributes(colonist))
	add_rows(rows, Colonist.GetCommandAttributes(colonist))
	add_rows(rows, Colonist.GetResidenceWorkplaceAttributes(colonist))
	add_rows(rows, Colonist.GetTransportAttributes(colonist))
	add_rows(rows, Colonist.GetHealthStateAttributes(colonist))

	for _, method_name in ipairs({
		"SetCommand",
		"ClearPath",
		"SetWorkplace",
		"SetResidence",
		"SetDome",
		"AssignToService",
		"delete",
	}) do
		add_row(rows, method_name .. " method", Colonist.MethodExists(colonist, method_name))
	end

	add_row(rows, "DoneObject global", type(FD.Global("DoneObject")) == "function")

	return {
		title = "Colonist deletion attributes",
		rows = rows,
	}
end
