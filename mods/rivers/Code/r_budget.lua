-- Rivers -- per-source water budget + game-time ticker.
--
-- This module is what makes "+/- adjusts source discharge" work: the player
-- changes a source's discharge (m^3/s) and a periodic ticker accumulates the
-- corresponding volume, recomputes the connected flooded area via r_flood.lua,
-- derives an actual_level from volume + bowl geometry, and pushes that level
-- to the engine water marker. No more direct level control.
--
-- One ticker drives all segments. It's a CreateGameTimeThread so it pauses
-- with the game and survives save/load via the engine's standard thread
-- recreation. r_lifecycle.lua starts the ticker on Enable and on
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
--   Rivers.Budget.AdjustDischarge(seg_id, delta_m3s)  -> new_discharge | nil, err
--   Rivers.Budget.SetDischarge(seg_id, value_m3s)     -> new_discharge | nil, err
--   Rivers.Budget.Tick(map, dt_s)                     -- step every segment once
--   Rivers.Budget.StartTicker()                       -- spawn the game-time loop
--   Rivers.Budget.StopTicker()                        -- kill it
--   Rivers.Budget.Get(seg_id)                         -> snapshot table for console

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	return
end

local DebugLog = Rivers.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Budget"

local Budget = {}

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

function Budget.SetDischarge(seg_id, value_m3s)
	local seg = Rivers.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	local v = tonumber(value_m3s) or 0
	if v < 0 then v = 0 end
	seg.discharge_m3s = v
	if config().DEBUG_BUDGET == true then
		DebugLog.Info(SCOPE, "set discharge", { id = seg_id, value = v })
	end
	return v
end

function Budget.AdjustDischarge(seg_id, delta_m3s)
	local seg = Rivers.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	local prev = seg.discharge_m3s or 0
	return Budget.SetDischarge(seg_id, prev + (tonumber(delta_m3s) or 0))
end

function Budget.SetOutflow(seg_id, value_m3s)
	local seg = Rivers.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	local v = tonumber(value_m3s) or 0
	if v < 0 then v = 0 end
	seg.outflow_m3s = v
	if config().DEBUG_BUDGET == true then
		DebugLog.Info(SCOPE, "set outflow", { id = seg_id, value = v })
	end
	return v
end

function Budget.AdjustOutflow(seg_id, delta_m3s)
	local seg = Rivers.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	local prev = seg.outflow_m3s or 0
	return Budget.SetOutflow(seg_id, prev + (tonumber(delta_m3s) or 0))
end

