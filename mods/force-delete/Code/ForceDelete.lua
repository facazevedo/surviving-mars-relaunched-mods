-- Force Delete single-file refactor for Surviving Mars Relaunched.
-- Generated from the multi-file refactor, collapsed into one Script.lua.
-- Modes:
--   Ctrl+Delete       / LB+RB+X = light delete.
--   Ctrl+Shift+Delete / LB+RB+Y = hard delete.

ForceDelete = rawget(_G, "ForceDelete") or {}
local FD = ForceDelete
_G.ForceDelete = FD


-- ============================================================================
-- fd_safe.lua
-- ============================================================================

FD.LIGHT_ACTION_ID = "ForceDelete_CtrlDelete"
FD.HARD_ACTION_ID = "ForceDelete_CtrlShiftDelete"
FD.MAX_MARKER_GROUP_SCAN = 32
FD.MAX_CONTAINED_LABEL_SCAN = 2048
FD.shortcuts_patched = false

-- Return an optional global without creating sandbox assertion noise.
function FD.Global(name)
	return rawget(_G, name)
end

-- Run an optional function safely and return false on failure.
function FD.SafeCall(fn, ...)
	if type(fn) ~= "function" then
		return false
	end

	local ok, result = pcall(fn, ...)
	return ok and result or false
end

-- Check whether a map/game object is still valid.
function FD.IsObjectValid(obj)
	if not obj then
		return false
	end

	local is_valid = FD.Global("IsValid")

	if type(is_valid) == "function" then
		return FD.SafeCall(is_valid, obj) and true or false
	end

	return obj and true or false
end

-- Test an object class relationship through the engine helper when available.
function FD.IsKindOf(obj, class_name)
	return FD.IsObjectValid(obj)
		and FD.SafeCall(FD.Global("IsKindOf"), obj, class_name)
		and true
		or false
end

-- Read a field safely from engine userdata/table objects.
function FD.ReadField(obj, field)
	if not obj then
		return nil
	end

	local ok, value = pcall(function()
		return obj[field]
	end)

	return ok and value or nil
end

function FD.WriteField(obj, field, value)
	if not obj then
		return false
	end

	local ok = pcall(function()
		obj[field] = value
	end)

	return ok
end

-- Call a zero-argument object method safely.
function FD.CallMethod(obj, method)
	local fn = FD.ReadField(obj, method)

	if type(fn) ~= "function" then
		return nil
	end

	local ok, value = pcall(function()
		return fn(obj)
	end)

	return ok and value or nil
end

-- Return an object's class-like identifier.
function FD.ClassName(obj)
	local value = FD.ReadField(obj, "class") or FD.CallMethod(obj, "GetClass")
	local ok, result = pcall(tostring, value or obj)

	return ok and result or ""
end

-- Read an editor/game property by id when the object supports GetProperty.
function FD.ReadProperty(obj, prop_id)
	if not FD.IsObjectValid(obj) or type(FD.ReadField(obj, "GetProperty")) ~= "function" then
		return nil
	end

	local ok, value = pcall(function()
		return obj:GetProperty(prop_id)
	end)

	return ok and value or nil
end

-- Return the best fallback hex size for local terrain operations.
function FD.HexSize()
	local const = FD.Global("const")

	return const and const.HexSize or 1000
end

function FD.CallObjectMethod(obj, method_name, ...)
	local method = FD.ReadField(obj, method_name)

	if type(method) ~= "function" then
		return false
	end

	local args = { ... }
	local ok, result = pcall(function()
		return method(obj, unpack(args))
	end)

	return ok and result or false
end


-- ============================================================================
-- fd_types.lua
-- ============================================================================

-- Match an object by engine class relationship or by class-name substring.
function FD.ObjectMatches(obj, kind_names, class_patterns)
	if not FD.IsObjectValid(obj) then
		return false
	end

	for _, kind_name in ipairs(kind_names or {}) do
		if FD.IsKindOf(obj, kind_name) then
			return true
		end
	end

	local class_name = FD.ClassName(obj)

	for _, pattern in ipairs(class_patterns or {}) do
		if class_name:find(pattern, 1, true) ~= nil then
			return true
		end
	end

	return false
end

function FD.IsColonist(obj)
	return FD.ObjectMatches(obj, { "Colonist" }, { "Colonist" })
end

function FD.IsAnimal(obj)
	return FD.ObjectMatches(
		obj,
		{ "BaseAnimal", "BasePet", "Pet", "PastureAnimal" },
		{ "Animal", "Pet" }
	)
end

function FD.IsDroneObject(obj)
	return FD.ObjectMatches(obj, { "Drone" }, { "Drone" })
end

-- Detect live units that should not be pulled in by container recursion.
function FD.IsProtectedUnit(obj)
	return FD.IsColonist(obj)
		or FD.IsAnimal(obj)
		or FD.ObjectMatches(
			obj,
			{ "Unit", "Drone", "BaseRover", "BaseRobot" },
			{ "Rover", "Drone" }
		)
end

function FD.IsDome(obj)
	return FD.ObjectMatches(obj, { "Dome" }, { "Dome" })
end

function FD.IsPassageObject(obj)
	return FD.ObjectMatches(obj, { "PassageBase" }, { "Passage" })
		and type(FD.ReadField(obj, "elements")) == "table"
end

function FD.IsDomeVisualAttach(obj)
	return FD.ObjectMatches(
		obj,
		{ "BakedDomeDecal", "BakedDomeDecalLarge", "DomeTerrain", "DomeGrass", "DomeRoadConnection" },
		{ "BakedDomeDecal", "DomeTerrain", "DomeGrass", "DomeRoadConnection" }
	)
end

function FD.IsComponentLightObject(obj)
	return FD.ObjectMatches(obj, { "ComponentLight" }, { "ComponentLight" })
end

function FD.IsMarker(obj)
	return FD.ObjectMatches(
		obj,
		{ "DepositMarker", "SurfaceDepositMarker", "SubsurfaceDepositMarker" },
		{ "DepositMarker" }
	)
end

function FD.IsResourceStockpileObject(obj)
	return FD.ObjectMatches(
		obj,
		{ "ResourceStockpileBase", "ResourceStockpile" },
		{ "ResourceStockpile" }
	)
end

function FD.IsStockpileControllerObject(obj)
	return FD.IsObjectValid(obj) and type(FD.ReadField(obj, "stockpiles")) == "table"
end

