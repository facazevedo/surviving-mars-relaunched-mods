-- Rivers -- whole-map sea generation.
--
-- A "sea" is the engine's own definition: every tile of the map below a global
-- water level, flooded as one connected body (this mirrors the vanilla MapGen
-- "FlowSea" pipeline, which flood-fills terrain below a sea level -- see
-- Libs/MapGen/Data/MapGen/MapGen-Tools.lua in the game install). We reproduce
-- it at runtime with a single TerrainWaterObject placed at the map's lowest
-- point, its level set to (map_min_height + sea_level_m), applied map-wide with
-- spill-avoidance OFF so the engine floods the whole basin instead of clamping.
--
-- The sea is registered as a Rivers.State segment with is_sea=true so ClearAll
-- and the UI treat it like any body of water, BUT the budget ticker skips it
-- (r_budget.lua) -- a sea is a static, engine-managed body, not a per-tick
-- volume simulation. Adjusting its level re-applies the marker map-wide.
--
-- Public API:
--   Rivers.Sea.Generate(level_m?)   -> segment_id | nil, err
--   Rivers.Sea.SetLevel(seg_id, m)  -> level_m | nil, err   (used by the height field)

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	return
end

local DebugLog = Rivers.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Sea"

local Sea = {}

local function config()
	return Rivers.Config or {}
end

local function current_map()
	return rawget(_G, "CurrentMap")
end

local function meters_to_wu(m)
	return MulDivRound(m, guim, 1)
end

-- ----------------------------------------------------------------------------
-- Coarse map scan
-- ----------------------------------------------------------------------------

