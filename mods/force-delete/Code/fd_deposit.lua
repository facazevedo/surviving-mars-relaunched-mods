-- Resource deposit diagnostics and Level 2 deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining deposit helpers on repeated mod loads.
if FD.deposit_loaded then return end
FD.deposit_loaded = true

-- Create the deposit module namespace.
FD.Deposit = FD.Deposit or {}
local Deposit = FD.Deposit

-- State fields capture deposit ownership, marker links, resource, and scan state.
local state_fields = {
	"resource",
	"amount",
	"max_amount",
	"grade",
	"grade_name",
	"depth_layer",
	"revealed",
	"is_placed",
	"marker",
	"placed_obj",
	"deposit",
	"group",
	"transport_request",
	"city",
	"labels",
}

-- Method availability tells us which cleanup paths exist on this object.
local methods = { "GetAmount", "GetDeposit", "IsDepleted", "delete" }

-- Class-name fragments that mention deposits but are not deposit objects.
local excluded_class_parts = {
	"ConstructionRevealer",
	"DepositExploiter",
	"Exploiter",
	"Extractor",
	"Component",
	"SpawnDeposit",
}

-- Return whether a class name belongs to a deposit helper rather than a deposit.
local function HasExcludedClassName(class)
	for _, text in ipairs(excluded_class_parts) do
		if class:find(text, 1, true) ~= nil then
			return true
		end
	end

	return false
end

-- Return whether an object is a deposit marker.
function Deposit.IsMarker(obj)
	return FD.IsObjectValid(obj)
		and (
			FD.IsKindOf(obj, "DepositMarker")
			or FD.IsKindOf(obj, "SurfaceDepositMarker")
			or FD.IsKindOf(obj, "SubsurfaceDepositMarker")
			or FD.IsKindOf(obj, "TerrainDepositMarker")
			or FD.ClassName(obj):find("DepositMarker", 1, true) ~= nil
		)
end