function FD.IsResourceDepositObject(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	return FD.IsMarker(obj)
		or FD.ObjectMatches(
			obj,
			{ "TerrainDeposit", "SurfaceDeposit", "SubsurfaceDeposit" },
			{ "Deposit", "Concrete", "Metals", "Polymers", "PreciousMetals" }
		)
end

-- Keep light force-delete away from live units; hard delete handles these explicitly.
function FD.IsLightDeleteProtected(obj)
	return FD.IsColonist(obj) or FD.IsAnimal(obj) or FD.IsDroneObject(obj)
end

-- Detect grid pieces that should be allowed through the light-delete shortcut.
function FD.IsLightDeleteGridElement(obj)
	return FD.ObjectMatches(
		obj,
		{ "ElectricityGridElement", "LifeSupportGridElement" },
		{ "ElectricityGridElement", "LifeSupportGridElement" }
	)
end


-- ============================================================================
-- fd_tables.lua
-- ============================================================================

-- Visit valid object-like keys and values in array-style and hash-style engine tables.
function FD.ForEachTableObject(list, callback, max_scan)
	if type(list) ~= "table" or type(callback) ~= "function" then
		return
	end

	local scanned = 0
	local visited = {}

	local function visit(obj)
		if FD.IsObjectValid(obj) and not visited[obj] then
			visited[obj] = true
			callback(obj)
		end
	end

	for _, value in ipairs(list) do
		scanned = scanned + 1

		if max_scan and scanned > max_scan then
			return
		end

		visit(value)
	end

	for key, value in pairs(list) do
		scanned = scanned + 1

		if max_scan and scanned > max_scan then
			return
		end

		visit(key)
		visit(value)
	end
end

function FD.RemoveObjectFromTable(list, obj, max_scan)
	if type(list) ~= "table" or not obj then
		return
	end

	local limit = max_scan or FD.MAX_CONTAINED_LABEL_SCAN or #list

	for i = math.min(#list, limit), 1, -1 do
		if list[i] == obj then
			table.remove(list, i)
		end
	end

	local scanned = 0

	for key, value in pairs(list) do
		scanned = scanned + 1

		if max_scan and scanned > max_scan then
			return
		end

		if key == obj or value == obj then
			list[key] = nil
		end
	end
end

function FD.RemoveObjectFromTableEntries(list, obj)
	FD.RemoveObjectFromTable(list, obj)
end

function FD.TableContainsObject(list, obj, comparator)
	if type(list) ~= "table" or not obj then
		return false
	end

	local found = false
	local function same(candidate)
		if comparator then
			return comparator(candidate, obj)
		end
		return candidate == obj
	end

	FD.ForEachTableObject(list, function(candidate)
		if same(candidate) then
			found = true
		end
	end, FD.MAX_CONTAINED_LABEL_SCAN)

	return found
end

function FD.AddUniqueObject(list, obj)
	if not FD.IsObjectValid(obj) then
		return
	end

	for _, existing in ipairs(list) do
		if existing == obj then
			return
		end
	end

	list[#list + 1] = obj
end

function FD.MarkObject(seen, obj)
	if not FD.IsObjectValid(obj) or seen[obj] then
		return false
	end

	seen[obj] = true
	return true
end

function FD.CollectMatchingObjectsFromTable(list, output, seen, predicate)
	FD.ForEachTableObject(list, function(obj)
		if predicate(obj) and not seen[obj] then
			seen[obj] = true
			output[#output + 1] = obj
		end
	end, FD.MAX_CONTAINED_LABEL_SCAN)
end

function FD.PruneLabelList(label_list, delete_set, prune_invalid)
	if type(label_list) ~= "table" then
		return
	end

	for i = math.min(#label_list, FD.MAX_CONTAINED_LABEL_SCAN), 1, -1 do
		local obj = label_list[i]

		if delete_set[obj] or prune_invalid and not FD.IsObjectValid(obj) then
			table.remove(label_list, i)
		end
	end

	local scanned = 0

	for key, value in pairs(label_list) do
		scanned = scanned + 1

		if scanned > FD.MAX_CONTAINED_LABEL_SCAN then
			return
		end

		if delete_set[key] or delete_set[value] then
			label_list[key] = nil
		end
	end
end

function FD.PruneLabelsTable(labels, delete_set, prune_invalid)
	if type(labels) ~= "table" then
		return
	end

	local scanned = 0

	for _, label_list in pairs(labels) do
		scanned = scanned + 1

		if scanned > FD.MAX_CONTAINED_LABEL_SCAN then
			return
		end

		FD.PruneLabelList(label_list, delete_set, prune_invalid)
	end
end

function FD.PruneObjectFromContainerLabels(container, obj)
	local labels = FD.ReadField(container, "labels")

	if type(labels) ~= "table" then
		return
	end

	FD.PruneLabelsTable(labels, { [obj] = true }, false)
end

function FD.PruneObjectsFromGlobalLabels(delete_set)
	local containers = {
		FD.Global("UICity"),
		FD.Global("MainCity"),
		FD.Global("SelectedCity"),
		FD.Global("UIColony"),
	}

	for _, container in ipairs(containers) do
		if container then
			FD.PruneLabelsTable(FD.ReadField(container, "labels"), delete_set, false)
		end
	end
end

function FD.PruneObjectFromGlobalLabels(obj)
	FD.PruneObjectsFromGlobalLabels({ [obj] = true })
end

function FD.ForEachContainedEntry(list, callback)
	FD.ForEachTableObject(list, callback, FD.MAX_CONTAINED_LABEL_SCAN)
end


-- ============================================================================
-- fd_selection.lua
-- ============================================================================

function FD.ResolveContext(context)
	if not context then
		return false
	end

	return FD.SafeCall(FD.Global("ResolvePropObj"), context) or context
end

function FD.ContextObjectFromDialog(dialog)
	if not dialog then
		return false
	end

	local context = FD.ReadField(dialog, "context") or FD.CallMethod(dialog, "GetContext") or FD.ReadField(dialog, "Context")
	local obj = FD.ResolveContext(context)

	return FD.IsObjectValid(obj) and obj or false
end

function FD.ValidObjectsFromArray(list)
	local objects = {}

	if type(list) ~= "table" then
		return objects
	end

	for _, obj in ipairs(list) do
		if FD.IsObjectValid(obj) then
			objects[#objects + 1] = obj
		end
	end

	return objects
end

function FD.SelectedObjects()
	local objects = FD.ValidObjectsFromArray(FD.Global("Selection"))

	if #objects > 1 then
		return objects
	end

	local infopanel = FD.SafeCall(FD.Global("GetDialog"), "Infopanel")
	local obj = FD.ContextObjectFromDialog(infopanel)

	if obj then
		return { obj }
	end

	obj = FD.Global("SelectedObj")

	if FD.IsObjectValid(obj) then
		return { obj }
	end

	if #objects == 1 then
		return objects
	end

	local editor = FD.Global("editor")

	if editor and type(editor.GetSel) == "function" then
		objects = FD.ValidObjectsFromArray(FD.SafeCall(editor.GetSel))

		if #objects > 0 then
			return objects
		end
	end

	local selo = FD.Global("selo")

	if type(selo) == "function" then
		obj = FD.SafeCall(selo)

		if FD.IsObjectValid(obj) then
			return { obj }
		end
	end

	return {}
end

function FD.HasSelectedObject()
	if FD.IsObjectValid(FD.Global("SelectedObj")) then
		return true
	end

	return #FD.SelectedObjects() > 0
end

function FD.ClearSelection()
	FD.SafeCall(FD.Global("SelectObj"), false)

	local editor = FD.Global("editor")

	if editor and type(editor.ClearSel) == "function" then
		pcall(function()
			editor.ClearSel()
		end)
	end
end

-- Return whether an object can be safely tracked by XEditorUndo.

function FD.IsHudVisible()
	local hud = FD.SafeCall(FD.Global("GetHUD"))

	return hud and type(hud.GetVisible) == "function" and hud:GetVisible()
end

-- Register the bindable delete actions in the game shortcut container.


-- ============================================================================
-- fd_collect.lua
-- ============================================================================

function FD.PassageObjectFor(obj)
	if FD.IsPassageObject(obj) then
		return obj
	end

	local passage_obj = FD.ReadField(obj, "passage_obj")

	return FD.IsPassageObject(passage_obj) and passage_obj or false
end

function FD.HasPassageReference(obj)
	return FD.IsObjectValid(obj)
		and (type(FD.ReadField(obj, "elements")) == "table" or FD.ReadField(obj, "passage_obj") ~= nil)
end

function FD.SamePassageTarget(left, right)
	if left == right then
		return true
	end

	if not FD.HasPassageReference(left) or not FD.HasPassageReference(right) then
		return false
	end

	local left_passage = FD.PassageObjectFor(left)
	local right_passage = FD.PassageObjectFor(right)

	return left_passage and right_passage and left_passage == right_passage
end

function FD.PreparePassageForDelete(obj)
	if not FD.IsPassageObject(obj) then
		return
	end

	-- Passage elements ask the passage whether it can delete itself while the
	-- passage is already being deleted. Keep them from DoneObject-ing it twice.
	FD.WriteField(obj, "CanDelete", function()
		return false
	end)
end

function FD.AddPassageRelatedObject(objects, seen, obj)
	if FD.IsObjectValid(obj) and not seen[obj] then
		seen[obj] = true
		objects[#objects + 1] = obj
	end
end

function FD.CollectPassageRelatedObjects(passage)
	local objects = {}
	local seen = {}

	if not FD.IsPassageObject(passage) then
		return objects
	end

	FD.AddPassageRelatedObject(objects, seen, passage)

	for _, field in ipairs({
		"elements",
		"elements_under_construction",
		"traversing_colonists",
		"start_el",
		"end_el",
	}) do
		local value = FD.ReadField(passage, field)

		if FD.IsObjectValid(value) then
			FD.AddPassageRelatedObject(objects, seen, value)
		elseif type(value) == "table" then
			for _, obj in ipairs(value) do
				FD.AddPassageRelatedObject(objects, seen, obj)
			end

			for key, obj in pairs(value) do
				FD.AddPassageRelatedObject(objects, seen, key)
				FD.AddPassageRelatedObject(objects, seen, obj)
			end
		end
	end

	return objects
end

-- Detect whether an object is a dome floor/terrain visual attachment.

function FD.MarkerCandidate(obj, key)
	local candidate = FD.ReadField(obj, key) or FD.ReadProperty(obj, key)

	return FD.IsObjectValid(candidate) and candidate or false
end

function FD.FindMarker(obj, visited)
	if not FD.IsObjectValid(obj) then
		return false
	end

	if FD.IsMarker(obj) then
		return obj
	end

	visited = visited or {}

	if visited[obj] then
		return false
	end

	visited[obj] = true

	for _, key in ipairs({ "marker", "placed_obj" }) do
		local candidate = FD.MarkerCandidate(obj, key)

		if candidate then
			return candidate
		end
	end

	local deposit = FD.CallMethod(obj, "GetDeposit")

	if FD.IsObjectValid(deposit) then
		return deposit
	end

	local group = FD.ReadField(obj, "group")

	if type(group) == "table" then
		local scanned = 0

		for _, group_obj in ipairs(group) do
			scanned = scanned + 1

			if scanned > FD.MAX_MARKER_GROUP_SCAN then
				break
			end

			local marker = FD.FindMarker(group_obj, visited)

			if FD.IsObjectValid(marker) then
				return marker
			end
		end
	end

	return false
end

function FD.CollectResourceDepositObjects(obj, objects, seen)
	if not FD.IsObjectValid(obj) then
		return
	end

	if not FD.MarkObject(seen, obj) then
		return
	end

	FD.AddUniqueObject(objects, obj)

	local marker = FD.FindMarker(obj)

	if FD.IsObjectValid(marker) and marker ~= obj then
		FD.AddUniqueObject(objects, marker)
	end

	local candidate_fields = {
		"marker",
		"placed_obj",
		"deposit",
		"deposits",
		"group",
		"objects",
		"resources",
		"markers",
		"surface",
		"subsurface",
		"deep",
		"pieces",
	}

	for _, field in ipairs(candidate_fields) do
		local value = FD.ReadField(obj, field) or FD.ReadProperty(obj, field)

		if FD.IsObjectValid(value) and value ~= obj then
			if FD.IsResourceDepositObject(value) or FD.IsMarker(value) then
				FD.CollectResourceDepositObjects(value, objects, seen)
			end
		elseif type(value) == "table" then
			FD.ForEachContainedEntry(value, function(child)
				if child ~= obj and (FD.IsResourceDepositObject(child) or FD.IsMarker(child)) then
					FD.CollectResourceDepositObjects(child, objects, seen)
				end
			end)
		end
	end
end

function FD.CollectContainedObjects(container, objects, seen)
	local labels = FD.ReadField(container, "labels")

	if type(labels) ~= "table" then
		return
	end

	for _, label_list in pairs(labels) do
		FD.ForEachContainedEntry(label_list, function(child)
			if child ~= container and not FD.IsProtectedUnit(child) then
				FD.CollectDeleteObjects(child, objects, seen, false)
			end
		end)
	end
end

FD.CollectDeleteObjects = function(obj, objects, seen, is_root)
	if FD.IsProtectedUnit(obj) and not is_root then
		return
	end

	local passage_obj = FD.PassageObjectFor(obj)

	if passage_obj and passage_obj ~= obj then
		FD.CollectDeleteObjects(passage_obj, objects, seen, is_root)
		return
	end

	if FD.IsResourceDepositObject(obj) or FD.IsMarker(obj) then
		FD.CollectResourceDepositObjects(obj, objects, seen)
		return
	end

	if not FD.MarkObject(seen, obj) then
		return
	end

	if not FD.IsProtectedUnit(obj) then
		FD.CollectContainedObjects(obj, objects, seen)
	end

	FD.AddUniqueObject(objects, obj)

	if not FD.IsProtectedUnit(obj) then
		local marker = FD.FindMarker(obj)

		if FD.IsObjectValid(marker) and marker ~= obj then
			FD.AddUniqueObject(objects, marker)
		end
	end
end


-- ============================================================================
-- fd_cleanup_colonists.lua
-- ============================================================================

function FD.RemoveColonistFromTransportObject(obj, colonist)
	if not obj then
		return
	end

	for _, field in ipairs({
		"colonists_inbound",
		"waiting_for_train",
		"units",
		"visitors",
	}) do
		FD.RemoveObjectFromTableEntries(FD.ReadField(obj, field), colonist)
	end
end

function FD.ClearColonistTransportState(colonist)
	if not FD.IsColonist(colonist) then
		return
	end

	local holder = FD.ReadField(colonist, "holder")

	if FD.IsObjectValid(holder) then
		local exit_pos = false

		if type(FD.ReadField(holder, "GetImmediateExitPos")) == "function" then
			pcall(function()
				exit_pos = holder:GetImmediateExitPos(colonist)
			end)
		end

		if not exit_pos and type(FD.ReadField(holder, "GetPos")) == "function" then
			pcall(function()
				exit_pos = holder:GetPos()
			end)
		end

		if exit_pos and type(FD.ReadField(colonist, "SetPos")) == "function" then
			pcall(function()
				colonist:SetPos(exit_pos)
			end)
		end
	end

	local ticket = FD.ReadField(colonist, "transport_ticket")

	if type(ticket) == "table" then
		for _, field in ipairs({ "src_station", "dst_station", "vehicle", "destination" }) do
			FD.RemoveColonistFromTransportObject(FD.ReadField(ticket, field), colonist)
		end
	end

	FD.RemoveColonistFromTransportObject(holder, colonist)

	local assign_to_service = FD.ReadField(colonist, "AssignToService")

	if type(assign_to_service) == "function" then
		pcall(function()
			assign_to_service(colonist, false)
		end)
	end

	if type(FD.ReadField(colonist, "ClearPath")) == "function" then
		pcall(function()
			colonist:ClearPath()
		end)
	end

	-- SetHolder(false) may call OnExitHolder on a holder that hard-delete is
	-- about to destroy. Clear the raw field like the game's invalid-holder fixup.
	FD.WriteField(colonist, "holder", false)
	FD.WriteField(colonist, "lead_in_out", false)
	FD.WriteField(colonist, "lead_interrupted", true)
	FD.WriteField(colonist, "visit_end_time", false)
	FD.WriteField(colonist, "visit_spot_end_time", false)
	colonist.transport_ticket = false
	colonist.work_route = false
	colonist.leave_early_for_work = false
end

function FD.TransportTicketTargetsObject(ticket, obj)
	if type(ticket) ~= "table" then
		return false
	end

	for _, field in ipairs({ "src_station", "dst_station", "destination", "vehicle", "param" }) do
		if FD.SamePassageTarget(FD.ReadField(ticket, field), obj) then
			return true
		end
	end

	return false
end

function FD.ColonistTargetsObject(colonist, obj)
	if not FD.IsColonist(colonist) then
		return false
	end

	for _, field in ipairs({
		"holder",
		"dome",
		"workplace",
		"residence",
		"reserved_residence",
		"assigned_to_service",
		"arriving",
		"emigration_dome",
		"emigration_elevator",
		"leaving_elevator",
	}) do
		if FD.SamePassageTarget(FD.ReadField(colonist, field), obj) then
			return true
		end
	end

	if FD.TransportTicketTargetsObject(FD.ReadField(colonist, "transport_ticket"), obj) then
		return true
	end

	if FD.TableContainsObject(FD.ReadField(colonist, "work_route"), obj) then
		return true
	end

	local work_route = FD.ReadField(colonist, "work_route")

	if type(work_route) == "table" then
		for _, route_obj in ipairs(work_route) do
			if FD.SamePassageTarget(route_obj, obj) then
				return true
			end
		end

		for key, route_obj in pairs(work_route) do
			if FD.SamePassageTarget(key, obj) or FD.SamePassageTarget(route_obj, obj) then
				return true
			end
		end
	end

	return false
end

function FD.DetachColonistsTargetingObject(obj)
	local seen_containers = {}

	for _, container in ipairs({
		FD.ReadField(obj, "city"),
		FD.Global("UICity"),
		FD.Global("MainCity"),
		FD.Global("SelectedCity"),
		FD.Global("UIColony"),
	}) do
		if container and not seen_containers[container] then
			seen_containers[container] = true

			local labels = FD.ReadField(container, "labels")
			local colonists = labels and labels.Colonist

			if type(colonists) == "table" then
				local scanned = 0

				for _, colonist in ipairs(colonists) do
					scanned = scanned + 1

					if scanned > FD.MAX_CONTAINED_LABEL_SCAN then
						break
					end

					if FD.ColonistTargetsObject(colonist, obj) then
						FD.DetachColonist(colonist)
					end
				end
			end
		end
	end
end

function FD.NeutralizeColonistStatusSigns(colonist)
	if not FD.IsColonist(colonist) then
		return
	end

	if type(FD.ReadField(colonist, "DestroyAttaches")) == "function" then
		pcall(function()
			colonist:DestroyAttaches("UnitSign")
		end)
	end

	FD.WriteField(colonist, "status_effect_sign", false)
	FD.WriteField(colonist, "status_effect_sign_visible", false)
	FD.WriteField(colonist, "status_effects", {})
end

-- Detach colonists from common ownership fields before deleting containers.

FD.DetachColonist = function(colonist)
	if not FD.IsColonist(colonist) then
		return
	end

	FD.NeutralizeColonistStatusSigns(colonist)
	FD.ClearColonistTransportState(colonist)
	FD.StopCommandObject(colonist)

	for _, method in ipairs({ "SetWorkplace", "SetResidence", "SetDome" }) do
		local fn = FD.ReadField(colonist, method)

		if type(fn) == "function" then
			pcall(function()
				fn(colonist, false)
			end)
		end
	end
end

function FD.DetachColonistsFromTable(list)
	if type(list) ~= "table" then
		return
	end

	for _, obj in ipairs(list) do
		FD.DetachColonist(obj)
	end

	for key, value in pairs(list) do
		FD.DetachColonist(value)
		FD.DetachColonist(key)
	end
end

function FD.DetachContainedColonists(obj)
	if FD.IsColonist(obj) then
		FD.DetachColonist(obj)
		return
	end

	for _, field in ipairs({
		"workers",
		"colonists",
		"residents",
		"occupants",
		"children",
		"visitors",
		"patients",
		"students",
		"residence_colonists",
		"service_comfort_workers",
		"colonists_inbound",
		"waiting_for_train",
		"units",
		"transported_passengers",
		"cargo_request_passengers",
		"cargo_passengers",
		"crew",
		"disembarking",
		"traversing_colonists",
	}) do
		local value = FD.ReadField(obj, field)

		if FD.IsColonist(value) then
			FD.DetachColonist(value)
		else
			FD.DetachColonistsFromTable(value)
		end
	end

	local labels = FD.ReadField(obj, "labels")

	if type(labels) == "table" then
		for _, label_list in pairs(labels) do
			FD.DetachColonistsFromTable(label_list)
		end
	end

	FD.DetachColonistsTargetingObject(obj)

	local passage_obj = FD.PassageObjectFor(obj)

	if passage_obj == obj then
		for _, related in ipairs(FD.CollectPassageRelatedObjects(passage_obj)) do
			if related ~= obj then
				FD.DetachContainedColonists(related)
			end
		end
	end
end


-- ============================================================================
-- fd_cleanup_animals.lua
-- ============================================================================

function FD.AddContainedAnimal(animals, seen, obj)
	if not FD.IsAnimal(obj) or seen[obj] then
		return
	end

	seen[obj] = true
	animals[#animals + 1] = obj
end

function FD.CollectAnimalsFromTable(list, animals, seen)
	if type(list) ~= "table" then
		return
	end

	for _, obj in ipairs(list) do
		FD.AddContainedAnimal(animals, seen, obj)
	end

	for key, value in pairs(list) do
		FD.AddContainedAnimal(animals, seen, value)
		FD.AddContainedAnimal(animals, seen, key)
	end
end

function FD.RemoveAnimalFromTable(list, animal)
	FD.RemoveObjectFromTableEntries(list, animal)
end

function FD.StopAnimalCommand(animal)
	FD.StopCommandObject(animal)
end

function FD.DeleteAnimalNow(animal)
	if not FD.IsAnimal(animal) then
		return false
	end

	local ok = pcall(function()
		local dome = FD.ReadField(animal, "dome")
		local pasture = FD.ReadField(animal, "pasture")

		if FD.IsObjectValid(dome) and type(FD.ReadField(dome, "RemoveFromLabel")) == "function" then
			pcall(function()
				dome:RemoveFromLabel("Pet", animal)
			end)
		end

		if FD.IsObjectValid(pasture) then
			FD.RemoveAnimalFromTable(FD.ReadField(pasture, "current_herd"), animal)
			FD.RemoveAnimalFromTable(FD.ReadField(pasture, "animals"), animal)
		end

		FD.StopAnimalCommand(animal)

		if type(FD.ReadField(animal, "delete")) == "function" then
			animal:delete()
			return
		end

		FD.SafeCall(FD.Global("DoneObject"), animal)
	end)

	return ok
end

function FD.DeleteContainedAnimals(obj)
	if not FD.IsObjectValid(obj) or FD.IsAnimal(obj) then
		return
	end

	local animals, seen = {}, {}

	for _, field in ipairs({
		"animal",
		"animals",
		"pets",
		"current_herd",
		"herd",
		"spawned_animals",
		"visitors",
		"children",
	}) do
		local value = FD.ReadField(obj, field)

		if FD.IsAnimal(value) then
			FD.AddContainedAnimal(animals, seen, value)
		else
			FD.CollectAnimalsFromTable(value, animals, seen)
		end
	end

	local labels = FD.ReadField(obj, "labels")

	if type(labels) == "table" then
		for _, label_name in ipairs({
			"Pet",
			"Animal",
			"Animals",
			"BaseAnimal",
			"BasePet",
			"RoamingPet",
			"StaticPet",
			"PastureAnimal",
		}) do
			FD.CollectAnimalsFromTable(labels[label_name], animals, seen)
		end
	end

	for _, animal in ipairs(animals) do
		FD.DeleteAnimalNow(animal)
	end
end


-- ============================================================================
-- fd_cleanup_drones.lua
-- ============================================================================

function FD.ObjectInDeleteSet(obj, delete_set)
	if not FD.IsObjectValid(obj) then
		return false
	end

	if delete_set[obj] then
		return true
	end

	local parent = FD.ReadField(obj, "parent")

	if parent and delete_set[parent] then
		return true
	end

	local building = FD.ReadField(obj, "building")

	if building and delete_set[building] then
		return true
	end

	return false
end

function FD.RequestSource(req, unit)
	if not req or type(FD.ReadField(req, "GetSource")) ~= "function" then
		return false
	end

	local ok, source = pcall(function()
		return req:GetSource(unit)
	end)

	return ok and source or false
end

function FD.DroneRequestTargetsDeletedObject(drone, req, delete_set)
	if not req then
		return false
	end

	if delete_set[req] then
		return true
	end

	local source = FD.RequestSource(req, drone)

	return FD.ObjectInDeleteSet(source, delete_set)
end

function FD.DroneTargetsDeletedObject(drone, delete_set)
	if not FD.IsDroneObject(drone) then
		return false
	end

	for _, field in ipairs({
		"target",
		"goto_target",
		"fx_moving_target",
		"rogue_target",
		"holder",
		"building",
		"command_center",
	}) do
		if FD.ObjectInDeleteSet(FD.ReadField(drone, field), delete_set) then
			return true
		end
	end

	for _, field in ipairs({
		"d_request",
		"s_request",
		"w_request",
		"picked_up_from_req",
	}) do
		if FD.DroneRequestTargetsDeletedObject(drone, FD.ReadField(drone, field), delete_set) then
			return true
		end
	end

	return false
end

function FD.DroneHasCarriedResource(drone)
	local resource = FD.ReadField(drone, "resource")
	local amount = FD.ReadField(drone, "amount")

	return resource and amount and amount ~= 0
end

function FD.DroneIsActiveDelivery(drone)
	local command = FD.ReadField(drone, "command")

	return command == "Deliver"
		or command == "PickUp"
		or command == "Work"
		or FD.DroneHasCarriedResource(drone)
end

function FD.DroneShouldResetForDelete(drone, delete_set, affected_cities)
	if FD.DroneTargetsDeletedObject(drone, delete_set) then
		return true
	end

	local city = FD.ReadField(drone, "city")

	return affected_cities[city] and FD.DroneIsActiveDelivery(drone)
end

function FD.ResetDroneForDeletedTarget(drone)
	if not FD.IsDroneObject(drone) then
		return
	end

	-- Do not call SetCommand("Reset") here. Reset can run command
	-- destructors later, and those destructors may call DroneUnloadResource on
	-- a stockpile/building whose map state was just invalidated by hard-delete.
	-- Hard-delete needs an immediate raw detach instead.
	FD.StopCommandObject(drone)

	for _, method_name in ipairs({
		"DroneLoadResource",
		"DroneUnloadResource",
		"DroneWork",
	}) do
		FD.WriteField(drone, method_name, FD.ForceDeleteNoOp)
	end

	for _, field in ipairs({
		"target",
		"goto_target",
		"fx_moving_target",
		"rogue_target",
		"holder",
		"building",
		"command_center",
		"d_request",
		"s_request",
		"w_request",
		"picked_up_from_req",
		"request",
		"resource_request",
		"destination",
		"resource",
	}) do
		FD.WriteField(drone, field, false)
	end

	FD.WriteField(drone, "amount", 0)
	FD.WriteField(drone, "command", false)
	FD.WriteField(drone, "command_queue", nil)
	FD.WriteField(drone, "command_destructors", false)

	if type(FD.ReadField(drone, "DestroyAttaches")) == "function" then
		pcall(function()
			drone:DestroyAttaches("ResourceStockpileBox")
		end)
	end
end

function FD.ResetDronesFromTable(list, delete_set, affected_cities, seen)
	if type(list) ~= "table" then
		return
	end

	local scanned = 0

	for _, drone in ipairs(list) do
		scanned = scanned + 1

		if scanned > FD.MAX_CONTAINED_LABEL_SCAN then
			return
		end

		if FD.IsDroneObject(drone) and not seen[drone] then
			seen[drone] = true

			if FD.DroneShouldResetForDelete(drone, delete_set, affected_cities) then
				FD.ResetDroneForDeletedTarget(drone)
			end
		end
	end

	for key, drone in pairs(list) do
		scanned = scanned + 1

		if scanned > FD.MAX_CONTAINED_LABEL_SCAN then
			return
		end

		for _, candidate in ipairs({ key, drone }) do
			if FD.IsDroneObject(candidate) and not seen[candidate] then
				seen[candidate] = true

				if FD.DroneShouldResetForDelete(candidate, delete_set, affected_cities) then
					FD.ResetDroneForDeletedTarget(candidate)
				end
			end
		end
	end
end

function FD.ResetDronesTargetingDeletedObjects(objects_to_delete, delete_set)
	local seen = {}
	local affected_cities = {}
	local containers = {}
	local seen_containers = {}

	local function add_container(container)
		if container and not seen_containers[container] then
			seen_containers[container] = true
			containers[#containers + 1] = container
		end
	end

	for _, obj in ipairs(objects_to_delete) do
		local city = FD.ReadField(obj, "city")

		if city then
			affected_cities[city] = true
			add_container(city)
		end

		FD.ResetDronesFromTable(FD.ReadField(obj, "drones"), delete_set, affected_cities, seen)

		local labels = FD.ReadField(obj, "labels")

		if type(labels) == "table" then
			FD.ResetDronesFromTable(labels.Drone, delete_set, affected_cities, seen)
		end
	end

	for _, container in ipairs({
		FD.Global("UICity"),
		FD.Global("MainCity"),
		FD.Global("SelectedCity"),
		FD.Global("UIColony"),
	}) do
		add_container(container)
	end

	for _, container in ipairs(containers) do
		local labels = FD.ReadField(container, "labels")

		if type(labels) == "table" then
			FD.ResetDronesFromTable(labels.Drone, delete_set, affected_cities, seen)
		end
	end
end


-- ============================================================================
-- fd_cleanup_stockpiles.lua
-- ============================================================================

function FD.StockpileStoredAmount(stockpile)
	if not FD.IsObjectValid(stockpile) then
		return 0
	end

	local get_stored_amount = FD.ReadField(stockpile, "GetStoredAmount")

	if type(get_stored_amount) == "function" then
		local ok, amount = pcall(function()
			return get_stored_amount(stockpile)
		end)

		if ok and type(amount) == "number" then
			return amount
		end
	end

	local amount = FD.ReadField(stockpile, "stockpiled_amount")

	return type(amount) == "number" and amount or 0
end

function FD.PauseResourceProducer(obj)
	if not FD.IsObjectValid(obj) then
		return
	end

	if FD.IsKindOf(obj, "ResourceProducer") or FD.ReadField(obj, "producers") then
		FD.WriteField(obj, "working", false)
		FD.WriteField(obj, "last_production_start_ts", false)
	end
end

function FD.PruneStockpileController(controller, delete_set)
	if not FD.IsStockpileControllerObject(controller) then
		return
	end

	local stockpiles = FD.ReadField(controller, "stockpiles")
	local total_stockpiled = 0
	local kept = 0

	for i = #stockpiles, 1, -1 do
		local stockpile = stockpiles[i]

		if delete_set[stockpile] or not FD.IsObjectValid(stockpile) then
			if FD.IsResourceStockpileObject(stockpile) then
				FD.WriteField(stockpile, "parent", false)
				FD.WriteField(stockpile, "destroy_when_empty", true)
			end

			table.remove(stockpiles, i)
		else
			kept = kept + 1
			total_stockpiled = total_stockpiled + FD.StockpileStoredAmount(stockpile)
		end
	end

	for key, stockpile in pairs(stockpiles) do
		if delete_set[key] or delete_set[stockpile] or not FD.IsObjectValid(stockpile) then
			stockpiles[key] = nil
		end
	end

	if kept <= 0 then
		FD.WriteField(controller, "stockpiles", {})
		FD.WriteField(controller, "total_stockpiled", 0)
		FD.WriteField(controller, "next_stockpile_idx", 1)
		FD.WriteField(controller, "current_stockpile_idx_stockpiled_amount", 0)
		return
	end

	local next_stockpile_idx = FD.ReadField(controller, "next_stockpile_idx")

	if type(next_stockpile_idx) ~= "number" or next_stockpile_idx < 1 or next_stockpile_idx > kept then
		FD.WriteField(controller, "next_stockpile_idx", 1)
	end

	FD.WriteField(controller, "total_stockpiled", total_stockpiled)
	FD.WriteField(controller, "current_stockpile_idx_stockpiled_amount", 0)
end

function FD.ForEachProducerController(obj, callback)
	local visited = {}

	local function visit(controller)
		if FD.IsObjectValid(controller) and not visited[controller] then
			visited[controller] = true
			callback(controller)
		end
	end

	visit(obj)
	visit(FD.ReadField(obj, "wasterock_producer"))

	local producers = FD.ReadField(obj, "producers")

	if type(producers) == "table" then
		for _, producer in ipairs(producers) do
			visit(producer)
		end

		for _, producer in pairs(producers) do
			visit(producer)
		end
	end
end

function FD.ForceDeleteNoOp()
	return false
end

function FD.NeutralizeStockpileCallbacks(stockpile)
	if not FD.IsObjectValid(stockpile) then
		return
	end

	for _, method_name in ipairs({
		"SetCount",
		"SetCountInternal",
		"SetCountFromRequest",
		"DroneLoadResource",
		"DroneUnloadResource",
		"UpdateVisualStockpile",
	}) do
		FD.WriteField(stockpile, method_name, FD.ForceDeleteNoOp)
	end

	FD.WriteField(stockpile, "parent", false)
	FD.WriteField(stockpile, "destroy_when_empty", true)
end

function FD.NeutralizeStockpileTableCallbacks(stockpiles)
	if type(stockpiles) ~= "table" then
		return
	end

	local scanned = 0

	for _, stockpile in ipairs(stockpiles) do
		scanned = scanned + 1

		if scanned > FD.MAX_CONTAINED_LABEL_SCAN then
			return
		end

		FD.NeutralizeStockpileCallbacks(stockpile)
	end

	for key, stockpile in pairs(stockpiles) do
		scanned = scanned + 1

		if scanned > FD.MAX_CONTAINED_LABEL_SCAN then
			return
		end

		FD.NeutralizeStockpileCallbacks(key)
		FD.NeutralizeStockpileCallbacks(stockpile)
	end
end

function FD.NeutralizeDroneResourceCallbacks(obj)
	if not FD.IsObjectValid(obj) then
		return
	end

	for _, method_name in ipairs({
		"DroneLoadResource",
		"DroneUnloadResource",
		"DroneWork",
		"ConsumptionDroneUnload",
		"MaintenanceDroneUnload",
		"UpdateVisualStockpile",
		"UpdateRequestConnectivity",
		"UpdateConsumption",
		"RunProduction",
		"Produce",
		"DoesHaveConsumption",
		"DoesRequireMaintenance",
		"IsOwnRequest",
	}) do
		FD.WriteField(obj, method_name, FD.ForceDeleteNoOp)
	end

	FD.NeutralizeStockpileCallbacks(FD.ReadField(obj, "consumption_resource_stockpile"))
	FD.NeutralizeStockpileTableCallbacks(FD.ReadField(obj, "stockpiles"))
	FD.WriteField(obj, "consumption_resource_stockpile", false)
	FD.WriteField(obj, "consumption_resource_request", false)
	FD.WriteField(obj, "maintenance_resource_request", false)
end

function FD.NeutralizeDroneResourceCallbacksForDelete(objects_to_delete)
	for _, obj in ipairs(objects_to_delete) do
		if FD.IsObjectValid(obj) then
			FD.NeutralizeDroneResourceCallbacks(obj)

			FD.ForEachProducerController(obj, function(controller)
				FD.NeutralizeDroneResourceCallbacks(controller)
			end)
		end
	end
end

function FD.CleanupStockpileReferences(objects_to_delete, delete_set)
	for _, obj in ipairs(objects_to_delete) do
		if FD.IsObjectValid(obj) then
			FD.PauseResourceProducer(obj)

			FD.ForEachProducerController(obj, function(controller)
				FD.PruneStockpileController(controller, delete_set)
				FD.WriteField(controller, "last_production_start_ts", false)
			end)

			local parent = FD.ReadField(obj, "parent")

			if parent then
				FD.PruneStockpileController(parent, delete_set)
			end

			if FD.IsResourceStockpileObject(obj) then
				FD.WriteField(obj, "parent", false)
			end
		end
	end
end

-- Detect whether an object is a visible or marker-backed resource deposit.


-- ============================================================================
-- fd_cleanup_deposits.lua
-- ============================================================================

function FD.UnregisterDepositObject(obj)
	if not FD.IsObjectValid(obj) then
		return
	end

	local marker = false

	if FD.IsMarker(obj) then
		marker = obj
	else
		marker = FD.FindMarker(obj)
	end

	if not FD.IsObjectValid(marker) then
		return
	end

	local city = FD.SafeCall(FD.Global("GetCity"), marker) or FD.Global("UICity")
	local sector = false

	if city then
		sector = FD.SafeCall(FD.Global("GetMapSector"), city, marker)
	end

	if sector and type(FD.ReadField(sector, "UnregisterDeposit")) == "function" then
		pcall(function()
			sector:UnregisterDeposit(marker)
		end)
	end

	local markers = sector and FD.ReadField(sector, "markers")

	if type(markers) == "table" then
		FD.RemoveObjectFromTable(markers.surface, marker)
		FD.RemoveObjectFromTable(markers.subsurface, marker)
		FD.RemoveObjectFromTable(markers.deep, marker)
		FD.RemoveObjectFromTable(markers.block, marker)
	end

	if sector then
		FD.RemoveObjectFromTable(FD.ReadField(sector, "revealed_surf"), marker)
		FD.RemoveObjectFromTable(FD.ReadField(sector, "revealed_deep"), marker)
	end

	FD.PruneObjectFromGlobalLabels(marker)
end


-- ============================================================================
-- fd_cleanup_domes.lua
-- ============================================================================

function FD.DisableObjectLights(obj)
	if not FD.IsObjectValid(obj) then
		return
	end

	if type(FD.ReadField(obj, "SetIsNightLightPossible")) == "function" then
		pcall(function()
			obj:SetIsNightLightPossible(false, true)
		end)

		pcall(function()
			obj:SetIsNightLightPossible(false)
		end)
	end

	if type(FD.ReadField(obj, "NightLightDisable")) == "function" then
		pcall(function()
			obj:NightLightDisable()
		end)
	end

	if type(FD.ReadField(obj, "WorkLightsOff")) == "function" then
		pcall(function()
			obj:WorkLightsOff()
		end)
	elseif type(FD.ReadField(obj, "SetSIModulation")) == "function" then
		pcall(function()
			obj:SetSIModulation(0)
		end)
	end
end

function FD.ClearLightFlags(obj)
	if type(FD.ReadField(obj, "ClearLightFlags")) ~= "function" then
		return
	end

	local game_const = FD.Global("const")

	if not game_const then
		return
	end

	for _, flag_name in ipairs({
		"elfInterior",
		"elfExterior",
		"elfInteriorAndExteriorWhenHasShadowmap",
		"elfCastShadows",
		"elfTerrainShadows",
		"elfDetailedShadows",
	}) do
		local flag = game_const[flag_name]

		if flag then
			pcall(function()
				obj:ClearLightFlags(flag)
			end)
		end
	end
end

function FD.NeutralizeClusterLight(obj)
	if not FD.IsObjectValid(obj) then
		return
	end

	FD.DisableObjectLights(obj)

	local game_const = FD.Global("const")

	if game_const and game_const.efVisible and type(FD.ReadField(obj, "ClearEnumFlags")) == "function" then
		pcall(function()
			obj:ClearEnumFlags(game_const.efVisible)
		end)
	end

	FD.ClearLightFlags(obj)

	for _, method_name in ipairs({
		"SetIntensity",
		"SetIntensity0",
		"SetIntensity1",
		"SetConstantIntensity",
	}) do
		local method = FD.ReadField(obj, method_name)

		if type(method) == "function" then
			pcall(function()
				method(obj, 0)
			end)
		end
	end

	for _, method_name in ipairs({
		"SetVolumeId",
		"SetTargetVolumeId",
	}) do
		local method = FD.ReadField(obj, method_name)

		if type(method) == "function" then
			pcall(function()
				method(obj, 0)
			end)
		end
	end

	if game_const and game_const.eLightTypePoint and type(FD.ReadField(obj, "SetLightType")) == "function" then
		pcall(function()
			obj:SetLightType(game_const.eLightTypePoint)
		end)
	end

	if type(FD.ReadField(obj, "DestroyRenderObj")) == "function" then
		pcall(function()
			obj:DestroyRenderObj(true)
		end)

		pcall(function()
			obj:DestroyRenderObj()
		end)
	end
end

function FD.DestroyLightObject(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	FD.NeutralizeClusterLight(obj)

	if type(FD.ReadField(obj, "Destroy")) == "function" then
		local ok = pcall(function()
			obj:Destroy()
		end)

		if ok then
			return true
		end
	end

	local ok = pcall(function()
		if type(FD.ReadField(obj, "delete")) == "function" then
			obj:delete()
			return
		end

		FD.SafeCall(FD.Global("DoneObject"), obj)
	end)

	return ok
end

function FD.NeedsRenderObjectsRebuild(objects_to_delete)
	for _, obj in ipairs(objects_to_delete) do
		if FD.IsDome(obj) or FD.IsComponentLightObject(obj) then
			return true
		end
	end

	return false
end

function FD.AddDomeLight(lights, seen, obj)
	if FD.IsComponentLightObject(obj) and not seen[obj] then
		seen[obj] = true
		lights[#lights + 1] = obj
	end
end

function FD.CollectDomeLights(dome)
	local lights = {}
	local seen = {}

	FD.AddDomeLight(lights, seen, FD.ReadField(dome, "cupola_interior_marker"))

	if type(FD.ReadField(dome, "ForEachAttach")) == "function" then
		pcall(function()
			dome:ForEachAttach("ComponentLight", function(attach)
				FD.AddDomeLight(lights, seen, attach)
			end)
		end)

		pcall(function()
			dome:ForEachAttach(function(attach)
				FD.AddDomeLight(lights, seen, attach)
			end)
		end)
	end

	return lights
end

function FD.DisableObjectsLightsFromTable(list, seen)
	if type(list) ~= "table" then
		return
	end

	local scanned = 0

	for _, obj in ipairs(list) do
		scanned = scanned + 1

		if scanned > FD.MAX_CONTAINED_LABEL_SCAN then
			return
		end

		if FD.IsObjectValid(obj) and not seen[obj] then
			seen[obj] = true
			FD.DisableObjectLights(obj)
		end
	end

	for key, value in pairs(list) do
		if scanned > FD.MAX_CONTAINED_LABEL_SCAN then
			return
		end

		local obj = false

		if FD.IsObjectValid(value) then
			obj = value
		elseif FD.IsObjectValid(key) then
			obj = key
		end

		if obj and not seen[obj] then
			scanned = scanned + 1
			seen[obj] = true
			FD.DisableObjectLights(obj)
		end
	end
end

function FD.DisableDomeLights(dome)
	if not FD.IsDome(dome) then
		return
	end

	local seen = {}

	seen[dome] = true
	FD.DisableObjectLights(dome)

	local labels = FD.ReadField(dome, "labels")

	if type(labels) == "table" then
		for _, label_list in pairs(labels) do
			FD.DisableObjectsLightsFromTable(label_list, seen)
		end
	end

	for _, light in ipairs(FD.CollectDomeLights(dome)) do
		FD.DestroyLightObject(light)
	end

	FD.WriteField(dome, "cupola_interior_marker", false)
end

-- Remove one valid object without invoking recursive delete logic.

function FD.ForceDeleteObject(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	FD.DisableObjectLights(obj)

	local ok = pcall(function()
		if type(FD.ReadField(obj, "delete")) == "function" then
			obj:delete()
			return
		end

		FD.SafeCall(FD.Global("DoneObject"), obj)
	end)

	return ok
end

-- Remove dome floor, grass, decals, and road visual attachments only.

function FD.ClearDomeVisuals(dome)
	if not FD.IsDome(dome) then
		return
	end

	local attach_classes = {
		"BakedDomeDecal",
		"BakedDomeDecalLarge",
		"DomeTerrain",
		"DomeGrass",
		"DomeRoadConnection",
	}

	if type(FD.ReadField(dome, "DestroyAttaches")) == "function" then
		for _, class_name in ipairs(attach_classes) do
			pcall(function()
				dome:DestroyAttaches(class_name)
			end)
		end
	end

	local to_delete = {}

	if type(FD.ReadField(dome, "ForEachAttach")) == "function" then
		for _, class_name in ipairs(attach_classes) do
			pcall(function()
				dome:ForEachAttach(class_name, function(attach)
					if FD.IsObjectValid(attach) then
						to_delete[#to_delete + 1] = attach
					end
				end)
			end)
		end

		pcall(function()
			dome:ForEachAttach(function(attach)
				if FD.IsDomeVisualAttach(attach) then
					to_delete[#to_delete + 1] = attach
				end
			end)
		end)
	end

	for _, attach in ipairs(to_delete) do
		FD.ForceDeleteObject(attach)
	end
end

-- Return the best available map object for terrain edits.

function FD.CurrentTerrainMap()
	return FD.Global("CurrentMap") or FD.Global("MainMap")
end

-- Return an approximate object radius for terrain cleanup.

function FD.ObjectRadius(obj, fallback)
	if not FD.IsObjectValid(obj) then
		return fallback or 0
	end

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

-- Return the terrain type at a world position.

function FD.TerrainTypeAt(map, pos, visual)
	local terrain_api = FD.Global("terrain")

	if not terrain_api or type(terrain_api.GetTerrainType) ~= "function" then
		return false
	end

	local ok, terrain_type = pcall(function()
		return terrain_api.GetTerrainType(map, pos, visual)
	end)

	if ok and terrain_type ~= nil then
		return terrain_type
	end

	return false
end

-- Sample nearby terrain outside the dome footprint.

function FD.SampleOuterTerrainType(dome)
	local map = FD.CurrentTerrainMap()

	if not map or not FD.IsObjectValid(dome) or type(FD.Global("point")) ~= "function" then
		return false
	end

	local pos = FD.CallMethod(dome, "GetPos") or FD.ReadField(dome, "pos")

	if not pos then
		return false
	end

	local hex_size = FD.HexSize()
	local radius = FD.ObjectRadius(dome, hex_size * 10)
	local sample_radius = radius + hex_size * 3
	local point_fn = FD.Global("point")

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

		if ok and sample_pos then
			local terrain_type = FD.TerrainTypeAt(map, sample_pos, true)

			if terrain_type then
				counts[terrain_type] = (counts[terrain_type] or 0) + 1
			end
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

-- Repaint the dome footprint with surrounding terrain.

function FD.ResetDomeTerrain(dome)
	if not FD.IsDome(dome) then
		return
	end

	local terrain_api = FD.Global("terrain")
	local map = FD.CurrentTerrainMap()

	if not terrain_api or not map or type(terrain_api.SetTypeCircle) ~= "function" then
		return
	end

	local pos = FD.CallMethod(dome, "GetPos") or FD.ReadField(dome, "pos")

	if not pos then
		return
	end

	local hex_size = FD.HexSize()
	local radius = FD.ObjectRadius(dome, hex_size * 10)
	local cleanup_radius = radius + hex_size * 2
	local terrain_type = FD.SampleOuterTerrainType(dome)

	if not terrain_type then
		return
	end

	pcall(function()
		terrain_api.SetTypeCircle(map, pos, cleanup_radius, terrain_type, terrain_type)
	end)

	if type(terrain_api.InvalidateType) == "function" then
		pcall(function()
			terrain_api.InvalidateType(map)
		end)
	end
end


-- ============================================================================
-- fd_delete.lua
-- ============================================================================

function FD.StopCommandObject(obj)
	if not FD.IsObjectValid(obj) then
		return
	end

	local command_thread = FD.ReadField(obj, "command_thread")
	local destructor_thread = FD.ReadField(obj, "thread_running_destructors")

	obj.command_destructors = false
	obj.command_queue = nil
	obj.forced_cmd_importance = nil

	for _, thread in ipairs({ command_thread, destructor_thread }) do
		if FD.SafeCall(FD.Global("IsValidThread"), thread) then
			FD.SafeCall(FD.Global("DeleteThread"), thread, true)
		end
	end

	obj.command_thread = nil
	obj.thread_running_destructors = nil
	obj.command = false
end

FD.DeleteObject = function(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local passage_obj = FD.PassageObjectFor(obj)

	if passage_obj and passage_obj ~= obj then
		obj = passage_obj
	end

	if FD.IsDome(obj) then
		FD.DisableDomeLights(obj)
	else
		FD.DisableObjectLights(obj)
	end

	if FD.IsResourceDepositObject(obj) or FD.IsMarker(obj) then
		FD.UnregisterDepositObject(obj)
		FD.PruneObjectFromGlobalLabels(obj)
	end

	if FD.IsDome(obj) then
		FD.ResetDomeTerrain(obj)
		FD.ClearDomeVisuals(obj)
	end

	local ok = pcall(function()
		local set_command = FD.ReadField(obj, "SetCommand")

		if FD.IsPassageObject(obj) then
			FD.PreparePassageForDelete(obj)
		end

		if FD.IsColonist(obj) then
			FD.NeutralizeColonistStatusSigns(obj)

			if type(set_command) == "function" and type(FD.ReadField(obj, "Erase")) == "function" then
				obj:SetCommand("Erase")
				return
			end

			if type(FD.ReadField(obj, "delete")) == "function" then
				obj:delete()
				return
			end

			FD.SafeCall(FD.Global("DoneObject"), obj)
			return
		end

		if FD.IsAnimal(obj) then
			if type(set_command) == "function" and type(FD.ReadField(obj, "Die")) == "function" then
				obj:SetCommand("Die")
				return
			end

			if type(FD.ReadField(obj, "Die")) == "function" then
				obj:Die()
				return
			end

			if type(FD.ReadField(obj, "delete")) == "function" then
				obj:delete()
				return
			end

			FD.SafeCall(FD.Global("DoneObject"), obj)
			return
		end

		if FD.IsKindOf(obj, "Drone") or FD.ClassName(obj):find("Drone", 1, true) ~= nil then
			if type(set_command) == "function" and type(FD.ReadField(obj, "DieNow")) == "function" then
				obj:SetCommand("DieNow")
				return
			end

			if type(FD.ReadField(obj, "DieNow")) == "function" then
				obj:DieNow()
				return
			end

			if type(FD.ReadField(obj, "delete")) == "function" then
				obj:delete()
				return
			end

			FD.SafeCall(FD.Global("DoneObject"), obj)
			return
		end

		if type(FD.ReadField(obj, "delete")) == "function" then
			obj:delete()
			return
		end

		FD.SafeCall(FD.Global("DoneObject"), obj)
	end)

	return ok
end


-- ============================================================================
-- fd_undo.lua
-- ============================================================================

function FD.IsUndoTrackableObject(obj)
	if type(obj) ~= "table" then
		return false
	end

	if FD.ReadField(obj, "class") then
		return true
	end

	if FD.ReadField(obj, "Index") then
		return true
	end

	return false
end

-- Return whether a delete batch should skip editor undo tracking.

function FD.ShouldSkipDeleteUndo(objects_to_delete)
	for _, obj in ipairs(objects_to_delete) do
		if FD.IsResourceDepositObject(obj) or FD.IsMarker(obj) then
			return true
		end
	end

	return false
end

-- Start an optional editor undo operation for compatible delete batches.

function FD.BeginDeleteUndo(objects_to_delete)
	if FD.ShouldSkipDeleteUndo(objects_to_delete) then
		return false
	end

	local undo = FD.Global("XEditorUndo")

	if not undo or type(FD.ReadField(undo, "BeginOp")) ~= "function" then
		return false
	end

	local undo_objects = {}

	for _, obj in ipairs(objects_to_delete) do
		if FD.IsUndoTrackableObject(obj) then
			undo_objects[#undo_objects + 1] = obj
		end
	end

	if #undo_objects == 0 then
		return false
	end

	return pcall(function()
		undo:BeginOp({
			objects = undo_objects,
			name = string.format("Force Delete hard-deleted %d object(s)", #objects_to_delete),
		})
	end)
end

function FD.EndDeleteUndo(undo_started)
	if not undo_started then
		return
	end

	local undo = FD.Global("XEditorUndo")

	if undo and type(FD.ReadField(undo, "EndOp")) == "function" then
		pcall(function()
			undo:EndOp()
		end)
	end
end

-- Delete selected root objects with the same broad path used by Attribute Inspector.


-- ============================================================================
-- fd_light_delete.lua
-- ============================================================================

-- Check whether the selected object can use the normal demolish pipeline.
function FD.CanForceDelete(obj)
	return FD.IsObjectValid(obj)
		and not FD.IsLightDeleteProtected(obj)
		and FD.IsKindOf(obj, "Demolishable")
		and FD.SafeCall(obj.CanDemolish, obj)
end

-- Stop any pending demolition countdown thread before forcing demolition now.
function FD.StopDemolitionThread(obj)
	local thread = FD.ReadField(obj, "demolishing_thread")

	if FD.SafeCall(FD.Global("IsValidThread"), thread) then
		FD.SafeCall(FD.Global("DeleteThread"), thread)
	end

	FD.WriteField(obj, "demolishing_thread", false)
end

-- Ctrl+Delete: run the normal demolition path when possible.
function FD.FD_LightDeleteSelectedObject()
	local obj = FD.Global("SelectedObj")

	if not FD.CanForceDelete(obj) then
		if not FD.IsLightDeleteGridElement(obj) then
			return false
		end

		FD.SafeCall(FD.Global("SelectObj"), false)
		return FD.DeleteObject(obj)
	end

	FD.WriteField(obj, "demolishing", true)
	FD.WriteField(obj, "demolishing_countdown", 0)
	FD.StopDemolitionThread(obj)
	FD.SafeCall(FD.Global("SelectObj"), false)

	local ok = pcall(function()
		obj:DoDemolish()
	end)

	return ok
end

-- Compatibility alias for the original single-file function name.
FD.ForceDeleteSelectedObject = FD.FD_LightDeleteSelectedObject


-- ============================================================================
-- fd_hard_delete.lua
-- ============================================================================

function FD.PruneContainerLabels(container, delete_set)
	local labels = FD.ReadField(container, "labels")

	if type(labels) ~= "table" then
		return
	end

	FD.PruneLabelsTable(labels, delete_set, true)
end

function FD.PruneDeleteLabels(objects_to_delete)
	local delete_set = {}

	for _, obj in ipairs(objects_to_delete) do
		delete_set[obj] = true
	end

	for _, obj in ipairs(objects_to_delete) do
		if FD.IsObjectValid(obj) then
			FD.PruneContainerLabels(obj, delete_set)
		end
	end

	FD.PruneObjectsFromGlobalLabels(delete_set)
end

-- Run unit cleanup before physical objects are deleted.
function FD.PreDeleteCleanup(objects_to_delete)
	local delete_set = {}

	for _, obj in ipairs(objects_to_delete) do
		delete_set[obj] = true
	end

	-- Prevent queued drone/resource callbacks from running on objects that are
	-- about to lose their stockpile/map state. This avoids ResourceStockpile
	-- UpdateVisualStockpile assertions during dome hard-delete.
	FD.NeutralizeDroneResourceCallbacksForDelete(objects_to_delete)

	FD.ResetDronesTargetingDeletedObjects(objects_to_delete, delete_set)
	FD.CleanupStockpileReferences(objects_to_delete, delete_set)

	for _, obj in ipairs(objects_to_delete) do
		if FD.IsObjectValid(obj) then
			FD.DetachContainedColonists(obj)
			FD.DeleteContainedAnimals(obj)
		end
	end
end

-- Ctrl+Shift+Delete: broad forced deletion with cleanup and collection.
function FD.FD_HardDeleteSelectedObjects()
	local selected_objects = FD.SelectedObjects()
	local objects_to_delete = {}
	local seen = {}

	for _, obj in ipairs(selected_objects) do
		if FD.IsObjectValid(obj) then
			FD.CollectDeleteObjects(obj, objects_to_delete, seen, true)
		end
	end

	if #objects_to_delete == 0 then
		return false
	end

	local rebuild_render_objects = FD.NeedsRenderObjectsRebuild(objects_to_delete)
	local undo_started = FD.BeginDeleteUndo(objects_to_delete)

	FD.SafeCall(FD.Global("SuspendPassEditsForEditOp"))
	FD.SafeCall(FD.Global("Msg"), "EditorCallback", "EditorCallbackDelete", objects_to_delete)

	FD.PreDeleteCleanup(objects_to_delete)
	FD.PruneDeleteLabels(objects_to_delete)

	for _, obj in ipairs(objects_to_delete) do
		FD.DeleteObject(obj)
	end

	FD.SafeCall(FD.Global("ResumePassEditsForEditOp"))
	FD.EndDeleteUndo(undo_started)

	if rebuild_render_objects then
		FD.SafeCall(FD.Global("RecreateRenderObjects"))
	end

	FD.ClearSelection()

	return true
end

-- Compatibility alias for the original single-file function name.
FD.HardForceDeleteSelectedObjects = FD.FD_HardDeleteSelectedObjects


-- ============================================================================
-- fd_shortcuts.lua
-- ============================================================================

-- Register the bindable delete actions in the game shortcut container.
function FD.AddForceDeleteActions(parent, context)
	local x_action = FD.Global("XAction")

	if not x_action then
		return
	end

	-- Register the hard action first. Some XAction/input paths may treat
	-- Ctrl+Shift+Delete as also matching Ctrl+Delete. If the light action is
	-- registered first, it can consume the shortcut before hard delete runs.
	x_action:new({
		ActionId = FD.HARD_ACTION_ID,
		ActionMode = "Game",
		ActionTranslate = false,
		ActionName = "Hard Force Delete Selected",
		ActionShortcut = "Ctrl-Shift-Delete",
		ActionGamepad = "LeftShoulder-RightShoulder-ButtonY",
		ActionBindable = true,
		ActionState = function()
			return FD.HasSelectedObject() and "enabled" or "disabled"
		end,
		OnAction = function()
			if not FD.IsHudVisible() then
				return "break"
			end

			FocusInfopanel = false
			FD.FD_HardDeleteSelectedObjects()

			return "break"
		end,
		IgnoreRepeated = true,
	}, parent, context)

	x_action:new({
		ActionId = FD.LIGHT_ACTION_ID,
		ActionMode = "Game",
		ActionTranslate = false,
		ActionName = "Light Force Delete Selected",
		ActionShortcut = "Ctrl-Delete",
		ActionGamepad = "LeftShoulder-RightShoulder-ButtonX",
		ActionBindable = true,
		-- Keep Ctrl+Delete enabled for selected objects so unsafe light deletes can no-op
		-- without falling through to the game's devtools slab shortcut.
		ActionState = function()
			return FD.HasSelectedObject() and "enabled" or "disabled"
		end,
		OnAction = function()
			if not FD.IsHudVisible() then
				return "break"
			end

			FocusInfopanel = false
			FD.FD_LightDeleteSelectedObject()

			return "break"
		end,
		IgnoreRepeated = true,
	}, parent, context)
end

-- Patch GameShortcuts once; the function is safe to retry while classes load.
function FD.PatchGameShortcuts()
	local game_shortcuts = FD.Global("GameShortcuts")

	if FD.shortcuts_patched or not game_shortcuts or type(game_shortcuts.Init) ~= "function" then
		return
	end

	local original_init = game_shortcuts.Init

	-- Add the Ctrl+Delete shortcut action after the base shortcut container initializes.
	function game_shortcuts:Init(parent, context)
		original_init(self, parent, context)
		FD.AddForceDeleteActions(parent, context)
	end

	FD.shortcuts_patched = true
end

-- Preserve any existing OnMsg handler while also retrying shortcut registration.
function FD.ChainOnMsg(message_name, handler)
	local previous = OnMsg[message_name]

	-- Call the existing message handler first, then this mod's retry hook.
	OnMsg[message_name] = function(...)
		if previous then
			previous(...)
		end

		handler(...)
	end
end

-- Retry shortcut registration after class post-processing.
FD.ChainOnMsg("ClassesPostprocess", FD.PatchGameShortcuts)

-- Retry shortcut registration after data loading.
FD.ChainOnMsg("DataLoaded", FD.PatchGameShortcuts)

FD.PatchGameShortcuts()
