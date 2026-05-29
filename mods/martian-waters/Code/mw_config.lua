-- MartianWaters configuration.
-- Edit these values, then reload the mod or restart the game.
--
-- All knobs live in the private `config` builder below. The typed MartianWaters.Config
-- view at the bottom of the file is what the rest of the mod reads. ENABLE_MOD
-- is the master switch; every feature must respect it.

local config = {}

-- ============================================================================
-- MASTER SWITCH
-- ============================================================================
-- false -> mod stays passive even if it loads: no OnMsg hooks register, no
--          terrain is touched, ClearAll still works so a save can be cleaned up.
config.EnableMod = true

-- ============================================================================
-- WATER BODY FOOTPRINT
-- ============================================================================
-- DefaultWidthMeters is the half-size of the bounding box used when a click-placed
-- water marker is dropped (the engine expands it as needed when neighbouring water
-- objects merge). Distances are in world units via guim.
config.DefaultWidthMeters = 30

-- ============================================================================
-- WATER TOOL (click-to-fill mode)
-- ============================================================================
-- The right-side "Water Tool" panel lets the player click a hole to drop a
-- water marker, then dial the surface up/down with + / - buttons. These knobs
-- control the initial level and the size of each + / - step.
--
-- WaterToolStartLevelMeters -- water height above the ground at the click point
--                              used when a NEW marker is placed (i.e. how full
--                              the hole is on first click).
-- WaterToolStepMeters       -- meters added/removed per + / - button press,
--                              applied to the most recently placed marker.
-- WaterToolSelectRadiusM    -- if a click lands within this radius of an
--                              existing marker, that marker becomes the
--                              "current" one (no new marker is created) so the
--                              + / - buttons keep modifying the same body of
--                              water. Use 0 to always place a new marker.
config.WaterToolStartLevelMeters = 5
config.WaterToolStepMeters = 1
config.WaterToolSelectRadiusM = 25

-- ============================================================================
-- RAIN (UI buttons)
-- ============================================================================
-- DefaultRainPreset feeds MartianWaters.Rain.StartDisaster when called without an
-- argument (i.e. from the UI button). Must match an Id in the engine's
-- Presets.MapSettings.RainsDisaster table. Valid in vanilla:
--   "Normal_VeryLow", "Normal_Low", "Normal_High"
--   "Toxic_VeryLow", "Toxic_Low", "Toxic_High"
-- "Normal_Low" is the mildest beneficial-soil option and is a sensible default.
config.DefaultRainPreset = "Normal_Low"

-- ============================================================================
-- CLOUDS (UI controls)
-- ============================================================================
-- The CLOUDS section drives the engine's cloud-SHADOW system (the editor's
-- "Show cloud shadows" toggle, plus the CloudsCoverage / CloudsSpeed scene
-- params). Coverage is a percentage (0..100, raw 0..1000); speed is in m/s
-- (engine raw range 0..50*guim, scale 1000 -> ~0..5 m/s).
config.CloudCoverageStepPct = 10   -- coverage + / - step (%)
config.CloudCoverageMaxPct = 100   -- soft cap on the coverage input field
config.CloudSpeedStepM = 1         -- speed + / - step (m/s)
config.CloudSpeedMaxM = 50         -- soft cap on the speed input field. Engine range
                                   -- is 0..(50*guim) at scale 1000 => 0..50 m/s
                                   -- (guim == 1000). Shipped lightmodels run ~7 m/s,
                                   -- so a cap of 5 clamped real values DOWN -- hence
                                   -- "+ did nothing". 50 covers the full engine range.