-- Return whether an object is a resource deposit or deposit group.
function Deposit.IsDeposit(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	if HasExcludedClassName(class) then
		return false
	end

	return Deposit.IsMarker(obj)
		or FD.IsKindOf(obj, "Deposit")
		or FD.IsKindOf(obj, "SurfaceDeposit")
		or FD.IsKindOf(obj, "SubsurfaceDeposit")
		or FD.IsKindOf(obj, "TerrainDeposit")
		or class:find("Deposit", 1, true) ~= nil
end

-- Return the marker directly attached to one deposit object.
function Deposit.MarkerFor(obj)
	if Deposit.IsMarker(obj) then
		return obj
	end

	for _, field in ipairs({ "marker", "placed_obj", "deposit" }) do
		local candidate = FD.ReadField(obj, field)

		if Deposit.IsMarker(candidate) then
			return candidate
		end

		if Deposit.IsDeposit(candidate) and Deposit.IsMarker(FD.ReadField(candidate, "marker")) then
			return FD.ReadField(candidate, "marker")
		end
	end

	local from_method = FD.CallMethod(obj, "GetDeposit")
	if Deposit.IsMarker(from_method) then
		return from_method
	end

	if Deposit.IsDeposit(from_method) then
		return Deposit.MarkerFor(from_method)
	end

	return false
end

-- Return the best city object for deposit-sector cleanup.
local function CityFor(obj)
	return FD.SafeCall(FD.Global("GetCity"), obj)
		or FD.ReadField(obj, "city")
		or FD.Global("UICity")
		or FD.Global("MainCity")
		or FD.Global("SelectedCity")
		or FD.Global("UIColony")
end

-- Remove an object from all common city/colony label tables.
local function PruneGlobalLabels(obj)
	for _, container in ipairs({
		FD.ReadField(obj, "city"),
		FD.Global("UICity"),
		FD.Global("MainCity"),
		FD.Global("SelectedCity"),
		FD.Global("UIColony"),
	}) do
		local labels = FD.ReadField(container, "labels")

		if type(labels) == "table" then
			for _, label_list in pairs(labels) do
				FD.RemoveObjectFromTable(label_list, obj)
			end
		end
	end
end

-- Remove one marker from map-sector marker and revealed-deposit lists.
function Deposit.UnregisterMarker(marker)
	if not Deposit.IsMarker(marker) then
		return false
	end

	local city = CityFor(marker)
	local sector = city and FD.SafeCall(FD.Global("GetMapSector"), city, marker)

	if sector and type(FD.ReadField(sector, "UnregisterDeposit")) == "function" then
		pcall(function()
			sector:UnregisterDeposit(marker)
		end)
	end

	local markers = FD.ReadField(sector, "markers")
	if type(markers) == "table" then
		for _, field in ipairs({ "surface", "subsurface", "deep", "block" }) do
			FD.RemoveObjectFromTable(markers[field], marker)
		end
	end

	FD.RemoveObjectFromTable(FD.ReadField(sector, "revealed_surf"), marker)
	FD.RemoveObjectFromTable(FD.ReadField(sector, "revealed_deep"), marker)
	PruneGlobalLabels(marker)

	return true
end

-- Collect a selected deposit, related group members, and related markers.
function Deposit.CollectRelatedObjects(obj)
	local objects = {}
	local markers = {}
	local seen_objects = {}
	local seen_markers = {}

	local function add_marker(marker)
		FD.AddUniqueObject(markers, seen_markers, marker)
	end

	local function add_deposit(deposit)
		if not FD.AddUniqueObject(objects, seen_objects, deposit) then
			return
		end

		add_marker(Deposit.MarkerFor(deposit))
	end

	add_deposit(obj)

	for _, field in ipairs({ "group", "objects", "deposits" }) do
		FD.ForEachTableObject(FD.ReadField(obj, field), function(child)
			if Deposit.IsDeposit(child) then
				add_deposit(child)
			end
		end)
	end

	local marker = Deposit.MarkerFor(obj)
	if marker then
		add_marker(marker)
		add_deposit(FD.ReadField(marker, "placed_obj"))
		add_deposit(FD.ReadField(marker, "deposit"))
		add_deposit(FD.CallMethod(marker, "GetDeposit"))
	end

	return objects, markers
end

-- Delete one collected deposit or marker through direct object removal.
local function DeleteObject(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	PruneGlobalLabels(obj)

	if FD.CallObjectMethod(obj, "delete") then
		return true
	end

	return FD.SafeCall(FD.Global("DoneObject"), obj) and true or false
end

-- Show deposit diagnostics for the selected object.
function Deposit.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Deposit.GetRelevantAttributes(obj))
	end
end

-- Delete a resource deposit, its related marker, and any selected group members.
function Deposit.Delete(obj)
	if not Deposit.IsDeposit(obj) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a deposit.")
		return false
	end

	local summary = FD.ObjectSummary(obj)
	local objects, markers = Deposit.CollectRelatedObjects(obj)
	local unregistered = 0
	local deleted_objects = 0
	local deleted_markers = 0

	for _, marker in ipairs(markers) do
		if Deposit.UnregisterMarker(marker) then
			unregistered = unregistered + 1
		end
	end

	for _, deposit in ipairs(objects) do
		if not Deposit.IsMarker(deposit) and DeleteObject(deposit) then
			deleted_objects = deleted_objects + 1
		end
	end

	for _, marker in ipairs(markers) do
		if DeleteObject(marker) then
			deleted_markers = deleted_markers + 1
		end
	end

	FD.ShowDeleteMessage(
		"Ctrl+Shift+Delete pressed."
			.. "\n\nDeposit: "
			.. summary
			.. "\nMarkers unregistered: "
			.. FD.SafeToString(unregistered)
			.. "\nDeposit objects deleted: "
			.. FD.SafeToString(deleted_objects)
			.. "\nMarkers deleted: "
			.. FD.SafeToString(deleted_markers)
	)

	return deleted_objects > 0 or deleted_markers > 0 or unregistered > 0
end

-- Return deposit diagnostic attributes.
function Deposit.GetRelevantAttributes(obj)
	local rows = {}
	local marker = Deposit.MarkerFor(obj)

	FD.AddCommonObjectAttributes(rows, obj, "deposit", "resource deposits require marker and sector cleanup")
	FD.AddAttribute(rows, "deposit_marker", marker)
	FD.AddAttribute(rows, "deposit_depth_class", FD.CallMethod(marker, "GetDepthClass"))
	FD.AddFieldAttributes(rows, obj, FD.IDENTITY_FIELDS)
	FD.AddFieldAttributes(rows, obj, state_fields)
	FD.AddMethodDiagnostics(rows, obj, methods)

	return {
		title = "Deposit attributes",
		rows = rows,
	}
end
