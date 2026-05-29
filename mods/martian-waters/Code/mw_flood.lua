-- MartianWaters -- connected flood-fill from each segment source.
--
-- A tile is "flooded" only if both:
--   (1) terrain_height at the tile center < the segment's actual_level, AND
--   (2) it is reachable from the segment source through other flooded tiles.
--
-- This is what makes the model terrain-aware instead of bbox-based: isolated
-- depressions elsewhere on the map at the same global level do NOT flood --
-- they're not connected to the source. The walk uses 4-neighbour BFS on a
-- coarse tile grid (FLOOD_TILE_SIZE_M meters per tile) bounded by the segment
-- bbox expanded by FLOOD_SCAN_MARGIN_M; FLOOD_MAX_TILES is a runaway guard.
--
-- Public API:
--   MartianWaters.Flood.RecomputeSegment(map, seg) -> tile_count, area_wu2
--   MartianWaters.Flood.Get(seg_id)                -> { tile_count, area_wu2 } | nil
--
-- The flood-fill writes flooded_tile_count, flooded_area_wu2, surface_area_wu2
-- into the segment record. Other modules read those; they do NOT keep their
-- own flood state. Phase 1 stores counts only; visualising the actual tile
-- positions is a Phase 1.5 (debug overlay) concern.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Flood"

local Flood = {}

local function config()
	return MartianWaters.Config or {}
end

local function meters_to_wu(m)
	return MulDivRound(m, guim, 1)
end

local function current_map()
	return rawget(_G, "CurrentMap")
end

-- ----------------------------------------------------------------------------
-- Tile key encoding
-- ----------------------------------------------------------------------------

-- Encode an (ix, iy) tile index as a single string key for set membership.
-- BFS uses a `visited` set of these keys; allocating a fresh string each step
-- is fine -- LuaJIT interns short literals and we cap the walk via FLOOD_MAX_TILES.
local function tile_key(ix, iy)
	return ix .. "," .. iy
end

-- ----------------------------------------------------------------------------
-- BFS
-- ----------------------------------------------------------------------------

