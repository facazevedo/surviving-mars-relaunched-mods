-- MartianWaters -- per-source water budget + game-time ticker.
--
-- This module is what makes "+/- adjusts source discharge" work: the player
-- changes a source's discharge (m^3/s) and a periodic ticker accumulates the
-- corresponding volume, recomputes the connected flooded area via mw_flood.lua,
-- derives an actual_level from volume + bowl geometry, and pushes that level
-- to the engine water marker. No more direct level control.
--
-- One ticker drives all segments. It's a CreateGameTimeThread so it pauses
-- with the game and survives save/load via the engine's standard thread
-- recreation. mw_lifecycle.lua starts the ticker on Enable and on
-- OnMsg.NewMapLoaded, and kills it on Disable / DoneMap.
--
-- Volume-to-level model (intentionally cheap, NOT a real fluid solver):
--   * Below spill: level = volume / bowl_area
--   * Above spill: level = spill + (volume - bowl_volume_at_spill) /
--                          max(prev_surface_area, bowl_area)
-- prev_surface_area is whatever r_flood.RecomputeSegment wrote last tick. The
-- two values converge across a few ticks because each tick's flood-fill uses
-- the new level.
--
-- Public API:
--   MartianWaters.Budget.AdjustDischarge(seg_id, delta_m3s)  -> new_discharge | nil, err
--   MartianWaters.Budget.SetDischarge(seg_id, value_m3s)     -> new_discharge | nil, err
--   MartianWaters.Budget.Tick(map, dt_s)                     -- step every segment once
--   MartianWaters.Budget.StartTicker()                       -- spawn the game-time loop
--   MartianWaters.Budget.StopTicker()                        -- kill it
--   MartianWaters.Budget.Get(seg_id)                         -> snapshot table for console

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Budget"

local Budget = {}

local function config()
	return MartianWaters.Config or {}
end

local function current_map()
	return rawget(_G, "CurrentMap")
end

local function meters_to_wu(m)
	return MulDivRound(m, guim, 1)
end

-- ----------------------------------------------------------------------------
-- Volume <-> level conversion (declared up here so Budget.SetLevel and
-- tick_segment can both see them as upvalues; Lua resolves locals at function
-- creation time, so they MUST be lexically above the first reference)
-- ----------------------------------------------------------------------------

-- Inverse of "how much water is in the basin given a level?". bowl_area_m2 is
-- the segment's estimated bowl floor area; surface_area_m2 is the spilled-
-- water surface area from the previous tick (or 0 if no spill yet).
local function level_from_volume(seg, volume_m3, bowl_area_m2, surface_area_m2)
	local spill_m = seg.spill_level_m or 0
	if spill_m <= 0 then
		return 0
	end
	-- Volume needed to fill the bowl to the spill rim.
	local bowl_capacity_m3 = bowl_area_m2 * spill_m
	if volume_m3 <= 0 then
		return 0
	end
	if volume_m3 <= bowl_capacity_m3 then
		return volume_m3 / bowl_area_m2
	end
	-- Above-spill overflow uses the actual flooded surface (previous tick) so
	-- a wide flood doesn't keep raising the level once it spread out. Falls
	-- back to bowl_area if we haven't run the flood-fill yet.
	local area = surface_area_m2 > 0 and surface_area_m2 or bowl_area_m2
	local overflow_m3 = volume_m3 - bowl_capacity_m3
	return spill_m + overflow_m3 / area
end

-- Forward inverse of `level_from_volume`. Used by Budget.SetLevel so the player
-- can ask for an instantaneous flood-to-height: we work backwards to the
-- volume that would produce that level, then let the regular tick continue.
local function volume_from_level(seg, level_m, bowl_area_m2, surface_area_m2)
	if level_m <= 0 then
		return 0
	end
	local spill_m = seg.spill_level_m or 0
	if spill_m <= 0 then
		return 0
	end
	if level_m <= spill_m then
		return level_m * bowl_area_m2
	end
	local bowl_capacity_m3 = bowl_area_m2 * spill_m
	local area = surface_area_m2 > 0 and surface_area_m2 or bowl_area_m2
	return bowl_capacity_m3 + (level_m - spill_m) * area
end

-- ----------------------------------------------------------------------------
-- Discharge controls (the "+ / -" buttons go through these)
-- ----------------------------------------------------------------------------

-- The four budget rates (inflow/drainage/evaporation/infiltration) are all
-- per-segment m^3/s values clamped to >= 0. set_rate / adjust_rate factor out
-- the shared logic so each public Set*/Adjust* is a one-line wrapper naming the
-- segment field it owns.
local function set_rate(seg_id, field, value_m3s, label)
	local seg = MartianWaters.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	local v = tonumber(value_m3s) or 0
	if v < 0 then v = 0 end
	seg[field] = v
	if config().DEBUG_BUDGET == true then
		DebugLog.Info(SCOPE, "set " .. label, { id = seg_id, value = v })
	end
	return v
