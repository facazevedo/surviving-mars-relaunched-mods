-- Attribute Inspector mod
-- Bottom-right panel showing selected objects, marker/deposit references,
-- and a recursive delete button for scenario/map editing.

local PANEL_ID = "AttributeInspectorDialog"
local POLL_THREAD = "AttributeInspectorPoll"
local POLL_INTERVAL_MS = 250
local PANEL_Z_ORDER = 10000
local MAX_MARKER_GROUP_SCAN = 32
local MAX_CONTAINED_LABEL_SCAN = 2048

local AttributeInspectorDialog = false

-- Return an optional engine global without triggering mod-environment errors.
local function Global(name)
    return rawget(_G, name)
end

-- Invoke an optional function and return false instead of propagating errors.
local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return false
    end

    local ok, result = pcall(fn, ...)

    if ok then
        return result
    end

    return false
end

-- Check whether a map/game object still exists before inspecting or deleting it.
local function IsGameObjectValid(obj)
    if not obj then
        return false
    end

    local is_valid = Global("IsValid")

    if type(is_valid) == "function" then
        return SafeCall(is_valid, obj) and true or false
    end

    return true
end

-- Check whether an X window can still be safely updated.
local function IsWindowAlive(win)
    return win
        and win.window_state ~= "destroying"
        and win.window_state ~= "destroyed"
end

-- Test an object class relationship through the engine helper when available.
local function IsKindOf(obj, class_name)
    if not IsGameObjectValid(obj) then
        return false
    end

    return SafeCall(Global("IsKindOf"), obj, class_name) and true or false
end

-- Convert any inspected value into short, UI-safe text.
local function Text(value)
    local value_type = type(value)

    if value == nil then
        return "nil"
    end

    if value_type == "string" then
        return string.format("%q", value)
    end

    if value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end

    if value_type == "function" then
        return "<function>"
    end

    local ok, result = pcall(tostring, value)

    return ok and result or string.format("<%s>", value_type)
end

-- Read a field safely from game userdata/table objects.
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

-- Read an editor/game property by id when the object supports GetProperty.
local function ReadProperty(obj, prop_id)
    if not IsGameObjectValid(obj) then
        return nil
    end

    if type(ReadField(obj, "GetProperty")) ~= "function" then
        return nil
    end

    local ok, value = pcall(function()
        return obj:GetProperty(prop_id)
    end)

    return ok and value or nil
end

-- Return the object's class-like identifier for display.
local function ClassName(obj)
    return Text(ReadField(obj, "class") or CallMethod(obj, "GetClass") or obj)
end

-- Return the object's entity/model identifier for display.
local function EntityName(obj)
    if not IsGameObjectValid(obj) then
        return "nil"
    end

    return Text(CallMethod(obj, "GetEntity") or ReadField(obj, "entity"))
end

-- Return the object's current map/visual position for display.
local function PositionText(obj)
    if not IsGameObjectValid(obj) then
        return "nil"
    end

    return Text(
        CallMethod(obj, "GetPos")
            or CallMethod(obj, "GetVisualPos")
            or ReadField(obj, "pos")
    )
end

-- Return the object's orientation/angle for display.
local function AngleText(obj)
    if not IsGameObjectValid(obj) then
        return "nil"
    end

    return Text(
        CallMethod(obj, "GetAngle")
            or CallMethod(obj, "GetOrientation")
            or ReadField(obj, "angle")
    )
end

-- Return the runtime object handle, which can be looked up with HandleToObject.
local function HandleText(obj)
    return Text(ReadField(obj, "handle"))
end

-- Return an object's semantic id field when it has one.
local function IdText(obj)
    return Text(ReadField(obj, "id"))
end

-- Return the best fallback hex size for local terrain operations.
local function HexSize()
    local const = Global("const")

    return const and const.HexSize or 1000
end