-- Sample an NxN grid of terrain heights and return:
--   min_pt   -- world point of the lowest sample (sea source / floor reference)
--   min_h_wu -- that lowest height (world units)
--   samples  -- flat array of sampled heights (row-major), for reuse
--   cell_wu2 -- area of one sample cell (world units^2)
-- Cheap one-shot cost: N*N terrain.GetHeight calls.
local function scan_heights(map)
	local terrain_table = rawget(_G, "terrain")
	if type(terrain_table) ~= "table"
		or type(terrain_table.GetHeight) ~= "function"
		or type(terrain_table.GetMapSize) ~= "function" then
		return nil
	end
	local sx, sy = terrain_table.GetMapSize(map)
	local n = config().SEA_SCAN_SAMPLES or 64
	if n < 2 then n = 2 end
	local cell_x = sx / n
	local cell_y = sy / n
	local samples = {}
	local min_h, min_pt
	for iy = 0, n - 1 do
		for ix = 0, n - 1 do
			local px = ix * cell_x + cell_x / 2
			local py = iy * cell_y + cell_y / 2
			local h = terrain_table.GetHeight(map, point(px, py))
			samples[#samples + 1] = h
			if not min_h or h < min_h then
				min_h = h
				min_pt = point(px, py)
			end
		end
	end
	return min_pt, min_h, samples, cell_x * cell_y
end

-- Given the scan and a sea water height (wu), estimate flooded surface area
-- (wu^2) and volume (m^3) by counting/summing sample cells below the level.
-- This is an approximation (sample resolution, ignores connectivity) but is
-- cheap and good enough for the readout; the actual water is engine-driven.
local function estimate_sea(samples, cell_wu2, water_z_wu)
	local flooded_wu2 = 0
	local volume_m3 = 0
	local cell_m2 = cell_wu2 / (guim * guim)
	for i = 1, #samples do
		local depth_wu = water_z_wu - samples[i]
		if depth_wu > 0 then
			flooded_wu2 = flooded_wu2 + cell_wu2
			local depth_m = MulDivRound(depth_wu, 1, guim)
			volume_m3 = volume_m3 + depth_m * cell_m2
		end
	end
	return flooded_wu2, volume_m3
end

-- ----------------------------------------------------------------------------
-- Generate
-- ----------------------------------------------------------------------------

-- Find the existing sea segment (there is at most one). Returns seg_id, seg.
function Sea.Find()
	for id, seg in pairs(Rivers.State.segments) do
		if seg.is_sea then
			return id, seg
		end
	end
	return nil
end

-- Absorb every lake the sea has reached: any non-sea segment whose source point
-- now sits at or below the sea surface (sea_z_wu) is part of the sea, so we
-- delete its marker and segment ("the river becomes a sea"). The sea's own
-- map-wide water object keeps that ground flooded after the lake marker is
-- removed. sea_id is kept as the current marker if an absorbed lake was current.
local function absorb_touching_lakes(map, sea_z_wu, sea_id)
	local terrain_table = rawget(_G, "terrain")
	if type(terrain_table) ~= "table" or type(terrain_table.GetHeight) ~= "function" then
		return 0
	end
	local Water = Rivers.Water
	local segments = Rivers.State.segments
	local absorbed = 0
	for id, seg in pairs(segments) do
		if not seg.is_sea then
			local th = terrain_table.GetHeight(map, point(seg.marker_x or 0, seg.marker_y or 0))
			if type(th) == "number" and th <= sea_z_wu then
				if Water and type(Water.RemoveMarker) == "function" and seg.water_obj then
					Water.RemoveMarker(map, seg.water_obj, seg.bbox)
				end
				segments[id] = nil
				if Rivers.State.current_marker_segment == id then
					local sea_seg = sea_id and segments[sea_id] or nil
					Rivers.State.current_marker = sea_seg and sea_seg.water_obj or false
					Rivers.State.current_marker_segment = sea_id or false
				end
				absorbed = absorbed + 1
			end
		end
	end
	if absorbed > 0 then
		DebugLog.Info(SCOPE, "absorbed lakes into sea", { count = absorbed })
	end
	return absorbed
end

function Sea.Generate(level_m)
	if config().ENABLE_MOD ~= true then
		DebugLog.Warn(SCOPE, "Generate called but ENABLE_MOD is false")
		return nil, "Rivers mod disabled in config"
	end
	local map = current_map()
	if not map then
		return nil, "no current map (start or load a game first)"
	end
	local Water = Rivers.Water
	if not Water or type(Water.PlaceMarker) ~= "function" then
		return nil, "Rivers.Water module not loaded"
	end
	-- Only one sea at a time. Lakes are allowed to exist -- any the sea reaches
	-- get absorbed below (merge-on-contact), so we don't block on them.
	if Sea.Find() then
		DebugLog.Warn(SCOPE, "Generate blocked: a sea already exists")
		return nil, "a sea already exists (clear it first)"
	end

	local cfg = config()
	level_m = level_m or cfg.SEA_LEVEL_METERS or 10
	if level_m <= 0 then
		return nil, "sea level must be > 0"
	end

	local terrain_table = rawget(_G, "terrain")
	local sx, sy = terrain_table.GetMapSize(map)
	local full_bbox = box(0, 0, sx, sy)

	local min_pt, min_h_wu, samples, cell_wu2 = scan_heights(map)
	if not min_pt then
		return nil, "could not sample terrain heights"
	end

	local floor_wu = min_h_wu
	local water_z_wu = floor_wu + meters_to_wu(level_m)

	DebugLog.Info(SCOPE, "generating sea", {
		level_m = level_m,
		floor_wu = floor_wu,
		water_z_wu = water_z_wu,
		map_sx = sx,
		map_sy = sy,
	})

	-- Place the source at the lowest point; spill-avoidance OFF so it floods the
	-- whole basin, applied over the entire map.
	local obj, err = Water.PlaceMarker(map, min_pt, floor_wu, level_m, full_bbox, false, full_bbox)
	if not obj then
		DebugLog.Error(SCOPE, "Generate: water placement failed", { error = err })
		return nil, err
	end

	local flooded_wu2, volume_m3 = estimate_sea(samples, cell_wu2, water_z_wu)

	local id = Rivers.State:RegisterSegment({
		is_sea = true,
		water_obj = obj,
		bbox = full_bbox,
		floor_wu = floor_wu,
		marker_x = min_pt:x(),
		marker_y = min_pt:y(),
		spill_level_m = level_m,
		discharge_m3s = 0,
		drainage_m3s = 0,
		evaporation_m3s = 0,
		infiltration_m3s = 0,
		volume_m3 = volume_m3,
		actual_level_m = level_m,
		applied_level_m = level_m,
		flooded_tile_count = 0,
		flooded_area_wu2 = flooded_wu2,
		surface_area_wu2 = flooded_wu2,
	})
	-- Make the sea the current source so the height field (and its +/-) act on
	-- it. These are the same State fields r_tool.lua's set_current writes.
	Rivers.State.current_marker = obj
	Rivers.State.current_marker_segment = id

	-- Any lake the freshly-placed sea now covers becomes part of the sea.
	absorb_touching_lakes(map, water_z_wu, id)

	DebugLog.Info(SCOPE, "Generate ok", {
		id = id,
		level_m = level_m,
		flooded_area_wu2 = flooded_wu2,
		volume_m3 = volume_m3,
	})
	return id
end

-- ----------------------------------------------------------------------------
-- SetLevel (height field / +/- on a sea segment route here via r_budget)
-- ----------------------------------------------------------------------------

function Sea.SetLevel(seg_id, level_m)
	local seg = Rivers.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	if not seg.is_sea then
		return nil, "segment is not a sea"
	end
	local map = current_map()
	if not map then
		return nil, "no current map"
	end
	local Water = Rivers.Water
	if not Water or type(Water.SetMarkerLevel) ~= "function" then
		return nil, "Rivers.Water module not loaded"
	end
	if not seg.water_obj or not IsValid(seg.water_obj) then
		return nil, "sea marker is gone"
	end

	local v = tonumber(level_m) or 0
	if v < 0 then v = 0 end
	local water_z_wu = (seg.floor_wu or 0) + meters_to_wu(v)

	-- Re-apply over the whole map with spill-avoidance off.
	local terrain_table = rawget(_G, "terrain")
	local sx, sy = terrain_table.GetMapSize(map)
	local full_bbox = box(0, 0, sx, sy)
	Water.SetMarkerLevel(map, seg.water_obj, water_z_wu, false, full_bbox)

	seg.actual_level_m = v
	seg.applied_level_m = v

	-- Raising the sea can reach lakes it didn't before -- absorb them.
	absorb_touching_lakes(map, water_z_wu, seg_id)

	-- Refresh the area/volume estimate for the new level.
	local _pt, _min, samples, cell_wu2 = scan_heights(map)
	if samples then
		local flooded_wu2, volume_m3 = estimate_sea(samples, cell_wu2, water_z_wu)
		seg.flooded_area_wu2 = flooded_wu2
		seg.surface_area_wu2 = flooded_wu2
		seg.volume_m3 = volume_m3
	end

	DebugLog.Info(SCOPE, "SetLevel", { id = seg_id, level_m = v })
	return v
end

-- Convenience wrappers that operate on "the sea" (whichever segment is the sea)
-- so the UI's sea-level field doesn't need the segment id. Return nil if no sea.
function Sea.GetLevel()
	local _id, seg = Sea.Find()
	if not seg then return nil end
	return seg.actual_level_m or 0
end

function Sea.SetCurrentLevel(level_m)
	local id = Sea.Find()
	if not id then return nil, "no sea exists" end
	return Sea.SetLevel(id, level_m)
end

function Sea.AdjustLevel(delta_m)
	local id, seg = Sea.Find()
	if not id then return nil, "no sea exists" end
	return Sea.SetLevel(id, (seg.actual_level_m or 0) + (tonumber(delta_m) or 0))
end

Rivers.Sea = Sea