end

local function adjust_rate(seg_id, field, delta_m3s, set_fn)
	local seg = MartianWaters.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	return set_fn(seg_id, (seg[field] or 0) + (tonumber(delta_m3s) or 0))
end

function Budget.SetDischarge(seg_id, v) return set_rate(seg_id, "discharge_m3s", v, "discharge") end
function Budget.AdjustDischarge(seg_id, d) return adjust_rate(seg_id, "discharge_m3s", d, Budget.SetDischarge) end

function Budget.SetDrainage(seg_id, v) return set_rate(seg_id, "drainage_m3s", v, "drainage") end
function Budget.AdjustDrainage(seg_id, d) return adjust_rate(seg_id, "drainage_m3s", d, Budget.SetDrainage) end

function Budget.SetEvaporation(seg_id, v) return set_rate(seg_id, "evaporation_m3s", v, "evaporation") end
function Budget.AdjustEvaporation(seg_id, d) return adjust_rate(seg_id, "evaporation_m3s", d, Budget.SetEvaporation) end

function Budget.SetInfiltration(seg_id, v) return set_rate(seg_id, "infiltration_m3s", v, "infiltration") end
function Budget.AdjustInfiltration(seg_id, d) return adjust_rate(seg_id, "infiltration_m3s", d, Budget.SetInfiltration) end

function Budget.Get(seg_id)
	local seg = MartianWaters.State.segments[seg_id]
	if not seg then return nil end
	return {
		discharge_m3s = seg.discharge_m3s or 0,
		drainage_m3s = seg.drainage_m3s or 0,
		evaporation_m3s = seg.evaporation_m3s or 0,
		infiltration_m3s = seg.infiltration_m3s or 0,
		volume_m3 = seg.volume_m3 or 0,
		actual_level_m = seg.actual_level_m or 0,
		flooded_tile_count = seg.flooded_tile_count or 0,
		flooded_area_wu2 = seg.flooded_area_wu2 or 0,
	}
end

-- ----------------------------------------------------------------------------
-- Level controls (the "height" input field on the UI)
-- ----------------------------------------------------------------------------

-- Snap the water level to `level_m` immediately, bypassing the rate-limited
-- chase the budget normally drives. We do this by inverting the volume-to-level
-- function: pick the volume that would produce that level, then let the next
-- regular tick continue from there. Pushes the new level to the engine marker
-- and re-runs the flood-fill so the visual snaps in the same frame.
function Budget.SetLevel(seg_id, level_m)
	local seg = MartianWaters.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	-- A sea isn't volume-driven; its level is applied map-wide by mw_sea.lua.
	if seg.is_sea then
		if MartianWaters.Sea and type(MartianWaters.Sea.SetLevel) == "function" then
			return MartianWaters.Sea.SetLevel(seg_id, level_m)
		end
		return nil, "MartianWaters.Sea module not loaded"
	end
	local v = tonumber(level_m) or 0
	if v < 0 then v = 0 end

	local bowl_area_m2 = (seg.bowl_area_wu2 or 0) / (guim * guim)
	local surface_area_m2 = (seg.surface_area_wu2 or 0) / (guim * guim)
	local new_volume = volume_from_level(seg, v, bowl_area_m2, surface_area_m2)
	seg.volume_m3 = new_volume
	seg.actual_level_m = v

	local map = current_map()
	if MartianWaters.Flood and type(MartianWaters.Flood.RecomputeSegment) == "function" then
		MartianWaters.Flood.RecomputeSegment(map, seg)
	end
	local Water = MartianWaters.Water
	if Water and type(Water.SetMarkerLevel) == "function" and seg.water_obj then
		local new_water_z = (seg.floor_wu or 0) + meters_to_wu(v)
		-- A direct SetLevel snaps exactly to the requested level, and resets the
		-- tick gate's baseline so the next tick measures drift from here.
		seg.applied_level_m = v
		Water.SetMarkerLevel(map, seg.water_obj, new_water_z)
	end

	if config().DEBUG_BUDGET == true then
		DebugLog.Info(SCOPE, "set level", {
			id = seg_id,
			level_m = v,
			volume_m3 = new_volume,
		})
	end
	return v
end

function Budget.AdjustLevel(seg_id, delta_m)
	local seg = MartianWaters.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	local prev = seg.actual_level_m or 0
	return Budget.SetLevel(seg_id, prev + (tonumber(delta_m) or 0))
end

-- ----------------------------------------------------------------------------
-- Tick
-- ----------------------------------------------------------------------------

