-- MartianWaters -- water-depth sampling + classification.
--
-- Phase 1 hydrology primitive. Every gameplay effect added in Phase 3 will
-- decide "is this object affected by water?" by calling Depth.SampleAt and
-- looking at the returned class, NOT by checking river bbox membership.
--
-- Public API:
--   MartianWaters.Depth.Classify(depth_m)         -> "dry"|"wet"|"shallow"|"deep"|"submerged"
--   MartianWaters.Depth.SampleAt(map, pt_or_xy)   -> depth_m, class, terrain_h_wu, water_h_wu
--   MartianWaters.Depth.At(x, y)                  -> class    (console convenience)
--
-- Depth is computed from the engine's own grids:
--   depth_wu = terrain.GetWaterHeight(map, pt) - terrain.GetHeight(map, pt)
-- and converted to meters via the engine `guim` constant. terrain.GetWaterHeight
-- returns the height of the water surface at the queried column or terrain
-- height if the column is dry, so a non-positive depth means "dry".

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Depth"

local Depth = {}

local function config()
	return MartianWaters.Config or {}
end

local function current_map()
	return rawget(_G, "CurrentMap")
end

-- ----------------------------------------------------------------------------
-- Unit conversion
-- ----------------------------------------------------------------------------

local function wu_to_meters(wu)
	-- guim is the engine constant for "1 meter in world units" (== 100). Use
	-- MulDivRound for integer math; depth is then expressed as meters with two
	-- decimals of precision after the division.
	return MulDivRound(wu, 1, guim)
end

-- ----------------------------------------------------------------------------
-- Classification
-- ----------------------------------------------------------------------------

-- depth_m is a number (meters). Returns the class name.
function Depth.Classify(depth_m)
	if type(depth_m) ~= "number" or depth_m <= 0 then
		return "dry"
	end
	local cfg = config()
	local wet = cfg.DEPTH_WET_M or 0.01
	local shallow = cfg.DEPTH_SHALLOW_M or 0.20
	local deep = cfg.DEPTH_DEEP_M or 0.75
	local submerged = cfg.DEPTH_SUBMERGED_M or 2.00
	if depth_m < wet then return "dry" end
	if depth_m < shallow then return "wet" end
	if depth_m < deep then return "shallow" end
	if depth_m < submerged then return "deep" end
	return "submerged"
end

-- ----------------------------------------------------------------------------
-- Sampling
-- ----------------------------------------------------------------------------

local function resolve_point(pt_or_xy)
	if type(pt_or_xy) == "table" then
		local x, y = pt_or_xy[1], pt_or_xy[2]
		if type(x) == "number" and type(y) == "number" then
			return point(x, y), x, y
		end
		return nil, nil, nil
	end
	if IsPoint and IsPoint(pt_or_xy) then
		local px, py = pt_or_xy:xy()
		return pt_or_xy, px, py
	end
	if type(pt_or_xy) == "userdata" then
		-- Assume it's an engine point; xy() will fail if not, caller's problem.
		local px, py = pt_or_xy:xy()
		return pt_or_xy, px, py
	end
	return nil, nil, nil
end

-- Sample the depth (meters) and class at the given map position.
-- Returns: depth_m, class, terrain_h_wu, water_h_wu.
-- On error returns (nil, "dry") so callers reading depth_m can short-circuit.
function Depth.SampleAt(map, pt_or_xy)
	if not map then
		return nil, "dry"
	end
	local terrain_table = rawget(_G, "terrain")
	if type(terrain_table) ~= "table" then
		return nil, "dry"
	end
	local get_h = terrain_table.GetHeight
	local get_wh = terrain_table.GetWaterHeight
	if type(get_h) ~= "function" or type(get_wh) ~= "function" then
		return nil, "dry"
	end
	local pt = resolve_point(pt_or_xy)
	if not pt then
		return nil, "dry"
	end
	local terrain_h = get_h(map, pt)
	local water_h = get_wh(map, pt)
	if type(terrain_h) ~= "number" or type(water_h) ~= "number" then
		return nil, "dry", terrain_h, water_h
	end
	local depth_wu = water_h - terrain_h
	if depth_wu <= 0 then
		return 0, "dry", terrain_h, water_h
	end
	local depth_m = wu_to_meters(depth_wu)
	return depth_m, Depth.Classify(depth_m), terrain_h, water_h
end

-- Console convenience. Resolves the current map, samples, returns just the class.
function Depth.At(x, y)
	local map = current_map()
	if not map then
		DebugLog.Warn(SCOPE, "At: no current map")
		return "dry"
	end
	local _, class = Depth.SampleAt(map, { x, y })
	return class
end

MartianWaters.Depth = Depth
