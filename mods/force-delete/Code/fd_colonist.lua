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

-- Append the dome owned by a related assignment object.
local function AddRelatedDome(rows, colonist, field)
	local related = FD.ReadField(colonist, field)
	local related_dome = FD.IsObjectValid(related) and FD.ReadField(related, "dome") or nil

	FD.AddAttribute(rows, field .. ".dome", related_dome)
end

-- Return true when a colonist is in a dead/dying state.
local function IsDeadOrDying(colonist)
	return FD.ReadField(colonist, "dead") == true
		or FD.MethodBool(colonist, "IsDead") == true
		or FD.MethodBool(colonist, "IsDying") == true
end

-- Clear relationship/path state before asking the game to erase the colonist.
local function PrepareForDelete(colonist)
	FD.CallObjectMethod(colonist, "AssignToService", false)
	FD.CallObjectMethod(colonist, "SetWorkplace", false)
	FD.CallObjectMethod(colonist, "SetResidence", false)
	FD.CallObjectMethod(colonist, "SetDome", false)
	FD.CallObjectMethod(colonist, "ClearPath")
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

-- Detach a colonist from doomed objects and ask it to stop current work.
function Colonist.IdleForRelatedObjectDelete(colonist)
	if not Colonist.IsColonist(colonist) then
		return false
	end

	PrepareForDelete(colonist)
	return FD.CallObjectMethod(colonist, "SetCommand", "Idle")
end

-- Delete a colonist through the safest available game path.
function Colonist.Delete(colonist)
	if not Colonist.IsColonist(colonist) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a colonist.")
		return false
	end

	local summary = FD.ObjectSummary(colonist)
	PrepareForDelete(colonist)

	-- Prefer the game's colonist erase command for normal cleanup.
	if not IsDeadOrDying(colonist)
		and type(FD.ReadField(colonist, "Erase")) == "function"
		and FD.CallObjectMethod(colonist, "SetCommand", "Erase") then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleting colonist: " .. summary)
		return true
	end

	-- Fall back to direct object removal if the command path is unavailable.
	if FD.CallObjectMethod(colonist, "delete") then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted colonist: " .. summary)
		return true
	end

	-- Use DoneObject as the final engine-level fallback.
	if FD.SafeCall(FD.Global("DoneObject"), colonist) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted colonist: " .. summary)
		return true
	end

	FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nCould not delete colonist: " .. summary)
	return false
end

-- Return all currently useful colonist diagnostic attributes.
function Colonist.GetRelevantAttributes(colonist)
	local rows = {}

	FD.AddCommonObjectAttributes(
		rows,
		colonist,
		"colonist",
		"colonist/human requires state reset before deletion"
	)

	-- Add identity values first so the selected object is easy to recognize.
	FD.AddFieldAttributes(rows, colonist, FD.IDENTITY_FIELDS)

	-- Add cross-dome assignment hints early because the panel clips lower rows.
	AddRelatedDome(rows, colonist, "workplace")
	AddRelatedDome(rows, colonist, "residence")
	AddRelatedDome(rows, colonist, "reserved_residence")
	AddRelatedDome(rows, colonist, "assigned_to_service")

	-- Add current command, assignment, movement, and traversal references.
	FD.AddFieldAttributes(rows, colonist, state_fields)

	-- Show which future reset/delete methods are present.
	FD.AddMethodDiagnostics(rows, colonist, methods)

	return {
		title = "Colonist attributes",
		rows = rows,
	}
end