-- ============================================================================
-- HYDROLOGY -- depth classification
-- ============================================================================
-- Depth (meters of water above terrain at the sampled point) is bucketed into
-- five classes by these thresholds. The classes drive every Phase 3 gameplay
-- effect (movement, placement, damage). Thresholds are inclusive on the lower
-- bound, e.g. depth >= 0.20 is "shallow".
--   dry        depth < DepthWet
--   wet        DepthWet   <= depth < DepthShallow
--   shallow    DepthShallow <= depth < DepthDeep
--   deep       DepthDeep   <= depth < DepthSubmerged
--   submerged  depth >= DepthSubmerged
config.DepthWetMeters = 0.01
config.DepthShallowMeters = 0.20
config.DepthDeepMeters = 0.75
config.DepthSubmergedMeters = 2.00

-- ============================================================================
-- HYDROLOGY -- per-source water budget
-- ============================================================================
-- Each river segment runs a discrete water budget instead of a fixed level:
--   volume += (inflow - drainage - evaporation - infiltration) * dt
-- where dt is HydroTickIntervalMs. All four terms are player-controlled
-- per-segment fields in m^3/s, each with its own +/- buttons. The level rises
-- when inflow exceeds drainage + evaporation + infiltration, and recedes
-- otherwise. inflow/drainage default to 0; evaporation/infiltration start at a
-- small nonzero default so a pool slowly recedes on its own unless fed.
config.HydroTickIntervalMs = 1000           -- budget tick period (ms)
config.HydroDischargeStepM3S = 0.5          -- inflow + / - step (m^3/s)
config.HydroDischargeMaxM3S = 100           -- soft cap on the inflow input field
config.HydroInitialDischargeM3S = 0         -- inflow of a freshly created segment
config.HydroDrainageStepM3S = 0.5           -- drainage + / - step (m^3/s)
config.HydroDrainageMaxM3S = 100            -- soft cap on the drainage input field
config.HydroInitialDrainageM3S = 0          -- drainage of a freshly created segment
config.HydroEvaporationStepM3S = 0.5        -- evaporation + / - step (m^3/s)
config.HydroEvaporationMaxM3S = 100         -- soft cap on the evaporation input field
config.HydroInitialEvaporationM3S = 1.0     -- default evaporation level (m^3/s) -- a
                                            -- new pool slowly recedes if left unfed;
                                            -- raise/lower it live with the +/- buttons
config.HydroInfiltrationStepM3S = 0.5       -- infiltration + / - step (m^3/s)
config.HydroInfiltrationMaxM3S = 100        -- soft cap on the infiltration input field
config.HydroInitialInfiltrationM3S = 0.5    -- default infiltration level (m^3/s),
                                            -- the slower ground-soak loss; changeable too
config.HydroLevelStepMeters = 0.5           -- height + / - step (m), bypasses the budget
config.HydroLevelMaxMeters = 50             -- soft cap on the height input field
config.HydroApplyStepMeters = 1.0           -- min level change (m) before the budget tick
                                            -- rebuilds the water grid (perf gate; bigger =
                                            -- less lag, coarser visual stepping)
config.HydroMaxRebuildsPerTick = 3          -- max heavy water-grid rebuilds per tick across
                                            -- ALL lakes; overflow defers to later ticks
                                            -- (round-robin). Hard-bounds frame cost when many
                                            -- lakes are active at once.
config.HydroButtonRepeatStartMs = 300       -- delay before a held +/- button starts auto-firing
config.HydroButtonRepeatIntervalMs = 150    -- gap between subsequent fires while held

-- ============================================================================
-- HYDROLOGY -- connected flood-fill
-- ============================================================================
-- The flood-fill walks a coarse tile grid out from the source point, accepting
-- tiles whose terrain height is below the segment's current actual_level and
-- which are reachable through other accepted tiles. FloodTileSizeMeters trades
-- accuracy for cost; FloodMaxTiles is a runaway-guard cap.
config.FloodTileSizeMeters = 5              -- grid resolution
config.FloodMaxTiles = 5000                 -- safety cap per segment per recompute
config.FloodScanMarginMeters = 50           -- padding around segment bbox for the scan window