-- Run the flood-fill for one segment. Mutates `seg.flooded_tile_count`,
-- `seg.flooded_area_wu2`, `seg.surface_area_wu2`. Returns the same counts.
--
-- sea_z_wu (optional): if given, the walk also flags seg.reached_sea = true when
-- any flooded tile's terrain sits at or below the sea surface. That means this
-- (lake) body has spread down into sea-level terrain -- i.e. it has grown into
-- the sea -- which mw_budget uses to merge the lake into the sea.
function Flood.RecomputeSegment(map, seg, sea_z_wu)
	seg.reached_sea = false
	if not map or type(seg) ~= "table" then
		return 0, 0
	end
	local terrain_table = rawget(_G, "terrain")
	if type(terrain_table) ~= "table" then
		return 0, 0
	end
	local get_h = terrain_table.GetHeight
	local get_size = terrain_table.GetMapSize
	if type(get_h) ~= "function" or type(get_size) ~= "function" then
		return 0, 0
	end
	local map_sx, map_sy = get_size(map)
	local cfg = config()
	local tile_wu = meters_to_wu(cfg.FLOOD_TILE_SIZE_M or 5)
	if tile_wu <= 0 then
		return 0, 0
	end
	local max_tiles = cfg.FLOOD_MAX_TILES or 5000
	local margin_wu = meters_to_wu(cfg.FLOOD_SCAN_MARGIN_M or 50)

	local floor_wu = seg.floor_wu or 0
	local actual_level_m = seg.actual_level_m or 0
	-- actual_level_wu is the absolute height at which water sits in the world.
	local actual_level_wu = floor_wu + meters_to_wu(actual_level_m)

	-- Scan window: segment bbox expanded by margin, clamped to the map.
	local bbox = seg.bbox
	local minx, miny, maxx, maxy
	if bbox and type(bbox) ~= "number" then
		local bx0, by0, bx1, by1 = bbox:xyxy()
		minx, miny, maxx, maxy = bx0 - margin_wu, by0 - margin_wu, bx1 + margin_wu, by1 + margin_wu
	else
		-- No bbox -- fall back to a window centred on the source.
		local cx, cy = seg.marker_x or 0, seg.marker_y or 0
		minx, miny, maxx, maxy = cx - margin_wu, cy - margin_wu, cx + margin_wu, cy + margin_wu
	end
	if minx < 0 then minx = 0 end
	if miny < 0 then miny = 0 end
	if maxx >= map_sx then maxx = map_sx - 1 end
	if maxy >= map_sy then maxy = map_sy - 1 end

	-- Source tile index.
	local src_x, src_y = seg.marker_x or 0, seg.marker_y or 0
	local src_ix = src_x / tile_wu
	local src_iy = src_y / tile_wu

	-- Index bounds for the scan window.
	local lo_ix, lo_iy = minx / tile_wu, miny / tile_wu
	local hi_ix, hi_iy = maxx / tile_wu, maxy / tile_wu

	local function in_window(ix, iy)
		return ix >= lo_ix and iy >= lo_iy and ix <= hi_ix and iy <= hi_iy
	end

	local reached_sea = false

	-- Tile height at the tile centre, or nil if off-grid. Side effect: marks
	-- reached_sea when a sampled tile sits at/below the sea surface.
	local function tile_height(ix, iy)
		local cx = ix * tile_wu + tile_wu / 2
		local cy = iy * tile_wu + tile_wu / 2
		local h = get_h(map, point(cx, cy))
		if type(h) ~= "number" then return nil end
		if sea_z_wu and h <= sea_z_wu then
			reached_sea = true
		end
		return h
	end

	local function terrain_below_level(ix, iy)
		local h = tile_height(ix, iy)
		return h ~= nil and h < actual_level_wu
	end

	-- Reject the source itself if its tile centre is above the level -- the
	-- player asked for a flood that doesn't exist yet, so just report zero.
	if not in_window(src_ix, src_iy) or not terrain_below_level(src_ix, src_iy) then
		seg.flooded_tile_count = 0
		seg.flooded_area_wu2 = 0
		seg.surface_area_wu2 = 0
		return 0, 0
	end

	local visited = { [tile_key(src_ix, src_iy)] = true }
	local queue = { { src_ix, src_iy } }
	local count = 1
	-- Iterative BFS; bail if we hit the safety cap.
	local head = 1
	while head <= #queue do
		if count >= max_tiles then
			DebugLog.Warn(SCOPE, "hit FLOOD_MAX_TILES, truncating", { cap = max_tiles })
			break
		end
		local cur = queue[head]
		head = head + 1
		local cix, ciy = cur[1], cur[2]
		-- 4-neighbours. 8-neighbours would round the flood off more naturally
		-- but doubles the visit count; 4 is plenty for Phase 1.
		local steps = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
		for i = 1, 4 do
			local nix = cix + steps[i][1]
			local niy = ciy + steps[i][2]
			local key = tile_key(nix, niy)
			if not visited[key] and in_window(nix, niy) and terrain_below_level(nix, niy) then
				visited[key] = true
				queue[#queue + 1] = { nix, niy }
				count = count + 1
				if count >= max_tiles then
					break
				end
			end
		end
	end

	local area_wu2 = count * tile_wu * tile_wu
	seg.flooded_tile_count = count
	seg.flooded_area_wu2 = area_wu2
	seg.surface_area_wu2 = area_wu2
	seg.reached_sea = reached_sea

	if cfg.DEBUG_FLOOD == true then
		DebugLog.Info(SCOPE, "recompute", {
			tiles = count,
			area_wu2 = area_wu2,
			actual_level_m = actual_level_m,
		})
	end
	return count, area_wu2
end

-- Console convenience: snapshot for a segment id.
function Flood.Get(seg_id)
	local seg = MartianWaters.State.segments[seg_id]
	if not seg then return nil end
	return {
		tile_count = seg.flooded_tile_count or 0,
		area_wu2 = seg.flooded_area_wu2 or 0,
	}
end

MartianWaters.Flood = Flood
