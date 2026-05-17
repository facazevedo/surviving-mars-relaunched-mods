local LIGHT_ACTION_ID = "ForceDelete_CtrlDelete"
local HARD_ACTION_ID = "ForceDelete_CtrlShiftDelete"
local MAX_MARKER_GROUP_SCAN = 32
local MAX_CONTAINED_LABEL_SCAN = 2048

local shortcuts_patched = false

-- Return an optional global without creating sandbox assertion noise.
local function Global(name)
	return rawget(_G, name)
end

-- Run an optional function safely and return false on failure.
local function SafeCall(fn, ...)
	if type(fn) ~= "function" then
		return false
	end

	local ok, result = pcall(fn, ...)
	return ok and result or false
end

-- Check whether a map/game object is still valid.
local function IsObjectValid(obj)
	if not obj then
		return false
	end

	local is_valid = Global("IsValid")

	if type(is_valid) == "function" then
		return SafeCall(is_valid, obj) and true or false
	end

	return obj and true or false
end

-- Test an object class relationship through the engine helper when available.
local function IsKindOf(obj, class_name)
	return IsObjectValid(obj) and SafeCall(Global("IsKindOf"), obj, class_name) and true or false
end

-- Read a field safely from engine userdata/table objects.
local function ReadField(obj, field)
	if not obj then
		return nil
	end

	local ok, value = pcall(function()
		return obj[field]
	end)

	return ok and value or nil
end

-- Call a zero-argument object method safely.
local function CallMethod(obj, method)
	local fn = ReadField(obj, method)

	if type(fn) ~= "function" then
		return nil
	end

	local ok, value = pcall(function()
		return fn(obj)
	end)

	return ok and value or nil
end

-- Return an object's class-like identifier.
local function ClassName(obj)
	local value = ReadField(obj, "class") or CallMethod(obj, "GetClass")
	local ok, result = pcall(tostring, value or obj)

	return ok and result or ""
end

-- Read an editor/game property by id when the object supports GetProperty.
local function ReadProperty(obj, prop_id)
	if not IsObjectValid(obj) or type(ReadField(obj, "GetProperty")) ~= "function" then
		return nil
	end

	local ok, value = pcall(function()
		return obj:GetProperty(prop_id)
	end)

	return ok and value or nil
end

-- Return the best fallback hex size for local terrain operations.
local function HexSize()
	local const = Global("const")

	return const and const.HexSize or 1000
end

-- Keep light force-delete away from live units; hard delete handles these explicitly.
local function IsLightDeleteProtected(obj)
	local class_name = ClassName(obj)

	return IsKindOf(obj, "Colonist")
		or IsKindOf(obj, "BaseAnimal")
		or IsKindOf(obj, "BasePet")
		or IsKindOf(obj, "Pet")
		or IsKindOf(obj, "PastureAnimal")
		or IsKindOf(obj, "Drone")
		or class_name:find("Colonist", 1, true) ~= nil
		or class_name:find("Animal", 1, true) ~= nil
		or class_name:find("Pet", 1, true) ~= nil
		or class_name:find("Drone", 1, true) ~= nil
end

-- Detect grid pieces that should be allowed through the light-delete shortcut.
local function IsLightDeleteGridElement(obj)
	local class_name = ClassName(obj)

	return IsObjectValid(obj)
		and (IsKindOf(obj, "ElectricityGridElement")
			or IsKindOf(obj, "LifeSupportGridElement")
			or class_name:find("ElectricityGridElement", 1, true) ~= nil
			or class_name:find("LifeSupportGridElement", 1, true) ~= nil)
end

-- Check whether the selected object can use the normal demolish pipeline.
local function CanForceDelete(obj)
	return IsObjectValid(obj)
		and not IsLightDeleteProtected(obj)
		and IsKindOf(obj, "Demolishable")
		and SafeCall(obj.CanDemolish, obj)
end

-- Stop any pending demolition countdown thread before forcing demolition now.
local function StopDemolitionThread(obj)
	local thread = obj.demolishing_thread

	if SafeCall(Global("IsValidThread"), thread) then
		SafeCall(Global("DeleteThread"), thread)
	end

	obj.demolishing_thread = false
end

local DeleteObject

