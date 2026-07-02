-- Attribute Inspector mod
-- Bottom-right panel showing selected objects, marker/deposit references,
-- and a recursive delete button for scenario/map editing.

local PANEL_ID = "AttributeInspectorDialog"
local POLL_THREAD = "AttributeInspectorPoll"
local POLL_INTERVAL_MS = 250
local PANEL_Z_ORDER = 10000
local PANEL_BACKGROUND = RGBA(0, 0, 0, 230)
local PANEL_TEXT_COLOR = RGB(255, 255, 255)
local TRANSPARENT_BACKGROUND = RGBA(0, 0, 0, 0)
local PANEL_HEIGHT = 610
local PANEL_HEADER_HEIGHT = 26
local PANEL_BODY_HEIGHT = 530
local SIDE_PANEL_WIDTH = 304
local CONTENT_PANEL_MIN_WIDTH = 520
local CONTENT_PANEL_MAX_WIDTH = 680
local INSPECTOR_PANEL_MIN_WIDTH = SIDE_PANEL_WIDTH + 8 + CONTENT_PANEL_MIN_WIDTH
local INSPECTOR_PANEL_MAX_WIDTH = SIDE_PANEL_WIDTH + 8 + CONTENT_PANEL_MAX_WIDTH
local GROUP_BUTTON_WIDTH = 284
local GROUP_BUTTON_HEIGHT = 26
local MINIMIZE_BUTTON_WIDTH = 28
local CLOSE_BUTTON_WIDTH = 28
local MINIMIZED_BUTTON_WIDTH = 54
local MINIMIZED_BUTTON_HEIGHT = 32
local CONTENT_TITLE_MIN_WIDTH =
    CONTENT_PANEL_MIN_WIDTH - MINIMIZE_BUTTON_WIDTH - CLOSE_BUTTON_WIDTH - 36
local CONTENT_TITLE_MAX_WIDTH =
    CONTENT_PANEL_MAX_WIDTH - MINIMIZE_BUTTON_WIDTH - CLOSE_BUTTON_WIDTH - 36
local GROUP_BUTTON_ACTIVE_BACKGROUND = RGBA(74, 107, 145, 230)
local GROUP_BUTTON_INACTIVE_BACKGROUND = RGBA(35, 35, 35, 230)
local GROUP_BUTTON_ROLLOVER_BACKGROUND = RGBA(95, 125, 160, 230)
local GROUP_BUTTON_PRESSED_BACKGROUND = RGBA(52, 78, 112, 230)
local MAX_MARKER_GROUP_SCAN = 32
local MAX_CONTAINED_LABEL_SCAN = 2048
local DEBUG_LOGS = false
local DEBUG_DRAG = false

local AttributeInspectorDialog = false
local AttributeInspectorLastBodyText = false
local AttributeInspectorControls = {}
local AttributeInspectorGroupState = false

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

-- Convert simple diagnostic values into readable log fragments.
local function LogValue(value)
    local value_type = type(value)

    if value_type == "string"
        or value_type == "number"
        or value_type == "boolean"
        or value == nil
    then
        return tostring(value)
    end

    return string.format("<%s>", value_type)
end

-- Emit optional diagnostics only when the explicit debug flags are enabled.
local function DebugLog(scope, message, data)
    if DEBUG_LOGS ~= true then
        return
    end

    if scope == "Drag" and DEBUG_DRAG ~= true then
        return
    end

    local parts = {
        string.format("[AttributeInspector][%s] %s", scope, message),
    }

    if type(data) == "table" then
        for key, value in pairs(data) do
            parts[#parts + 1] = string.format(
                "%s=%s",
                tostring(key),
                LogValue(value)
            )
        end
    end

    SafeCall(Global("print"), table.concat(parts, " "))
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

-- Read the engine lifecycle state for X windows without assuming table access is safe.
local function WindowState(win)
    if not win then
        return nil
    end

    local ok, state = pcall(function()
        return win.window_state
    end)

    return ok and state or nil
end

-- Check whether an X window can still be safely updated.
local function IsWindowAlive(win)
    local state = WindowState(win)

    return win
        and state ~= "destroying"
        and state ~= "destroyed"
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

