-- Rivers -- public API.
--
-- Globals exposed (call from the in-game console):
--   Rivers.Create(path, params)   -- carve + place water for one river segment
--                                    path:    list of {x, y} world units or point()s
--                                    params:  optional table {
--                                                width_m, bank_m, depth_m, step_m,
--                                                water_level_m,
--                                             }
--                                    returns: segment_id (string) on success, or
--                                             nil, error_string on failure.
--   Rivers.Demo()                 -- build the configured demo river across the map.
--   Rivers.CreateAtCursor(opts)   -- carve a short river through the terrain cursor;
--                                    convenient if you don't want to type coords.
--                                    opts: optional table { length_m, angle_deg, plus any
--                                          params accepted by Rivers.Create }.
--   Rivers.ClearAll()             -- remove every water marker the mod placed.
--                                    Terrain heights are NOT restored (prototype caveat).
--   Rivers.List()                 -- print active segment ids.
--
-- All public functions respect Rivers.Config.ENABLE_MOD: if it is false they
-- log and return without touching the map.

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	return
end

local DebugLog = Rivers.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "API"

local function config()
	return Rivers.Config or {}
end

local function current_map()
	-- CurrentMap is the engine's currently-loaded map (set by Mars/CommonLua).
	local m = rawget(_G, "CurrentMap")
	return m
end

local function path_center(points)
	local sumx, sumy, n = 0, 0, #points
	for i = 1, n do
		local px, py = points[i]:xy()
		sumx = sumx + px
		sumy = sumy + py
	end
	return point(sumx / n, sumy / n)
end

-- Find the path point whose existing terrain height is lowest -- that's where
-- we put the water marker so the engine has a real depression to fill.
local function lowest_path_point(map, points)
	local best_pt, best_h
	for i = 1, #points do
		local pt = points[i]
		local h = terrain.GetHeight(map, pt)
		if not best_h or h < best_h then
			best_h = h
			best_pt = pt
		end
	end
	return best_pt
end

-- ----------------------------------------------------------------------------
-- Create
-- ----------------------------------------------------------------------------

function Rivers.Create(path, params)
	if config().ENABLE_MOD ~= true then
		DebugLog.Warn(SCOPE, "Create called but ENABLE_MOD is false")
		return nil, "Rivers mod disabled in config"
	end
	local map = current_map()
	if not map then
		return nil, "no current map (start or load a game first)"
	end
	local Terrain = Rivers.Terrain
	local Water = Rivers.Water
	if not Terrain or not Water then
		return nil, "Rivers.Terrain / Rivers.Water modules not loaded"
	end

	local points, err = Terrain.NormalizePath(path)
	if not points then
		DebugLog.Error(SCOPE, "Create: bad path", { error = err })
		return nil, err
	end

	params = params or {}
	local water_level_m = params.water_level_m or config().DEFAULT_WATER_LEVEL_METERS or 5

	local bbox, floor_wu = Terrain.CarveBowlAlongPath(map, points, params)
	if not bbox then
		DebugLog.Error(SCOPE, "Create: carve failed", { error = floor_wu })
		return nil, floor_wu
	end

	local marker_pt = lowest_path_point(map, points) or path_center(points)
	local obj, err2 = Water.PlaceMarker(map, marker_pt, floor_wu, water_level_m, bbox)
	if not obj then
		DebugLog.Error(SCOPE, "Create: water placement failed", { error = err2 })
		return nil, err2
	end

	local id = Rivers.State:RegisterSegment({
		water_obj = obj,
		bbox = bbox,
		floor_wu = floor_wu,
		marker_x = marker_pt:x(),
		marker_y = marker_pt:y(),
		water_level_m = water_level_m,
	})
	DebugLog.Info(SCOPE, "Create ok", {
		id = id,
		points = #points,
		floor_wu = floor_wu,
		water_level_m = water_level_m,
	})
	return id
end

-- ----------------------------------------------------------------------------
-- Demo
-- ----------------------------------------------------------------------------

function Rivers.Demo(params)
	local map = current_map()
	if not map then
		return nil, "no current map (start or load a game first)"
	end
	local sx, sy = terrain.GetMapSize(map)
	local pct = config().DEMO_PATH_PERCENTS or { {10, 50}, {35, 35}, {60, 65}, {90, 50} }
	local path = {}
	for i = 1, #pct do
		local px = MulDivRound(sx, pct[i][1], 100)
		local py = MulDivRound(sy, pct[i][2], 100)
		path[i] = { px, py }
	end
	DebugLog.Info(SCOPE, "Demo: building river across map", {
		map_sx = sx,
		map_sy = sy,
		points = #path,
	})
	return Rivers.Create(path, params)
end

-- ----------------------------------------------------------------------------
-- CreateAtCursor
-- ----------------------------------------------------------------------------

function Rivers.CreateAtCursor(opts)
	opts = opts or {}
	local get_cursor = rawget(_G, "GetTerrainCursor")
	if type(get_cursor) ~= "function" then
		return nil, "GetTerrainCursor is unavailable"
	end
	local center = get_cursor()
	if not center then
		return nil, "terrain cursor returned nil"
	end
	local length_m = opts.length_m or 200
	local angle_deg = opts.angle_deg or 0
	local half_wu = MulDivRound(length_m, guim, 2)
	-- Engine convention: angles are degrees * 60 ("minutes"). Rotate(pt, a) rotates
	-- pt around Z by a; CameraControlUtils.lua uses the same pattern.
	local engine_angle = angle_deg * 60
	local dir = Rotate(point(half_wu, 0, 0), engine_angle)
	local cx, cy = center:xy()
	local dx, dy = dir:xy()
	local path = {
		{ cx - dx, cy - dy },
		{ cx + dx, cy + dy },
	}
	DebugLog.Info(SCOPE, "CreateAtCursor", {
		cx = cx, cy = cy, length_m = length_m, angle_deg = angle_deg,
	})
	return Rivers.Create(path, opts)
end

-- ----------------------------------------------------------------------------
-- ClearAll / List
-- ----------------------------------------------------------------------------

function Rivers.ClearAll()
	local map = current_map()
	local Water = Rivers.Water
	local segments = Rivers.State.segments
	local removed = 0
	for id, seg in pairs(segments) do
		if Water and seg.water_obj then
			Water.RemoveMarker(map, seg.water_obj, seg.bbox)
		end
		segments[id] = nil
		removed = removed + 1
	end
	DebugLog.Info(SCOPE, "ClearAll", { removed = removed })
	return removed
end

function Rivers.List()
	local segments = Rivers.State.segments
	local ids = {}
	for id in pairs(segments) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	DebugLog.Info(SCOPE, "List", { count = #ids, ids = table.concat(ids, ", ") })
	return ids
end