-- Run the selected object's normal demolition cleanup immediately.
local function ForceDeleteSelectedObject()
	local obj = Global("SelectedObj")

	if not CanForceDelete(obj) then
		if not IsLightDeleteGridElement(obj) then
			return false
		end

		SafeCall(Global("SelectObj"), false)
		return DeleteObject(obj)
	end

	obj.demolishing = true
	obj.demolishing_countdown = 0
	StopDemolitionThread(obj)
	SafeCall(Global("SelectObj"), false)

	local ok = pcall(function()
		obj:DoDemolish()
	end)

	return ok
end

-- Detect live units that should not be pulled in by container recursion.
local function IsColonist(obj)
	return IsObjectValid(obj)
		and (IsKindOf(obj, "Colonist") or ClassName(obj):find("Colonist", 1, true) ~= nil)
end

local function IsAnimal(obj)
	local class_name = ClassName(obj)

	return IsObjectValid(obj)
		and (IsKindOf(obj, "BaseAnimal")
			or IsKindOf(obj, "BasePet")
			or IsKindOf(obj, "Pet")
			or IsKindOf(obj, "PastureAnimal")
			or class_name:find("Animal", 1, true) ~= nil
			or class_name:find("Pet", 1, true) ~= nil)
end

local function IsProtectedUnit(obj)
	local class_name = ClassName(obj)

	return IsColonist(obj)
		or IsAnimal(obj)
		or IsKindOf(obj, "Unit")
		or IsKindOf(obj, "Drone")
		or IsKindOf(obj, "BaseRover")
		or IsKindOf(obj, "BaseRobot")
		or class_name:find("Rover", 1, true) ~= nil
		or class_name:find("Drone", 1, true) ~= nil
end

-- Detect whether an object is a dome.
local function IsDome(obj)
	return IsObjectValid(obj)
		and (IsKindOf(obj, "Dome") or ClassName(obj):find("Dome", 1, true) ~= nil)
end

-- Detect whether an object is a dome floor/terrain visual attachment.
local function IsDomeVisualAttach(obj)
	local class_name = ClassName(obj)

	return IsObjectValid(obj)
		and (IsKindOf(obj, "BakedDomeDecal")
			or IsKindOf(obj, "BakedDomeDecalLarge")
			or IsKindOf(obj, "DomeTerrain")
			or IsKindOf(obj, "DomeGrass")
			or IsKindOf(obj, "DomeRoadConnection")
			or class_name:find("BakedDomeDecal", 1, true) ~= nil
			or class_name:find("DomeTerrain", 1, true) ~= nil
			or class_name:find("DomeGrass", 1, true) ~= nil
			or class_name:find("DomeRoadConnection", 1, true) ~= nil)
end

-- Detach colonists from common ownership fields before deleting containers.
local function DetachColonist(colonist)
	if not IsColonist(colonist) then
		return
	end

	for _, method in ipairs({ "SetWorkplace", "SetResidence", "SetDome" }) do
		local fn = ReadField(colonist, method)

		if type(fn) == "function" then
			pcall(function()
				fn(colonist, false)
			end)
		end
	end
end

local function DetachColonistsFromTable(list)
	if type(list) ~= "table" then
		return
	end

	for _, obj in ipairs(list) do
		DetachColonist(obj)
	end

	for key, value in pairs(list) do
		DetachColonist(value)
		DetachColonist(key)
	end
end

local function DetachContainedColonists(obj)
	if IsColonist(obj) then
		DetachColonist(obj)
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
	}) do
		local value = ReadField(obj, field)

		if IsColonist(value) then
			DetachColonist(value)
		else
			DetachColonistsFromTable(value)
		end
	end

	local labels = ReadField(obj, "labels")

	if type(labels) == "table" then
		for _, label_list in pairs(labels) do
			DetachColonistsFromTable(label_list)
		end
	end
end

-- Remove one valid object without invoking recursive delete logic.
local function ForceDeleteObject(obj)
	if not IsObjectValid(obj) then
		return false
	end

	local ok = pcall(function()
		if type(ReadField(obj, "delete")) == "function" then
			obj:delete()
			return
		end

		SafeCall(Global("DoneObject"), obj)
	end)

	return ok
end