-- Is the segment's level far enough from what we last pushed to the engine to
-- justify a heavy rebuild? True on the first tick (no baseline) and when the
-- pool has just fully drained, so the water visibly appears/disappears.
local function segment_is_due(seg, cfg)
	local last = seg.applied_level_m
	if last == nil then
		return true
	end
	local lvl = seg.actual_level_m or 0
	if lvl <= 0 and last > 0 then
		return true
	end
	local apply_step = cfg.HYDRO_APPLY_STEP_M or 1.0
	local drift = lvl - last
	if drift < 0 then drift = -drift end
	return drift >= apply_step
end

-- CHEAP per-tick integration. Runs for EVERY segment every tick so the water
-- budget stays physically correct regardless of how the heavy rebuilds are
-- throttled. Updates volume + actual_level_m only; does no flood-fill and
-- touches no engine state. Returns true if the segment is now "due" for a
-- (heavy) visual rebuild.
local function update_segment_volume(seg, dt_s, cfg)
	if not seg or not seg.water_obj or not IsValid(seg.water_obj) then
		return false
	end
	-- Seas are static, engine-managed bodies (mw_sea.lua); the per-tick volume
	-- simulation + map-wide flood-fill would be both wrong and expensive for
	-- them, so they never tick. Their level only changes on explicit player
	-- action via MartianWaters.Sea.SetLevel.
	if seg.is_sea then
		return false
	end

	local volume = seg.volume_m3 or 0
	local bowl_area_wu2 = seg.bowl_area_wu2 or 0
	-- Convert wu^2 areas to m^2 once. guim is wu/m, so wu^2 -> m^2 divides by guim^2.
	local bowl_area_m2 = bowl_area_wu2 / (guim * guim)
	local surface_area_m2 = (seg.surface_area_wu2 or 0) / (guim * guim)

	-- All four budget terms are flat per-segment rates in m^3/s: inflow adds,
	-- the other three remove. (Earlier builds scaled evaporation/infiltration by
	-- water surface area; they are now direct player-controlled fields like
	-- inflow/drainage, so the math is a simple sum of rates.)
	local inflow_m3 = (seg.discharge_m3s or 0) * dt_s
	local drainage_m3 = (seg.drainage_m3s or 0) * dt_s
	local evaporation_m3 = (seg.evaporation_m3s or 0) * dt_s
	local infiltration_m3 = (seg.infiltration_m3s or 0) * dt_s

	local new_volume = volume + inflow_m3 - drainage_m3 - evaporation_m3 - infiltration_m3
	if new_volume < 0 then new_volume = 0 end

	local new_level_m = level_from_volume(seg, new_volume, bowl_area_m2, surface_area_m2)
	if new_level_m < 0 then new_level_m = 0 end

	seg.volume_m3 = new_volume
	seg.actual_level_m = new_level_m

	if cfg.DEBUG_BUDGET == true then
		DebugLog.Info(SCOPE, "tick", {
			inflow_m3 = inflow_m3,
			drainage_m3 = drainage_m3,
			loss_m3 = evaporation_m3 + infiltration_m3,
			volume_m3 = new_volume,
			level_m = new_level_m,
			flooded_tiles = seg.flooded_tile_count or 0,
		})
	end

	return segment_is_due(seg, cfg)
end

-- HEAVY visual rebuild. The flood-fill (a BFS over up to FLOOD_MAX_TILES tiles,
-- one terrain.GetHeight each) and the engine water-grid rebuild (SetMarkerLevel
-- -> UpdateGridAndVisuals + ApplyAllWaterObjects) are the costly part, so this
-- is rate-limited two ways: per segment by segment_is_due (the per-meter gate),
-- and globally by the per-tick cap in Budget.Tick. Snaps applied_level_m to the
-- current level so the gate measures the next drift from here.
local function apply_segment(map, seg, sea_z_wu)
	seg.applied_level_m = seg.actual_level_m or 0
	if MartianWaters.Flood and type(MartianWaters.Flood.RecomputeSegment) == "function" then
		-- Pass the sea surface so the flood-fill flags seg.reached_sea when this
		-- lake's water has spread down into sea-level terrain (lake -> sea merge).
		MartianWaters.Flood.RecomputeSegment(map, seg, sea_z_wu)
	end
	local Water = MartianWaters.Water
	if Water and type(Water.SetMarkerLevel) == "function" then
		local new_water_z = (seg.floor_wu or 0) + meters_to_wu(seg.actual_level_m or 0)
		Water.SetMarkerLevel(map, seg.water_obj, new_water_z)
	end
end

