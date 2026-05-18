-- Dome diagnostics and staged Level 2 deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining dome helpers on repeated mod loads.
if FD.dome_loaded then return end
FD.dome_loaded = true

-- Create the dome module namespace.
FD.Dome = FD.Dome or {}
local Dome = FD.Dome

-- State fields capture dome identity, passage, and demolition state.
local state_fields = {
	"city",
	"labels",
	"passages",
	"connected_passages",
	"cupola_interior_marker",
	"demolishing",
	"demolishing_countdown",
	"demolishing_thread",
}

-- Fields that commonly reference domes from passages or passage elements.
local dome_reference_fields = {
	"start_dome",
	"end_dome",
	"dome",
	"parent_dome",
}

-- Fields that commonly contain passage pieces or connected objects.
local passage_piece_fields = {
	"elements",
	"elements_under_construction",
	"start_el",
	"end_el",
}

-- Fields that can keep colonists targeting a soon-deleted dome object.
local colonist_reference_fields = {
	"dome",
	"workplace",
	"residence",
	"reserved_residence",
	"assigned_to_service",
	"emigration_dome",
	"arriving",
	"holder",
	"building",
	"target",
	"goto_target",
	"destination",
	"passage",
	"passage_obj",
	"tunnel",
	"entering_tunnel",
	"leaving_tunnel",
}

-- Table fields that can keep colonists routing through a doomed object.
local colonist_reference_table_fields = {
	"transport_ticket",
	"work_route",
}

-- Transport ticket fields can be userdata-backed, so read them explicitly.
local colonist_transport_ticket_fields = {
	"src_station",
	"dst_station",
	"destination",
	"vehicle",
	"param",
}

-- Shuttle transport task fields can point colonists back at doomed domes.
local colonist_transport_task_fields = {
	"source_dome",
	"dest_dome",
	"shuttle",
	"dest_pos",
}

-- Commands that can keep hidden building/passage arguments on the command stack.
local colonist_transport_commands = {
	BoardVehicle = true,
	DisembarkOnArrival = true,
	ExitVehicle = true,
	GoToDome = true,
	GoToStation = true,
	MigrateByTrain = true,
	TransportByFoot = true,
	UseElevator = true,
	WaitForTransport = true,
}

-- Fields that can keep drones targeting a soon-deleted dome object.
local drone_reference_fields = {
	"command_center",
	"target",
	"goto_target",
	"fx_moving_target",
	"rogue_target",
	"holder",
	"building",
	"destination",
}

-- Request fields that can indirectly point drones at soon-deleted objects.
local drone_request_fields = {
	"d_request",
	"s_request",
	"w_request",
	"picked_up_from_req",
	"request",
	"resource_request",
}

-- Fields that can keep shuttles targeting a soon-deleted dome object.
local shuttle_reference_fields = {
	"holder",
	"target",
	"goto_target",
	"destination",
	"dest_dome",
	"hub",
	"shuttle_hub",
}

-- Transport task fields that can point shuttles at deleted domes.
local shuttle_task_reference_fields = {
	"source_dome",
	"dest_dome",
	"colonist",
	"dest_pos",
}

-- Return whether a class name looks like a passage controller or element.
local function HasPassageClassName(obj)
	return FD.ClassName(obj):find("Passage", 1, true) ~= nil
end

-- Return a compact stable id for diagnostics and staged logs.
local function ObjectId(obj)
	return FD.ReadField(obj, "handle")
		or FD.ReadField(obj, "id")
		or FD.ReadField(obj, "Index")
		or FD.ReadField(obj, "index")
		or FD.ObjectSummary(obj)
end

-- Visit object-like values in an engine table without scanning indefinitely.
-- A callback may return true to stop the scan early.
local function ForEachTableObject(list, callback)
	if type(list) ~= "table" or type(callback) ~= "function" then
		return
	end

	local scanned = 0

	-- Validate each candidate before handing it to caller-owned logic.
	local function visit(obj)
		if FD.IsObjectValid(obj) then
			return callback(obj) == true
		end

		return false
	end

	for _, obj in ipairs(list) do
		scanned = scanned + 1
		if scanned > FD.MAX_SCAN then
			return
		end

		if visit(obj) then
			return
		end
	end

	for key, value in pairs(list) do
		scanned = scanned + 1
		if scanned > FD.MAX_SCAN then
			return
		end

		if visit(key) or visit(value) then
			return
		end
	end
end