function Budget.Get(seg_id)
	local seg = Rivers.State.segments[seg_id]
	if not seg then return nil end
	return {
		discharge_m3s = seg.discharge_m3s or 0,
		outflow_m3s = seg.outflow_m3s or 0,
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
	local seg = Rivers.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	local v = tonumber(level_m) or 0
	if v < 0 then v = 0 end

	local bowl_area_m2 = (seg.bowl_area_wu2 or 0) / (guim * guim)
	local surface_area_m2 = (seg.surface_area_wu2 or 0) / (guim * guim)
	local new_volume = volume_from_level(seg, v, bowl_area_m2, surface_area_m2)
	seg.volume_m3 = new_volume
	seg.actual_level_m = v

	local map = current_map()
	if Rivers.Flood and type(Rivers.Flood.RecomputeSegment) == "function" then
		Rivers.Flood.RecomputeSegment(map, seg)
	end
	local Water = Rivers.Water
	if Water and type(Water.SetMarkerLevel) == "function" and seg.water_obj then
		local new_water_z = (seg.floor_wu or 0) + meters_to_wu(v)
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
	local seg = Rivers.State.segments[seg_id]
	if not seg then
		return nil, "no such segment: " .. tostring(seg_id)
	end
	local prev = seg.actual_level_m or 0
	return Budget.SetLevel(seg_id, prev + (tonumber(delta_m) or 0))
end

-- ----------------------------------------------------------------------------
-- Tick
-- ----------------------------------------------------------------------------

-- Advance one segment by dt_s seconds. Updates volume, actual_level_m, and
-- pushes the new level to the engine water marker via Rivers.Water.SetMarkerLevel.
local function tick_segment(map, seg, dt_s, cfg)
	if not seg or not seg.water_obj or not IsValid(seg.water_obj) then
		return false
	end

	local volume = seg.volume_m3 or 0
	local discharge = seg.discharge_m3s or 0
	local bowl_area_wu2 = seg.bowl_area_wu2 or 0
	-- Convert wu^2 areas to m^2 once. guim is wu/m, so wu^2 -> m^2 divides by guim^2.
	local bowl_area_m2 = bowl_area_wu2 / (guim * guim)
	local surface_area_wu2 = seg.surface_area_wu2 or 0
	local surface_area_m2 = surface_area_wu2 / (guim * guim)
	local flooded_area_m2 = (seg.flooded_area_wu2 or 0) / (guim * guim)

	local evap_rate = cfg.HYDRO_EVAPORATION_M_PER_SEC or 0
	local infil_rate = cfg.HYDRO_INFILTRATION_M_PER_SEC or 0
	local outflow = seg.outflow_m3s or 0

	-- Inflow.
	local inflow_m3 = discharge * dt_s

	-- Losses. Outflow is the player-controlled drain and always applies (it's
	-- water leaving the system regardless of level). Evaporation acts on the
	-- visible water surface; infiltration on whatever area is wet (approximated
	-- by bowl_area when no spill has been computed yet).
	local effective_surface_m2 = surface_area_m2 > 0 and surface_area_m2 or bowl_area_m2
	local effective_flooded_m2 = flooded_area_m2 > 0 and flooded_area_m2 or bowl_area_m2
	local outflow_m3 = outflow * dt_s
	local evap_loss_m3 = evap_rate * effective_surface_m2 * dt_s
	local infil_loss_m3 = infil_rate * effective_flooded_m2 * dt_s

	local new_volume = volume + inflow_m3 - outflow_m3 - evap_loss_m3 - infil_loss_m3
	if new_volume < 0 then new_volume = 0 end

	local new_level_m = level_from_volume(seg, new_volume, bowl_area_m2, surface_area_m2)
	if new_level_m < 0 then new_level_m = 0 end

	seg.volume_m3 = new_volume
	seg.actual_level_m = new_level_m

	-- Re-run the connected flood-fill with the new level so next tick's loss
	-- calculation uses up-to-date areas. Skip if Flood module isn't loaded.
	if Rivers.Flood and type(Rivers.Flood.RecomputeSegment) == "function" then
		Rivers.Flood.RecomputeSegment(map, seg)
	end

	-- Push the level back to the engine water marker.
	local Water = Rivers.Water
	if Water and type(Water.SetMarkerLevel) == "function" then
		local new_water_z = (seg.floor_wu or 0) + meters_to_wu(new_level_m)
		Water.SetMarkerLevel(map, seg.water_obj, new_water_z)
	end

	if cfg.DEBUG_BUDGET == true then
		DebugLog.Info(SCOPE, "tick", {
			inflow_m3 = inflow_m3,
			outflow_m3 = outflow_m3,
			loss_m3 = evap_loss_m3 + infil_loss_m3,
			volume_m3 = new_volume,
			level_m = new_level_m,
			flooded_tiles = seg.flooded_tile_count or 0,
		})
	end
	return true
end

-- Public tick: step every segment once by dt_s seconds.
function Budget.Tick(map, dt_s)
	if not map then return end
	local cfg = config()
	for _id, seg in pairs(Rivers.State.segments) do
		tick_segment(map, seg, dt_s, cfg)
	end
	-- The status label + the live input fields need a Refresh to reflect the
	-- new volume/level/discharge values. Refresh is cheap and gated on
	-- is_window_alive, so calling it every tick is safe even with no panel.
	if Rivers.UI and type(Rivers.UI.Refresh) == "function" then
		Rivers.UI.Refresh()
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
	if Rivers.State.budget_thread and IsValidThread(Rivers.State.budget_thread) then
		return Rivers.State.budget_thread
	end
	local create = rawget(_G, "CreateGameTimeThread")
	if type(create) ~= "function" then
		DebugLog.Warn(SCOPE, "CreateGameTimeThread unavailable; ticker will not start")
		return nil
	end
	Rivers.State.budget_thread = create(ticker_loop)
	DebugLog.Info(SCOPE, "ticker started", {
		period_ms = (config().HYDRO_TICK_INTERVAL_MS or 1000),
	})
	return Rivers.State.budget_thread
end

function Budget.StopTicker()
	local thread = Rivers.State.budget_thread
	if not thread then return end
	if type(rawget(_G, "DeleteThread")) == "function" and IsValidThread(thread) then
		DeleteThread(thread)
	end
	Rivers.State.budget_thread = false
	DebugLog.Info(SCOPE, "ticker stopped")
end

Rivers.Budget = Budget
