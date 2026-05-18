-- Rover diagnostic attributes and Level 2 deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining rover helpers on repeated mod loads.
if FD.rover_loaded then return end
FD.rover_loaded = true

-- Create the rover module namespace.
FD.Rover = FD.Rover or {}
local Rover = FD.Rover

-- Class names cover the known rover family without matching rover buildings.
local rover_classes = {
	"BaseRover",
	"RCRover",
	"RCTransport",
	"ExplorerRover",
	"RCConstructor",
	"RCDriller",
	"RCHarvester",
	"RCSafari",
	"RCSolar",
	"RCSensor",
	"RCTerraformer",
	"AttackRover",
}

-- State fields capture command, route, resource, and city ownership state.
local state_fields = {
	"command",
	"city",
	"holder",
	"target",
	"goto_target",
	"destination",
	"command_center",
	"resource",
	"amount",
	"transport_route",
	"route_visited_sources",
	"route_visited_dests",
	"drones",
	"attached_drones",
	"repair_work_request",
	"malfunction",
	"destroyed",
	"dead",
	"command_thread",
	"thread_running_destructors",
	"command_destructors",
	"command_queue",
	"forced_cmd_importance",
}

-- Method availability tells us which rover cleanup/delete paths exist.
local methods = {
	"SetCommand",
	"ClearPath",
	"ClearRequests",
	"DisconnectFromCommandCenters",
	"DoDemolish",
	"ClearDone",
	"delete",
}

-- Fields that can keep rover commands pointing at stale deleted objects.
local related_delete_fields = {
	"holder",
	"target",
	"goto_target",
	"destination",
	"command_center",
	"transport_route",
	"route_visited_sources",
	"route_visited_dests",
	"operation_interrupted_reason",
	"unreachable_objects",
}

-- Return whether a class name describes a rover-like unit.
local function HasRoverClassName(class)
	for _, class_name in ipairs(rover_classes) do
		if class == class_name or class:find(class_name, 1, true) ~= nil then
			return true
		end
	end

	return class:find("Rover", 1, true) ~= nil
end

-- Return whether a class name is a rover-related building, marker, or helper.
local function HasExcludedClassName(class)
	return class:find("Building", 1, true) ~= nil
		or class:find("Hub", 1, true) ~= nil
		or class:find("Rocket", 1, true) ~= nil
		or class:find("Construction", 1, true) ~= nil
		or class:find("Marker", 1, true) ~= nil
end

-- Clear rover routing and command-center references before deletion.
local function PrepareForDelete(rover)
	FD.DeactivateUnitControlFor(rover)
	FD.CallObjectMethod(rover, "ClearPath")
	FD.CallObjectMethod(rover, "ClearRequests")
	FD.CallObjectMethod(rover, "DisconnectFromCommandCenters")

	for _, field in ipairs(related_delete_fields) do
		FD.WriteField(rover, field, false)
	end

	FD.StopCommandNoDestructors(rover)
end

-- Detect mobile rovers while excluding rover buildings and construction helpers.
function Rover.IsRover(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	if HasExcludedClassName(class) then
		return false
	end

	for _, class_name in ipairs(rover_classes) do
		if FD.IsKindOf(obj, class_name) then
			return true
		end
	end

	return HasRoverClassName(class)
end

-- Detach a rover from doomed objects and stop its current command.
function Rover.IdleForRelatedObjectDelete(rover)
	if not Rover.IsRover(rover) then
		return false
	end

	PrepareForDelete(rover)
	return true
end

-- Show rover diagnostics for the selected object.
function Rover.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Rover.GetRelevantAttributes(obj))
	end
end

-- Delete a rover through Level 2 cleanup and direct object removal fallback.
function Rover.Delete(rover)
	if not Rover.IsRover(rover) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a rover.")
		return false
	end

	local summary = FD.ObjectSummary(rover)
	PrepareForDelete(rover)

	if FD.Level2DeleteObject(rover) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted rover: " .. summary)
		return true
	end

	FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nCould not delete rover: " .. summary)
	return false
end

-- Return all currently useful rover diagnostic attributes.
function Rover.GetRelevantAttributes(rover)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, rover, "rover", "rovers require Level 2 because they are live command units")
	FD.AddFieldAttributes(rows, rover, FD.IDENTITY_FIELDS)
	FD.AddFieldAttributes(rows, rover, state_fields)
	FD.AddMethodDiagnostics(rows, rover, methods)

	return {
		title = "Rover attributes",
		rows = rows,
	}
end