-- Detect whether an object is a colonist.
local function IsColonist(obj)
    if not IsGameObjectValid(obj) then
        return false
    end

    return IsKindOf(obj, "Colonist")
        or ClassName(obj):find("Colonist", 1, true) ~= nil
end

-- Detect whether an object is an animal or pet.
local function IsAnimal(obj)
    if not IsGameObjectValid(obj) then
        return false
    end

    return IsKindOf(obj, "BaseAnimal")
        or IsKindOf(obj, "BasePet")
        or IsKindOf(obj, "Pet")
        or IsKindOf(obj, "PastureAnimal")
        or ClassName(obj):find("Animal", 1, true) ~= nil
        or ClassName(obj):find("Pet", 1, true) ~= nil
end

-- Detect whether an object is a live unit protected from container deletion.
local function IsProtectedUnit(obj)
    if not IsGameObjectValid(obj) then
        return false
    end

    return IsColonist(obj)
        or IsAnimal(obj)
        or IsKindOf(obj, "Unit")
        or IsKindOf(obj, "Drone")
        or IsKindOf(obj, "BaseRover")
        or IsKindOf(obj, "BaseRobot")
        or ClassName(obj):find("Rover", 1, true) ~= nil
        or ClassName(obj):find("Drone", 1, true) ~= nil
end

-- Detect whether an object is a dome.
local function IsDome(obj)
    if not IsGameObjectValid(obj) then
        return false
    end

    return IsKindOf(obj, "Dome")
        or ClassName(obj):find("Dome", 1, true) ~= nil
end

-- Detect whether an object is a dome floor/terrain visual attachment.
local function IsDomeVisualAttach(obj)
    if not IsGameObjectValid(obj) then
        return false
    end

    local class_name = ClassName(obj)

    return IsKindOf(obj, "BakedDomeDecal")
        or IsKindOf(obj, "BakedDomeDecalLarge")
        or IsKindOf(obj, "DomeTerrain")
        or IsKindOf(obj, "DomeGrass")
        or IsKindOf(obj, "DomeRoadConnection")
        or class_name:find("BakedDomeDecal", 1, true) ~= nil
        or class_name:find("DomeTerrain", 1, true) ~= nil
        or class_name:find("DomeGrass", 1, true) ~= nil
        or class_name:find("DomeRoadConnection", 1, true) ~= nil
end

-- Clear a colonist's workplace before buildings are deleted.
local function ClearColonistWorkplace(colonist)
    if not IsColonist(colonist) then
        return
    end

    if type(ReadField(colonist, "SetWorkplace")) == "function" then
        pcall(function()
            colonist:SetWorkplace(false)
        end)
    end
end

-- Clear a colonist's residence before residences or domes are deleted.
local function ClearColonistResidence(colonist)
    if not IsColonist(colonist) then
        return
    end

    if type(ReadField(colonist, "SetResidence")) == "function" then
        pcall(function()
            colonist:SetResidence(false)
        end)
    end
end

-- Clear a colonist's dome reference before a dome is deleted.
local function ClearColonistDome(colonist)
    if not IsColonist(colonist) then
        return
    end

    if type(ReadField(colonist, "SetDome")) == "function" then
        pcall(function()
            colonist:SetDome(false)
        end)
    end
end

-- Detach a colonist from workplace, residence, and dome relationships.
local function DetachColonist(colonist)
    if not IsColonist(colonist) then
        return
    end

    ClearColonistWorkplace(colonist)
    ClearColonistResidence(colonist)
    ClearColonistDome(colonist)
end

-- Detach colonists found as values or keys in one table.
local function DetachColonistsFromTable(list)
    if type(list) ~= "table" then
        return
    end

    for _, obj in ipairs(list) do
        if IsColonist(obj) then
            DetachColonist(obj)
        end
    end

    for key, value in pairs(list) do
        if IsColonist(value) then
            DetachColonist(value)
        elseif IsColonist(key) then
            DetachColonist(key)
        end
    end