-- ============================================================================
-- SEA GENERATION
-- ============================================================================
-- Setting a positive Sea Level floods every tile of the map that sits below a
-- global sea level, measured in meters ABOVE the map's lowest terrain point. The flood is
-- done by the engine's own water grid (one TerrainWaterObject at the lowest
-- point, applied map-wide with spill-avoidance off), not the per-segment
-- flood-fill -- so it's cheap and the sea is a single static body.
--   SeaLevelMeters  -- default water depth above the map minimum for a new sea.
--   SeaScanSamples  -- coarse NxN grid used to find the lowest point and to
--                      estimate the sea's flooded area + volume. Higher = more
--                      accurate readouts, more GetHeight calls at generation.
config.SeaLevelMeters = 10
config.SeaScanSamples = 64
config.SeaLevelStepMeters = 1     -- sea-level field + / - step (m)
config.SeaLevelMaxMeters = 200    -- soft cap on the sea-level input field

-- ============================================================================
-- DEBUG LOGGING
-- ============================================================================
-- DebugLogs gates all log output. Scoped flags (Debug<Scope>) can be set to
-- false to silence one scope while DebugLogs stays on. Scopes emitted by this
-- mod: "Init", "Lifecycle", "API", "Terrain", "Water", "Tool", "UI", "Rain",
--      "Clouds", "Depth", "Flood", "Budget".
config.DebugLogs = true
config.DebugInit = true
config.DebugLifecycle = true
config.DebugApi = true
config.DebugTerrain = true
config.DebugWater = true
config.DebugTool = true
config.DebugUi = true
config.DebugRain = true
config.DebugClouds = true
config.DebugDepth = false
config.DebugFlood = true
config.DebugBudget = true

-- ============================================================================
-- Typed config view: MartianWaters.Config
-- ============================================================================
-- The private `config` builder above is the single source of values. This view
-- re-exposes the same values under stable UPPERCASE names plus an ENABLE_MOD
-- master flag, with booleans/numbers coerced, so every module reads a clean
-- typed config (MartianWaters.Config.*). Edit the settings above, not this view.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	MartianWaters = {}
	rawset(_G, "MartianWaters", MartianWaters)
end

local function as_bool(value)
	return value == true
end

local function as_number(value, default)
	if type(value) == "number" then
		return value
	end
	return default
end

local C = {}

C.ENABLE_MOD = as_bool(config.EnableMod)

C.DEFAULT_WIDTH_METERS = as_number(config.DefaultWidthMeters, 30)

C.DEFAULT_RAIN_PRESET = type(config.DefaultRainPreset) == "string" and config.DefaultRainPreset or "Normal_Low"

C.CLOUD_COVERAGE_STEP_PCT = as_number(config.CloudCoverageStepPct, 10)
C.CLOUD_COVERAGE_MAX_PCT = as_number(config.CloudCoverageMaxPct, 100)
C.CLOUD_SPEED_STEP_M = as_number(config.CloudSpeedStepM, 1)
C.CLOUD_SPEED_MAX_M = as_number(config.CloudSpeedMaxM, 50)

C.WATER_TOOL_START_LEVEL_METERS = as_number(config.WaterToolStartLevelMeters, 5)
C.WATER_TOOL_STEP_METERS = as_number(config.WaterToolStepMeters, 1)
C.WATER_TOOL_SELECT_RADIUS_M = as_number(config.WaterToolSelectRadiusM, 25)

C.DEPTH_WET_M = as_number(config.DepthWetMeters, 0.01)
C.DEPTH_SHALLOW_M = as_number(config.DepthShallowMeters, 0.20)
C.DEPTH_DEEP_M = as_number(config.DepthDeepMeters, 0.75)
C.DEPTH_SUBMERGED_M = as_number(config.DepthSubmergedMeters, 2.00)

