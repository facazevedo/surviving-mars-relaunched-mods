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
