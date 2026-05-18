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
	"transport_task",
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

-- Fields that can keep a colonist command destructor pointing at deleted objects.
local related_delete_fields = {
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
	"transport_ticket",
	"transport_task",
	"work_route",
	"lead_in_out",
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

-- Clear train transport state without starting a replacement command.
local function ClearTransportTicket(colonist)
	local ticket = FD.ReadField(colonist, "transport_ticket")

	if type(ticket) == "table" or type(ticket) == "userdata" then
		for _, field in ipairs({ "src_station", "dst_station", "vehicle" }) do
			local obj = FD.ReadField(ticket, field)

			FD.RemoveObjectFromTable(FD.ReadField(obj, "colonists_inbound"), colonist)
			FD.RemoveObjectFromTable(FD.ReadField(obj, "waiting_for_train"), colonist)
			FD.RemoveObjectFromTable(FD.ReadField(obj, "units"), colonist)
		end
	end

	FD.WriteField(colonist, "transport_ticket", false)
	FD.WriteField(colonist, "work_route", false)
	FD.WriteField(colonist, "leave_early_for_work", false)
end

-- Clear shuttle transport task links that can wake after dome deletion.
local function ClearTransportTask(colonist)
	local task = FD.ReadField(colonist, "transport_task")

	if type(task) == "table" or type(task) == "userdata" then
		-- Leave the shuttle's current task object in place. CargoShuttle can
		-- still be inside TransportColonist and indexes transport_task.state.
		FD.WriteField(task, "state", "done")

		if FD.ReadField(task, "colonist") == colonist then
			FD.WriteField(task, "colonist", false)
		end
	end

	FD.WriteField(colonist, "transport_task", false)
end

-- Return whether an object or point has a valid game position.
local function HasValidPosition(value)
	local is_valid_pos = FD.Global("IsValidPos")
	if type(is_valid_pos) ~= "function" then
		return value ~= nil
	end

	return FD.SafeCall(is_valid_pos, value) and true or false
end

-- Return a safe position from one related object.
local function PositionFromObject(obj, colonist)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local exit_pos = false
	local get_exit = FD.ReadField(obj, "GetImmediateExitPos")
	if type(get_exit) == "function" then
		local ok, result = pcall(function()
			return get_exit(obj, colonist)
		end)
		exit_pos = ok and result or false
	end

	local pos = exit_pos or FD.CallMethod(obj, "GetPos") or FD.CallMethod(obj, "GetVisualPos")
	return HasValidPosition(pos) and pos or false
end

-- Place a colonist at a valid map position before clearing holder/building refs.
local function EnsureValidPosition(colonist)
	if HasValidPosition(colonist) then
		return true
	end

	for _, field in ipairs({ "holder", "building", "dome", "residence", "workplace" }) do
		local pos = PositionFromObject(FD.ReadField(colonist, field), colonist)
		if pos and type(FD.ReadField(colonist, "SetPos")) == "function" then
			FD.WriteField(colonist, "holder", false)
			if FD.CallObjectMethod(colonist, "SetPos", pos) then
				return HasValidPosition(colonist)
			end
		end
	end

	return false
end

-- Clear movement and visit state that may reference soon-deleted objects.
local function PrepareForRelatedObjectDelete(colonist)
	EnsureValidPosition(colonist)
	ClearTransportTicket(colonist)
	ClearTransportTask(colonist)
	PrepareForDelete(colonist)

	for _, field in ipairs(related_delete_fields) do
		FD.WriteField(colonist, field, false)
	end

	FD.WriteField(colonist, "lead_interrupted", true)
	EnsureValidPosition(colonist)
end

-- Return whether two objects are safely on the same map.
local function IsSameMapSafe(left, right)
	local is_same_map = FD.Global("IsSameMap")
	if type(is_same_map) ~= "function" then
		return true
	end

	return FD.SafeCall(is_same_map, left, right) and true or false
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

-- Patch the engine's invalid train-exit branch to remove colonists by value.
function Colonist.PatchExitVehicle()
	if Colonist.exit_vehicle_patched then
		return true
	end

	local colonist_class = FD.Global("Colonist")
	local original = FD.ReadField(colonist_class, "ExitVehicle")
	if type(original) ~= "function" then
		return false
	end

	colonist_class.ExitVehicle = function(self, vehicle, ...)
		local holder = FD.ReadField(self, "holder")

		if not holder or holder ~= vehicle or not IsSameMapSafe(self, vehicle) then
			FD.RemoveObjectFromTable(FD.ReadField(vehicle, "units"), self)
			FD.CallObjectMethod(self, "DiscardTransportTicket")
			return false
		end

		return original(self, vehicle, ...)
	end

	Colonist.exit_vehicle_patched = true
	return true
end

-- Patch stale building entry attempts so deleted passages do not assert later.
function Colonist.PatchEnterBuilding()
	if Colonist.enter_building_patched then
		return true
	end

	local colonist_class = FD.Global("Colonist")
	local original = FD.ReadField(colonist_class, "EnterBuilding")
	if type(original) ~= "function" then
		return false
	end

	colonist_class.EnterBuilding = function(self, building, ...)
		if not FD.IsObjectValid(self) or not FD.IsObjectValid(building) then
			return false
		end

		return original(self, building, ...)
	end

	Colonist.enter_building_patched = true
	return true
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

	PrepareForRelatedObjectDelete(colonist)
	FD.StopCommandNoDestructors(colonist)
	return true
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

-- Install the transport patch now and retry when game classes are finalized.
FD.ChainOnMsg("ClassesPostprocess", "force_delete_colonist_exit_vehicle", Colonist.PatchExitVehicle)
FD.ChainOnMsg("DataLoaded", "force_delete_colonist_exit_vehicle", Colonist.PatchExitVehicle)
FD.ChainOnMsg("ClassesPostprocess", "force_delete_colonist_enter_building", Colonist.PatchEnterBuilding)
FD.ChainOnMsg("DataLoaded", "force_delete_colonist_enter_building", Colonist.PatchEnterBuilding)
Colonist.PatchExitVehicle()
Colonist.PatchEnterBuilding()
