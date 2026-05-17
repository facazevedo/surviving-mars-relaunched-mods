-- Colonist diagnostic attributes.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining colonist helpers on repeated mod loads.
if FD.colonist_loaded then return end
FD.colonist_loaded = true

-- Create the colonist module namespace.
FD.Colonist = FD.Colonist or {}
local Colonist = FD.Colonist

-- Identity fields help correlate the visible colonist with engine references.
local identity_fields = { "name", "display_name", "handle", "id", "index", "Index" }

-- State fields are the future reset/delete-relevant references to inspect.
local state_fields = {
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
	"dome",
	"workplace",
	"residence",
	"reserved_residence",
	"assigned_to_service",
	"arriving",
	"emigration_dome",
	"emigration_elevator",
	"leaving_elevator",
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
	"dead",
}

-- Method availability tells us which safe reset paths exist on this object.
local methods = {
	"SetCommand",
	"ClearPath",
	"SetWorkplace",
	"SetResidence",
	"SetDome",
	"AssignToService",
	"delete",
}

-- Convert values to compact text for the display module.
local function Text(value)
	local value_type = type(value)
	if value_type == "table" or value_type == "userdata" then
		return FD.ObjectSummary(value)
	end
	return FD.SafeToString(value)
end

-- Append one diagnostic row.
local function Add(rows, label, value)
	rows[#rows + 1] = { label, Text(value) }
end

-- Call a boolean method safely for display.
local function MethodResult(obj, method)
	local fn = FD.ReadField(obj, method)
	if type(fn) ~= "function" then
		return "unavailable"
	end

	local ok, result = pcall(fn, obj)
	return ok and tostring(result and true or false) or "unavailable"
end

-- Detect colonist/human objects and exclude common non-human classes.
function Colonist.IsColonist(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	if class:find("Drone", 1, true)
		or class:find("Animal", 1, true)
		or class:find("Pet", 1, true)
		or class:find("Shuttle", 1, true)
		or class:find("Building", 1, true)
		or class:find("Dome", 1, true) then
		return false
	end

	return FD.IsKindOf(obj, "Colonist")
		or FD.IsKindOf(obj, "Human")
		or class:find("Colonist", 1, true) ~= nil
		or class:find("Human", 1, true) ~= nil
end

-- Show colonist diagnostics for the selected object.
function Colonist.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Colonist.GetRelevantAttributes(obj))
	end
end

-- Return all currently useful colonist diagnostic attributes.
function Colonist.GetRelevantAttributes(colonist)
	local rows = {}

	Add(rows, "Selected", FD.ObjectSummary(colonist))
	Add(rows, "Class", FD.ClassName(colonist))
	Add(rows, "Level 1", true)
	Add(rows, "Level 2", true)
	Add(rows, "reason", "colonist/human requires state reset before deletion")
	Add(rows, "valid", FD.IsObjectValid(colonist))

	-- Add identity values first so the selected object is easy to recognize.
	for _, field in ipairs(identity_fields) do
		Add(rows, field, FD.ReadField(colonist, field))
	end

	-- Add current command, assignment, movement, and traversal references.
	for _, field in ipairs(state_fields) do
		Add(rows, field, FD.ReadField(colonist, field))
	end

	Add(rows, "IsDead()", MethodResult(colonist, "IsDead"))
	Add(rows, "IsDying()", MethodResult(colonist, "IsDying"))

	-- Show which future reset/delete methods are present.
	for _, method in ipairs(methods) do
		Add(rows, method .. " method", type(FD.ReadField(colonist, method)) == "function")
	end

	Add(rows, "DoneObject global", type(FD.Global("DoneObject")) == "function")

	return {
		title = "Colonist deletion attributes",
		rows = rows,
	}
end
