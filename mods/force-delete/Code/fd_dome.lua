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

-- Append an object to a collection once.
local function AddUnique(list, seen, obj)
	if not FD.IsObjectValid(obj) or seen[obj] then
		return false
	end

	seen[obj] = true
	list[#list + 1] = obj
	return true
end

-- Visit object-like values in an engine table without scanning indefinitely.
local function ForEachTableObject(list, callback)
	if type(list) ~= "table" or type(callback) ~= "function" then
		return
	end

	local scanned = 0

	local function visit(obj)
		if FD.IsObjectValid(obj) then
			callback(obj)
		end
	end

	for _, obj in ipairs(list) do
		scanned = scanned + 1
		if scanned > FD.MAX_SCAN then
			return
		end

		visit(obj)
	end

	for key, value in pairs(list) do
		scanned = scanned + 1
		if scanned > FD.MAX_SCAN then
			return
		end

		visit(key)
		visit(value)
	end
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
	if not AddUnique(passages, seen, passage) then
		return
	end

	for _, field in ipairs(passage_piece_fields) do
		local value = FD.ReadField(passage, field)

		if FD.IsObjectValid(value) then
			AddUnique(passages, seen, value)
		else
			ForEachTableObject(value, function(piece)
				AddUnique(passages, seen, piece)
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
			AddUnique(buildings, seen, obj)
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

-- Run Level 1-style demolition on a collection.
function Dome.DemolishObjects(objects)
	local demolished = 0

	for _, obj in ipairs(objects or {}) do
		if FD.Level1DemolishObject(obj) then
			demolished = demolished + 1
		end
	end

	return demolished
end

-- Run Level 2-style direct deletion on a collection.
function Dome.DeleteObjects(objects)
	local deleted = 0

	for _, obj in ipairs(objects or {}) do
		if FD.Level2DeleteObject(obj) then
			deleted = deleted + 1
		end
	end

	return deleted
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

-- Delete a dome through the requested staged order.
function Dome.Delete(dome)
	if not Dome.IsDome(dome) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a dome.")
		return false
	end

	local summary = FD.ObjectSummary(dome)
	local passages = Dome.CollectConnectedPassages(dome)
	local passage_ids = Dome.PassageIds(passages)
	local passage_demolished = Dome.DemolishObjects(passages)
	local passage_deleted = Dome.DeleteObjects(passages)
	local internal_buildings = Dome.CollectInternalBuildings(dome)
	local internal_demolished = Dome.DemolishObjects(internal_buildings)
	local internal_deleted = Dome.DeleteObjects(internal_buildings)
	local dome_demolished = FD.Level1DemolishObject(dome) and 1 or 0
	local dome_deleted = FD.Level2DeleteObject(dome) and 1 or 0

	FD.ShowDeleteMessage(
		"Ctrl+Shift+Delete pressed."
			.. "\n\nDome: "
			.. summary
			.. "\nPassage ids: "
			.. (passage_ids ~= "" and passage_ids or "none")
			.. "\nPassages demolished: "
			.. FD.SafeToString(passage_demolished)
			.. "\nPassages deleted: "
			.. FD.SafeToString(passage_deleted)
			.. "\nInternal buildings demolished: "
			.. FD.SafeToString(internal_demolished)
			.. "\nInternal buildings deleted: "
			.. FD.SafeToString(internal_deleted)
			.. "\nDome demolished: "
			.. FD.SafeToString(dome_demolished)
			.. "\nDome deleted: "
			.. FD.SafeToString(dome_deleted)
	)

	return dome_deleted > 0 or dome_demolished > 0
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
