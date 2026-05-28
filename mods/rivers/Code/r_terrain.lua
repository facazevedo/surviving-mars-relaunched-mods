-- Rivers -- terrain carving along a path.
--
-- Public API:
--   Rivers.Terrain.NormalizePath(path)              -> {point, ...} or nil, err
--   Rivers.Terrain.SampleLowestHeight(map, points)  -> int height_wu
--   Rivers.Terrain.CarveBowlAlongPath(map, points, params) -> bbox, floor_wu | nil, err
--
-- The carve uses terrain.SetHeightCircle with mode = const.hsMin: heights are
-- LOWERED to the target floor and nothing is raised, so a river crossing a
-- ridge cuts a notch instead of building a mound. The outer ring smooths back
-- up to existing terrain, which is what gives the channel its bowl shape.
--
-- Caveats (prototype):
--   * Terrain edits are NOT snapshotted/restored on disable. The water markers
--     are reversible (delete them, water drains) but the carved channel stays.
--     This mirrors how vanilla landscape buildings work (LandscapeLake bakes
--     terrain via prefabs) and is documented at the call sites.

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	return
end

local DebugLog = Rivers.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }

local Terrain = {}
local SCOPE = "Terrain"

-- ----------------------------------------------------------------------------
-- Unit helpers
-- ----------------------------------------------------------------------------

local function meters_to_wu(m)
	-- guim is the engine constant for "1 meter in world units" (== 100).
	return MulDivRound(m, guim, 1)
end

-- ----------------------------------------------------------------------------
-- Path normalization
-- ----------------------------------------------------------------------------

-- Accepts a list of points in either form:
--   { point(x, y), point(x, y), ... }     -- engine points
--   { {x, y}, {x, y}, ... }               -- plain tables
-- Returns a list of point() values or (nil, error_string).
function Terrain.NormalizePath(path)
	if type(path) ~= "table" then
		return nil, "path must be a table"
	end
	local cfg = Rivers.Config or {}
	local n = #path
	if n < 2 then
		return nil, "path must contain at least 2 points"
	end
	if cfg.MAX_PATH_POINTS and n > cfg.MAX_PATH_POINTS then
		return nil, "path exceeds MAX_PATH_POINTS (" .. tostring(n) .. " > " .. tostring(cfg.MAX_PATH_POINTS) .. ")"
	end
	local out = {}
	for i = 1, n do
		local p = path[i]
		if type(p) == "table" then
			local x, y = p[1], p[2]
			if type(x) ~= "number" or type(y) ~= "number" then
				return nil, "path[" .. i .. "] must be {x, y} numbers or a point"
			end
			out[i] = point(x, y)
		elseif IsPoint and IsPoint(p) then
			out[i] = p
		elseif type(p) == "userdata" then
			out[i] = p
		else
			return nil, "path[" .. i .. "] is not a point or {x, y}"
		end
	end
	return out
end

-- ----------------------------------------------------------------------------
-- Map bounds + sampling
-- ----------------------------------------------------------------------------

local function point_on_map(map, pt)
	local sx, sy = terrain.GetMapSize(map)
	local px, py = pt:xy()
	return px >= 0 and py >= 0 and px < sx and py < sy
end

-- Sample existing terrain along the path and return the minimum height seen.
-- This becomes the reference baseline against which depth is measured, so the
-- floor of the carved bowl is always at or below the lowest natural ground on
-- the path -- the river then "flows" along the natural depression.
function Terrain.SampleLowestHeight(map, points)
	local lowest
	for i = 1, #points do
		local pt = points[i]
		if point_on_map(map, pt) then
			local h = terrain.GetHeight(map, pt)
			if not lowest or h < lowest then
				lowest = h
			end
		end
	end
	return lowest
end

-- ----------------------------------------------------------------------------
-- Carving
-- ----------------------------------------------------------------------------

