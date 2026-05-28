-- Rivers -- water marker placement and engine water-grid integration.
--
-- The engine's TerrainWaterObject class is a marker that fills a depression
-- around itself up to a configurable z-offset using terrain.UpdateWaterGridFromObject.
-- WaterFill / WaterFillBig are entity-data wrappers around the same class (see
-- _EntityData.generated.lua in the game install: class_parent = "TerrainWaterObject").
--
-- For a carved channel we drop one marker at the lowest point of the carve,
-- set its position Z to "floor + water_level", call UpdateGridAndVisuals(true)
-- to avoid spill, then ApplyAllWaterObjects on the affected bbox to rebuild the
-- water grid + planes only in the area we changed.
--
-- Public API:
--   Rivers.Water.PlaceMarker(map, center_pt, floor_wu, water_level_m, bbox) -> obj | nil, err
--   Rivers.Water.RemoveMarker(map, obj, bbox)
--
-- Reversibility: deleting the marker and re-running ApplyAllWaterObjects on
-- the bbox makes the engine drain the water. Terrain heights are NOT restored
-- by this module -- see r_terrain.lua for the prototype caveat.

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	return
end

local DebugLog = Rivers.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }

local Water = {}
local SCOPE = "Water"

local function meters_to_wu(m)
	return MulDivRound(m, guim, 1)
end

-- Verify the required engine APIs are present. Logged behind the Water scope
-- so missing surface (e.g. the engine renamed TerrainWaterObject) shows up
-- explicitly instead of erroring at place time.
local function api_available()
	local has_class = rawget(_G, "g_Classes") and g_Classes.TerrainWaterObject ~= nil
	local has_apply = type(rawget(_G, "ApplyAllWaterObjects")) == "function"
	DebugLog.Info(SCOPE, "API availability", {
		TerrainWaterObject = has_class and "present" or "missing",
		ApplyAllWaterObjects = has_apply and "present" or "missing",
	})
	return has_class and has_apply
end

-- Place a TerrainWaterObject marker at `center_pt` with its visual z set to
-- (floor_wu + water_level_m_in_wu). Returns the placed marker or (nil, err).
--
-- avoid_spill (default true): when true the engine lowers z incrementally if the
-- chosen level would flood the map, keeping a pool contained. A SEA wants the
-- opposite -- it should flood the whole connected basin -- so r_sea.lua passes
-- false. apply_box, when given, forces ApplyAllWaterObjects over that exact box
-- (the sea passes the full map) instead of the engine's per-marker
-- invalidation_box.
function Water.PlaceMarker(map, center_pt, floor_wu, water_level_m, bbox, avoid_spill, apply_box)
	if not api_available() then
		return nil, "TerrainWaterObject / ApplyAllWaterObjects unavailable"
	end
	if type(map) ~= "table" and type(map) ~= "userdata" then
		return nil, "map handle is required"
	end

	local water_z = floor_wu + meters_to_wu(water_level_m)

	-- PlaceObject signature in this engine is (class_name, props_table, map, ...).
	-- The map argument is REQUIRED: Object.new -> CObject.new -> ResolveMap(nil)
	-- asserts "map and map:IsValid() and map.changing ~= 'destroying'".
	-- Canonical examples in the install: BaseRover.lua:609, MapTools.lua:64,
	-- XEditorObjectPalette.lua:382 all pass CurrentMap as the third argument.
	local place_obj = rawget(_G, "PlaceObject")
	if type(place_obj) ~= "function" then
		return nil, "PlaceObject is unavailable"
	end
	local obj = place_obj("TerrainWaterObject", nil, map)
	if not obj then
		return nil, "failed to construct TerrainWaterObject"
	end

	-- The marker's visual position determines the water surface height the engine
	-- fills depressions to. SetPos uses world units.
	obj:SetPos(center_pt:x(), center_pt:y(), water_z)

	-- avoid_spill=true clamps z down to avoid flooding the map; false lets the
	-- level stand (used for seas, which are supposed to flood the basin).
	obj:UpdateGridAndVisuals(avoid_spill ~= false)

	-- Rebuild water grid + planes. apply_box (sea: full map) wins; otherwise use
	-- the engine's per-marker invalidation_box, falling back to the passed bbox.
	local apply_bbox = apply_box or obj.invalidation_box or bbox
	ApplyAllWaterObjects(map, apply_bbox)

	DebugLog.Info(SCOPE, "placed water marker", {
		x = center_pt:x(),
		y = center_pt:y(),
		floor_wu = floor_wu,
		water_z = water_z,
		avoid_spill = avoid_spill ~= false,
		spilled = obj.zoffset ~= 0 and obj.zoffset or "no",
	})
	return obj
end

-- Raise/lower the water surface of an existing marker. `new_water_z` is in world
-- units; the caller computes it as (ground_at_marker_xy + level_meters * guim).
-- avoid_spill / apply_box behave as in PlaceMarker.
function Water.SetMarkerLevel(map, obj, new_water_z, avoid_spill, apply_box)
	if not obj or not IsValid(obj) then
		return false, "marker is invalid"
	end
	local x, y = obj:GetVisualPosXYZ()
	obj:SetPos(x, y, new_water_z)
	obj:UpdateGridAndVisuals(avoid_spill ~= false)
	local apply_bbox = apply_box or obj.invalidation_box
	if type(rawget(_G, "ApplyAllWaterObjects")) == "function" then
		ApplyAllWaterObjects(map, apply_bbox)
	end
	DebugLog.Info(SCOPE, "set marker level", {
		x = x, y = y, water_z = new_water_z,
	})
	return true
end

-- Delete a previously placed marker and rebuild the water grid in the
-- bbox so the depression drains. Safe to call on stale/invalid handles.
function Water.RemoveMarker(map, obj, bbox)
	if not obj or not IsValid(obj) then
		DebugLog.Info(SCOPE, "remove skipped, marker invalid", {})
		return
	end
	local apply_bbox = bbox or obj.invalidation_box
	DoneObject(obj)
	if type(rawget(_G, "ApplyAllWaterObjects")) == "function" then
		ApplyAllWaterObjects(map, apply_bbox)
	end
	DebugLog.Info(SCOPE, "removed water marker", {
		bbox = tostring(apply_bbox),
	})
end

Rivers.Water = Water