end

-- Detach colonists stored in common object fields.
local function DetachColonistsFromFields(obj)
    local fields = {
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
    }

    for _, field in ipairs(fields) do
        local value = ReadField(obj, field)

        if IsColonist(value) then
            DetachColonist(value)
        elseif type(value) == "table" then
            DetachColonistsFromTable(value)
        end
    end
end

-- Detach colonists stored inside an object's label tables.
local function DetachColonistsFromLabels(obj)
    local labels = ReadField(obj, "labels")

    if type(labels) ~= "table" then
        return
    end

    for _, label_list in pairs(labels) do
        DetachColonistsFromTable(label_list)
    end
end

-- Detach colonists associated with an object before object deletion starts.
local function DetachContainedColonists(obj)
    if not IsGameObjectValid(obj) then
        return
    end

    if IsColonist(obj) then
        DetachColonist(obj)
        return
    end

    DetachColonistsFromFields(obj)
    DetachColonistsFromLabels(obj)
end

-- Remove one valid object without invoking recursive delete logic.
local function ForceDeleteObject(obj)
    if not IsGameObjectValid(obj) then
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
                    if IsGameObjectValid(attach) then
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
    if not IsGameObjectValid(obj) then
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

    if not map or not IsGameObjectValid(dome) then
        return false
    end

    if type(Global("point")) ~= "function" then
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

    if not terrain_api or not map then
        return
    end

    if type(terrain_api.SetTypeCircle) ~= "function" then
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
        terrain_api.SetTypeCircle(
            map,
            pos,
            cleanup_radius,
            terrain_type,
            terrain_type
        )
    end)

    if type(terrain_api.InvalidateType) == "function" then
        pcall(function()
            terrain_api.InvalidateType(map)
        end)
    end
end

-- Unwrap dialog contexts into the underlying property/game object.
local function ResolveContext(context)
    if not context then
        return false
    end

    local resolved = SafeCall(Global("ResolvePropObj"), context)

    return resolved or context
end

-- Look up an open dialog by id when the UI helper exists.
local function DialogById(id)
    return SafeCall(Global("GetDialog"), id)
end

-- Extract the selected object from a dialog context.
local function ContextObjectFromDialog(dialog)
    if not dialog then
        return false
    end

    local context = ReadField(dialog, "context")

    if not context then
        context = CallMethod(dialog, "GetContext")
    end

    if not context then
        context = ReadField(dialog, "Context")
    end

    local obj = ResolveContext(context)

    return IsGameObjectValid(obj) and obj or false
end