-- Walk a segment p1 -> p2 in steps of step_wu, yielding one carve center per
-- step. Returns the number of carve calls applied.
local function carve_segment(map, p1, p2, inner_r_wu, outer_r_wu, floor_wu, step_wu, max_steps)
	local dx, dy = (p2 - p1):xy()
	local dist = sqrt(dx * dx + dy * dy)
	if dist <= 0 then
		return 0
	end
	local steps = (dist + step_wu - 1) / step_wu
	steps = (steps < 1) and 1 or steps
	if steps > max_steps then
		DebugLog.Warn(SCOPE, "segment exceeds MAX_STEPS_PER_SEGMENT, clamping", {
			steps = steps,
			max_steps = max_steps,
			dist_wu = dist,
		})
		steps = max_steps
	end
	for i = 0, steps do
		local t_num = i
		local t_den = steps
		local x = p1:x() + MulDivRound(dx, t_num, t_den)
		local y = p1:y() + MulDivRound(dy, t_num, t_den)
		local center = point(x, y)
		if point_on_map(map, center) then
			-- hsMin -> only lower, never raise. The outer ring blends to existing terrain.
			terrain.SetHeightCircle(map, center, inner_r_wu, outer_r_wu, floor_wu, const.hsMin)
		end
	end
	return steps + 1
end

-- Carve a bowl-shaped channel along the path. Returns the affected bbox and the
-- floor height (in world units) that should be used for water-level placement.
--
-- params (all optional, fall back to Rivers.Config defaults):
--   width_m        -- inner half-width of the flat bottom (meters)
--   bank_m         -- outer smoothing ring beyond inner (meters)
--   depth_m        -- floor depth below the lowest natural height on the path
--   step_m         -- spacing between carve circles along the path
function Terrain.CarveBowlAlongPath(map, points, params)
	params = params or {}
	local cfg = Rivers.Config or {}
	local width_m = params.width_m or cfg.DEFAULT_WIDTH_METERS or 30
	local bank_m = params.bank_m or cfg.DEFAULT_BANK_METERS or 15
	local depth_m = params.depth_m or cfg.DEFAULT_DEPTH_METERS or 8
	local step_m = params.step_m or cfg.DEFAULT_STEP_METERS or 15

	if width_m <= 0 or depth_m <= 0 or step_m <= 0 then
		return nil, "width_m/depth_m/step_m must be > 0"
	end
	if bank_m < 0 then
		return nil, "bank_m must be >= 0"
	end

	local inner_r_wu = meters_to_wu(width_m)
	local outer_r_wu = meters_to_wu(width_m + bank_m)
	local step_wu = meters_to_wu(step_m)
	local depth_wu = meters_to_wu(depth_m)

	local baseline = Terrain.SampleLowestHeight(map, points)
	if not baseline then
		return nil, "no path point is on the loaded map"
	end
	local floor_wu = baseline - depth_wu

	DebugLog.Info(SCOPE, "carving bowl", {
		points = #points,
		width_m = width_m,
		bank_m = bank_m,
		depth_m = depth_m,
		step_m = step_m,
		baseline_wu = baseline,
		floor_wu = floor_wu,
	})

	local max_steps = cfg.MAX_STEPS_PER_SEGMENT or 512
	local total_steps = 0
	for i = 1, #points - 1 do
		total_steps = total_steps + carve_segment(map, points[i], points[i + 1], inner_r_wu, outer_r_wu, floor_wu, step_wu, max_steps)
	end

	-- Compute affected bbox: union of each carve center +/- outer_r_wu.
	local minx, miny, maxx, maxy
	for i = 1, #points do
		local x, y = points[i]:xy()
		local lx, ly = x - outer_r_wu, y - outer_r_wu
		local ux, uy = x + outer_r_wu, y + outer_r_wu
		if not minx or lx < minx then minx = lx end
		if not miny or ly < miny then miny = ly end
		if not maxx or ux > maxx then maxx = ux end
		if not maxy or uy > maxy then maxy = uy end
	end
	local bbox = box(minx, miny, maxx, maxy)

	DebugLog.Info(SCOPE, "carve done", {
		total_steps = total_steps,
		bbox = tostring(bbox),
	})

	return bbox, floor_wu
end

Rivers.Terrain = Terrain