local function AddSectionTitle(lines, title)
    if lines[#lines] ~= "" then
        lines[#lines + 1] = ""
    end

    lines[#lines + 1] = title .. ":"
end

local function AttributeValue(value)
    if value == nil then
        return "N/A"
    end

    return Text(value)
end

local function AddAttributeLine(lines, key, value)
    lines[#lines + 1] = string.format("%s = %s", key, AttributeValue(value))
end

local function AddFieldLine(lines, obj, key, field)
    local value = ReadField(obj, field)

    if value == nil then
        value = ReadProperty(obj, field)
    end

    AddAttributeLine(lines, key, value)
end

local function AddMethodLine(lines, obj, key, method)
    if type(ReadField(obj, method)) ~= "function" then
        AddAttributeLine(lines, key, nil)
        return
    end

    AddAttributeLine(lines, key, CallMethod(obj, method))
end

local function AddKindLine(lines, obj, class_name)
    AddAttributeLine(
        lines,
        string.format("IsKindOf(obj, \"%s\")", class_name),
        IsKindOf(obj, class_name)
    )
end

local function PointComponent(pos, component)
    if not pos then
        return nil
    end

    local method = ReadField(pos, component)

    if type(method) == "function" then
        local ok, value = pcall(function()
            return method(pos)
        end)

        if ok then
            return value
        end
    end

    return ReadField(pos, component)
end

local function WorldHex(obj)
    local world_to_hex = Global("WorldToHex")

    if type(world_to_hex) ~= "function" then
        return nil, nil
    end

    local ok, q, r = pcall(function()
        return world_to_hex(obj)
    end)

    if ok and q ~= nil and r ~= nil then
        return q, r
    end

    return nil, nil
end

local function WorldHexText(obj)
    local q, r = WorldHex(obj)

    if q ~= nil and r ~= nil then
        return string.format("%s/%s", tostring(q), tostring(r))
    end

    return "N/A"
end

local function AddDisplayLine(lines, key, value)
    lines[#lines + 1] = string.format(
        "%s = %s",
        tostring(key),
        value ~= nil and tostring(value) or "N/A"
    )
end

local function PackedCall(fn, ...)
    local packed = {
        ok = false,
        n = 0,
    }

    if type(fn) ~= "function" then
        return packed
    end

    local function Capture(ok, ...)
        packed.ok = ok == true
        packed.n = select("#", ...)

        for i = 1, packed.n do
            packed[i] = select(i, ...)
        end
    end

    Capture(pcall(fn, ...))

    return packed
end

local function PackedText(packed)
    if not packed or packed.ok ~= true then
        return "N/A"
    end

    if packed.n == 0 then
        return "nil"
    end

    local values = {}

    for i = 1, packed.n do
        values[#values + 1] = Text(packed[i])
    end

    return table.concat(values, ", ")
end

local function PackedFirst(packed)
    if packed and packed.ok == true and packed.n > 0 then
        return packed[1]
    end

    return nil
end

local function CallMethodPacked(obj, method, ...)
    local fn = ReadField(obj, method)

    if type(fn) ~= "function" then
        return {
            ok = false,
            n = 0,
        }
    end

    return PackedCall(fn, obj, ...)
end

local function CallMethodFirst(obj, method, ...)
    return PackedFirst(CallMethodPacked(obj, method, ...))
end

local function AddMethodCallLine(lines, obj, key, method, ...)
    AddDisplayLine(lines, key, PackedText(CallMethodPacked(obj, method, ...)))
end

local function AddGlobalCallLine(lines, key, global_name, ...)
    AddDisplayLine(lines, key, PackedText(PackedCall(Global(global_name), ...)))
end

local function RawEntity(obj)
    return CallMethod(obj, "GetEntity") or ReadField(obj, "entity")
end

local function BareClassName(obj)
    local value = ReadField(obj, "class") or CallMethod(obj, "GetClass")

    if value ~= nil then
        return tostring(value)
    end

    return tostring(obj)
end

local function TableCount(value)
    if type(value) ~= "table" then
        return nil
    end

    local count = 0
    local ok = pcall(function()
        for _ in pairs(value) do
            count = count + 1
        end
    end)

    return ok and count or nil
end

local function SortedKeys(value)
    local keys = {}

    if type(value) ~= "table" then
        return keys
    end

    pcall(function()
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
    end)

    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    return keys
end

local function CompactTableText(value, max_items)
    if type(value) ~= "table" then
        return Text(value)
    end

    local keys = SortedKeys(value)
    local total = #keys
    local limit = max_items or total
    local parts = {
        string.format("count=%d", total),
    }

    for i = 1, math.min(total, limit) do
        local key = keys[i]
        parts[#parts + 1] = string.format("%s=%s", tostring(key), Text(value[key]))
    end

    if total > limit then
        parts[#parts + 1] = string.format("... %d more", total - limit)
    end

    return "{" .. table.concat(parts, ", ") .. "}"
end

local function ObjectSummaryText(obj)
    if not IsGameObjectValid(obj) then
        return Text(obj)
    end

    return string.format(
        "%s handle=%s entity=%s pos=%s",
        BareClassName(obj),
        HandleText(obj),
        EntityName(obj),
        PositionText(obj)
    )
end

local function ObjectListText(list, max_items)
    if type(list) ~= "table" then
        return Text(list)
    end

    local count = #list
    local limit = max_items or count
    local parts = {
        string.format("count=%d", count),
    }

    for i = 1, math.min(count, limit) do
        parts[#parts + 1] = string.format("[%d]=%s", i, ObjectSummaryText(list[i]))
    end

    if count > limit then
        parts[#parts + 1] = string.format("... %d more", count - limit)
    end

    return "{" .. table.concat(parts, ", ") .. "}"
end

local function AddTableEntries(lines, title, value, max_items)
    AddSectionTitle(lines, title)
    AddDisplayLine(lines, "value", CompactTableText(value, max_items))

    if type(value) ~= "table" then
        return
    end

    local keys = SortedKeys(value)
    local limit = max_items or #keys

    for i = 1, math.min(#keys, limit) do
        local key = keys[i]

        AddDisplayLine(lines, tostring(key), Text(value[key]))
    end

    if #keys > limit then
        AddDisplayLine(lines, "truncated", string.format("%d entries not shown", #keys - limit))
    end
end

local function AddFieldSet(lines, obj, fields)
    for _, item in ipairs(fields) do
        if type(item) == "table" then
            AddFieldLine(lines, obj, item[1], item[2])
        else
            AddFieldLine(lines, obj, item, item)
        end
    end
end

local function ObjectMap(obj)
    local map = CallMethod(obj, "GetMap")

    if map then
        return map
    end

    local resolve_map = Global("ResolveMap")

    if type(resolve_map) == "function" then
        map = PackedFirst(PackedCall(resolve_map, obj))

        if map then
            return map
        end
    end

    map = ReadField(obj, "map")

    if map then
        return map
    end

    local city = ReadField(obj, "city") or Global("UICity")

    if city and type(ReadField(city, "GetMap")) == "function" then
        map = CallMethod(city, "GetMap")

        if map then
            return map
        end
    end

    return Global("CurrentMap") or Global("MainMap")
end

local function ObjectHexGrid(obj)
    local grid = PackedFirst(PackedCall(Global("GetObjectHexGrid"), obj))

    if grid then
        return grid
    end

    local map = ObjectMap(obj)

    return map and ReadField(map, "object_hex_grid") or Global("ObjectGrid")
end

local function EntityDataFor(entity)
    local entity_data = Global("EntityData")

    if type(entity_data) == "table" and entity then
        return entity_data[entity]
    end

    return nil
end

local function EntitySurfaceAvailable(obj_or_entity, surface_name)
    local surfaces = Global("EntitySurfaces")
    local mask = type(surfaces) == "table" and surfaces[surface_name] or nil

    if not mask then
        return nil
    end

    if type(obj_or_entity) == "string" then
        return PackedFirst(PackedCall(Global("HasAnySurfaces"), obj_or_entity, mask))
    end

    if type(ReadField(obj_or_entity, "HasAnySurfaces")) == "function" then
        return PackedFirst(CallMethodPacked(obj_or_entity, "HasAnySurfaces", mask, true))
    end

    local entity = RawEntity(obj_or_entity)

    if entity then
        return PackedFirst(PackedCall(Global("HasAnySurfaces"), entity, mask))
    end

    return nil
end

local function EntityCollisionMaskAvailable(entity, mask_name)
    local const = Global("const")
    local mask = const and const[mask_name] or nil

    if not entity or not mask then
        return nil
    end

    return PackedFirst(PackedCall(Global("HasMeshWithCollisionMask"), entity, mask))
end

local function EnumFlagSet(obj, flag_name)
    local const = Global("const")
    local flag = const and const[flag_name] or nil

    if not flag then
        return nil
    end

    local packed = CallMethodPacked(obj, "GetEnumFlags", flag)

    if packed.ok == true and packed.n > 0 and type(packed[1]) == "number" then
        return packed[1] ~= 0
    end

    return nil
end

local function ShapeForObject(obj)
    local shape = CallMethod(obj, "GetShapePoints")

    if type(shape) == "table" then
        return shape, "obj:GetShapePoints()"
    end

    shape = CallMethod(obj, "GetRotatedShapePoints")

    if type(shape) == "table" then
        return shape, "obj:GetRotatedShapePoints()"
    end

    local entity = RawEntity(obj)

    if entity then
        shape = PackedFirst(PackedCall(Global("GetEntityOutlineShape"), entity))

        if type(shape) == "table" then
            return shape, "GetEntityOutlineShape(entity)"
        end
    end

    return nil, "unavailable"
end

local function TerrainHeightAt(obj)
    local pos = CallMethod(obj, "GetPos") or ReadField(obj, "pos")
    local x = PointComponent(pos, "x")
    local y = PointComponent(pos, "y")
    local map = ObjectMap(obj)

    if not x or not y then
        return nil
    end

    local packed

    if map and type(ReadField(map, "GetHeight")) == "function" then
        packed = CallMethodPacked(map, "GetHeight", x, y)

        if packed.ok == true then
            return packed[1]
        end

        packed = CallMethodPacked(map, "GetHeight", pos)

        if packed.ok == true then
            return packed[1]
        end
    end

    local terrain = Global("terrain")
    local get_height = terrain and terrain.GetHeight

    packed = PackedCall(get_height, map, x, y)

    if packed.ok == true then
        return packed[1]
    end

    packed = PackedCall(get_height, obj, x, y)

    if packed.ok == true then
        return packed[1]
    end

    return nil
end

local function ObjectProperties(obj)
    local props = nil

    if type(ReadField(obj, "GetProperties")) == "function" then
        props = PackedFirst(CallMethodPacked(obj, "GetProperties"))
    end

    if type(props) ~= "table" and type(ReadField(obj, "GatherProperties")) == "function" then
        props = PackedFirst(CallMethodPacked(obj, "GatherProperties"))
    end

    if type(props) ~= "table" then
        props = ReadField(obj, "properties")
    end

    if type(props) ~= "table" then
        return {}
    end

    local result = {}

    for _, prop in ipairs(props) do
        if type(prop) == "table" and prop.id ~= nil then
            result[#result + 1] = prop
        end
    end

    table.sort(result, function(a, b)
        local ac = tostring(a.category or "")
        local bc = tostring(b.category or "")

        if ac ~= bc then
            return ac < bc
        end

        return tostring(a.id) < tostring(b.id)
    end)

    return result
end

local function AddPropertyDump(lines, obj, title, category_filter)
    AddSectionTitle(lines, title)

    local props = ObjectProperties(obj)
    local count = 0

    for _, prop in ipairs(props) do
        local category = tostring(prop.category or "")

        if not category_filter or category_filter[category] == true then
            local id = prop.id
            local value = ReadProperty(obj, id)
            local label = string.format(
                "%s%s",
                category ~= "" and category .. "." or "",
                tostring(id)
            )

            AddDisplayLine(lines, label, Text(value))
            count = count + 1
        end
    end

    if count == 0 then
        AddDisplayLine(lines, "properties", "none")
    end
end

local function AddRawFieldDump(lines, obj)
    AddSectionTitle(lines, "Raw Lua Fields")

    if type(obj) ~= "table" then
        AddDisplayLine(lines, "fields", "object is not a Lua table")
        return
    end

    local keys = SortedKeys(obj)

    if #keys == 0 then
        AddDisplayLine(lines, "fields", "none")
        return
    end

    for _, key in ipairs(keys) do
        AddDisplayLine(lines, tostring(key), Text(ReadField(obj, key)))
    end
end

local function TemplateForObject(obj)
    local templates = Global("BuildingTemplates")
    local template_name = ReadField(obj, "template_name")
        or ReadField(obj, "template_id")
        or ReadField(obj, "building_class")
        or ReadField(obj, "template")

    if type(templates) == "table" and template_name and templates[template_name] then
        return templates[template_name], template_name
    end

    local template = ReadField(obj, "template")
        or ReadField(obj, "building_class_proto")
        or ReadField(obj, "template_obj")

    return template, template_name
end

local function HexObjectsAt(obj, class_name)
    local q, r = WorldHex(obj)
    local grid = ObjectHexGrid(obj)

    if q == nil or r == nil or not grid then
        return nil
    end

    local packed

    if class_name then
        packed = CallMethodPacked(grid, "GetObjects", q, r, class_name)
    else
        packed = CallMethodPacked(grid, "GetObjects", q, r)
    end

    if packed.ok == true and type(packed[1]) == "table" then
        return packed[1]
    end

    if class_name then
        packed = CallMethodPacked(grid, "GetObject", q, r, class_name)
    else
        packed = CallMethodPacked(grid, "GetObject", q, r)
    end

    if packed.ok == true and packed[1] then
        return { packed[1] }
    end

    return nil
end

local function ShapeObjects(obj, class_name, ignore_class)
    local shape = ShapeForObject(obj)
    local grid = ObjectHexGrid(obj)

    if type(shape) ~= "table" or not grid then
        return nil
    end

    local packed = PackedCall(
        Global("HexGridShapeGetObjectList"),
        grid,
        obj,
        shape,
        class_name,
        ignore_class
    )

    return packed.ok == true and type(packed[1]) == "table" and packed[1] or nil
end

local function AddTemplateFields(lines, template, prefix)
    if not template then
        AddDisplayLine(lines, prefix .. ".object", "N/A")
        return
    end

    AddDisplayLine(lines, prefix .. ".object", Text(template))
    local fields = {
        "id",
        "template_name",
        "object_class",
        "template_class",
        "entity",
        "display_name",
        "description",
        "build_category",
        "build_pos",
        "build_points",
        "instant_build",
        "is_tall",
        "dome_required",
        "dome_forbidden",
        "dome_spot",
        "hide_from_build_menu",
        "construction_cost_Concrete",
        "construction_cost_Metals",
        "construction_cost_Polymers",
        "construction_cost_Electronics",
        "construction_cost_MachineParts",
        "construction_cost_PreciousMetals",
        "power_consumption",
        "air_consumption",
        "water_consumption",
        "electricity_consumption",
        "maintenance_resource_type",
        "maintenance_resource_amount",
    }

    for _, field in ipairs(fields) do
        AddFieldLine(lines, template, prefix .. "." .. field, field)
    end
end

local function AddCommonMethodLines(lines, obj, methods)
    for _, method in ipairs(methods) do
        AddMethodCallLine(
            lines,
            obj,
            string.format("obj:%s()", method),
            method
        )
    end
end

local ATTRIBUTE_GROUPS = {
    {
        id = "summary",
        title = "Summary",
        default_enabled = true,
    },
    {
        id = "identity_class",
        title = "Identity / Class",
        default_enabled = true,
    },
    {
        id = "transform_placement",
        title = "Transform / Placement",
        default_enabled = true,
    },
    {
        id = "entity_visual_asset",
        title = "Entity / ArtSpec / Visual Asset",
        default_enabled = true,
    },
    {
        id = "materials_textures",
        title = "Materials / Textures",
        default_enabled = true,
    },
    {
        id = "footprint_hex_shape",
        title = "Footprint / Hex Shape",
        default_enabled = true,
    },
    {
        id = "collision_passability",
        title = "Collision / Passability",
        default_enabled = true,
    },
    {
        id = "pathfinding_object_grid",
        title = "Pathfinding / Object Grid",
        default_enabled = true,
    },
    {
        id = "passage_ramp_specific",
        title = "Passage / Ramp Specific",
        default_enabled = true,
    },
    {
        id = "buildability_construction",
        title = "Buildability / Construction",
        default_enabled = true,
    },
    {
        id = "work_spots_interaction_spots",
        title = "Work Spots / Interaction Spots",
        default_enabled = true,
    },
    {
        id = "ownership_lifecycle",
        title = "Ownership / Scenario Editor Lifecycle",
        default_enabled = true,
    },
    {
        id = "ui_selection",
        title = "UI / Selection",
        default_enabled = true,
    },
    {
        id = "object_specific",
        title = "Object-Specific",
        default_enabled = true,
    },
    {
        id = "raw_lua_advanced",
        title = "Raw Lua / Advanced",
        default_enabled = true,
    },
}

-- Initialize per-session group state. Default: all groups visible.
local function EnsureGroupState()
    if type(AttributeInspectorGroupState) == "table" then
        return
    end

    AttributeInspectorGroupState = {}

    for _, group in ipairs(ATTRIBUTE_GROUPS) do
        AttributeInspectorGroupState[group.id] = group.default_enabled ~= false
    end
end

local function IsGroupEnabled(group_id)
    EnsureGroupState()

    return AttributeInspectorGroupState[group_id] == true
end

local function SetAllGroupsEnabled(enabled)
    EnsureGroupState()

    for _, group in ipairs(ATTRIBUTE_GROUPS) do
        AttributeInspectorGroupState[group.id] = enabled == true
    end

    AttributeInspectorLastBodyText = false
end

local function ToggleGroupEnabled(group_id)
    EnsureGroupState()

    AttributeInspectorGroupState[group_id] =
        AttributeInspectorGroupState[group_id] ~= true
    AttributeInspectorLastBodyText = false
end

local function ShouldShowGroup(group_id, force_all_groups)
    if force_all_groups == true then
        return true
    end

    return IsGroupEnabled(group_id)
end

-- Keep renderer functions off the chunk-local list; Lua 5.1 caps active locals.
AttributeInspectorRenderers = Global("AttributeInspectorRenderers") or {}

function AttributeInspectorRenderers.AddWarningLine(lines, message)
    AddDisplayLine(lines, "warning", message)
end

function AttributeInspectorRenderers.AddTerrainHeightLines(lines, obj)
    local pos = CallMethod(obj, "GetPos") or ReadField(obj, "pos")
    local z = PointComponent(pos, "z")
    local terrain_z = TerrainHeightAt(obj)

    AddAttributeLine(lines, "terrain_height_at_object", terrain_z)

    if type(z) == "number" and type(terrain_z) == "number" then
        AddAttributeLine(lines, "height_above_terrain", z - terrain_z)
    else
        AddAttributeLine(lines, "height_above_terrain", nil)
    end
end

function AttributeInspectorRenderers.AddShapeSummaryLines(lines, obj)
    local shape, shape_source = ShapeForObject(obj)

    AddAttributeLine(lines, "shape_source", shape_source)
    AddAttributeLine(lines, "shape_count", type(shape) == "table" and #shape or nil)
    AddAttributeLine(lines, "shape_points", type(shape) == "table" and CompactTableText(shape, 20) or nil)

    return shape
end

function AttributeInspectorRenderers.AddEntityDataLines(lines, entity, max_items)
    local entity_data = EntityDataFor(entity)

    AddAttributeLine(lines, "EntityData[entity]", entity_data)

    if type(entity_data) ~= "table" then
        return
    end

    AddDisplayLine(lines, "EntityData.count", TableCount(entity_data))
    AddFieldSet(lines, entity_data, {
        { "EntityData.entity", "entity" },
        { "EntityData.display_name", "display_name" },
        { "EntityData.editor_category", "editor_category" },
        { "EntityData.material_type", "material_type" },
        { "EntityData.surfaces", "surfaces" },
        { "EntityData.collision", "collision" },
        { "EntityData.apply_to_grids", "apply_to_grids" },
        { "EntityData.entity_category", "entity_category" },
        { "EntityData.state_category", "state_category" },
        { "EntityData.states", "states" },
    })

    if max_items then
        AddTableEntries(lines, "EntityData Selected Fields", entity_data, max_items)
    end
end

function AttributeInspectorRenderers.AddMethodGroup(lines, obj, title, methods)
    AddSectionTitle(lines, title)
    AddCommonMethodLines(lines, obj, methods)
end

function AttributeInspectorRenderers.AddSummaryGroup(lines, obj, selected_count, source, marker, marker_source)
    local shape_objects = ShapeObjects(obj)
    local hex_objects = HexObjectsAt(obj)

    AddSectionTitle(lines, "Summary")
    AddAttributeLine(lines, "display_name", ReadField(obj, "display_name") or ReadField(obj, "name"))
    AddAttributeLine(lines, "class", ClassName(obj))
    AddAttributeLine(lines, "template_id", ReadField(obj, "template_name") or ReadField(obj, "template_id"))
    AddAttributeLine(lines, "entity", EntityName(obj))
    AddAttributeLine(lines, "position", PositionText(obj))
    AddAttributeLine(lines, "angle / rotation", AngleText(obj))
    AddAttributeLine(lines, "hex q/r", WorldHexText(obj))
    AddAttributeLine(lines, "validity", IsGameObjectValid(obj))
    AddAttributeLine(lines, "selection_source", source)
    AddAttributeLine(lines, "selected_count", selected_count or 1)
    AddAttributeLine(lines, "marker_source", marker_source)
    AddAttributeLine(lines, "marker", marker)
    AttributeInspectorRenderers.AddTerrainHeightLines(lines, obj)
    AttributeInspectorRenderers.AddShapeSummaryLines(lines, obj)
    AddAttributeLine(lines, "objects_at_hex", ObjectListText(hex_objects, 10))
    AddAttributeLine(lines, "objects_touching_shape", ObjectListText(shape_objects, 10))

    if type(shape_objects) == "table" and #shape_objects > 1 then
        AttributeInspectorRenderers.AddWarningLine(lines, "multiple objects overlap the inspected footprint")
    end
end

function AttributeInspectorRenderers.AddIdentityGroup(lines, obj)
    local object_class = Global("ObjectClass")

    AddSectionTitle(lines, "Identity / Class")
    AddAttributeLine(
        lines,
        "ObjectClass(obj)",
        type(object_class) == "function" and SafeCall(object_class, obj) or nil
    )
    AddAttributeLine(lines, "class", ClassName(obj))
    AddAttributeLine(lines, "bare_class", BareClassName(obj))
    AddFieldSet(lines, obj, {
        { "obj.class", "class" },
        { "obj.template_name", "template_name" },
        { "obj.template_id", "template_id" },
        { "obj.template", "template" },
        { "obj.display_name", "display_name" },
        { "obj.name", "name" },
        { "obj.id", "id" },
        { "obj.handle", "handle" },
        { "obj.entity", "entity" },
        { "obj.group", "group" },
        { "obj.labels", "labels" },
        { "obj.city", "city" },
        { "obj.map_id", "map_id" },
        { "obj.persist_baseclass", "persist_baseclass" },
        { "obj.__parents", "__parents" },
        { "obj.__hierarchy_cache", "__hierarchy_cache" },
    })
    AddMethodCallLine(lines, obj, "obj:GetEntity()", "GetEntity")
    AddMethodCallLine(lines, obj, "obj:GetClass()", "GetClass")
    AddAttributeLine(lines, "obj.handle_text", HandleText(obj))
    AddKindLine(lines, obj, "Building")
    AddKindLine(lines, obj, "GridObject")
    AddKindLine(lines, obj, "Unit")
    AddKindLine(lines, obj, "PassageRamp")
    AddKindLine(lines, obj, "PassageRampBase")
    AddKindLine(lines, obj, "PassageGridElement")
    AddKindLine(lines, obj, "ConstructionSite")
    AddKindLine(lines, obj, "WaypointsObj")
    AddKindLine(lines, obj, "AutoAttachObject")
    AddKindLine(lines, obj, "CObject")
end

function AttributeInspectorRenderers.AddTransformGroup(lines, obj)
    local pos = CallMethod(obj, "GetPos") or ReadField(obj, "pos")
    local visual_pos = CallMethod(obj, "GetVisualPos")

    AddSectionTitle(lines, "Transform / Placement")
    AddAttributeLine(lines, "obj:GetPos()", pos)
    AddAttributeLine(lines, "x", PointComponent(pos, "x"))
    AddAttributeLine(lines, "y", PointComponent(pos, "y"))
    AddAttributeLine(lines, "z", PointComponent(pos, "z"))
    AddAttributeLine(lines, "obj:GetVisualPos()", visual_pos)
    AddAttributeLine(lines, "visual_x", PointComponent(visual_pos, "x"))
    AddAttributeLine(lines, "visual_y", PointComponent(visual_pos, "y"))
    AddAttributeLine(lines, "visual_z", PointComponent(visual_pos, "z"))
    AddAttributeLine(lines, "WorldToHex(obj) q/r", WorldHexText(obj))
    AttributeInspectorRenderers.AddTerrainHeightLines(lines, obj)
    AttributeInspectorRenderers.AddMethodGroup(lines, obj, "Transform Methods", {
        "GetAngle",
        "GetAxis",
        "GetScale",
        "GetObjectBBox",
        "GetEntityBBox",
        "GetBSphere",
        "GetHeight",
        "GetRadius",
        "GetVisualPos",
        "GetPos",
    })
    AddFieldSet(lines, obj, {
        "pos",
        "angle",
        "axis",
        "scale",
        "orientation",
        "radius",
        "height",
        "bbox",
        "entity_bbox",
        "visual_pos",
        "valid_pos",
    })
end

function AttributeInspectorRenderers.AddEntityVisualGroup(lines, obj)
    local entity = RawEntity(obj)
    local is_valid_entity = Global("IsValidEntity")

    AddSectionTitle(lines, "Entity / ArtSpec / Visual Asset")
    AddAttributeLine(lines, "entity", entity)
    AddAttributeLine(
        lines,
        "IsValidEntity(entity)",
        type(is_valid_entity) == "function" and SafeCall(is_valid_entity, entity) or nil
    )
    AttributeInspectorRenderers.AddEntityDataLines(lines, entity, nil)
    AddFieldSet(lines, obj, {
        "entity",
        "forced_entity",
        "alternative_entity_t",
        "ArtSpec",
        "art_spec",
        "anim_state",
        "state",
        "anim",
        "entity_change_time",
        "auto_attach_at_init",
        "auto_attach_mode",
        "attached",
        "attaches",
    })
    AttributeInspectorRenderers.AddMethodGroup(lines, obj, "Entity Methods", {
        "HasEntity",
        "GetEntity",
        "GetState",
        "GetStateText",
        "GetAnim",
        "GetAnimMoment",
        "GetAnimPhase",
        "GetAnimSpeed",
        "GetLODsCount",
        "GetNumStates",
        "GetAttaches",
    })
    AddGlobalCallLine(lines, "GetNumStates(entity)", "GetNumStates", entity)
end

function AttributeInspectorRenderers.AddMaterialsGroup(lines, obj)
    local entity = RawEntity(obj)
    local entity_data = EntityDataFor(entity)

    AddSectionTitle(lines, "Materials / Textures")
    AddAttributeLine(lines, "entity", entity)
    AddFieldSet(lines, obj, {
        "material",
        "material_type",
        "texture",
        "color",
        "color_modifier",
        "palette",
        "palette_color",
        "palette_index",
        "entity_material",
        "entity_material_type",
        "entity_texture",
    })
    AttributeInspectorRenderers.AddMethodGroup(lines, obj, "Material Methods", {
        "GetMaterialType",
        "GetColorModifier",
        "GetGameFlags",
        "GetEnumFlags",
    })

    if type(entity_data) == "table" then
        AddFieldSet(lines, entity_data, {
            { "EntityData.material_type", "material_type" },
            { "EntityData.material", "material" },
            { "EntityData.materials", "materials" },
            { "EntityData.textures", "textures" },
            { "EntityData.surfaces", "surfaces" },
        })
    else
        AddAttributeLine(lines, "EntityData.material_type", nil)
    end
end

function AttributeInspectorRenderers.AddFootprintGroup(lines, obj)
    local shape = ShapeForObject(obj)
    local q, r = WorldHex(obj)
    local grid = ObjectHexGrid(obj)

    AddSectionTitle(lines, "Footprint / Hex Shape")
    AddAttributeLine(lines, "object_hex_grid", grid)
    AddAttributeLine(lines, "hex q/r", WorldHexText(obj))
    AddAttributeLine(lines, "q", q)
    AddAttributeLine(lines, "r", r)
    AttributeInspectorRenderers.AddShapeSummaryLines(lines, obj)
    AddAttributeLine(lines, "GetShapePoints()", PackedText(CallMethodPacked(obj, "GetShapePoints")))
    AddAttributeLine(lines, "GetRotatedShapePoints()", PackedText(CallMethodPacked(obj, "GetRotatedShapePoints")))
    AddGlobalCallLine(lines, "GetEntityOutlineShape(entity)", "GetEntityOutlineShape", RawEntity(obj))
    AddGlobalCallLine(lines, "GetEntityPeripheralShape(entity)", "GetEntityPeripheralShape", RawEntity(obj))
    AddMethodCallLine(lines, obj, "obj:GetObjectBBox()", "GetObjectBBox")
    AddMethodCallLine(lines, obj, "obj:GetEntityBBox()", "GetEntityBBox")
    AddAttributeLine(lines, "objects_at_hex", ObjectListText(HexObjectsAt(obj), 20))
    AddAttributeLine(lines, "objects_touching_shape", ObjectListText(ShapeObjects(obj), 20))

    if type(shape) ~= "table" then
        AttributeInspectorRenderers.AddWarningLine(lines, "no footprint shape was found for this object")
    end

    AddFieldSet(lines, obj, {
        "shape",
        "outline_shape",
        "peripheral_shape",
        "build_shape",
        "flatten_shape",
        "hex_shape",
        "shape_points",
        "object_grid",
        "object_hex_grid",
        "grid_object",
        "build_pos",
    })
end

function AttributeInspectorRenderers.AddCollisionGroup(lines, obj)
    local entity = RawEntity(obj)
    local collision = CallMethodFirst(obj, "GetCollision")
    local apply_to_grids = CallMethodFirst(obj, "GetApplyToGrids")
    local collision_surface = EntitySurfaceAvailable(entity, "Collision")
    local apply_surface = EntitySurfaceAvailable(entity, "ApplyToGrids")
    local passability_mask = EntityCollisionMaskAvailable(entity, "cmPassability")

    AddSectionTitle(lines, "Collision / Passability")
    AddAttributeLine(lines, "entity", entity)
    AttributeInspectorRenderers.AddMethodGroup(lines, obj, "Collision Methods", {
        "GetCollision",
        "GetWalkable",
        "GetApplyToGrids",
        "GetVisible",
        "GetGameFlags",
    })
    AddAttributeLine(lines, "efCollision", EnumFlagSet(obj, "efCollision"))
    AddAttributeLine(lines, "efWalkable", EnumFlagSet(obj, "efWalkable"))
    AddAttributeLine(lines, "efApplyToGrids", EnumFlagSet(obj, "efApplyToGrids"))
    AddAttributeLine(lines, "efSelectable", EnumFlagSet(obj, "efSelectable"))
    AddAttributeLine(lines, "efVisible", EnumFlagSet(obj, "efVisible"))
    AddAttributeLine(lines, "EntitySurfaces.Collision", collision_surface)
    AddAttributeLine(lines, "EntitySurfaces.ApplyToGrids", apply_surface)
    AddAttributeLine(lines, "EntitySurfaces.Walk", EntitySurfaceAvailable(entity, "Walk"))
    AddAttributeLine(lines, "EntitySurfaces.Height", EntitySurfaceAvailable(entity, "Height"))
    AddAttributeLine(lines, "EntitySurfaces.Terrain", EntitySurfaceAvailable(entity, "Terrain"))
    AddAttributeLine(lines, "HasMeshWithCollisionMask(cmPassability)", passability_mask)
    AddAttributeLine(lines, "HasMeshWithCollisionMask(cmDefaultObject)", EntityCollisionMaskAvailable(entity, "cmDefaultObject"))
    AddAttributeLine(lines, "HasMeshWithCollisionMask(cmTerrain)", EntityCollisionMaskAvailable(entity, "cmTerrain"))
    AddFieldSet(lines, obj, {
        "collision",
        "collision_radius",
        "passability",
        "apply_to_grids",
        "walkable",
        "visible",
        "obstacle",
        "blocking",
        "is_tall",
        "radius",
        "detail_class",
        "terrain_collision",
        "force_extend_bb_during_placement_checks",
    })

    if collision_surface == true and collision == false then
        AttributeInspectorRenderers.AddWarningLine(lines, "entity has Collision surface but object collision flag is off")
    end

    if apply_surface == true and apply_to_grids == false then
        AttributeInspectorRenderers.AddWarningLine(lines, "entity has ApplyToGrids surface but object grid flag is off")
    end

    if passability_mask == true and apply_to_grids == false then
        AttributeInspectorRenderers.AddWarningLine(lines, "entity has passability collision mask but is not applying to grids")
    end
end

function AttributeInspectorRenderers.AddPathfindingGroup(lines, obj)
    local map = ObjectMap(obj)
    local grid = ObjectHexGrid(obj)
    local q, r = WorldHex(obj)
    local pos = CallMethod(obj, "GetPos") or ReadField(obj, "pos")

    AddSectionTitle(lines, "Pathfinding / Object Grid")
    AddAttributeLine(lines, "map", map)
    AddAttributeLine(lines, "object_hex_grid", grid)
    AddAttributeLine(lines, "hex q/r", WorldHexText(obj))
    AddMethodCallLine(lines, map, "map:IsPassable(q, r)", "IsPassable", q, r)
    AddMethodCallLine(lines, map, "map:GetPassablePointNearby(pos)", "GetPassablePointNearby", pos)
    AddAttributeLine(lines, "objects_at_hex", ObjectListText(HexObjectsAt(obj), 30))
    AddAttributeLine(lines, "objects_touching_shape", ObjectListText(ShapeObjects(obj), 30))
    AddFieldSet(lines, obj, {
        "pfclass",
        "pf_class",
        "path",
        "pathing",
        "path_flags",
        "passable",
        "impassable",
        "object_grid",
        "object_hex_grid",
        "command",
        "command_thread",
        "goto_target",
        "destination",
        "route",
    })
end

function AttributeInspectorRenderers.AddPassageObjectDetails(lines, title, value)
    if not IsGameObjectValid(value) then
        AddDisplayLine(lines, title, Text(value))
        return
    end

    AddObjectLines(lines, title, value)
end

function AttributeInspectorRenderers.AddPassageGroup(lines, obj)
    local q, r = WorldHex(obj)
    local grid = ObjectHexGrid(obj)
    local get_ramp = Global("HexGetPassageRamp")
    local get_element = Global("HexGetPassageGridElement")
    local ramp = nil
    local element = nil

    if q ~= nil and r ~= nil and grid ~= nil then
        ramp = PackedFirst(PackedCall(get_ramp, grid, q, r))
        element = PackedFirst(PackedCall(get_element, grid, q, r))
    end

    AddSectionTitle(lines, "Passage / Ramp Specific")
    AddAttributeLine(lines, "object_hex_grid", grid)
    AddAttributeLine(lines, "hex q/r", WorldHexText(obj))
    AddAttributeLine(lines, "q", q)
    AddAttributeLine(lines, "r", r)
    AddAttributeLine(lines, "IsKindOf(obj, \"PassageRamp\")", IsKindOf(obj, "PassageRamp"))
    AddAttributeLine(lines, "IsKindOf(obj, \"PassageRampBase\")", IsKindOf(obj, "PassageRampBase"))
    AddAttributeLine(lines, "IsKindOf(obj, \"PassageGridElement\")", IsKindOf(obj, "PassageGridElement"))
    AddDisplayLine(lines, "HexGetPassageRamp(object_hex_grid, q, r)", ObjectSummaryText(ramp))
    AddDisplayLine(lines, "HexGetPassageGridElement(object_hex_grid, q, r)", ObjectSummaryText(element))
    AttributeInspectorRenderers.AddPassageObjectDetails(lines, "Passage ramp at hex", ramp)
    AttributeInspectorRenderers.AddPassageObjectDetails(lines, "Passage grid element at hex", element)
    AddFieldSet(lines, obj, {
        "passage",
        "passage_grid",
        "passage_grid_element",
        "passage_ramp",
        "passage_direction",
        "passage_connections",
        "connections",
        "track",
        "track_id",
        "start_dome",
        "end_dome",
        "dome",
        "build_connection",
        "entrance",
        "exit",
        "status",
        "block_reason",
        "node_idx",
    })
end

function AttributeInspectorRenderers.AddBuildabilityGroup(lines, obj)
    local template, template_name = TemplateForObject(obj)

    AddSectionTitle(lines, "Buildability / Construction")
    AddAttributeLine(lines, "template_name", template_name)
    AddTemplateFields(lines, template, "template")
    AttributeInspectorRenderers.AddShapeSummaryLines(lines, obj)
    AddFieldSet(lines, obj, {
        "building_class",
        "building_class_proto",
        "construction_statuses",
        "construction_group",
        "construction_costs",
        "construction_costs_at_start",
        "construction_resource_type",
        "construction_resource_amount",
        "construction_site",
        "construction_started",
        "build_points",
        "build_pos",
        "build_category",
        "build_shape",
        "flatten_shape",
        "stockpiles_obstruct",
        "resource_requests",
        "resource_stockpiles",
        "dome_required",
        "dome_forbidden",
        "dome_spot",
        "instant_build",
        "hide_from_build_menu",
    })
    AttributeInspectorRenderers.AddMethodGroup(lines, obj, "Buildability Methods", {
        "CanConstruct",
        "GetBuildMenuCategory",
        "GetBuildPos",
        "GetConstructionCost",
        "GetConstructionStatus",
    })
end

function AttributeInspectorRenderers.AddSpotLines(lines, obj, spot)
    local has_spot = CallMethodFirst(obj, "HasSpot", spot)
    local begin_packed = nil
    local begin_index = nil

    AddAttributeLine(lines, "HasSpot(" .. spot .. ")", has_spot)

    if has_spot ~= true then
        return
    end

    AddMethodCallLine(lines, obj, "GetSpotRange(" .. spot .. ")", "GetSpotRange", spot)
    begin_packed = CallMethodPacked(obj, "GetSpotBeginIndex", spot)
    begin_index = PackedFirst(begin_packed)
    AddDisplayLine(lines, "GetSpotBeginIndex(" .. spot .. ")", PackedText(begin_packed))
    AddMethodCallLine(lines, obj, "GetSpotEndIndex(" .. spot .. ")", "GetSpotEndIndex", spot)

    if type(begin_index) == "number" and begin_index >= 0 then
        AddMethodCallLine(lines, obj, "GetSpotPos(" .. tostring(begin_index) .. ")", "GetSpotPos", begin_index)
    else
        AddDisplayLine(lines, "GetSpotPos", "N/A")
    end
end

function AttributeInspectorRenderers.AddWorkSpotsGroup(lines, obj)
    local spots = {
        "Origin",
        "Work",
        "work",
        "Workplace",
        "Visit",
        "visit",
        "Entrance",
        "Exit",
        "Idle",
        "idle",
        "Interact",
        "Interaction",
        "Drone",
        "drone",
        "Service",
        "service",
        "Outside",
        "Inside",
        "Door",
        "Rover",
        "Colonist",
    }

    AddSectionTitle(lines, "Work Spots / Interaction Spots")
    AddFieldSet(lines, obj, {
        "work_spot_task",
        "work_spots",
        "interaction_spots",
        "entrance",
        "exit",
        "waypoints",
        "custom_waypoints",
        "holder",
        "holder_spot",
        "attached",
        "attaches",
        "auto_attach_at_init",
        "auto_attach_mode",
    })
    AddSectionTitle(lines, "Spot Method Availability")
    AddDisplayLine(lines, "obj:HasSpot(spot)", type(ReadField(obj, "HasSpot")) == "function" and "exists" or "N/A")
    AddDisplayLine(lines, "obj:GetSpotRange(spot)", type(ReadField(obj, "GetSpotRange")) == "function" and "exists" or "N/A")
    AddDisplayLine(lines, "obj:GetSpotBeginIndex(spot)", type(ReadField(obj, "GetSpotBeginIndex")) == "function" and "exists" or "N/A")
    AddDisplayLine(lines, "obj:GetSpotEndIndex(spot)", type(ReadField(obj, "GetSpotEndIndex")) == "function" and "exists" or "N/A")
    AddDisplayLine(lines, "obj:GetSpotPos(index)", type(ReadField(obj, "GetSpotPos")) == "function" and "exists" or "N/A")

    for _, spot in ipairs(spots) do
        AttributeInspectorRenderers.AddSpotLines(lines, obj, spot)
    end
end

function AttributeInspectorRenderers.AddOwnershipGroup(lines, obj, marker, marker_source)
    AddSectionTitle(lines, "Ownership / Scenario Editor Lifecycle")
    AddAttributeLine(lines, "marker_source", marker_source)
    AddAttributeLine(lines, "marker", marker)

    if IsGameObjectValid(marker) then
        AddObjectLines(lines, "Marker object", marker)
    end

    AddFieldSet(lines, obj, {
        "mod_id",
        "mod",
        "mod_name",
        "owner",
        "holder",
        "parent",
        "city",
        "map_id",
        "realm",
        "label",
        "labels",
        "groups",
        "created_by",
        "creator",
        "editable",
        "deletable",
        "can_delete",
        "scenario_editor",
        "scenario_editor_id",
        "scenario_editor_marker",
        "se_object_id",
        "se_marker",
        "se_group",
        "se_owner",
        "delete_me",
        "destroyed",
        "auto_remove",
    })
end

function AttributeInspectorRenderers.SelectedObjValue()
    local selected_obj = Global("SelectedObj")

    if type(selected_obj) == "function" then
        return PackedFirst(PackedCall(selected_obj))
    end

    return selected_obj
end

function AttributeInspectorRenderers.EditorSelection()
    local editor = Global("editor")

    if type(editor) == "table" and type(ReadField(editor, "GetSel")) == "function" then
        local packed = PackedCall(editor.GetSel, editor)

        if packed.ok == true then
            return packed[1]
        end

        packed = PackedCall(editor.GetSel)

        if packed.ok == true then
            return packed[1]
        end
    end

    return nil
end

function AttributeInspectorRenderers.AddUISelectionGroup(lines, obj, selected_count, source)
    local get_dialog = Global("GetDialog")
    local get_interface = Global("GetInGameInterface")
    local selection = SelectedObjects()
    local editor_selection = AttributeInspectorRenderers.EditorSelection()

    AddSectionTitle(lines, "UI / Selection")
    AddAttributeLine(lines, "selection_source", source)
    AddAttributeLine(lines, "selected_count", selected_count or 1)
    AddAttributeLine(lines, "SelectedObj", AttributeInspectorRenderers.SelectedObjValue())
    AddAttributeLine(lines, "SelectedObjects()", ObjectListText(selection, 20))
    AddAttributeLine(lines, "editor.GetSel()", ObjectListText(editor_selection, 20))
    AddAttributeLine(lines, "GetDialog(\"Infopanel\")", type(get_dialog) == "function" and SafeCall(get_dialog, "Infopanel") or nil)
    AddAttributeLine(lines, "GetInGameInterface()", type(get_interface) == "function" and SafeCall(get_interface) or nil)
    AddFieldSet(lines, obj, {
        "selected",
        "selection",
        "is_selected",
        "ui",
        "infopanel",
        "display_name",
        "rollover_title",
        "rollover_text",
        "description",
        "actions",
        "ip_template",
        "ip_template_name",
    })
end

function AttributeInspectorRenderers.ClassDefForName(class_name)
    local classes = Global("g_Classes")
    local classdef = nil

    if class_name == nil then
        return nil
    end

    if type(classes) == "table" and class_name then
        classdef = classes[class_name]

        if type(classdef) == "table" then
            return classdef
        end
    end

    classdef = Global(class_name)

    return type(classdef) == "table" and classdef or nil
end

function AttributeInspectorRenderers.IsGenericClassName(class_name)
    local generic = {
        Object = true,
        InitDone = true,
        PropertyObject = true,
        MapInterface = true,
        MapObject = true,
        CObject = true,
    }

    return generic[tostring(class_name or "")] == true
end

function AttributeInspectorRenderers.CollectClassDefs(class_name, entries, seen)
    local name = tostring(class_name or "")

    if name == "" or seen[name] == true then
        return
    end

    seen[name] = true

    local classdef = AttributeInspectorRenderers.ClassDefForName(name)

    if type(classdef) ~= "table" then
        return
    end

    if AttributeInspectorRenderers.IsGenericClassName(name) ~= true then
        entries[#entries + 1] = {
            name = name,
            def = classdef,
        }
    end

    local parents = ReadField(classdef, "__parents")

    if type(parents) == "table" then
        for _, parent in ipairs(parents) do
            AttributeInspectorRenderers.CollectClassDefs(parent, entries, seen)
        end
    end
end

function AttributeInspectorRenderers.ClassDefsForObject(obj)
    local entries = {}
    local seen = {}
    local object_class = Global("ObjectClass")
    local object_class_value = type(object_class) == "function"
        and SafeCall(object_class, obj)
        or nil

    AttributeInspectorRenderers.CollectClassDefs(BareClassName(obj), entries, seen)
    AttributeInspectorRenderers.CollectClassDefs(ReadField(obj, "class"), entries, seen)

    if type(object_class_value) == "string" then
        AttributeInspectorRenderers.CollectClassDefs(object_class_value, entries, seen)
    elseif type(object_class_value) == "table" then
        AttributeInspectorRenderers.CollectClassDefs(ReadField(object_class_value, "class"), entries, seen)
    end

    return entries
end

function AttributeInspectorRenderers.AddObjectSpecificClassList(lines, class_entries)
    AddSectionTitle(lines, "Object-Specific Classes")
    AddDisplayLine(lines, "class_count", #class_entries)

    if #class_entries == 0 then
        AddDisplayLine(lines, "classes", "none discovered")
        return
    end

    for index, entry in ipairs(class_entries) do
        AddDisplayLine(lines, string.format("class[%d]", index), entry.name)
    end
end

function AttributeInspectorRenderers.AddObjectSpecificPropertyLines(lines, obj, class_entries)
    local class_names = {}
    local count = 0

    for _, entry in ipairs(class_entries) do
        class_names[entry.name] = true
    end

    AddSectionTitle(lines, "Object-Specific Properties")

    for _, prop in ipairs(ObjectProperties(obj)) do
        local defined_in = tostring(prop.defined_in or "")

        if class_names[defined_in] == true then
            local id = prop.id
            local value = ReadProperty(obj, id)
            local label = string.format(
                "%s.%s",
                defined_in ~= "" and defined_in or "object",
                tostring(id)
            )
            local details = string.format(
                "%s | type=%s editor=%s getter=%s setter=%s",
                Text(value),
                tostring(prop.type or ""),
                tostring(prop.editor or ""),
                tostring(prop.getter or ""),
                tostring(prop.setter or "")
            )

            AddDisplayLine(lines, label, details)
            count = count + 1
        end
    end

    if count == 0 then
        AddDisplayLine(lines, "properties", "none defined directly by discovered object classes")
    end
end

function AttributeInspectorRenderers.CollectObjectSpecificMembers(class_entries)
    local methods = {}
    local fields = {}
    local seen_methods = {}
    local seen_fields = {}

    for _, entry in ipairs(class_entries) do
        local keys = SortedKeys(entry.def)

        for _, key in ipairs(keys) do
            local key_text = tostring(key)

            if type(key) == "string"
                and string.sub(key_text, 1, 2) ~= "__"
                and key_text ~= "properties"
            then
                local value = ReadField(entry.def, key)

                if type(value) == "function" then
                    if seen_methods[key_text] ~= true then
                        methods[#methods + 1] = {
                            name = key_text,
                            class = entry.name,
                        }
                        seen_methods[key_text] = true
                    end
                elseif seen_fields[key_text] ~= true then
                    fields[#fields + 1] = {
                        name = key_text,
                        class = entry.name,
                        default = value,
                    }
                    seen_fields[key_text] = true
                end
            end
        end
    end

    table.sort(methods, function(a, b)
        return a.name < b.name
    end)

    table.sort(fields, function(a, b)
        return a.name < b.name
    end)

    return methods, fields
end

function AttributeInspectorRenderers.AddObjectSpecificFieldLines(lines, obj, fields)
    AddSectionTitle(lines, "Object-Specific Class Fields")
    AddDisplayLine(lines, "field_count", #fields)

    if #fields == 0 then
        AddDisplayLine(lines, "fields", "none discovered")
        return
    end

    for _, field in ipairs(fields) do
        local value = ReadField(obj, field.name)

        if value == nil then
            value = field.default
        end

        AddDisplayLine(
            lines,
            string.format("%s.%s", field.class, field.name),
            Text(value)
        )
    end
end

function AttributeInspectorRenderers.AddObjectSpecificMethodLines(lines, obj, methods)
    AddSectionTitle(lines, "Object-Specific Methods")
    AddDisplayLine(lines, "method_count", #methods)

    if #methods == 0 then
        AddDisplayLine(lines, "methods", "none discovered")
        return
    end

    for _, method in ipairs(methods) do
        local callable = type(ReadField(obj, method.name)) == "function"

        AddDisplayLine(
            lines,
            string.format("%s:%s()", method.class, method.name),
            callable and "exists" or "class_only"
        )
    end
end

function AttributeInspectorRenderers.AddObjectSpecificGroup(lines, obj)
    local class_entries = AttributeInspectorRenderers.ClassDefsForObject(obj)
    local methods, fields = AttributeInspectorRenderers.CollectObjectSpecificMembers(class_entries)

    AttributeInspectorRenderers.AddObjectSpecificClassList(lines, class_entries)
    AttributeInspectorRenderers.AddObjectSpecificPropertyLines(lines, obj, class_entries)
    AttributeInspectorRenderers.AddObjectSpecificFieldLines(lines, obj, fields)
    AttributeInspectorRenderers.AddObjectSpecificMethodLines(lines, obj, methods)
end

function AttributeInspectorRenderers.AddRawGroup(lines, obj, marker, marker_source)
    local entity = RawEntity(obj)
    local template = TemplateForObject(obj)
    local entity_data = EntityDataFor(entity)

    AddSectionTitle(lines, "Raw Lua / Advanced")
    AddObjectLines(lines, "Selected object", obj)
    AddDisplayLine(lines, "marker_source", marker_source)

    if IsGameObjectValid(marker) then
        AddObjectLines(lines, "Marker object", marker)
    else
        AddDisplayLine(lines, "marker", "nil")
    end

    AddPropertyDump(lines, obj, "All Object Properties", nil)
    AddRawFieldDump(lines, obj)
    AddTableEntries(lines, "Template Raw Fields", template, nil)
    AddTableEntries(lines, "EntityData Raw Fields", entity_data, nil)
end

-- Build the full inspector text for the first selected object and its marker.
local function PanelText(obj, selected_count, source, force_all_groups)
    local marker, marker_source = FindMarker(obj)
    local lines = {
        string.format("source = %s", source),
        string.format("selected_count = %d", selected_count or 1),
        "",
    }
    local visible_groups = 0

    EnsureGroupState()

    for _, group in ipairs(ATTRIBUTE_GROUPS) do
        if ShouldShowGroup(group.id, force_all_groups) then
            visible_groups = visible_groups + 1

            if group.id == "summary" then
                AttributeInspectorRenderers.AddSummaryGroup(lines, obj, selected_count, source, marker, marker_source)
            elseif group.id == "identity_class" then
                AttributeInspectorRenderers.AddIdentityGroup(lines, obj)
            elseif group.id == "transform_placement" then
                AttributeInspectorRenderers.AddTransformGroup(lines, obj)
            elseif group.id == "entity_visual_asset" then
                AttributeInspectorRenderers.AddEntityVisualGroup(lines, obj)
            elseif group.id == "materials_textures" then
                AttributeInspectorRenderers.AddMaterialsGroup(lines, obj)
            elseif group.id == "footprint_hex_shape" then
                AttributeInspectorRenderers.AddFootprintGroup(lines, obj)
            elseif group.id == "collision_passability" then
                AttributeInspectorRenderers.AddCollisionGroup(lines, obj)
            elseif group.id == "pathfinding_object_grid" then
                AttributeInspectorRenderers.AddPathfindingGroup(lines, obj)
            elseif group.id == "passage_ramp_specific" then
                AttributeInspectorRenderers.AddPassageGroup(lines, obj)
            elseif group.id == "buildability_construction" then
                AttributeInspectorRenderers.AddBuildabilityGroup(lines, obj)
            elseif group.id == "work_spots_interaction_spots" then
                AttributeInspectorRenderers.AddWorkSpotsGroup(lines, obj)
            elseif group.id == "ownership_lifecycle" then
                AttributeInspectorRenderers.AddOwnershipGroup(lines, obj, marker, marker_source)
            elseif group.id == "ui_selection" then
                AttributeInspectorRenderers.AddUISelectionGroup(lines, obj, selected_count, source)
            elseif group.id == "object_specific" then
                AttributeInspectorRenderers.AddObjectSpecificGroup(lines, obj)
            elseif group.id == "raw_lua_advanced" then
                AttributeInspectorRenderers.AddRawGroup(lines, obj, marker, marker_source)
            else
                AddSectionTitle(lines, group.title)
                AttributeInspectorRenderers.AddWarningLine(lines, "no renderer registered for this attribute group")
            end
        end
    end

    if visible_groups == 0 then
        lines[#lines + 1] = "No attribute groups selected."
    end

    return table.concat(lines, "\n")
end

local function PrintExportLine(line)
    SafeCall(Global("print"), "[AttributeInspector][Export] " .. tostring(line or ""))
end

-- Append the full inspector dump to the active game log.
function AttributeInspector_ExportToLog()
    local obj, selected_count, source = SelectedObject()

    PrintExportLine("BEGIN")

    if IsGameObjectValid(obj) then
        PrintExportLine(string.format("source = %s", source))
        PrintExportLine(string.format("selected_count = %d", selected_count or 1))
        PrintExportLine("groups = all")
        PrintExportLine("")

        local text = PanelText(obj, selected_count, source, true)

        for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
            PrintExportLine(line)
        end
    else
        PrintExportLine("No object selected.")
    end

    PrintExportLine("END")

    return true
end

-- Find a panel child control by id across engine versions.
local function PanelControl(id)
    if not AttributeInspectorDialog then
        return false
    end

    local control = AttributeInspectorControls[id]

    if control then
        return control
    end

    control = ReadField(AttributeInspectorDialog, id)

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

-- Update a color property through the control setter when this UI version has it.
local function SetControlColor(control, setter_name, color)
    local setter = ReadField(control, setter_name)

    if type(setter) == "function" then
        pcall(function()
            setter(control, color)
        end)
    end
end

-- Keep hover, focus, and disabled text states visually identical.
local function LockControlTextColor(control)
    SetControlColor(control, "SetTextColor", PANEL_TEXT_COLOR)
    SetControlColor(control, "SetRolloverTextColor", PANEL_TEXT_COLOR)
    SetControlColor(control, "SetFocusedTextColor", PANEL_TEXT_COLOR)
    SetControlColor(control, "SetDisabledTextColor", PANEL_TEXT_COLOR)
    SetControlColor(control, "SetDisabledRolloverTextColor", PANEL_TEXT_COLOR)
end

-- Keep toggle buttons readable and make active filters visually distinct.
local function SetGroupButtonState(button, active)
    if not button then
        return
    end

    SetControlColor(
        button,
        "SetBackground",
        active and GROUP_BUTTON_ACTIVE_BACKGROUND or GROUP_BUTTON_INACTIVE_BACKGROUND
    )
    SetControlColor(button, "SetRolloverBackground", GROUP_BUTTON_ROLLOVER_BACKGROUND)
    SetControlColor(button, "SetPressedBackground", GROUP_BUTTON_PRESSED_BACKGROUND)
    LockControlTextColor(button)
end

-- Find the draggable inspector root from a nested child control.
local function InspectorPanelFromControl(control)
    local current = control

    while current do
        if type(ReadField(current, "StartDrag")) == "function" then
            return current
        end

        current = ReadField(current, "parent")
    end

    return false
end

local function UpdateGroupButtons()
    EnsureGroupState()

    for _, group in ipairs(ATTRIBUTE_GROUPS) do
        SetGroupButtonState(
            PanelControl("idGroupButton_" .. group.id),
            AttributeInspectorGroupState[group.id] == true
        )
    end
end

-- Reset text scroll only when the displayed body content actually changes.
local function ResetScroll()
    local scroll_area = PanelControl("idScrollArea")

    if scroll_area and type(ReadField(scroll_area, "ScrollTo")) == "function" then
        pcall(function()
            scroll_area:ScrollTo(0, 0, true)
        end)
    end
end

-- Update inspector body text without fighting the user's manual scroll position.
local function SetBodyText(control, text)
    local next_text = tostring(text or "")

    if AttributeInspectorLastBodyText == next_text then
        return
    end

    AttributeInspectorLastBodyText = next_text
    SetText(control, next_text)
    ResetScroll()
end

-- Extract screen coordinates from an engine point value.
local function PointXY(pt)
    if not pt then
        return false, false
    end

    local ok, x, y = pcall(function()
        return pt:xy()
    end)

    if ok and type(x) == "number" and type(y) == "number" then
        return x, y
    end

    local ok_x, px = pcall(function()
        return pt:x()
    end)
    local ok_y, py = pcall(function()
        return pt:y()
    end)

    if ok_x and ok_y and type(px) == "number" and type(py) == "number" then
        return px, py
    end

    return false, false
end

-- Extract rectangle coordinates from an engine box value.
local function BoxMetrics(rect)
    if not rect then
        return false, false, false, false
    end

    local ok, x, y, width, height = pcall(function()
        return rect:minx(), rect:miny(), rect:sizex(), rect:sizey()
    end)

    if ok
        and type(x) == "number"
        and type(y) == "number"
        and type(width) == "number"
        and type(height) == "number"
    then
        return x, y, width, height
    end

    return false, false, false, false
end

-- Clamp a draggable coordinate to the visible parent area when available.
local function ClampPanelPosition(panel, x, y, width, height)
    local parent = ReadField(panel, "parent")
    local desktop = ReadField(panel, "desktop")
    local bounds = parent and ReadField(parent, "content_box")

    if not bounds and desktop then
        bounds = ReadField(desktop, "box")
    end

    local bounds_x, bounds_y, bounds_width, bounds_height = BoxMetrics(bounds)

    if not bounds_x then
        return x, y
    end

    local max_x = bounds_x + math.max(0, bounds_width - width)
    local max_y = bounds_y + math.max(0, bounds_height - height)

    return math.min(math.max(x, bounds_x), max_x),
        math.min(math.max(y, bounds_y), max_y)
end

-- Switch the panel from layout-docked placement to explicit draggable placement.
local function SetPanelManualBox(panel, x, y, width, height)
    panel.Dock = "ignore"
    panel.HAlign = "none"
    panel.VAlign = "none"
    panel.Margins = box(0, 0, 0, 0)

    if type(ReadField(panel, "SetBox")) == "function" then
        pcall(function()
            panel:SetBox(x, y, width, height)
        end)
    end
end

local function SetPanelSizeLimits(panel, min_width, max_width, min_height, max_height)
    panel.MinWidth = min_width
    panel.MaxWidth = max_width
    panel.MinHeight = min_height
    panel.MaxHeight = max_height
end

local function InvalidatePanelLayout(panel)
    local invalidate_measure = ReadField(panel, "InvalidateMeasure")
    local invalidate_layout = ReadField(panel, "InvalidateLayout")
    local invalidate = ReadField(panel, "Invalidate")

    if type(invalidate_measure) == "function" then
        pcall(function()
            invalidate_measure(panel)
        end)
    end

    if type(invalidate_layout) == "function" then
        pcall(function()
            invalidate_layout(panel)
        end)
    end

    if type(invalidate) == "function" then
        pcall(function()
            invalidate(panel)
        end)
    end
end

local function MinimizedPanelPosition(panel)
    local parent = ReadField(panel, "parent")
    local desktop = ReadField(panel, "desktop")
    local bounds = parent and ReadField(parent, "content_box")

    if not bounds and desktop then
        bounds = ReadField(desktop, "box")
    end

    local bounds_x, bounds_y, bounds_width, bounds_height = BoxMetrics(bounds)

    if not bounds_x then
        return 0, 0
    end

    return bounds_x + math.max(0, bounds_width - MINIMIZED_BUTTON_WIDTH - 20),
        bounds_y + math.max(0, bounds_height - MINIMIZED_BUTTON_HEIGHT - 80)
end

local function SetInspectorPanelMinimized(self, minimized)
    minimized = minimized == true

    if minimized and self.attribute_inspector_minimized ~= true then
        local x, y, width, height = BoxMetrics(ReadField(self, "box"))

        if x then
            self.attribute_inspector_restore_box = {
                x = x,
                y = y,
                width = width,
                height = height,
            }
        end
    end

    self.attribute_inspector_minimized = minimized

    SetVisible(PanelControl("idSidePanel"), not minimized)
    SetVisible(PanelControl("idContentPanel"), not minimized)
    SetVisible(PanelControl("idMinimizedButton"), minimized)

    if minimized then
        local x, y = MinimizedPanelPosition(self)

        SetPanelSizeLimits(
            self,
            MINIMIZED_BUTTON_WIDTH,
            MINIMIZED_BUTTON_WIDTH,
            MINIMIZED_BUTTON_HEIGHT,
            MINIMIZED_BUTTON_HEIGHT
        )
        SetPanelManualBox(self, x, y, MINIMIZED_BUTTON_WIDTH, MINIMIZED_BUTTON_HEIGHT)
    else
        local restore_box = self.attribute_inspector_restore_box

        SetPanelSizeLimits(
            self,
            INSPECTOR_PANEL_MIN_WIDTH,
            INSPECTOR_PANEL_MAX_WIDTH,
            PANEL_HEIGHT,
            PANEL_HEIGHT
        )

        if restore_box then
            SetPanelManualBox(
                self,
                restore_box.x,
                restore_box.y,
                restore_box.width,
                restore_box.height
            )
        else
            self.Dock = "box"
            self.HAlign = "right"
            self.VAlign = "bottom"
            self.Margins = box(0, 0, 20, 80)
        end
    end

    InvalidatePanelLayout(self)
    DebugLog("UI", "Panel minimized state changed", {
        minimized = minimized,
    })
end

-- Create the non-scroll fallback body if engine scroll controls are unavailable.
local function CreatePlainBody(panel)
    if not XText then
        DebugLog("UI", "Plain body skipped", {
            reason = "XText_unavailable",
        })
        return false
    end

    local body = XText:new({
        Id = "idBody",
        Text = "",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = PANEL_TEXT_COLOR,
        RolloverTextColor = PANEL_TEXT_COLOR,
        DisabledTextColor = PANEL_TEXT_COLOR,
        DisabledRolloverTextColor = PANEL_TEXT_COLOR,
        HAlign = "stretch",
        VAlign = "top",
        WordWrap = true,
        MinHeight = PANEL_BODY_HEIGHT,
        MaxHeight = PANEL_BODY_HEIGHT,
        UseClipBox = true,
        HandleMouse = false,
    }, panel)
    AttributeInspectorControls.idBody = body
    LockControlTextColor(body)

    return true
end

-- Create a scrollable inspector body using the engine's standard XScrollArea.
local function CreateScrollableBody(panel)
    local x_window = Global("XWindow")
    local x_scroll_area = Global("XScrollArea")
    local x_text = Global("XText")
    local scroll_class = Global("XSleekScroll") or Global("Scrollbar")

    if not x_window or not x_scroll_area or not x_text or not scroll_class then
        DebugLog("UI", "Scrollable body skipped", {
            reason = "scroll_controls_unavailable",
        })
        return false
    end

    local ok = pcall(function()
        local body_container = x_window:new({
            Id = "idBodyContainer",
            HAlign = "stretch",
            VAlign = "stretch",
            LayoutMethod = "HList",
            MinWidth = 480,
            MaxWidth = 640,
            MinHeight = PANEL_BODY_HEIGHT,
            MaxHeight = PANEL_BODY_HEIGHT,
            Background = TRANSPARENT_BACKGROUND,
            FocusedBackground = TRANSPARENT_BACKGROUND,
            DisabledBackground = TRANSPARENT_BACKGROUND,
            HandleMouse = false,
            ChildrenHandleMouse = true,
        }, panel)

        local scroll_area = x_scroll_area:new({
            Id = "idScrollArea",
            IdNode = false,
            HAlign = "stretch",
            VAlign = "stretch",
            MinWidth = 480,
            MaxWidth = 640,
            MinHeight = PANEL_BODY_HEIGHT,
            MaxHeight = PANEL_BODY_HEIGHT,
            VScroll = "idScroll",
            MouseScroll = true,
            Background = TRANSPARENT_BACKGROUND,
            FocusedBackground = TRANSPARENT_BACKGROUND,
            DisabledBackground = TRANSPARENT_BACKGROUND,
            HandleMouse = true,
            ChildrenHandleMouse = true,
        }, body_container)
        AttributeInspectorControls.idScrollArea = scroll_area

        local body = x_text:new({
            Id = "idBody",
            Text = "",
            Translate = false,
            TextStyle = "ConsoleLog",
            TextColor = PANEL_TEXT_COLOR,
            RolloverTextColor = PANEL_TEXT_COLOR,
            DisabledTextColor = PANEL_TEXT_COLOR,
            DisabledRolloverTextColor = PANEL_TEXT_COLOR,
            HAlign = "stretch",
            VAlign = "top",
            WordWrap = true,
            MinHeight = PANEL_BODY_HEIGHT,
            HandleMouse = false,
        }, scroll_area)
        AttributeInspectorControls.idBody = body
        LockControlTextColor(body)

        local scroll = scroll_class:new({
            Id = "idScroll",
            Dock = "right",
            Target = "idScrollArea",
            AutoHide = true,
        }, body_container)
        AttributeInspectorControls.idScroll = scroll
    end)

    if ok ~= true then
        DebugLog("UI", "Scrollable body creation failed")
        return false
    end

    return true
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
        SetBodyText(body, PanelText(obj, selected_count, source))
        SetVisible(delete_button, true)
    else
        SetText(title, "Attribute Inspector  (Selected: 0)")
        SetBodyText(body, "")
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
    Padding = box(0, 0, 0, 0),
    LayoutMethod = "HList",
    LayoutHSpacing = 8,
    Clip = false,
    MinWidth = INSPECTOR_PANEL_MIN_WIDTH,
    MaxWidth = INSPECTOR_PANEL_MAX_WIDTH,
    MinHeight = PANEL_HEIGHT,
    MaxHeight = PANEL_HEIGHT,
    Background = TRANSPARENT_BACKGROUND,
    FocusedBackground = TRANSPARENT_BACKGROUND,
    DisabledBackground = TRANSPARENT_BACKGROUND,
    HandleMouse = true,
    ChildrenHandleMouse = true,
}

function AttributeInspectorPanel:SetMinimized(minimized)
    return SetInspectorPanelMinimized(self, minimized)
end

-- Start a drag operation from the panel or title bar.
function AttributeInspectorPanel:StartDrag(pt, button)
    if button ~= "L" then
        return
    end

    local mouse_x, mouse_y = PointXY(pt)
    local box_x, box_y, box_width, box_height = BoxMetrics(ReadField(self, "box"))

    if not mouse_x or not box_x then
        DebugLog("Drag", "Start skipped", {
            reason = "missing_point_or_box",
        })
        return
    end

    self.drag_start_x = mouse_x
    self.drag_start_y = mouse_y
    self.drag_box_x = box_x
    self.drag_box_y = box_y
    self.drag_box_width = box_width
    self.drag_box_height = box_height
    self.dragging_panel = true

    SetPanelManualBox(self, box_x, box_y, box_width, box_height)

    local desktop = ReadField(self, "desktop")

    if desktop and type(ReadField(desktop, "SetMouseCapture")) == "function" then
        pcall(function()
            desktop:SetMouseCapture(self)
        end)
    end

    DebugLog("Drag", "Started", {
        x = box_x,
        y = box_y,
        width = box_width,
        height = box_height,
    })

    return "break"
end

-- Move the panel while a drag operation is active.
function AttributeInspectorPanel:MoveDrag(pt)
    if self.dragging_panel ~= true then
        return
    end

    local mouse_x, mouse_y = PointXY(pt)

    if not mouse_x then
        return "break"
    end

    local width = self.drag_box_width or 0
    local height = self.drag_box_height or 0
    local x = (self.drag_box_x or 0) + mouse_x - (self.drag_start_x or mouse_x)
    local y = (self.drag_box_y or 0) + mouse_y - (self.drag_start_y or mouse_y)

    x, y = ClampPanelPosition(self, x, y, width, height)
    SetPanelManualBox(self, x, y, width, height)

    return "break"
end

-- End the active drag operation and release mouse capture.
function AttributeInspectorPanel:StopDrag(pt, button)
    if button ~= "L" or self.dragging_panel ~= true then
        return
    end

    self:MoveDrag(pt)
    self.dragging_panel = false

    local desktop = ReadField(self, "desktop")

    if desktop and type(ReadField(desktop, "SetMouseCapture")) == "function" then
        pcall(function()
            desktop:SetMouseCapture(false)
        end)
    end

    DebugLog("Drag", "Stopped")

    return "break"
end

function AttributeInspectorPanel:OnMouseButtonDown(pt, button)
    return self:StartDrag(pt, button)
end

function AttributeInspectorPanel:OnMousePos(pt)
    return self:MoveDrag(pt)
end

function AttributeInspectorPanel:OnMouseButtonUp(pt, button)
    return self:StopDrag(pt, button)
end

function AttributeInspectorPanel:OnMouseWheelForward()
    local scroll_area = PanelControl("idScrollArea")

    if scroll_area and type(ReadField(scroll_area, "OnMouseWheelForward")) == "function" then
        return scroll_area:OnMouseWheelForward()
    end
end

function AttributeInspectorPanel:OnMouseWheelBack()
    local scroll_area = PanelControl("idScrollArea")

    if scroll_area and type(ReadField(scroll_area, "OnMouseWheelBack")) == "function" then
        return scroll_area:OnMouseWheelBack()
    end
end

function AttributeInspectorPanel:OnCaptureLost()
    if self.dragging_panel == true then
        DebugLog("Drag", "Capture lost")
    end

    self.dragging_panel = false
end

local function ForwardDragFromChild(child, pt, button)
    local panel = InspectorPanelFromControl(child)

    return panel and panel:StartDrag(pt, button)
end

local function ForwardDragMoveFromChild(child, pt)
    local panel = InspectorPanelFromControl(child)

    return panel and panel:MoveDrag(pt)
end

local function ForwardDragStopFromChild(child, pt, button)
    local panel = InspectorPanelFromControl(child)

    return panel and panel:StopDrag(pt, button)
end

local function ForwardWheelForwardFromChild(child)
    local panel = InspectorPanelFromControl(child)

    return panel and panel:OnMouseWheelForward()
end

local function ForwardWheelBackFromChild(child)
    local panel = InspectorPanelFromControl(child)

    return panel and panel:OnMouseWheelBack()
end

local function CreateGroupToggleButton(parent, group)
    local button = XTextButton:new({
        Id = "idGroupButton_" .. group.id,
        Text = group.button or group.title,
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = PANEL_TEXT_COLOR,
        RolloverTextColor = PANEL_TEXT_COLOR,
        DisabledTextColor = PANEL_TEXT_COLOR,
        DisabledRolloverTextColor = PANEL_TEXT_COLOR,
        HAlign = "left",
        VAlign = "top",
        MinWidth = GROUP_BUTTON_WIDTH,
        MaxWidth = GROUP_BUTTON_WIDTH,
        MinHeight = GROUP_BUTTON_HEIGHT,
        MaxHeight = GROUP_BUTTON_HEIGHT,
    }, parent)
    AttributeInspectorControls["idGroupButton_" .. group.id] = button
    LockControlTextColor(button)

    SetGroupButtonState(button, IsGroupEnabled(group.id))

    function button:OnPress()
        ToggleGroupEnabled(group.id)
        UpdateGroupButtons()
        AttributeInspector_UpdatePanel()
    end

    function button:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function button:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    return button
end

local function CreateCommandButton(parent, id, text, on_press)
    local button = XTextButton:new({
        Id = id,
        Text = text,
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = PANEL_TEXT_COLOR,
        RolloverTextColor = PANEL_TEXT_COLOR,
        DisabledTextColor = PANEL_TEXT_COLOR,
        DisabledRolloverTextColor = PANEL_TEXT_COLOR,
        HAlign = "left",
        VAlign = "top",
        MinWidth = GROUP_BUTTON_WIDTH,
        MaxWidth = GROUP_BUTTON_WIDTH,
        MinHeight = GROUP_BUTTON_HEIGHT,
        MaxHeight = GROUP_BUTTON_HEIGHT,
    }, parent)
    AttributeInspectorControls[id] = button
    LockControlTextColor(button)

    SetGroupButtonState(button, false)

    function button:OnPress()
        on_press()
        UpdateGroupButtons()
        AttributeInspector_UpdatePanel()
    end

    function button:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function button:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    return button
end

local function CreateSidePanel(panel)
    local side_panel = XWindow:new({
        Id = "idSidePanel",
        HAlign = "left",
        VAlign = "stretch",
        MinWidth = SIDE_PANEL_WIDTH,
        MaxWidth = SIDE_PANEL_WIDTH,
        MinHeight = PANEL_HEIGHT,
        MaxHeight = PANEL_HEIGHT,
        Padding = box(8, 8, 8, 8),
        LayoutMethod = "VList",
        LayoutVSpacing = 4,
        Clip = "self",
        Background = PANEL_BACKGROUND,
        FocusedBackground = PANEL_BACKGROUND,
        DisabledBackground = PANEL_BACKGROUND,
        HandleMouse = true,
        ChildrenHandleMouse = true,
    }, panel)

    function side_panel:OnMouseButtonDown(pt, button)
        return ForwardDragFromChild(self, pt, button)
    end

    function side_panel:OnMousePos(pt)
        return ForwardDragMoveFromChild(self, pt)
    end

    function side_panel:OnMouseButtonUp(pt, button)
        return ForwardDragStopFromChild(self, pt, button)
    end

    function side_panel:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function side_panel:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    AttributeInspectorControls.idSidePanel = side_panel

    local side_title = XLabel:new({
        Id = "idSideTitle",
        Text = "Groups",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = PANEL_TEXT_COLOR,
        RolloverTextColor = PANEL_TEXT_COLOR,
        DisabledTextColor = PANEL_TEXT_COLOR,
        DisabledRolloverTextColor = PANEL_TEXT_COLOR,
        HAlign = "stretch",
        VAlign = "top",
        MinHeight = 22,
        MaxHeight = 22,
        HandleMouse = true,
    }, side_panel)
    AttributeInspectorControls.idSideTitle = side_title
    LockControlTextColor(side_title)

    function side_title:OnMouseButtonDown(pt, button)
        return ForwardDragFromChild(self, pt, button)
    end

    function side_title:OnMousePos(pt)
        return ForwardDragMoveFromChild(self, pt)
    end

    function side_title:OnMouseButtonUp(pt, button)
        return ForwardDragStopFromChild(self, pt, button)
    end

    function side_title:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function side_title:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    CreateCommandButton(side_panel, "idAllGroupsButton", "All", function()
        SetAllGroupsEnabled(true)
    end)

    CreateCommandButton(side_panel, "idNoGroupsButton", "None", function()
        SetAllGroupsEnabled(false)
    end)

    CreateCommandButton(side_panel, "idResetGroupsButton", "Reset", function()
        SetAllGroupsEnabled(true)
    end)

    CreateCommandButton(side_panel, "idExportLogButton", "Export Log", function()
        AttributeInspector_ExportToLog()
    end)

    for _, group in ipairs(ATTRIBUTE_GROUPS) do
        CreateGroupToggleButton(side_panel, group)
    end

    return side_panel
end

local function CreateContentPanel(panel)
    local content_panel = XWindow:new({
        Id = "idContentPanel",
        HAlign = "left",
        VAlign = "stretch",
        MinWidth = CONTENT_PANEL_MIN_WIDTH,
        MaxWidth = CONTENT_PANEL_MAX_WIDTH,
        MinHeight = PANEL_HEIGHT,
        MaxHeight = PANEL_HEIGHT,
        Padding = box(8, 8, 8, 8),
        LayoutMethod = "VList",
        LayoutVSpacing = 4,
        Clip = "self",
        Background = PANEL_BACKGROUND,
        FocusedBackground = PANEL_BACKGROUND,
        DisabledBackground = PANEL_BACKGROUND,
        HandleMouse = true,
        ChildrenHandleMouse = true,
    }, panel)
    AttributeInspectorControls.idContentPanel = content_panel

    function content_panel:OnMouseButtonDown(pt, button)
        return ForwardDragFromChild(self, pt, button)
    end

    function content_panel:OnMousePos(pt)
        return ForwardDragMoveFromChild(self, pt)
    end

    function content_panel:OnMouseButtonUp(pt, button)
        return ForwardDragStopFromChild(self, pt, button)
    end

    function content_panel:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function content_panel:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    return content_panel
end

-- Construct child controls and start the polling fallback thread.
function AttributeInspectorPanel:Init()
    AttributeInspectorDialog = self
    AttributeInspectorLastBodyText = false
    AttributeInspectorControls = {}
    EnsureGroupState()

    local content_panel

    local minimized_button = XTextButton:new({
        Id = "idMinimizedButton",
        Text = "AI",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = PANEL_TEXT_COLOR,
        RolloverTextColor = PANEL_TEXT_COLOR,
        DisabledTextColor = PANEL_TEXT_COLOR,
        DisabledRolloverTextColor = PANEL_TEXT_COLOR,
        HAlign = "stretch",
        VAlign = "stretch",
        MinWidth = MINIMIZED_BUTTON_WIDTH,
        MaxWidth = MINIMIZED_BUTTON_WIDTH,
        MinHeight = MINIMIZED_BUTTON_HEIGHT,
        MaxHeight = MINIMIZED_BUTTON_HEIGHT,
        Visible = false,
    }, self)
    AttributeInspectorControls.idMinimizedButton = minimized_button
    LockControlTextColor(minimized_button)
    SetControlColor(minimized_button, "SetBackground", GROUP_BUTTON_ACTIVE_BACKGROUND)
    SetControlColor(minimized_button, "SetRolloverBackground", GROUP_BUTTON_ROLLOVER_BACKGROUND)
    SetControlColor(minimized_button, "SetPressedBackground", GROUP_BUTTON_PRESSED_BACKGROUND)

    function minimized_button:OnPress()
        local panel = InspectorPanelFromControl(self)

        if panel and type(ReadField(panel, "SetMinimized")) == "function" then
            panel:SetMinimized(false)
        end
    end

    CreateSidePanel(self)
    content_panel = CreateContentPanel(self)

    local header = XWindow:new({
        Id = "idTitleHeader",
        HAlign = "stretch",
        VAlign = "top",
        LayoutMethod = "HList",
        LayoutHSpacing = 4,
        MinHeight = PANEL_HEADER_HEIGHT,
        MaxHeight = PANEL_HEADER_HEIGHT,
        Background = TRANSPARENT_BACKGROUND,
        FocusedBackground = TRANSPARENT_BACKGROUND,
        DisabledBackground = TRANSPARENT_BACKGROUND,
        HandleMouse = true,
        ChildrenHandleMouse = true,
    }, content_panel)
    AttributeInspectorControls.idTitleHeader = header

    function header:OnMouseButtonDown(pt, button)
        return ForwardDragFromChild(self, pt, button)
    end

    function header:OnMousePos(pt)
        return ForwardDragMoveFromChild(self, pt)
    end

    function header:OnMouseButtonUp(pt, button)
        return ForwardDragStopFromChild(self, pt, button)
    end

    function header:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function header:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    local title = XLabel:new({
        Id = "idTitle",
        Text = "Attribute Inspector  (Selected: 0)",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = PANEL_TEXT_COLOR,
        RolloverTextColor = PANEL_TEXT_COLOR,
        DisabledTextColor = PANEL_TEXT_COLOR,
        DisabledRolloverTextColor = PANEL_TEXT_COLOR,
        HAlign = "left",
        VAlign = "top",
        MinWidth = CONTENT_TITLE_MIN_WIDTH,
        MaxWidth = CONTENT_TITLE_MAX_WIDTH,
        MinHeight = PANEL_HEADER_HEIGHT,
        MaxHeight = PANEL_HEADER_HEIGHT,
        HandleMouse = true,
    }, header)
    AttributeInspectorControls.idTitle = title
    LockControlTextColor(title)

    function title:OnMouseButtonDown(pt, button)
        return ForwardDragFromChild(self, pt, button)
    end

    function title:OnMousePos(pt)
        return ForwardDragMoveFromChild(self, pt)
    end

    function title:OnMouseButtonUp(pt, button)
        return ForwardDragStopFromChild(self, pt, button)
    end

    function title:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function title:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    local minimize_button = XTextButton:new({
        Id = "idMinimizeButton",
        Text = "-",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = PANEL_TEXT_COLOR,
        RolloverTextColor = PANEL_TEXT_COLOR,
        DisabledTextColor = PANEL_TEXT_COLOR,
        DisabledRolloverTextColor = PANEL_TEXT_COLOR,
        HAlign = "right",
        VAlign = "top",
        MinWidth = MINIMIZE_BUTTON_WIDTH,
        MaxWidth = MINIMIZE_BUTTON_WIDTH,
        MinHeight = PANEL_HEADER_HEIGHT,
        MaxHeight = PANEL_HEADER_HEIGHT,
    }, header)
    AttributeInspectorControls.idMinimizeButton = minimize_button
    LockControlTextColor(minimize_button)
    SetControlColor(minimize_button, "SetBackground", GROUP_BUTTON_INACTIVE_BACKGROUND)
    SetControlColor(minimize_button, "SetRolloverBackground", GROUP_BUTTON_ROLLOVER_BACKGROUND)
    SetControlColor(minimize_button, "SetPressedBackground", GROUP_BUTTON_PRESSED_BACKGROUND)

    function minimize_button:OnPress()
        local panel = InspectorPanelFromControl(self)

        if panel and type(ReadField(panel, "SetMinimized")) == "function" then
            panel:SetMinimized(true)
        end
    end

    function minimize_button:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function minimize_button:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    local close_button = XTextButton:new({
        Id = "idCloseButton",
        Text = "X",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = PANEL_TEXT_COLOR,
        RolloverTextColor = PANEL_TEXT_COLOR,
        DisabledTextColor = PANEL_TEXT_COLOR,
        DisabledRolloverTextColor = PANEL_TEXT_COLOR,
        HAlign = "right",
        VAlign = "top",
        MinWidth = CLOSE_BUTTON_WIDTH,
        MaxWidth = CLOSE_BUTTON_WIDTH,
        MinHeight = PANEL_HEADER_HEIGHT,
        MaxHeight = PANEL_HEADER_HEIGHT,
    }, header)
    AttributeInspectorControls.idCloseButton = close_button
    LockControlTextColor(close_button)
    SetControlColor(close_button, "SetBackground", GROUP_BUTTON_INACTIVE_BACKGROUND)
    SetControlColor(close_button, "SetRolloverBackground", GROUP_BUTTON_ROLLOVER_BACKGROUND)
    SetControlColor(close_button, "SetPressedBackground", GROUP_BUTTON_PRESSED_BACKGROUND)

    function close_button:OnPress()
        AttributeInspector_ClosePanel()
    end

    function close_button:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function close_button:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    if not CreateScrollableBody(content_panel) then
        CreatePlainBody(content_panel)
    end

    local delete_button = XTextButton:new({
        Id = "idDeleteButton",
        Text = "Delete Selected Objects",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = PANEL_TEXT_COLOR,
        RolloverTextColor = PANEL_TEXT_COLOR,
        DisabledTextColor = PANEL_TEXT_COLOR,
        DisabledRolloverTextColor = PANEL_TEXT_COLOR,
        HAlign = "left",
        VAlign = "top",
        MinWidth = 260,
        MaxWidth = 420,
        Visible = false,
    }, content_panel)
    AttributeInspectorControls.idDeleteButton = delete_button
    LockControlTextColor(delete_button)

    function delete_button:OnPress()
        AttributeInspector_DeleteCurrentObject()
    end

    function delete_button:OnMouseWheelForward()
        return ForwardWheelForwardFromChild(self)
    end

    function delete_button:OnMouseWheelBack()
        return ForwardWheelBackFromChild(self)
    end

    UpdateGroupButtons()

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

    local created_panel = false
    local create_ok, create_err = pcall(function()
        created_panel = AttributeInspectorPanel:new({
            Id = PANEL_ID,
            ZOrder = PANEL_Z_ORDER,
        }, parent)

        AttributeInspectorDialog = created_panel

        if WindowState(created_panel) == "new"
            and type(ReadField(created_panel, "Open")) == "function"
        then
            created_panel:Open()
        end
    end)

    if create_ok ~= true then
        DebugLog("UI", "Panel creation failed", {
            error = create_err,
        })
        AttributeInspectorDialog = false
        AttributeInspectorControls = {}
        return
    end

    local update_ok, update_err = pcall(AttributeInspector_UpdatePanel)

    if update_ok ~= true then
        DebugLog("UI", "Initial panel update failed", {
            error = update_err,
        })
    end
end

-- Close the inspector panel manually from Lua/debug sessions.
function AttributeInspector_ClosePanel()
    if not IsWindowAlive(AttributeInspectorDialog) then
        return
    end

    local panel = AttributeInspectorDialog
    local state = WindowState(panel)
    local ok = true
    local err = false

    if state == "open" or state == "closing" then
        local close = ReadField(panel, "Close")

        if type(close) == "function" then
            ok, err = pcall(function()
                close(panel)
            end)
        end
    elseif state == "new" then
        local delete = ReadField(panel, "delete")

        if type(delete) == "function" then
            ok, err = pcall(function()
                delete(panel)
            end)
        else
            ok = false
            err = "delete_unavailable"
        end
    else
        DebugLog("UI", "Panel close skipped", {
            state = state,
        })
    end

    if ok ~= true then
        DebugLog("UI", "Panel close failed", {
            state = state,
            error = err,
        })
        return
    end

    if AttributeInspectorDialog == panel then
        AttributeInspectorDialog = false
    end

    AttributeInspectorControls = {}
    AttributeInspectorLastBodyText = false
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