-- Remove dome floor, grass, decals, and road visual attachments only.
local function ClearDomeVisuals(dome)
	if not IsDome(dome) then
		return
	end

	local attach_classes = {
		"BakedDomeDecal",
		"BakedDomeDecalLarge",
		"DomeTerrain",
		"DomeGrass",
		"DomeRoadConnection",
	}

	if type(ReadField(dome, "DestroyAttaches")) == "function" then
		for _, class_name in ipairs(attach_classes) do
			pcall(function()
				dome:DestroyAttaches(class_name)
			end)
		end
	end

	local to_delete = {}

	if type(ReadField(dome, "ForEachAttach")) == "function" then
		for _, class_name in ipairs(attach_classes) do
			pcall(function()
				dome:ForEachAttach(class_name, function(attach)
					if IsObjectValid(attach) then
						to_delete[#to_delete + 1] = attach
					end
				end)
			end)
		end

		pcall(function()
			dome:ForEachAttach(function(attach)
				if IsDomeVisualAttach(attach) then
					to_delete[#to_delete + 1] = attach
				end
			end)
		end)
	end

	for _, attach in ipairs(to_delete) do
		ForceDeleteObject(attach)
	end
end

-- Return the best available map object for terrain edits.
local function CurrentTerrainMap()
	return Global("CurrentMap") or Global("MainMap")
end

-- Return an approximate object radius for terrain cleanup.
local function ObjectRadius(obj, fallback)
	if not IsObjectValid(obj) then
		return fallback or 0
	end

	local radius = CallMethod(obj, "GetRadius")

	if type(radius) == "number" and radius > 0 then
		return radius
	end

	local bbox = CallMethod(obj, "GetEntityBBox")

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
local function TerrainTypeAt(map, pos, visual)
	local terrain_api = Global("terrain")

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
local function SampleOuterTerrainType(dome)
	local map = CurrentTerrainMap()

	if not map or not IsObjectValid(dome) or type(Global("point")) ~= "function" then
		return false
	end

	local pos = CallMethod(dome, "GetPos") or ReadField(dome, "pos")

	if not pos then
		return false
	end

	local hex_size = HexSize()
	local radius = ObjectRadius(dome, hex_size * 10)
	local sample_radius = radius + hex_size * 3
	local point_fn = Global("point")

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
			local terrain_type = TerrainTypeAt(map, sample_pos, true)

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
local function ResetDomeTerrain(dome)
	if not IsDome(dome) then
		return
	end

	local terrain_api = Global("terrain")
	local map = CurrentTerrainMap()

	if not terrain_api or not map or type(terrain_api.SetTypeCircle) ~= "function" then
		return
	end

	local pos = CallMethod(dome, "GetPos") or ReadField(dome, "pos")

	if not pos then
		return
	end

	local hex_size = HexSize()
	local radius = ObjectRadius(dome, hex_size * 10)
	local cleanup_radius = radius + hex_size * 2
	local terrain_type = SampleOuterTerrainType(dome)

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

local function ResolveContext(context)
	if not context then
		return false
	end

	return SafeCall(Global("ResolvePropObj"), context) or context
end

local function ContextObjectFromDialog(dialog)
	if not dialog then
		return false
	end

	local context = ReadField(dialog, "context") or CallMethod(dialog, "GetContext") or ReadField(dialog, "Context")
	local obj = ResolveContext(context)

	return IsObjectValid(obj) and obj or false
end

local function ValidObjectsFromArray(list)
	local objects = {}

	if type(list) ~= "table" then
		return objects
	end

	for _, obj in ipairs(list) do
		if IsObjectValid(obj) then
			objects[#objects + 1] = obj
		end
	end

	return objects
end

local function SelectedObjects()
	local objects = ValidObjectsFromArray(Global("Selection"))

	if #objects > 1 then
		return objects
	end

	local infopanel = SafeCall(Global("GetDialog"), "Infopanel")
	local obj = ContextObjectFromDialog(infopanel)

	if obj then
		return { obj }
	end

	obj = Global("SelectedObj")

	if IsObjectValid(obj) then
		return { obj }
	end

	if #objects == 1 then
		return objects
	end

	local editor = Global("editor")

	if editor and type(editor.GetSel) == "function" then
		objects = ValidObjectsFromArray(SafeCall(editor.GetSel))

		if #objects > 0 then
			return objects
		end
	end

	local selo = Global("selo")

	if type(selo) == "function" then
		obj = SafeCall(selo)

		if IsObjectValid(obj) then
			return { obj }
		end
	end

	return {}
end

local function HasSelectedObject()
	if IsObjectValid(Global("SelectedObj")) then
		return true
	end

	return #SelectedObjects() > 0
end

local function IsMarker(obj)
	return IsObjectValid(obj)
		and (IsKindOf(obj, "DepositMarker")
			or IsKindOf(obj, "SurfaceDepositMarker")
			or IsKindOf(obj, "SubsurfaceDepositMarker")
			or ClassName(obj):find("DepositMarker", 1, true) ~= nil)
end

local function MarkerCandidate(obj, key)
	local candidate = ReadField(obj, key) or ReadProperty(obj, key)

	return IsObjectValid(candidate) and candidate or false
end

local function FindMarker(obj, visited)
	if not IsObjectValid(obj) then
		return false
	end

	if IsMarker(obj) then
		return obj
	end

	visited = visited or {}

	if visited[obj] then
		return false
	end

	visited[obj] = true

	for _, key in ipairs({ "marker", "placed_obj" }) do
		local candidate = MarkerCandidate(obj, key)

		if candidate then
			return candidate
		end
	end

	local deposit = CallMethod(obj, "GetDeposit")

	if IsObjectValid(deposit) then
		return deposit
	end

	local group = ReadField(obj, "group")

	if type(group) == "table" then
		local scanned = 0

		for _, group_obj in ipairs(group) do
			scanned = scanned + 1

			if scanned > MAX_MARKER_GROUP_SCAN then
				break
			end

			local marker = FindMarker(group_obj, visited)

			if IsObjectValid(marker) then
				return marker
			end
		end
	end

	return false
end

local function AddUniqueObject(list, obj)
	if not IsObjectValid(obj) then
		return
	end

	for _, existing in ipairs(list) do
		if existing == obj then
			return
		end
	end

	list[#list + 1] = obj
end

local function MarkObject(seen, obj)
	if not IsObjectValid(obj) or seen[obj] then
		return false
	end

	seen[obj] = true
	return true
end

-- Remove one object from array/hash-style engine tables.
local function RemoveObjectFromTable(list, obj)
	if type(list) ~= "table" or not obj then
		return
	end

	for i = #list, 1, -1 do
		if list[i] == obj then
			table.remove(list, i)
		end
	end

	for key, value in pairs(list) do
		if key == obj or value == obj then
			list[key] = nil
		end
	end
end

-- Remove one object from a container's label tables.
local function PruneObjectFromContainerLabels(container, obj)
	local labels = ReadField(container, "labels")

	if type(labels) ~= "table" then
		return
	end

	for _, label_list in pairs(labels) do
		RemoveObjectFromTable(label_list, obj)
	end
end

-- Remove one object from common global city/colony label tables.
local function PruneObjectFromGlobalLabels(obj)
	local containers = {
		Global("UICity"),
		Global("MainCity"),
		Global("SelectedCity"),
		Global("UIColony"),
	}

	for _, container in ipairs(containers) do
		if container then
			PruneObjectFromContainerLabels(container, obj)
		end
	end
end

-- Detect whether an object is a visible or marker-backed resource deposit.
local function IsResourceDepositObject(obj)
	if not IsObjectValid(obj) then
		return false
	end

	local class_name = ClassName(obj)

	return IsMarker(obj)
		or IsKindOf(obj, "TerrainDeposit")
		or IsKindOf(obj, "SurfaceDeposit")
		or IsKindOf(obj, "SubsurfaceDeposit")
		or class_name:find("Deposit", 1, true) ~= nil
		or class_name:find("Concrete", 1, true) ~= nil
		or class_name:find("Metals", 1, true) ~= nil
		or class_name:find("Polymers", 1, true) ~= nil
		or class_name:find("PreciousMetals", 1, true) ~= nil
end

-- Unregister a deposit marker from its map sector when possible.
local function UnregisterDepositObject(obj)
	if not IsObjectValid(obj) then
		return
	end

	local marker = false

	if IsMarker(obj) then
		marker = obj
	else
		marker = FindMarker(obj)
	end

	if not IsObjectValid(marker) then
		return
	end

	local city = SafeCall(Global("GetCity"), marker) or Global("UICity")
	local sector = false

	if city then
		sector = SafeCall(Global("GetMapSector"), city, marker)
	end

	if sector and type(ReadField(sector, "UnregisterDeposit")) == "function" then
		pcall(function()
			sector:UnregisterDeposit(marker)
		end)
	end

	local markers = sector and ReadField(sector, "markers")

	if type(markers) == "table" then
		RemoveObjectFromTable(markers.surface, marker)
		RemoveObjectFromTable(markers.subsurface, marker)
		RemoveObjectFromTable(markers.deep, marker)
		RemoveObjectFromTable(markers.block, marker)
	end

	if sector then
		RemoveObjectFromTable(ReadField(sector, "revealed_surf"), marker)
		RemoveObjectFromTable(ReadField(sector, "revealed_deep"), marker)
	end

	PruneObjectFromGlobalLabels(marker)
end

local CollectDeleteObjects

local function ForEachContainedEntry(list, callback)
	if type(list) ~= "table" then
		return
	end

	local scanned = 0
	local visited = {}

	for _, obj in ipairs(list) do
		scanned = scanned + 1

		if scanned > MAX_CONTAINED_LABEL_SCAN then
			return
		end

		if IsObjectValid(obj) and not visited[obj] then
			visited[obj] = true
			callback(obj)
		end
	end

	for key, value in pairs(list) do
		if scanned > MAX_CONTAINED_LABEL_SCAN then
			return
		end

		local obj = false

		if IsObjectValid(value) then
			obj = value
		elseif IsObjectValid(key) then
			obj = key
		end

		if obj and not visited[obj] then
			scanned = scanned + 1
			visited[obj] = true
			callback(obj)
		end
	end
end

-- Recursively collect a resource deposit group, its members, and its marker.
local function CollectResourceDepositObjects(obj, objects, seen)
	if not IsObjectValid(obj) then
		return
	end

	if not MarkObject(seen, obj) then
		return
	end

	AddUniqueObject(objects, obj)

	local marker = FindMarker(obj)

	if IsObjectValid(marker) and marker ~= obj then
		AddUniqueObject(objects, marker)
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
		local value = ReadField(obj, field) or ReadProperty(obj, field)

		if IsObjectValid(value) and value ~= obj then
			if IsResourceDepositObject(value) or IsMarker(value) then
				CollectResourceDepositObjects(value, objects, seen)
			end
		elseif type(value) == "table" then
			ForEachContainedEntry(value, function(child)
				if child ~= obj and (IsResourceDepositObject(child) or IsMarker(child)) then
					CollectResourceDepositObjects(child, objects, seen)
				end
			end)
		end
	end
end

local function CollectContainedObjects(container, objects, seen)
	local labels = ReadField(container, "labels")

	if type(labels) ~= "table" then
		return
	end

	for _, label_list in pairs(labels) do
		ForEachContainedEntry(label_list, function(child)
			if child ~= container and not IsProtectedUnit(child) then
				CollectDeleteObjects(child, objects, seen, false)
			end
		end)
	end
end

CollectDeleteObjects = function(obj, objects, seen, is_root)
	if IsProtectedUnit(obj) and not is_root then
		return
	end

	if IsResourceDepositObject(obj) or IsMarker(obj) then
		CollectResourceDepositObjects(obj, objects, seen)
		return
	end

	if not MarkObject(seen, obj) then
		return
	end

	if not IsProtectedUnit(obj) then
		CollectContainedObjects(obj, objects, seen)
	end

	AddUniqueObject(objects, obj)

	if not IsProtectedUnit(obj) then
		local marker = FindMarker(obj)

		if IsObjectValid(marker) and marker ~= obj then
			AddUniqueObject(objects, marker)
		end
	end
end

local function PruneContainerLabels(container, delete_set)
	local labels = ReadField(container, "labels")

	if type(labels) ~= "table" then
		return
	end

	for _, label_list in pairs(labels) do
		if type(label_list) == "table" then
			for i = #label_list, 1, -1 do
				local obj = label_list[i]

				if delete_set[obj] or not IsObjectValid(obj) then
					table.remove(label_list, i)
				end
			end

			for key, value in pairs(label_list) do
				if delete_set[key] or delete_set[value] then
					label_list[key] = nil
				end
			end
		end
	end
end

local function PruneDeleteLabels(objects_to_delete)
	local delete_set = {}

	for _, obj in ipairs(objects_to_delete) do
		delete_set[obj] = true
	end

	for _, obj in ipairs(objects_to_delete) do
		if IsObjectValid(obj) then
			PruneContainerLabels(obj, delete_set)
			PruneObjectFromGlobalLabels(obj)
		end
	end
end

-- Run colonist cleanup before physical objects are deleted.
local function PreDeleteCleanup(objects_to_delete)
	for _, obj in ipairs(objects_to_delete) do
		if IsObjectValid(obj) then
			DetachContainedColonists(obj)
		end
	end
end

DeleteObject = function(obj)
	if not IsObjectValid(obj) then
		return false
	end

	if IsResourceDepositObject(obj) or IsMarker(obj) then
		UnregisterDepositObject(obj)
		PruneObjectFromGlobalLabels(obj)
	end

	if IsDome(obj) then
		ResetDomeTerrain(obj)
		ClearDomeVisuals(obj)
	end

	local ok = pcall(function()
		local set_command = ReadField(obj, "SetCommand")

		if IsColonist(obj) then
			if type(set_command) == "function" and type(ReadField(obj, "Erase")) == "function" then
				obj:SetCommand("Erase")
				return
			end

			if type(ReadField(obj, "delete")) == "function" then
				obj:delete()
				return
			end

			SafeCall(Global("DoneObject"), obj)
			return
		end

		if IsAnimal(obj) then
			if type(set_command) == "function" and type(ReadField(obj, "Die")) == "function" then
				obj:SetCommand("Die")
				return
			end

			if type(ReadField(obj, "Die")) == "function" then
				obj:Die()
				return
			end

			if type(ReadField(obj, "delete")) == "function" then
				obj:delete()
				return
			end

			SafeCall(Global("DoneObject"), obj)
			return
		end

		if IsKindOf(obj, "Drone") or ClassName(obj):find("Drone", 1, true) ~= nil then
			if type(set_command) == "function" and type(ReadField(obj, "DieNow")) == "function" then
				obj:SetCommand("DieNow")
				return
			end

			if type(ReadField(obj, "DieNow")) == "function" then
				obj:DieNow()
				return
			end

			if type(ReadField(obj, "delete")) == "function" then
				obj:delete()
				return
			end

			SafeCall(Global("DoneObject"), obj)
			return
		end

		if type(ReadField(obj, "delete")) == "function" then
			obj:delete()
			return
		end

		SafeCall(Global("DoneObject"), obj)
	end)

	return ok
end

local function ClearSelection()
	SafeCall(Global("SelectObj"), false)

	local editor = Global("editor")

	if editor and type(editor.ClearSel) == "function" then
		pcall(function()
			editor.ClearSel()
		end)
	end
end

-- Return whether an object can be safely tracked by XEditorUndo.
local function IsUndoTrackableObject(obj)
	if type(obj) ~= "table" then
		return false
	end

	if ReadField(obj, "class") then
		return true
	end

	if ReadField(obj, "Index") then
		return true
	end

	return false
end

-- Return whether a delete batch should skip editor undo tracking.
local function ShouldSkipDeleteUndo(objects_to_delete)
	for _, obj in ipairs(objects_to_delete) do
		if IsResourceDepositObject(obj) or IsMarker(obj) then
			return true
		end
	end

	return false
end

-- Start an optional editor undo operation for compatible delete batches.
local function BeginDeleteUndo(objects_to_delete)
	if ShouldSkipDeleteUndo(objects_to_delete) then
		return false
	end

	local undo = Global("XEditorUndo")

	if not undo or type(ReadField(undo, "BeginOp")) ~= "function" then
		return false
	end

	local undo_objects = {}

	for _, obj in ipairs(objects_to_delete) do
		if IsUndoTrackableObject(obj) then
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

local function EndDeleteUndo(undo_started)
	if not undo_started then
		return
	end

	local undo = Global("XEditorUndo")

	if undo and type(ReadField(undo, "EndOp")) == "function" then
		pcall(function()
			undo:EndOp()
		end)
	end
end

-- Delete selected root objects with the same broad path used by Attribute Inspector.
local function HardForceDeleteSelectedObjects()
	local selected_objects = SelectedObjects()
	local objects_to_delete = {}
	local seen = {}

	for _, obj in ipairs(selected_objects) do
		if IsObjectValid(obj) then
			CollectDeleteObjects(obj, objects_to_delete, seen, true)
		end
	end

	if #objects_to_delete == 0 then
		return false
	end

	local undo_started = BeginDeleteUndo(objects_to_delete)

	SafeCall(Global("SuspendPassEditsForEditOp"))
	SafeCall(Global("Msg"), "EditorCallback", "EditorCallbackDelete", objects_to_delete)

	PreDeleteCleanup(objects_to_delete)
	PruneDeleteLabels(objects_to_delete)

	for _, obj in ipairs(objects_to_delete) do
		DeleteObject(obj)
	end

	SafeCall(Global("ResumePassEditsForEditOp"))
	EndDeleteUndo(undo_started)
	ClearSelection()

	return true
end

-- Check whether the HUD is visible enough to process gameplay shortcuts.
local function IsHudVisible()
	local hud = SafeCall(Global("GetHUD"))

	return hud and type(hud.GetVisible) == "function" and hud:GetVisible()
end

-- Register the bindable delete actions in the game shortcut container.
local function AddForceDeleteActions(parent, context)
	local x_action = Global("XAction")

	if not x_action then
		return
	end

	x_action:new({
		ActionId = LIGHT_ACTION_ID,
		ActionMode = "Game",
		ActionTranslate = false,
		ActionName = "Light Force Delete Selected",
		ActionShortcut = "Ctrl-Delete",
		ActionGamepad = "LeftShoulder-RightShoulder-ButtonX",
		ActionBindable = true,
		-- Keep Ctrl+Delete enabled for selected objects so unsafe light deletes can no-op
		-- without falling through to the game's devtools slab shortcut.
		ActionState = function()
			return HasSelectedObject() and "enabled" or "disabled"
		end,
		-- Force-delete the selected object from the registered shortcut path.
		OnAction = function()
			if not IsHudVisible() then
				return
			end

			FocusInfopanel = false
			ForceDeleteSelectedObject()

			return "break"
		end,
		IgnoreRepeated = true,
	}, parent, context)

	x_action:new({
		ActionId = HARD_ACTION_ID,
		ActionMode = "Game",
		ActionTranslate = false,
		ActionName = "Hard Force Delete Selected",
		ActionShortcut = "Ctrl-Shift-Delete",
		ActionGamepad = "LeftShoulder-RightShoulder-ButtonY",
		ActionBindable = true,
		ActionState = function()
			return #SelectedObjects() > 0 and "enabled" or "disabled"
		end,
		OnAction = function()
			if not IsHudVisible() then
				return
			end

			FocusInfopanel = false

			if HardForceDeleteSelectedObjects() then
				return "break"
			end
		end,
		IgnoreRepeated = true,
	}, parent, context)
end

-- Patch GameShortcuts once; the function is safe to retry while classes load.
local function PatchGameShortcuts()
	local game_shortcuts = Global("GameShortcuts")

	if shortcuts_patched or not game_shortcuts or type(game_shortcuts.Init) ~= "function" then
		return
	end

	local original_init = game_shortcuts.Init

	-- Add the Ctrl+Delete shortcut action after the base shortcut container initializes.
	function game_shortcuts:Init(parent, context)
		original_init(self, parent, context)
		AddForceDeleteActions(parent, context)
	end

	shortcuts_patched = true
end

-- Preserve any existing OnMsg handler while also retrying shortcut registration.
local function ChainOnMsg(message_name, handler)
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
ChainOnMsg("ClassesPostprocess", PatchGameShortcuts)

-- Retry shortcut registration after data loading.
ChainOnMsg("DataLoaded", PatchGameShortcuts)

PatchGameShortcuts()
