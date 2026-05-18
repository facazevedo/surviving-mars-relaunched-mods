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

-- Object fields can safely use false as the engine's empty reference value.
local object_reference_fields = {
	"command_center",
	"target",
	"goto_target",
	"fx_moving_target",
	"rogue_target",
	"holder",
	"building",
	"destination",
}

-- Request fields use nil so delayed request cleanup never indexes booleans.
local request_reference_fields = {
	"d_request",
	"s_request",
	"w_request",
	"picked_up_from_req",
	"request",
	"resource_request",
}

-- Write the same value to a list of fields.
local function ClearFields(obj, fields, value)
	for _, field in ipairs(fields) do
		FD.WriteField(obj, field, value)
	end
end

-- Clear target and request state before related objects are deleted.
local function PrepareForRelatedObjectDelete(drone)
	ClearFields(drone, object_reference_fields, false)
	ClearFields(drone, request_reference_fields, nil)
	FD.WriteField(drone, "resource", false)
	FD.WriteField(drone, "amount", 0)
end

-- Show one standard drone delete result message.
local function ShowDeleteResult(status, summary)
	FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\n" .. status .. " drone: " .. summary)
end

-- Ask the game's command system to kill the drone when that path exists.
local function TryCommandedDeath(drone)
	return type(FD.ReadField(drone, "DieNow")) == "function"
		and FD.CallObjectMethod(drone, "SetCommand", "DieNow")
end

-- Fall back through direct drone deletion methods.
local function TryDirectDelete(drone)
	if FD.CallObjectMethod(drone, "DieNow") then
		return true
	end

	if FD.CallObjectMethod(drone, "delete") then
		return true
	end

	return FD.SafeCall(FD.Global("DoneObject"), drone)
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

-- Detach a drone from doomed objects without running stale request destructors.
function Drone.IdleForRelatedObjectDelete(drone)
	if not Drone.IsDrone(drone) then
		return false
	end

	FD.StopCommandNoDestructors(drone)
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
	if TryCommandedDeath(drone) then
		ShowDeleteResult("Deleting", summary)
		return true
	end

	if TryDirectDelete(drone) then
		ShowDeleteResult("Deleted", summary)
		return true
	end

	ShowDeleteResult("Could not delete", summary)
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