-- Disable night-light state on any object that supports the light API.
function Dome.DisableNightLights(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	-- Prefer the engine-owned night-light switch; it owns any attach cleanup.
	local disabled = FD.CallObjectMethod(obj, "SetIsNightLightPossible", false, true)

	if not disabled then
		disabled = FD.CallObjectMethod(obj, "NightLightDisable", true)
	end

	FD.CallObjectMethod(obj, "SetSIModulation", 0)
	return disabled
end

-- Disable dome and internal-building night lights before staged deletion.
function Dome.DisableDomeLights(dome, internal_buildings)
	if not Dome.IsDome(dome) then
		return 0
	end

	local disabled = 0

	if Dome.DisableNightLights(dome) then
		disabled = disabled + 1
	end

	for _, building in ipairs(internal_buildings or {}) do
		if Dome.DisableNightLights(building) then
			disabled = disabled + 1
		end
	end

	return disabled
end

-- Return whether an object directly references a selected dome.
local function ObjectReferencesDome(obj, dome)
	for _, field in ipairs(dome_reference_fields) do
		if FD.ReadField(obj, field) == dome then
			return true
		end
	end

	return false
end

-- Return whether a passage or passage piece is connected to a selected dome.
local function PassageConnectsToDome(obj, dome)
	if ObjectReferencesDome(obj, dome) then
		return true
	end

	for _, field in ipairs(passage_piece_fields) do
		local value = FD.ReadField(obj, field)

		if FD.IsObjectValid(value) and ObjectReferencesDome(value, dome) then
			return true
		end

		local found = false
		ForEachTableObject(value, function(piece)
			if ObjectReferencesDome(piece, dome) then
				found = true
			end
		end)

		if found then
			return true
		end
	end

	return false
end

-- Return whether an object should be treated as a passage candidate.
local function IsPassageCandidate(obj)
	return FD.IsObjectValid(obj)
		and HasPassageClassName(obj)
		and (
			type(FD.ReadField(obj, "elements")) == "table"
			or FD.ReadField(obj, "start_dome") ~= nil
			or FD.ReadField(obj, "end_dome") ~= nil
			or FD.ReadField(obj, "passage_obj") ~= nil
		)
end

-- Add a passage and its directly owned pieces to the staged passage list.
local function AddPassageWithPieces(passages, seen, passage)
	if not FD.AddUniqueObject(passages, seen, passage) then
		return
	end

	for _, field in ipairs(passage_piece_fields) do
		local value = FD.ReadField(passage, field)

		if FD.IsObjectValid(value) then
			FD.AddUniqueObject(passages, seen, value)
		else
			ForEachTableObject(value, function(piece)
				FD.AddUniqueObject(passages, seen, piece)
			end)
		end
	end
end

-- Scan one object/table source for passages connected to the selected dome.
local function CollectPassagesFromSource(passages, seen, source, dome)
	if FD.IsObjectValid(source) then
		if IsPassageCandidate(source) and PassageConnectsToDome(source, dome) then
			AddPassageWithPieces(passages, seen, source)
		end

		local passage_obj = FD.ReadField(source, "passage_obj")
		if IsPassageCandidate(passage_obj) and PassageConnectsToDome(passage_obj, dome) then
			AddPassageWithPieces(passages, seen, passage_obj)
		end

		return
	end

	ForEachTableObject(source, function(obj)
		CollectPassagesFromSource(passages, seen, obj, dome)
	end)
end

-- Return city/colony containers worth scanning for selected dome references.
local function CandidateContainers(dome)
	return {
		FD.ReadField(dome, "city"),
		FD.Global("UICity"),
		FD.Global("MainCity"),
		FD.Global("SelectedCity"),
		FD.Global("UIColony"),
	}
end

-- Return passages connected to one dome, optionally scanning global labels.
local function CollectConnectedPassages(dome, include_global_labels)
	local passages = {}
	local seen = {}

	for _, field in ipairs({ "passages", "connected_passages", "children", "attached_buildings" }) do
		CollectPassagesFromSource(passages, seen, FD.ReadField(dome, field), dome)
	end

	local labels = FD.ReadField(dome, "labels")
	if type(labels) == "table" then
		for _, label_list in pairs(labels) do
			CollectPassagesFromSource(passages, seen, label_list, dome)
		end
	end

	if include_global_labels then
		local seen_containers = {}
		for _, container in ipairs(CandidateContainers(dome)) do
			if container and not seen_containers[container] then
				seen_containers[container] = true

				local container_labels = FD.ReadField(container, "labels")
				if type(container_labels) == "table" then
					for _, label_list in pairs(container_labels) do
						CollectPassagesFromSource(passages, seen, label_list, dome)
					end
				end
			end
		end
	end

	return passages
end

-- Return all known passages and passage elements connected to one dome.
function Dome.CollectConnectedPassages(dome)
	return CollectConnectedPassages(dome, true)
end

-- Return nearby passage references for the inspector without global scans.
function Dome.CollectInspectorPassages(dome)
	return CollectConnectedPassages(dome, false)
end

-- Return the number of passage controllers connected to one dome.
function Dome.CountConnectedPassages(dome)
	local connected_passages = FD.ReadField(dome, "connected_passages")
	local seen = {}
	local count = 0

	local function count_passage(passage)
		if FD.IsObjectValid(passage)
			and not seen[passage]
			and HasPassageClassName(passage)
			and type(FD.ReadField(passage, "elements")) == "table"
		then
			seen[passage] = true
			count = count + 1
		end
	end

	if type(connected_passages) == "table" then
		for passage in pairs(connected_passages) do
			count_passage(passage)
		end

		return count
	end

	for _, obj in ipairs(Dome.CollectInspectorPassages(dome)) do
		count_passage(FD.ReadField(obj, "passage_obj") or obj)
	end

	return count
end

-- Return whether an object is the main passage controller, not a passage piece.
function Dome.IsPassageController(obj)
	return FD.IsObjectValid(obj)
		and HasPassageClassName(obj)
		and type(FD.ReadField(obj, "elements")) == "table"
end

-- Return the main passage controller for a passage object or passage piece.
function Dome.PassageControllerFor(obj)
	if Dome.IsPassageController(obj) then
		return obj
	end

	local passage_obj = FD.ReadField(obj, "passage_obj")
	if Dome.IsPassageController(passage_obj) then
		return passage_obj
	end

	return false
end

-- Return only connected passage controllers from the dome connection table.
function Dome.CollectConnectedPassageControllers(dome)
	local connected_passages = FD.ReadField(dome, "connected_passages")
	local passages = {}
	local seen = {}

	if type(connected_passages) == "table" then
		for key, value in pairs(connected_passages) do
			FD.AddUniqueObject(passages, seen, Dome.PassageControllerFor(key))
			FD.AddUniqueObject(passages, seen, Dome.PassageControllerFor(value))
		end
	end

	return passages
end

-- Return ids for a collection of passage objects.
function Dome.PassageIds(passages)
	local ids = {}

	for _, passage in ipairs(passages or {}) do
		ids[#ids + 1] = FD.SafeToString(ObjectId(passage))
	end

	return table.concat(ids, ", ")
end

-- Return internal buildings owned by one dome, optionally scanning dome labels.
local function CollectInternalBuildings(dome, include_labels)
	local buildings = {}
	local seen = {}

	local function add(obj)
		if FD.InternalBuilding
			and FD.InternalBuilding.IsInternalBuilding(obj)
			and (
				FD.ReadField(obj, "dome") == dome
				or FD.ReadField(obj, "parent_dome") == dome
				or FD.ReadField(obj, "parent") == dome
			) then
			FD.AddUniqueObject(buildings, seen, obj)
		end
	end

	if include_labels then
		local labels = FD.ReadField(dome, "labels")
		if type(labels) == "table" then
			for _, label_list in pairs(labels) do
				ForEachTableObject(label_list, add)
			end
		end
	end

	for _, field in ipairs({ "buildings", "inside_buildings", "service_buildings", "residence_buildings", "workplace_buildings", "children" }) do
		ForEachTableObject(FD.ReadField(dome, field), add)
	end

	return buildings
end

-- Return all internal buildings owned by one dome.
function Dome.CollectInternalBuildings(dome)
	return CollectInternalBuildings(dome, true)
end

-- Return direct internal-building references for the inspector.
function Dome.CollectInspectorInternalBuildings(dome)
	return CollectInternalBuildings(dome, false)
end

-- Add one valid object to a set used for target-reference checks.
function Dome.AddTarget(targets, obj)
	if FD.IsObjectValid(obj) then
		targets[obj] = true
	end
end

-- Build the set of objects that units must stop targeting before deletion.
function Dome.BuildDeletionTargetSet(dome, passages, internal_buildings)
	local targets = {}

	Dome.AddTarget(targets, dome)

	for _, obj in ipairs(passages or {}) do
		Dome.AddTarget(targets, obj)
	end

	for _, obj in ipairs(internal_buildings or {}) do
		Dome.AddTarget(targets, obj)
	end

	return targets
end

-- Return whether an object belongs to the dome being deleted.
function Dome.ObjectBelongsToDome(obj, dome)
	return FD.IsObjectValid(obj)
		and (
			obj == dome
			or FD.ReadField(obj, "dome") == dome
			or FD.ReadField(obj, "parent_dome") == dome
			or FD.ReadField(obj, "parent") == dome
		)
end

-- Return whether one value points at a doomed dome object.
function Dome.ValueTargetsDomeDelete(value, dome, targets)
	if not FD.IsObjectValid(value) then
		return false
	end

	if targets[value] or Dome.ObjectBelongsToDome(value, dome) then
		return true
	end

	local passage = Dome.PassageControllerFor(value)
	return passage and targets[passage] or false
end

-- Return whether any listed field points at a doomed dome object.
function Dome.FieldsTargetDomeDelete(obj, fields, dome, targets)
	for _, field in ipairs(fields or {}) do
		if Dome.ValueTargetsDomeDelete(FD.ReadField(obj, field), dome, targets) then
			return true
		end
	end

	return false
end

-- Return whether one table field contains a doomed dome object.
function Dome.TableTargetsDomeDelete(list, dome, targets)
	local found = false

	ForEachTableObject(list, function(value)
		if Dome.ValueTargetsDomeDelete(value, dome, targets) then
			found = true
			return true
		end
	end)

	return found
end

-- Return whether any listed table field contains a doomed dome object.
function Dome.TableFieldsTargetDomeDelete(obj, fields, dome, targets)
	for _, field in ipairs(fields or {}) do
		if Dome.TableTargetsDomeDelete(FD.ReadField(obj, field), dome, targets) then
			return true
		end
	end

	return false
end

-- Return whether a colonist transport ticket points at doomed dome objects.
function Dome.ColonistTransportTicketTargetsDomeDelete(ticket, dome, targets)
	if type(ticket) ~= "table" and type(ticket) ~= "userdata" then
		return false
	end

	return Dome.FieldsTargetDomeDelete(ticket, colonist_transport_ticket_fields, dome, targets)
end

-- Return whether a colonist shuttle task points at doomed dome objects.
function Dome.ColonistTransportTaskTargetsDomeDelete(task, dome, targets)
	if type(task) ~= "table" and type(task) ~= "userdata" then
		return false
	end

	return Dome.FieldsTargetDomeDelete(task, colonist_transport_task_fields, dome, targets)
end

-- Return whether a colonist command may hold hidden dome/passage arguments.
function Dome.ColonistHasTransportCommand(colonist)
	return colonist_transport_commands[FD.ReadField(colonist, "command")] == true
end

-- Return whether a colonist is currently tied to the dome deletion target set.
function Dome.ColonistTargetsDomeDelete(colonist, dome, targets)
	if not FD.Colonist or not FD.Colonist.IsColonist(colonist) then
		return false
	end

	return Dome.FieldsTargetDomeDelete(colonist, colonist_reference_fields, dome, targets)
		or Dome.TableFieldsTargetDomeDelete(colonist, colonist_reference_table_fields, dome, targets)
		or Dome.ColonistTransportTicketTargetsDomeDelete(
			FD.ReadField(colonist, "transport_ticket"),
			dome,
			targets
		)
		or Dome.ColonistTransportTaskTargetsDomeDelete(
			FD.ReadField(colonist, "transport_task"),
			dome,
			targets
		)
		or Dome.ColonistHasTransportCommand(colonist)
end

-- Add affected objects from one container's label tables.
function Dome.CollectAffectedObjectsFromContainer(container, matches, objects, seen)
	if type(matches) ~= "function" then
		return
	end

	local labels = FD.ReadField(container, "labels")
	if type(labels) ~= "table" then
		return
	end

	for _, label_list in pairs(labels) do
		ForEachTableObject(label_list, function(obj)
			local ok, is_match = pcall(matches, obj)

			if ok and is_match then
				FD.AddUniqueObject(objects, seen, obj)
			end
		end)
	end
end

-- Return affected objects found in the dome and city/colony label tables.
function Dome.CollectAffectedObjects(dome, passages, internal_buildings, matches, targets)
	if type(matches) ~= "function" then
		return {}
	end

	targets = targets or Dome.BuildDeletionTargetSet(dome, passages, internal_buildings)
	local objects = {}
	local seen = {}
	local seen_containers = {}
	local function matches_target(obj)
		return matches(obj, dome, targets)
	end

	for _, container in ipairs(CandidateContainers(dome)) do
		if container and not seen_containers[container] then
			seen_containers[container] = true
			Dome.CollectAffectedObjectsFromContainer(container, matches_target, objects, seen)
		end
	end

	Dome.CollectAffectedObjectsFromContainer(dome, matches_target, objects, seen)

	return objects
end

-- Return colonists whose current command or assignment points at doomed objects.
function Dome.CollectAffectedColonists(dome, passages, internal_buildings, targets)
	return Dome.CollectAffectedObjects(
		dome,
		passages,
		internal_buildings,
		Dome.ColonistTargetsDomeDelete,
		targets
	)
end

-- Detach and idle colonists before deleting the objects they target.
function Dome.IdleAffectedColonists(dome, passages, internal_buildings, targets)
	return FD.CountSuccessfulActions(
		Dome.CollectAffectedColonists(dome, passages, internal_buildings, targets),
		function(colonist)
			return FD.Colonist and FD.Colonist.IdleForRelatedObjectDelete(colonist)
		end
	)
end

-- Return the source object behind a request, when available.
function Dome.RequestSource(request, unit)
	local get_source = FD.ReadField(request, "GetSource")
	if type(get_source) ~= "function" then
		return false
	end

	local ok, source = pcall(function()
		return get_source(request, unit)
	end)

	return ok and source or false
end

-- Preserve the older drone-specific request source helper name.
function Dome.DroneRequestSource(request, drone)
	return Dome.RequestSource(request, drone)
end

-- Return whether one task/request points at a doomed dome object.
function Dome.RequestTargetsDomeDelete(unit, request, dome, targets)
	if Dome.ValueTargetsDomeDelete(request, dome, targets) then
		return true
	end

	return Dome.ValueTargetsDomeDelete(Dome.RequestSource(request, unit), dome, targets)
end

-- Preserve the older drone-specific helper name for compatibility.
function Dome.DroneRequestTargetsDomeDelete(drone, request, dome, targets)
	return Dome.RequestTargetsDomeDelete(drone, request, dome, targets)
end

-- Return whether a drone is currently tied to the dome deletion target set.
function Dome.DroneTargetsDomeDelete(drone, dome, targets)
	if not FD.Drone or not FD.Drone.IsDrone(drone) then
		return false
	end

	if Dome.FieldsTargetDomeDelete(drone, drone_reference_fields, dome, targets) then
		return true
	end

	for _, field in ipairs(drone_request_fields) do
		if Dome.RequestTargetsDomeDelete(drone, FD.ReadField(drone, field), dome, targets) then
			return true
		end
	end

	return false
end

-- Return drones whose current command or request points at doomed objects.
function Dome.CollectAffectedDrones(dome, passages, internal_buildings, targets)
	return Dome.CollectAffectedObjects(
		dome,
		passages,
		internal_buildings,
		Dome.DroneTargetsDomeDelete,
		targets
	)
end

-- Detach and idle drones before deleting the objects they target.
function Dome.IdleAffectedDrones(dome, passages, internal_buildings, targets)
	return FD.CountSuccessfulActions(
		Dome.CollectAffectedDrones(dome, passages, internal_buildings, targets),
		function(drone)
			return FD.Drone and FD.Drone.IdleForRelatedObjectDelete(drone)
		end
	)
end

-- Return whether one shuttle transport task points at a doomed dome object.
function Dome.ShuttleTaskTargetsDomeDelete(shuttle, task, dome, targets)
	if type(task) ~= "table" and type(task) ~= "userdata" then
		return false
	end

	if Dome.FieldsTargetDomeDelete(task, shuttle_task_reference_fields, dome, targets) then
		return true
	end

	for _, index in ipairs({ 2, 3 }) do
		if Dome.RequestTargetsDomeDelete(shuttle, FD.ReadField(task, index), dome, targets) then
			return true
		end
	end

	return false
end

-- Return whether a shuttle is currently tied to the dome deletion target set.
function Dome.ShuttleTargetsDomeDelete(shuttle, dome, targets)
	if not FD.Shuttle or not FD.Shuttle.IsShuttle(shuttle) then
		return false
	end

	if Dome.FieldsTargetDomeDelete(shuttle, shuttle_reference_fields, dome, targets) then
		return true
	end

	return Dome.ShuttleTaskTargetsDomeDelete(
		shuttle,
		FD.ReadField(shuttle, "transport_task"),
		dome,
		targets
	)
end

-- Return shuttles whose current transport task points at doomed objects.
function Dome.CollectAffectedShuttles(dome, passages, internal_buildings, targets)
	return Dome.CollectAffectedObjects(
		dome,
		passages,
		internal_buildings,
		Dome.ShuttleTargetsDomeDelete,
		targets
	)
end

-- Detach and idle shuttles before deleting the objects they target.
function Dome.IdleAffectedShuttles(dome, passages, internal_buildings, targets)
	return FD.CountSuccessfulActions(
		Dome.CollectAffectedShuttles(dome, passages, internal_buildings, targets),
		function(shuttle)
			return FD.Shuttle and FD.Shuttle.IdleForRelatedObjectDelete(shuttle)
		end
	)
end

-- Run Level 1-style demolition on a collection.
function Dome.DemolishObjects(objects)
	return FD.CountSuccessfulActions(objects, FD.Level1DemolishObject)
end

-- Run the Level 2 delete sequence on a collection.
function Dome.DeleteObjects(objects)
	return FD.CountSuccessfulActions(objects, FD.Level2DeleteObject)
end

-- Remove stale references from one table before the dome's Done handler runs.
function Dome.PruneDeleteReferencesFromTable(list, delete_set)
	if type(list) ~= "table" then
		return
	end

	for obj in pairs(delete_set or {}) do
		FD.RemoveObjectFromTable(list, obj)
	end

	for i = #list, 1, -1 do
		local obj = list[i]
		if (type(obj) == "table" or type(obj) == "userdata")
			and not FD.IsObjectValid(obj)
		then
			table.remove(list, i)
		end
	end

	for key, value in pairs(list) do
		local key_is_object = type(key) == "table" or type(key) == "userdata"
		local value_is_object = type(value) == "table" or type(value) == "userdata"

		if key_is_object and not FD.IsObjectValid(key)
			or value_is_object and not FD.IsObjectValid(value)
		then
			list[key] = nil
		end
	end
end

-- Remove deleted passages/buildings from dome labels and connection tables.
function Dome.PruneDeletedDomeReferences(dome, passages, internal_buildings)
	if not Dome.IsDome(dome) then
		return
	end

	local delete_set = {}

	for _, obj in ipairs(passages or {}) do
		delete_set[obj] = true
	end

	for _, obj in ipairs(internal_buildings or {}) do
		delete_set[obj] = true
	end

	local labels = FD.ReadField(dome, "labels")
	if type(labels) == "table" then
		for _, label_list in pairs(labels) do
			Dome.PruneDeleteReferencesFromTable(label_list, delete_set)
		end
	end

	Dome.PruneDeleteReferencesFromTable(FD.ReadField(dome, "passages"), delete_set)
	Dome.PruneDeleteReferencesFromTable(FD.ReadField(dome, "connected_passages"), delete_set)
end

-- Return rotated hex-shape coordinates without trusting engine point types.
local function RotatedHexPoint(pt, dir)
	local hex_rotate = FD.Global("HexRotate")
	if type(hex_rotate) ~= "function" then
		return false
	end

	local ok, q, r = pcall(function()
		return hex_rotate(pt, dir)
	end)
	if not ok then
		return false
	end

	if type(q) == "number" and type(r) == "number" then
		return q, r
	end

	if q and type(FD.ReadField(q, "xy")) == "function" then
		local xy_ok, x, y = pcall(function()
			return q:xy()
		end)

		if xy_ok then
			return x, y
		end
	end

	return false
end

-- Clear one dome's supply connection bits after passages/internal buildings are gone.
function Dome.ClearSupplyConnectionGrid(dome)
	if not Dome.IsDome(dome) then
		return false
	end

	local map = FD.CallMethod(dome, "GetMap")
	local supply_connection_grid = FD.ReadField(map, "supply_connection_grid")
	local world_to_hex = FD.Global("WorldToHex")
	local hex_angle_to_direction = FD.Global("HexAngleToDirection")
	local hex_grid_get = FD.Global("HexGridGet")
	local hex_grid_set = FD.Global("HexGridSet")
	local hex_get_direction = FD.Global("HexGetDirection")
	local hex_neighbours = FD.Global("HexNeighbours")
	local band_fn = FD.Global("band")
	local bnot_fn = FD.Global("bnot")
	local shift_fn = FD.Global("shift")

	if not supply_connection_grid
		or type(world_to_hex) ~= "function"
		or type(hex_angle_to_direction) ~= "function"
		or type(hex_grid_get) ~= "function"
		or type(hex_grid_set) ~= "function"
		or type(hex_get_direction) ~= "function"
		or type(hex_neighbours) ~= "table"
		or type(band_fn) ~= "function"
		or type(bnot_fn) ~= "function"
		or type(shift_fn) ~= "function"
	then
		return false
	end

	local ok_hex, dome_q, dome_r = pcall(function()
		return world_to_hex(dome)
	end)
	local shape = nil
	local ok_shape = pcall(function()
		shape = dome:GetSupplyGridConnectionShapePoints("electricity")
	end)

	if not ok_hex or not ok_shape or type(shape) ~= "table" then
		return false
	end

	local dir = hex_angle_to_direction(FD.CallMethod(dome, "GetAngle") or 0)

	for _, pt in ipairs(shape) do
		local pt_q, pt_r = RotatedHexPoint(pt, dir)

		if type(pt_q) == "number" and type(pt_r) == "number" then
			local q = dome_q + pt_q
			local r = dome_r + pt_r

			for _, resource in ipairs({ "electricity", "water" }) do
				local grid = supply_connection_grid[resource]

				if grid then
					for _, neighbor in ipairs(hex_neighbours) do
						local xy_ok, neighbor_q, neighbor_r = pcall(function()
							return neighbor:xy()
						end)

						if xy_ok then
							local n_q = q + neighbor_q
							local n_r = r + neighbor_r
							local value = hex_grid_get(grid, n_q, n_r)

							if value and value ~= 0 then
								local rev_dir = hex_get_direction(n_q, n_r, q, r)
								local cleared = band_fn(value, bnot_fn(shift_fn(1, rev_dir)))

								hex_grid_set(grid, n_q, n_r, cleared)
							end
						end
					end

					hex_grid_set(grid, q, r, 0)
				end
			end
		end
	end

	return true
end

-- Return the configured hex size, with a safe fallback for terrain math.
local function HexSize()
	local const = FD.Global("const")

	return const and const.HexSize or 1000
end

-- Return the best map object to use for dome terrain edits.
local function DomeTerrainMap(dome)
	return FD.CallMethod(dome, "GetMap")
		or FD.Global("CurrentMap")
		or FD.Global("MainMap")
end

-- Return an approximate radius for repainting a dome footprint.
local function ObjectRadius(obj, fallback)
	local radius = FD.CallMethod(obj, "GetRadius")

	if type(radius) == "number" and radius > 0 then
		return radius
	end

	local bbox = FD.CallMethod(obj, "GetEntityBBox")
	if bbox then
		local ok, size_x, size_y = pcall(function()
			return bbox:sizex(), bbox:sizey()
		end)

		if ok and type(size_x) == "number" and type(size_y) == "number" then
			return math.max(size_x, size_y) / 2
		end
	end

	return fallback or 0
end

-- Return the terrain type at one position, or false if the engine call fails.
local function TerrainTypeAt(map, pos, visual)
	local terrain_api = FD.Global("terrain")
	if not terrain_api or type(terrain_api.GetTerrainType) ~= "function" then
		return false
	end

	local ok, terrain_type = pcall(function()
		return terrain_api.GetTerrainType(map, pos, visual)
	end)

	return ok and terrain_type ~= nil and terrain_type or false
end

-- Return the most common terrain type just outside the dome footprint.
local function SampleOuterTerrainType(dome)
	local map = DomeTerrainMap(dome)
	local point_fn = FD.Global("point")
	local pos = FD.CallMethod(dome, "GetPos") or FD.ReadField(dome, "pos")

	if not map or type(point_fn) ~= "function" or not pos then
		return false
	end

	local hex_size = HexSize()
	local sample_radius = ObjectRadius(dome, hex_size * 10) + hex_size * 3
	local offsets = {
		point_fn(sample_radius, 0, 0),
		point_fn(-sample_radius, 0, 0),
		point_fn(0, sample_radius, 0),
		point_fn(0, -sample_radius, 0),
		point_fn(sample_radius, sample_radius, 0),
		point_fn(-sample_radius, sample_radius, 0),
		point_fn(sample_radius, -sample_radius, 0),
		point_fn(-sample_radius, -sample_radius, 0),
	}
	local counts = {}

	for _, offset in ipairs(offsets) do
		local ok, sample_pos = pcall(function()
			return pos + offset
		end)
		local terrain_type = ok and TerrainTypeAt(map, sample_pos, true) or false

		if terrain_type then
			counts[terrain_type] = (counts[terrain_type] or 0) + 1
		end
	end

	local best_type = false
	local best_count = 0

	for terrain_type, count in pairs(counts) do
		if count > best_count then
			best_type = terrain_type
			best_count = count
		end
	end

	return best_type
end

-- Repaint the dome footprint with the nearest surrounding terrain type.
function Dome.ResetTerrain(dome)
	if not Dome.IsDome(dome) then
		return false
	end

	local terrain_api = FD.Global("terrain")
	local map = DomeTerrainMap(dome)
	local pos = FD.CallMethod(dome, "GetPos") or FD.ReadField(dome, "pos")

	if not terrain_api
		or not map
		or not pos
		or type(terrain_api.SetTypeCircle) ~= "function"
	then
		return false
	end

	local hex_size = HexSize()
	local cleanup_radius = ObjectRadius(dome, hex_size * 10) + hex_size * 2
	local terrain_type = SampleOuterTerrainType(dome)

	if not terrain_type then
		return false
	end

	local ok = pcall(function()
		terrain_api.SetTypeCircle(map, pos, cleanup_radius, terrain_type, terrain_type)
	end)

	if ok and type(terrain_api.InvalidateType) == "function" then
		pcall(function()
			terrain_api.InvalidateType(map)
		end)
	end

	return ok and true or false
end

-- Demolish one passage and run Level 2 only if demolition left it valid.
function Dome.DeletePassageSequentially(passage)
	if not Dome.IsPassageController(passage) then
		return false, false
	end

	local demolished = FD.Level1DemolishObject(passage)
	local deleted = false

	if FD.IsObjectValid(passage) then
		deleted = FD.Level2DeleteObject(passage)
	end

	return demolished, deleted
end

-- Demolish and then delete each connected passage before moving to the next.
function Dome.DeletePassagesSequentially(passages)
	local demolished = 0
	local deleted = 0

	for _, passage in ipairs(passages or {}) do
		local did_demolish, did_delete = Dome.DeletePassageSequentially(passage)

		if did_demolish then
			demolished = demolished + 1
		end

		if did_delete then
			deleted = deleted + 1
		end
	end

	return demolished, deleted
end

-- Demolish and clear the dome shell before falling back to direct deletion.
function Dome.DeleteDomeShell(dome)
	local demolished_or_cleared = FD.DemolishThenClearObject(dome)

	if not FD.IsObjectValid(dome) then
		return demolished_or_cleared and 1 or 0, 0
	end

	local deleted = FD.DeleteObjectDirect(dome)
	return demolished_or_cleared and 1 or 0, deleted and 1 or 0
end

-- Rebuild render objects after dome removal so clustered lights refresh cleanly.
function Dome.RebuildRenderObjects()
	return FD.SafeCall(FD.Global("RecreateRenderObjects")) and true or false
end

-- Format the staged dome deletion result for the inspector panel.
local function DomeDeletionMessage(result)
	return "Ctrl+Shift+Delete pressed."
		.. "\n\nDome: "
		.. result.summary
		.. "\nPassage ids: "
		.. (result.passage_ids ~= "" and result.passage_ids or "none")
		.. "\nColonists idled: "
		.. FD.SafeToString(result.idled_colonists)
		.. "\nDrones idled: "
		.. FD.SafeToString(result.idled_drones)
		.. "\nShuttles idled: "
		.. FD.SafeToString(result.idled_shuttles)
		.. "\nDome lights disabled: "
		.. FD.SafeToString(result.lights_disabled)
		.. "\nPassages demolished: "
		.. FD.SafeToString(result.passage_demolished)
		.. "\nPassages direct-deleted: "
		.. FD.SafeToString(result.passage_deleted)
		.. "\nPassages remaining: "
		.. FD.SafeToString(result.passages_remaining)
		.. "\nInternal buildings demolished: "
		.. FD.SafeToString(result.internal_demolished)
		.. "\nInternal buildings deleted: "
		.. FD.SafeToString(result.internal_deleted)
		.. "\nDome grid cleaned: "
		.. FD.SafeToString(result.grid_cleaned == true)
		.. "\nDome terrain reset: "
		.. FD.SafeToString(result.terrain_reset == true)
		.. "\nDome demolished: "
		.. FD.SafeToString(result.dome_demolished)
		.. "\nDome deleted: "
		.. FD.SafeToString(result.dome_deleted)
		.. "\nRender rebuilt: "
		.. FD.SafeToString(result.render_rebuilt == true)
end

-- Return whether any staged dome deletion step succeeded.
local function DomeDeletionSucceeded(result)
	return result.dome_deleted > 0
		or result.dome_demolished > 0
		or result.internal_deleted > 0
		or result.internal_demolished > 0
		or result.passage_deleted > 0
		or result.passage_demolished > 0
end

-- Detect dome objects.
function Dome.IsDome(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	if FD.IsKindOf(obj, "Dome") then
		return true
	end

	if FD.InternalBuilding and FD.InternalBuilding.IsInternalBuilding(obj) then
		return false
	end

	return FD.ClassName(obj):find("Dome", 1, true) ~= nil
		and type(FD.ReadField(obj, "labels")) == "table"
end

-- Show dome diagnostics for the selected object.
function Dome.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Dome.GetRelevantAttributes(obj))
	end
end

-- Delete a dome by staging passages, internal buildings, and the dome itself.
function Dome.Delete(dome)
	if not Dome.IsDome(dome) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a dome.")
		return false
	end

	local summary = FD.ObjectSummary(dome)
	local passages = Dome.CollectConnectedPassageControllers(dome)
	local passage_ids = Dome.PassageIds(passages)
	local internal_buildings = Dome.CollectInternalBuildings(dome)
	local targets = Dome.BuildDeletionTargetSet(dome, passages, internal_buildings)
	local lights_disabled = Dome.DisableDomeLights(dome, internal_buildings)
	local idled_colonists = Dome.IdleAffectedColonists(dome, passages, internal_buildings, targets)
	local idled_drones = Dome.IdleAffectedDrones(dome, passages, internal_buildings, targets)
	local idled_shuttles = Dome.IdleAffectedShuttles(dome, passages, internal_buildings, targets)
	local passage_demolished, passage_deleted = Dome.DeletePassagesSequentially(passages)
	local passages_remaining = Dome.CountConnectedPassages(dome)
	local internal_demolished = Dome.DemolishObjects(internal_buildings)
	local internal_deleted = Dome.DeleteObjects(internal_buildings)
	Dome.PruneDeletedDomeReferences(dome, passages, internal_buildings)
	local grid_cleaned = Dome.ClearSupplyConnectionGrid(dome)
	local terrain_reset = Dome.ResetTerrain(dome)
	lights_disabled = lights_disabled + Dome.DisableDomeLights(dome)
	local dome_demolished, dome_deleted = Dome.DeleteDomeShell(dome)
	local render_rebuilt = Dome.RebuildRenderObjects()
	local result = {
		summary = summary,
		passage_ids = passage_ids,
		idled_colonists = idled_colonists,
		idled_drones = idled_drones,
		idled_shuttles = idled_shuttles,
		lights_disabled = lights_disabled,
		passage_demolished = passage_demolished,
		passage_deleted = passage_deleted,
		passages_remaining = passages_remaining,
		internal_demolished = internal_demolished,
		internal_deleted = internal_deleted,
		grid_cleaned = grid_cleaned,
		terrain_reset = terrain_reset,
		dome_demolished = dome_demolished,
		dome_deleted = dome_deleted,
		render_rebuilt = render_rebuilt,
	}

	FD.ShowDeleteMessage(DomeDeletionMessage(result))

	return DomeDeletionSucceeded(result)
end

-- Return dome diagnostic attributes.
function Dome.GetRelevantAttributes(dome)
	local rows = {}
	local passages = Dome.CollectInspectorPassages(dome)
	local internal_buildings = Dome.CollectInspectorInternalBuildings(dome)

	FD.AddCommonObjectAttributes(rows, dome, "dome", "dome deletion is staged")
	table.insert(rows, 2, { "num_passages", FD.AttributeText(Dome.CountConnectedPassages(dome)) })
	FD.AddAttribute(rows, "inspector_scan", "local only; full scan runs on delete")
	FD.AddAttribute(rows, "local_passage_ids", Dome.PassageIds(passages))
	FD.AddAttribute(rows, "local_internal_building_count", #internal_buildings)
	FD.AddFieldAttributes(rows, dome, FD.IDENTITY_FIELDS)
	FD.AddFieldAttributes(rows, dome, state_fields)
	FD.AddMethodDiagnostics(rows, dome, FD.DEMOLISHABLE_METHODS)

	return {
		title = "Dome attributes",
		rows = rows,
	}
end
