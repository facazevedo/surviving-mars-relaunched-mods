-- Drone diagnostic attributes and Level 2 deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining drone helpers on repeated mod loads.
if FD.drone_loaded then return end
FD.drone_loaded = true

-- Create the drone module namespace.
FD.Drone = FD.Drone or {}
local Drone = FD.Drone

-- State fields capture command, ownership, task, and carried-resource state.
local state_fields = {
	"command",
	"command_center",
	"target",
	"goto_target",
	"fx_moving_target",
	"rogue_target",
	"holder",
	"building",
	"destination",
	"d_request",
	"s_request",
	"w_request",
	"picked_up_from_req",
	"request",
	"resource_request",
	"resource",
	"amount",
	"command_thread",
	"thread_running_destructors",
	"command_destructors",
	"command_queue",
	"dead",
}

-- Method availability tells us which safe delete paths exist on this object.
local methods = { "SetCommand", "DieNow", "delete" }

-- Direct object fields that can keep a drone targeting an object about to be deleted.
local delete_target_fields = {
	"command_center",
	"target",
	"goto_target",
	"fx_moving_target",
	"rogue_target",
	"holder",
	"building",
	"destination",
}

-- Request fields must be nil, not false, because request destructors index them.
local delete_request_fields = {
	"d_request",
	"s_request",
	"w_request",
	"picked_up_from_req",
	"request",
	"resource_request",
}

-- Stop a drone command without letting stale destructors touch deleted objects.
local function StopCommandNoDestructors(drone)
	FD.WriteField(drone, "command_destructors", false)
	FD.WriteField(drone, "command_queue", nil)
	FD.WriteField(drone, "forced_cmd_importance", nil)

	for _, thread in ipairs({
		FD.ReadField(drone, "command_thread"),
		FD.ReadField(drone, "thread_running_destructors"),
	}) do
		if FD.SafeCall(FD.Global("IsValidThread"), thread) then
			FD.SafeCall(FD.Global("DeleteThread"), thread)
		end
	end

	FD.WriteField(drone, "command_thread", nil)
	FD.WriteField(drone, "thread_running_destructors", nil)
	FD.WriteField(drone, "command", "Idle")
end

-- Clear target and request state before related objects are deleted.
local function PrepareForRelatedObjectDelete(drone)
	for _, field in ipairs(delete_target_fields) do
		FD.WriteField(drone, field, false)
	end

	for _, field in ipairs(delete_request_fields) do
		FD.WriteField(drone, field, nil)
	end

	FD.WriteField(drone, "resource", false)
	FD.WriteField(drone, "amount", 0)
end

-- Detect mobile drones while excluding drone-related buildings.
function Drone.IsDrone(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	if FD.IsKindOf(obj, "Drone") then
		return true
	end

	if class:find("Hub", 1, true)
		or class:find("Factory", 1, true)
		or class:find("Building", 1, true)
		or class:find("Station", 1, true) then
		return false
	end

	return class:find("Drone", 1, true) ~= nil
end

-- Show drone diagnostics for the selected object.
function Drone.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Drone.GetRelevantAttributes(obj))
	end
end

-- Detach a drone from doomed objects and ask it to stop current work.
function Drone.IdleForRelatedObjectDelete(drone)
	if not Drone.IsDrone(drone) then
		return false
	end

	local commanded = FD.CallObjectMethod(drone, "SetCommand", "Idle")
		or FD.CallObjectMethod(drone, "SetCommand", "Reset")

	if not commanded then
		StopCommandNoDestructors(drone)
	end

	PrepareForRelatedObjectDelete(drone)
	return true
end

-- Delete a drone through the safest available game path.
function Drone.Delete(drone)
	if not Drone.IsDrone(drone) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a drone.")
		return false
	end

	local summary = FD.ObjectSummary(drone)

	-- Prefer the game's drone death command for normal cleanup.
	if type(FD.ReadField(drone, "DieNow")) == "function"
		and FD.CallObjectMethod(drone, "SetCommand", "DieNow") then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleting drone: " .. summary)
		return true
	end

	-- Fall back to direct drone death if command dispatch is unavailable.
	if FD.CallObjectMethod(drone, "DieNow") then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted drone: " .. summary)
		return true
	end

	-- Fall back to direct object removal if the death path is unavailable.
	if FD.CallObjectMethod(drone, "delete") then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted drone: " .. summary)
		return true
	end

	-- Use DoneObject as the final engine-level fallback.
	if FD.SafeCall(FD.Global("DoneObject"), drone) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted drone: " .. summary)
		return true
	end

	FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nCould not delete drone: " .. summary)
	return false
end

-- Return all currently useful drone diagnostic attributes.
function Drone.GetRelevantAttributes(drone)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, drone, "drone")

	-- Add identity values first so the selected object is easy to recognize.
	FD.AddFieldAttributes(rows, drone, FD.IDENTITY_FIELDS)

	-- Add command, task, request, and carried-resource references.
	FD.AddFieldAttributes(rows, drone, state_fields)

	-- Show which future reset/delete methods are present.
	FD.AddMethodDiagnostics(rows, drone, methods)

	return {
		title = "Drone attributes",
		rows = rows,
	}
end