-- Public tick: step every segment once by dt_s seconds.
--
-- Two phases:
--   1. Integrate every segment's volume/level (cheap arithmetic). Any segment
--      that becomes "due" for a visual rebuild is enqueued once.
--   2. Process at most HYDRO_MAX_REBUILDS_PER_TICK due segments from the front
--      of the queue (FIFO round-robin). The overflow stays queued and is picked
--      up on following ticks, so frame cost is hard-bounded no matter how many
--      lakes are active. Deferred lakes keep integrating in phase 1 -- only
--      their visual refresh waits its turn.
function Budget.Tick(map, dt_s)
	if not map then return end
	local cfg = config()

	local queue = MartianWaters.State.rebuild_queue
	if type(queue) ~= "table" then
		queue = {}
		MartianWaters.State.rebuild_queue = queue
	end

	-- If a sea exists, compute its surface height once so the per-lake flood-fill
	-- can detect a lake growing into the sea (lake -> sea merge).
	local sea_z_wu
	if MartianWaters.Sea and type(MartianWaters.Sea.Find) == "function" then
		local _sea_id, sea_seg = MartianWaters.Sea.Find()
		if sea_seg then
			sea_z_wu = (sea_seg.floor_wu or 0) + meters_to_wu(sea_seg.actual_level_m or 0)
		end
	end

	-- Phase 1: cheap integration + enqueue newly-due segments (no duplicates).
	for id, seg in pairs(MartianWaters.State.segments) do
		if update_segment_volume(seg, dt_s, cfg) and not seg.rebuild_queued then
			seg.rebuild_queued = true
			queue[#queue + 1] = id
		end
	end

	-- Phase 2: spend the per-tick rebuild budget on the oldest due segments.
	local cap = cfg.HYDRO_MAX_REBUILDS_PER_TICK or 3
	if cap < 1 then cap = 1 end
	local processed = 0
	while processed < cap and #queue > 0 do
		local id = table.remove(queue, 1)
		local seg = MartianWaters.State.segments[id]
		if seg then
			seg.rebuild_queued = false
			-- Re-check: the segment may have been levelled (instant SetLevel) or
			-- drifted back since it was queued. Only spend budget if still due.
			if seg.water_obj and IsValid(seg.water_obj) and segment_is_due(seg, cfg) then
				apply_segment(map, seg, sea_z_wu)
				processed = processed + 1
				-- If this lake's flood reached sea-level terrain, it has grown
				-- into the sea -- merge it in.
				if sea_z_wu and not seg.is_sea and seg.reached_sea
					and MartianWaters.Sea and type(MartianWaters.Sea.Absorb) == "function" then
					MartianWaters.Sea.Absorb(id)
				end
			end
		end
		-- A stale/invalid/no-longer-due id is simply dropped without cost.
	end

	-- The status label + the live input fields need a Refresh to reflect the
	-- new volume/level/discharge values. Refresh is cheap and gated on
	-- is_window_alive, so calling it every tick is safe even with no panel.
	if MartianWaters.UI and type(MartianWaters.UI.Refresh) == "function" then
		MartianWaters.UI.Refresh()
	end
end

-- ----------------------------------------------------------------------------
-- Game-time ticker
-- ----------------------------------------------------------------------------

local function ticker_loop()
	local cfg = config()
	local period_ms = cfg.HYDRO_TICK_INTERVAL_MS or 1000
	if period_ms < 50 then period_ms = 50 end
	local dt_s = period_ms / 1000.0
	while true do
		local map = current_map()
		if map then
			Budget.Tick(map, dt_s)
		end
		-- Sleep is in milliseconds in this engine; it's a game-time sleep here
		-- because we ran on CreateGameTimeThread.
		Sleep(period_ms)
	end
end

function Budget.StartTicker()
	if MartianWaters.State.budget_thread and IsValidThread(MartianWaters.State.budget_thread) then
		return MartianWaters.State.budget_thread
	end
	local create = rawget(_G, "CreateGameTimeThread")
	if type(create) ~= "function" then
		DebugLog.Warn(SCOPE, "CreateGameTimeThread unavailable; ticker will not start")
		return nil
	end
	MartianWaters.State.budget_thread = create(ticker_loop)
	DebugLog.Info(SCOPE, "ticker started", {
		period_ms = (config().HYDRO_TICK_INTERVAL_MS or 1000),
	})
	return MartianWaters.State.budget_thread
end

function Budget.StopTicker()
	local thread = MartianWaters.State.budget_thread
	-- Drop the rebuild queue so ids from this map/session don't linger into the
	-- next one (they'd be skipped as stale, but clearing keeps it tidy).
	MartianWaters.State.rebuild_queue = {}
	if not thread then return end
	if type(rawget(_G, "DeleteThread")) == "function" and IsValidThread(thread) then
		DeleteThread(thread)
	end
	MartianWaters.State.budget_thread = false
	DebugLog.Info(SCOPE, "ticker stopped")
end

MartianWaters.Budget = Budget
