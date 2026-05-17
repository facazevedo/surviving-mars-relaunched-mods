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
	"dome",
	"workplace",
	"residence",
	"reserved_residence",
	"assigned_to_service",
	"emigration_dome",
	"emigration_elevator",
	"leaving_elevator",
	"transport_ticket",
	"work_route",
	"lead_in_out",
	"lead_interrupted",
	"target",
	"goto_target",
	"destination",
	"holder",
	"building",
	"arriving",
	"visit_end_time",
	"visit_spot_end_time",
	"path",
	"passage",
	"passage_obj",
	"tunnel",
	"entering_tunnel",
	"leaving_tunnel",
	"fx_moving_target",
	"command_thread",
	"thread_running_destructors",
	"command_destructors",
	"command_queue",
	"forced_cmd_importance",
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

-- Append the dome owned by a related assignment object.
local function AddRelatedDome(rows, colonist, field)
	local related = FD.ReadField(colonist, field)
	local related_dome = FD.IsObjectValid(related) and FD.ReadField(related, "dome") or nil

	Add(rows, field .. ".dome", related_dome)
end

-- Call a boolean object method safely for deletion decisions.
local function MethodBool(obj, method)
	local fn = FD.ReadField(obj, method)
	if type(fn) ~= "function" then
		return nil
	end

	local ok, result = pcall(fn, obj)
	return ok and (result and true or false) or nil
end

-- Convert a boolean method result to compact inspector text.
local function MethodText(obj, method)
	local result = MethodBool(obj, method)
	return result == nil and "unavailable" or tostring(result)
end

-- Call an object method with arguments without trusting engine userdata.
local function CallMethod(obj, method, ...)
	local fn = FD.ReadField(obj, method)
	if type(fn) ~= "function" then
		return false
	end

	local ok = pcall(fn, obj, ...)
	return ok and true or false
end

-- Return true when a colonist is in a dead/dying state.
local function IsDeadOrDying(colonist)
	return FD.ReadField(colonist, "dead") == true
		or MethodBool(colonist, "IsDead") == true
		or MethodBool(colonist, "IsDying") == true
end

-- Clear relationship/path state before asking the game to erase the colonist.
local function PrepareForDelete(colonist)
	CallMethod(colonist, "AssignToService", false)
	CallMethod(colonist, "SetWorkplace", false)
	CallMethod(colonist, "SetResidence", false)
	CallMethod(colonist, "SetDome", false)
	CallMethod(colonist, "ClearPath")
end

-- Show a short Level 2 deletion result without forcing the panel on.
local function ShowDeleteMessage(message)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.ShowMessage(message)
	end
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

-- Delete a colonist through the safest available game path.
function Colonist.Delete(colonist)
	if not Colonist.IsColonist(colonist) then
		ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a colonist.")
		return false
	end

	local summary = FD.ObjectSummary(colonist)
	PrepareForDelete(colonist)

	-- Prefer the game's colonist erase command for normal cleanup.
	if not IsDeadOrDying(colonist)
		and type(FD.ReadField(colonist, "Erase")) == "function"
		and CallMethod(colonist, "SetCommand", "Erase") then
		ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleting colonist: " .. summary)
		return true
	end

	-- Fall back to direct object removal if the command path is unavailable.
	if CallMethod(colonist, "delete") then
		ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted colonist: " .. summary)
		return true
	end

	-- Use DoneObject as the final engine-level fallback.
	if FD.SafeCall(FD.Global("DoneObject"), colonist) then
		ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted colonist: " .. summary)
		return true
	end

	ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nCould not delete colonist: " .. summary)
	return false
end

-- Return all currently useful colonist diagnostic attributes.
function Colonist.GetRelevantAttributes(colonist)
	local rows = {}

	-- Read the configured level policy so the panel reflects real shortcut behavior.
	local object_type = "colonist"
	local object_level = FD.Config and FD.Config.GetObjectLevel and FD.Config.GetObjectLevel(object_type)
	local level_1_allowed = FD.Config
		and FD.Config.CanForceDeleteAtLevel
		and FD.Config.CanForceDeleteAtLevel(object_type, 1)
	local level_2_allowed = FD.Config
		and FD.Config.CanForceDeleteAtLevel
		and FD.Config.CanForceDeleteAtLevel(object_type, 2)

	Add(rows, "Selected", FD.ObjectSummary(colonist))
	Add(rows, "Class", FD.ClassName(colonist))
	Add(rows, "object_type", object_type)
	Add(rows, "configured level", object_level and ("Level " .. object_level) or "unconfigured")
	Add(rows, "Level 1 delete", level_1_allowed == true)
	Add(rows, "Level 2 delete", level_2_allowed == true)
	Add(rows, "reason", "colonist/human requires state reset before deletion")
	Add(rows, "valid", FD.IsObjectValid(colonist))

	-- Add identity values first so the selected object is easy to recognize.
	for _, field in ipairs(identity_fields) do
		Add(rows, field, FD.ReadField(colonist, field))
	end

	-- Add cross-dome assignment hints early because the panel clips lower rows.
	AddRelatedDome(rows, colonist, "workplace")
	AddRelatedDome(rows, colonist, "residence")
	AddRelatedDome(rows, colonist, "reserved_residence")
	AddRelatedDome(rows, colonist, "assigned_to_service")

	-- Add current command, assignment, movement, and traversal references.
	for _, field in ipairs(state_fields) do
		Add(rows, field, FD.ReadField(colonist, field))
	end

	Add(rows, "IsDead()", MethodText(colonist, "IsDead"))
	Add(rows, "IsDying()", MethodText(colonist, "IsDying"))

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