C.HYDRO_TICK_INTERVAL_MS = as_number(config.HydroTickIntervalMs, 1000)
C.HYDRO_DISCHARGE_STEP_M3S = as_number(config.HydroDischargeStepM3S, 0.5)
C.HYDRO_DISCHARGE_MAX_M3S = as_number(config.HydroDischargeMaxM3S, 100)
C.HYDRO_INITIAL_DISCHARGE_M3S = as_number(config.HydroInitialDischargeM3S, 0)
C.HYDRO_DRAINAGE_STEP_M3S = as_number(config.HydroDrainageStepM3S, 0.5)
C.HYDRO_DRAINAGE_MAX_M3S = as_number(config.HydroDrainageMaxM3S, 100)
C.HYDRO_INITIAL_DRAINAGE_M3S = as_number(config.HydroInitialDrainageM3S, 0)
C.HYDRO_EVAPORATION_STEP_M3S = as_number(config.HydroEvaporationStepM3S, 0.5)
C.HYDRO_EVAPORATION_MAX_M3S = as_number(config.HydroEvaporationMaxM3S, 100)
C.HYDRO_INITIAL_EVAPORATION_M3S = as_number(config.HydroInitialEvaporationM3S, 1.0)
C.HYDRO_INFILTRATION_STEP_M3S = as_number(config.HydroInfiltrationStepM3S, 0.5)
C.HYDRO_INFILTRATION_MAX_M3S = as_number(config.HydroInfiltrationMaxM3S, 100)
C.HYDRO_INITIAL_INFILTRATION_M3S = as_number(config.HydroInitialInfiltrationM3S, 0.5)
C.HYDRO_LEVEL_STEP_M = as_number(config.HydroLevelStepMeters, 0.5)
C.HYDRO_LEVEL_MAX_M = as_number(config.HydroLevelMaxMeters, 50)
C.HYDRO_APPLY_STEP_M = as_number(config.HydroApplyStepMeters, 1.0)
C.HYDRO_MAX_REBUILDS_PER_TICK = as_number(config.HydroMaxRebuildsPerTick, 3)
C.HYDRO_BUTTON_REPEAT_START_MS = as_number(config.HydroButtonRepeatStartMs, 300)
C.HYDRO_BUTTON_REPEAT_INTERVAL_MS = as_number(config.HydroButtonRepeatIntervalMs, 150)

C.FLOOD_TILE_SIZE_M = as_number(config.FloodTileSizeMeters, 5)
C.FLOOD_MAX_TILES = as_number(config.FloodMaxTiles, 5000)
C.FLOOD_SCAN_MARGIN_M = as_number(config.FloodScanMarginMeters, 50)

C.SEA_LEVEL_METERS = as_number(config.SeaLevelMeters, 10)
C.SEA_SCAN_SAMPLES = as_number(config.SeaScanSamples, 64)
C.SEA_LEVEL_STEP_M = as_number(config.SeaLevelStepMeters, 1)
C.SEA_LEVEL_MAX_M = as_number(config.SeaLevelMaxMeters, 200)

C.DEBUG_LOGS = as_bool(config.DebugLogs)
C.DEBUG_INIT = as_bool(config.DebugInit)
C.DEBUG_LIFECYCLE = as_bool(config.DebugLifecycle)
C.DEBUG_API = as_bool(config.DebugApi)
C.DEBUG_TERRAIN = as_bool(config.DebugTerrain)
C.DEBUG_WATER = as_bool(config.DebugWater)
C.DEBUG_TOOL = as_bool(config.DebugTool)
C.DEBUG_UI = as_bool(config.DebugUi)
C.DEBUG_RAIN = as_bool(config.DebugRain)
C.DEBUG_CLOUDS = as_bool(config.DebugClouds)
C.DEBUG_DEPTH = as_bool(config.DebugDepth)
C.DEBUG_FLOOD = as_bool(config.DebugFlood)
C.DEBUG_BUDGET = as_bool(config.DebugBudget)

MartianWaters.Config = C