-- Return all valid objects from an array-like table.
local function ValidObjectsFromArray(list)
    local objects = {}

    if type(list) ~= "table" then
        return objects
    end

    for _, obj in ipairs(list) do
        if IsGameObjectValid(obj) then
            objects[#objects + 1] = obj
        end
    end

    return objects
end

-- Resolve selected objects while in editor-like contexts.
local function EditorSelections()
    local editor = Global("editor")

    if editor and type(editor.GetSel) == "function" then
        local objects = ValidObjectsFromArray(SafeCall(editor.GetSel))

        if #objects > 0 then
            return objects, #objects, "editor.GetSel()"
        end
    end

    local selo = Global("selo")

    if type(selo) == "function" then
        local obj = SafeCall(selo)

        if IsGameObjectValid(obj) then
            return { obj }, 1, "selo()"
        end
    end

    return {}, 0, "none"
end

-- Resolve selected objects from the normal gameplay UI.
local function GameplaySelections()
    local selection_objects = ValidObjectsFromArray(Global("Selection"))

    if #selection_objects > 1 then
        return selection_objects, #selection_objects, "Selection"
    end

    local obj = ContextObjectFromDialog(DialogById("Infopanel"))

    if obj then
        return { obj }, 1, "infopanel"
    end

    obj = Global("SelectedObj")

    if IsGameObjectValid(obj) then
        return { obj }, 1, "SelectedObj"
    end

    if #selection_objects == 1 then
        return selection_objects, 1, "Selection"
    end

    return {}, 0, "none"
end

-- Return the best available selected objects, count, and source label.
local function SelectedObjects()
    local objects, count, source = GameplaySelections()

    if count and count > 0 then
        return objects, count, source
    end

    return EditorSelections()
end

-- Return the first selected object for display-focused operations.
local function SelectedObject()
    local objects, count, source = SelectedObjects()

    if objects and #objects > 0 then
        return objects[1], count, source
    end

    return false, 0, "none"
end

-- Detect whether an object is already a deposit marker.
local function IsMarker(obj)
    if not IsGameObjectValid(obj) then
        return false
    end

    return IsKindOf(obj, "DepositMarker")
        or IsKindOf(obj, "SurfaceDepositMarker")
        or IsKindOf(obj, "SubsurfaceDepositMarker")
        or ClassName(obj):find("DepositMarker", 1, true) ~= nil
end

-- Read a likely marker reference from either a field or property.
local function MarkerCandidate(obj, key)
    local candidate = ReadField(obj, key) or ReadProperty(obj, key)

    if IsGameObjectValid(candidate) then
        return candidate
    end

    return false
end

-- Find the marker/deposit object related to the selected object.
local function FindMarker(obj, visited)
    if not IsGameObjectValid(obj) then
        return false, "not found"
    end

    if IsMarker(obj) then
        return obj, "selected object is marker"
    end

    visited = visited or {}

    if visited[obj] then
        return false, "not found"
    end

    visited[obj] = true

    for _, key in ipairs({ "marker", "placed_obj" }) do
        local candidate = MarkerCandidate(obj, key)

        if candidate then
            return candidate, key
        end
    end

    local deposit = CallMethod(obj, "GetDeposit")

    if IsGameObjectValid(deposit) then
        return deposit, "GetDeposit()"
    end

    local group = ReadField(obj, "group")

    if type(group) == "table" then
        local scanned = 0

        for _, group_obj in ipairs(group) do
            scanned = scanned + 1

            if scanned > MAX_MARKER_GROUP_SCAN then
                break
            end

            local marker, source = FindMarker(group_obj, visited)

            if IsGameObjectValid(marker) then
                return marker, "group -> " .. source
            end
        end
    end

    return false, "not found"
end

-- Append an object to a list unless it is invalid or already present.
local function AddUniqueObject(list, obj)
    if not IsGameObjectValid(obj) then
        return
    end

    for _, existing in ipairs(list) do
        if existing == obj then
            return
        end
    end

    list[#list + 1] = obj
end

-- Mark an object as part of the recursive delete closure.
local function MarkObject(seen, obj)
    if not IsGameObjectValid(obj) then
        return false
    end

    if seen[obj] then
        return false
    end

    seen[obj] = true

    return true
end

-- Iterate valid object entries from an engine label/list table.
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

        if IsGameObjectValid(obj) and not visited[obj] then
            visited[obj] = true
            callback(obj)
        end
    end

    for key, value in pairs(list) do
        if scanned > MAX_CONTAINED_LABEL_SCAN then
            return
        end

        local obj = false

        if IsGameObjectValid(value) then
            obj = value
        elseif IsGameObjectValid(key) then
            obj = key
        end

        if obj and not visited[obj] then
            scanned = scanned + 1
            visited[obj] = true
            callback(obj)
        end
    end
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
    if not IsGameObjectValid(obj) then
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
    if not IsGameObjectValid(obj) then
        return
    end

    local marker = false

    if IsMarker(obj) then
        marker = obj
    else
        marker = FindMarker(obj)
    end

    if not IsGameObjectValid(marker) then
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

-- Recursively collect a resource deposit group, its members, and its marker.
local function CollectResourceDepositObjects(obj, objects, seen)
    if not IsGameObjectValid(obj) then
        return
    end

    if not MarkObject(seen, obj) then
        return
    end

    AddUniqueObject(objects, obj)

    local marker = FindMarker(obj)

    if IsGameObjectValid(marker) and marker ~= obj then
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

        if IsGameObjectValid(value) and value ~= obj then
            if IsResourceDepositObject(value) or IsMarker(value) then
                CollectResourceDepositObjects(value, objects, seen)
            end
        elseif type(value) == "table" then
            ForEachContainedEntry(value, function(child)
                if child ~= obj
                    and (IsResourceDepositObject(child) or IsMarker(child))
                then
                    CollectResourceDepositObjects(child, objects, seen)
                end
            end)
        end
    end
end

-- Recursively collect non-unit objects stored in container label tables.
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

-- Recursively collect an object, its contents, and its marker for deletion.
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

        if IsGameObjectValid(marker) and marker ~= obj then
            AddUniqueObject(objects, marker)
        end
    end
end

-- Remove soon-deleted objects from one container's label arrays.
local function PruneContainerLabels(container, delete_set)
    local labels = ReadField(container, "labels")

    if type(labels) ~= "table" then
        return
    end

    for _, label_list in pairs(labels) do
        if type(label_list) == "table" then
            for i = #label_list, 1, -1 do
                local obj = label_list[i]

                if delete_set[obj] or not IsGameObjectValid(obj) then
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

-- Remove soon-deleted objects from all collected container label tables.
local function PruneDeleteLabels(objects_to_delete)
    local delete_set = {}

    for _, obj in ipairs(objects_to_delete) do
        delete_set[obj] = true
    end

    for _, obj in ipairs(objects_to_delete) do
        if IsGameObjectValid(obj) then
            PruneContainerLabels(obj, delete_set)
            PruneObjectFromGlobalLabels(obj)
        end
    end
end

-- Run colonist cleanup before physical objects are deleted.
local function PreDeleteCleanup(objects_to_delete)
    for _, obj in ipairs(objects_to_delete) do
        if IsGameObjectValid(obj) then
            DetachContainedColonists(obj)
        end
    end
end

-- Delete one game object using the safest available engine method.
local function DeleteObject(obj)
    if not IsGameObjectValid(obj) then
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
            if type(set_command) == "function"
                and type(ReadField(obj, "Erase")) == "function"
            then
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
            if type(set_command) == "function"
                and type(ReadField(obj, "Die")) == "function"
            then
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

        if IsKindOf(obj, "Drone")
            or ClassName(obj):find("Drone", 1, true) ~= nil
        then
            if type(set_command) == "function"
                and type(ReadField(obj, "DieNow")) == "function"
            then
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

-- Clear active gameplay/editor selection after deleting selected objects.
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

    local ok = pcall(function()
        undo:BeginOp({
            objects = undo_objects,
            name = string.format(
                "Attribute Inspector deleted %d object(s)",
                #objects_to_delete
            ),
        })
    end)

    return ok
end

-- End an optional editor undo operation for the delete batch.
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

-- Delete all selected root objects plus contained non-unit objects and markers.
function AttributeInspector_DeleteCurrentObject()
    local selected_objects = SelectedObjects()
    local objects_to_delete = {}
    local seen = {}

    if type(selected_objects) ~= "table" or #selected_objects == 0 then
        return false
    end

    for _, obj in ipairs(selected_objects) do
        if IsGameObjectValid(obj) then
            CollectDeleteObjects(obj, objects_to_delete, seen, true)
        end
    end

    if #objects_to_delete == 0 then
        return false
    end

    local undo_started = BeginDeleteUndo(objects_to_delete)

    SafeCall(Global("SuspendPassEditsForEditOp"))
    SafeCall(
        Global("Msg"),
        "EditorCallback",
        "EditorCallbackDelete",
        objects_to_delete
    )

    PreDeleteCleanup(objects_to_delete)
    PruneDeleteLabels(objects_to_delete)

    for _, delete_obj in ipairs(objects_to_delete) do
        DeleteObject(delete_obj)
    end

    SafeCall(Global("ResumePassEditsForEditOp"))
    EndDeleteUndo(undo_started)

    ClearSelection()
    AttributeInspector_UpdatePanel()

    return true
end

-- Append a standard identity block for one object to the panel text.
local function AddObjectLines(lines, title, obj)
    lines[#lines + 1] = title
    lines[#lines + 1] = string.format("object = %s", Text(obj))
    lines[#lines + 1] = string.format("handle = %s", HandleText(obj))
    lines[#lines + 1] = string.format("id = %s", IdText(obj))
    lines[#lines + 1] = string.format("class = %s", ClassName(obj))
    lines[#lines + 1] = string.format("entity = %s", EntityName(obj))
    lines[#lines + 1] = string.format("pos = %s", PositionText(obj))
    lines[#lines + 1] = string.format("angle = %s", AngleText(obj))
end

-- Build the full inspector text for the first selected object and its marker.
local function PanelText(obj, selected_count, source)
    local marker, marker_source = FindMarker(obj)
    local lines = {
        string.format("source = %s", source),
        string.format("selected_count = %d", selected_count or 1),
        "",
    }

    AddObjectLines(lines, "First selected object:", obj)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Object marker:"
    lines[#lines + 1] = string.format("marker_source = %s", marker_source)

    if IsGameObjectValid(marker) then
        AddObjectLines(lines, "Marker object:", marker)
    else
        lines[#lines + 1] = "marker = nil"
    end

    return table.concat(lines, "\n")
end

-- Find a panel child control by id across engine versions.
local function PanelControl(id)
    if not AttributeInspectorDialog then
        return false
    end

    local control = ReadField(AttributeInspectorDialog, id)

    if control then
        return control
    end

    local resolve_id = ReadField(AttributeInspectorDialog, "ResolveId")

    if type(resolve_id) == "function" then
        local ok, resolved = pcall(function()
            return AttributeInspectorDialog:ResolveId(id)
        end)

        if ok then
            return resolved
        end
    end

    return false
end

-- Update a text control while swallowing stale-window errors.
local function SetText(control, text)
    if type(ReadField(control, "SetText")) == "function" then
        pcall(function()
            control:SetText(text)
        end)
    end
end

-- Show or hide a panel control while swallowing stale-window errors.
local function SetVisible(control, visible)
    if type(ReadField(control, "SetVisible")) == "function" then
        pcall(function()
            control:SetVisible(visible)
        end)
    end
end

-- Refresh the inspector panel with the current selected object, if any.
function AttributeInspector_UpdatePanel()
    if not IsWindowAlive(AttributeInspectorDialog) then
        return
    end

    local obj, selected_count, source = SelectedObject()
    local title = PanelControl("idTitle")
    local body = PanelControl("idBody")
    local delete_button = PanelControl("idDeleteButton")

    if IsGameObjectValid(obj) then
        SetText(
            title,
            string.format(
                "Attribute Inspector  (Selected: %d)",
                selected_count or 1
            )
        )
        SetText(body, PanelText(obj, selected_count, source))
        SetVisible(delete_button, true)
    else
        SetText(title, "Attribute Inspector  (Selected: 0)")
        SetText(body, "")
        SetVisible(delete_button, false)
    end
end

DefineClass.AttributeInspectorPanel = {
    __parents = { "XDialog" },
    IdNode = true,
    Dock = "box",
    HAlign = "right",
    VAlign = "bottom",
    Margins = box(0, 0, 20, 80),
    Padding = box(8, 8, 8, 8),
    LayoutMethod = "VList",
    LayoutVSpacing = 4,
    Clip = "self",
    MinWidth = 520,
    MaxWidth = 680,
    MinHeight = 300,
    MaxHeight = 600,
    Background = RGBA(0, 0, 0, 230),
    HandleMouse = true,
}

-- Construct child controls and start the polling fallback thread.
function AttributeInspectorPanel:Init()
    AttributeInspectorDialog = self

    self.idTitle = XLabel:new({
        Id = "idTitle",
        Text = "Attribute Inspector  (Selected: 0)",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = RGB(255, 255, 255),
        HAlign = "stretch",
        VAlign = "top",
    }, self)

    self.idBody = XText:new({
        Id = "idBody",
        Text = "",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = RGB(255, 255, 255),
        HAlign = "stretch",
        VAlign = "top",
        WordWrap = true,
        MinHeight = 220,
        MaxHeight = 500,
        UseClipBox = true,
    }, self)

    self.idDeleteButton = XTextButton:new({
        Id = "idDeleteButton",
        Text = "Delete Selected Objects",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = RGB(255, 255, 255),
        HAlign = "left",
        VAlign = "top",
        MinWidth = 260,
        MaxWidth = 420,
        Visible = false,
    }, self)

    function self.idDeleteButton:OnPress()
        AttributeInspector_DeleteCurrentObject()
    end

    if self.CreateThread then
        self:CreateThread(POLL_THREAD, function(dialog)
            local sleep = Global("Sleep")

            while IsWindowAlive(dialog) do
                AttributeInspectorDialog = dialog
                pcall(AttributeInspector_UpdatePanel)

                if type(sleep) ~= "function" then
                    break
                end

                sleep(POLL_INTERVAL_MS)
            end
        end, self)
    end
end

-- Create the inspector panel once the in-game UI parent is available.
function AttributeInspector_EnsurePanel()
    local parent = false
    local ok = pcall(function()
        local get_interface = Global("GetInGameInterface")
        local terminal = Global("terminal")

        parent = type(get_interface) == "function" and get_interface() or false
        parent = parent or (terminal and terminal.desktop)
    end)

    if not ok or not parent or IsWindowAlive(AttributeInspectorDialog) then
        return
    end

    pcall(function()
        AttributeInspectorDialog = AttributeInspectorPanel:new({
            Id = PANEL_ID,
            ZOrder = PANEL_Z_ORDER,
        }, parent)
    end)

    pcall(AttributeInspector_UpdatePanel)
end

-- Close the inspector panel manually from Lua/debug sessions.
function AttributeInspector_ClosePanel()
    if not IsWindowAlive(AttributeInspectorDialog) then
        return
    end

    pcall(function()
        if AttributeInspectorDialog.Close then
            AttributeInspectorDialog:Close()
        elseif AttributeInspectorDialog.Delete then
            AttributeInspectorDialog:Delete()
        end

        AttributeInspectorDialog = false
    end)
end

-- Ensure the panel exists, then refresh its contents.
local function RefreshInspector()
    AttributeInspector_EnsurePanel()
    AttributeInspector_UpdatePanel()
end

-- Create/update the panel when the gameplay interface is created.
function OnMsg.InGameInterfaceCreated()
    pcall(RefreshInspector)
end

-- Refresh when the selected gameplay object changes.
function OnMsg.SelectedObjChange()
    pcall(RefreshInspector)
end

-- Refresh when the gameplay selection table changes.
function OnMsg.SelectionChange()
    pcall(RefreshInspector)
end

-- Refresh when an object is added to multi-selection.
function OnMsg.SelectionAdded()
    pcall(RefreshInspector)
end

-- Refresh when an object is removed from multi-selection.
function OnMsg.SelectionRemoved()
    pcall(RefreshInspector)
end

-- Refresh when entering editor-style selection contexts.
function OnMsg.GameEnterEditor()
    pcall(RefreshInspector)
end

-- Refresh when leaving editor-style selection contexts.
function OnMsg.GameExitEditor()
    pcall(RefreshInspector)
end

pcall(RefreshInspector)