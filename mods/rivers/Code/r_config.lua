-- Rivers configuration.
-- Edit these values, then reload the mod or restart the game.
--
-- All knobs live in the private `config` builder below. The typed Rivers.Config
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
-- DEFAULT RIVER SHAPE
-- ============================================================================
-- Used when Rivers.Create / Rivers.Demo is called without explicit overrides.
-- Distances are in world units (1 meter = guim = 100 wu). The defaults aim for
-- a "big" river: ~20 hex wide, deep enough that the engine reliably fills it.
--
-- DefaultWidthMeters     -- inner channel half-width where the carved height
--                           reaches its minimum (the flat bottom of the bowl).
-- DefaultBankMeters      -- outer ring beyond the inner width over which the
--                           carved height smooths back up to the existing
--                           terrain. Wider banks = gentler slopes.
-- DefaultDepthMeters     -- how far BELOW the lowest existing terrain height
--                           along the path the bowl floor sits.
-- DefaultWaterLevelMeters -- how far ABOVE the bowl floor the water marker is
--                           placed. Must be < DefaultDepthMeters or the engine
--                           will report a map-wide water spill and clamp the
--                           level down. ~70% of depth is a safe default.
-- DefaultStepMeters      -- spacing between consecutive carve circles along the
--                           path. Smaller = smoother but more SetHeightCircle
--                           calls. The default is half of DefaultWidthMeters.
config.DefaultWidthMeters = 30
config.DefaultBankMeters = 15
config.DefaultDepthMeters = 8
config.DefaultWaterLevelMeters = 5
config.DefaultStepMeters = 15

-- ============================================================================
-- DEMO PATH
-- ============================================================================
-- Rivers.Demo() builds a single curved river across the loaded map for quick
-- testing. The points below are fractions of the map width/height (0..100).
-- Three points produce a gentle S; add more for a longer or more winding river.
config.DemoPathPercents = {
	{ 10, 50 },
	{ 35, 35 },
	{ 60, 65 },
	{ 90, 50 },
}

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
-- DefaultRainPreset feeds Rivers.Rain.StartDisaster when called without an
-- argument (i.e. from the UI button). Must match an Id in the engine's
-- Presets.MapSettings.RainsDisaster table. Valid in vanilla:
--   "Normal_VeryLow", "Normal_Low", "Normal_High"
--   "Toxic_VeryLow", "Toxic_Low", "Toxic_High"
-- "Normal_Low" is the mildest beneficial-soil option and is a sensible default.
config.DefaultRainPreset = "Normal_Low"

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
--   volume += (inflow - outflow - evap*surface_area - infil*flooded_area) * dt
-- where dt is HydroTickIntervalMs. inflow (discharge) and outflow are both
-- player-controlled per-segment fields, each with its own +/- buttons stepping
-- by HydroDischargeStepM3S / HydroOutflowStepM3S. The level rises when
-- inflow exceeds outflow + passive losses, and recedes otherwise.
config.HydroTickIntervalMs = 1000           -- budget tick period (ms)
config.HydroDischargeStepM3S = 0.5          -- inflow + / - step (m^3/s)
config.HydroDischargeMaxM3S = 100           -- soft cap on the inflow input field
config.HydroInitialDischargeM3S = 0         -- inflow of a freshly created segment
config.HydroOutflowStepM3S = 0.5            -- outflow + / - step (m^3/s)
config.HydroOutflowMaxM3S = 100             -- soft cap on the outflow input field
config.HydroInitialOutflowM3S = 0           -- outflow of a freshly created segment
config.HydroLevelStepMeters = 0.5           -- height + / - step (m), bypasses the budget
config.HydroLevelMaxMeters = 50             -- soft cap on the height input field
config.HydroApplyStepMeters = 1.0           -- min level change (m) before the budget tick
                                            -- rebuilds the water grid (perf gate; bigger =
                                            -- less lag, coarser visual stepping)
config.HydroButtonRepeatStartMs = 300       -- delay before a held +/- button starts auto-firing
config.HydroButtonRepeatIntervalMs = 150    -- gap between subsequent fires while held
config.HydroEvaporationMPerSec = 0.00005    -- meters lost per second per m^2 of surface
config.HydroInfiltrationMPerSec = 0.00002   -- meters lost per second per m^2 of flooded area

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
-- SAFETY
-- ============================================================================
-- The carve operation iterates SetHeightCircle calls along the path. If a path
-- is malformed (zero length, off-map points) the mod aborts early instead of
-- looping forever. These caps bound runaway calls in case a future caller
-- passes unusual data.
config.MaxPathPoints = 64           -- refuse paths with more than N control points
config.MaxStepsPerSegment = 512     -- refuse path segments longer than this many carve steps

-- ============================================================================
-- DEBUG LOGGING
-- ============================================================================
-- DebugLogs gates all log output. Scoped flags (Debug<Scope>) can be set to
-- false to silence one scope while DebugLogs stays on. Scopes emitted by this
-- mod: "Init", "Lifecycle", "API", "Terrain", "Water", "Tool", "UI", "Rain",
--      "Depth", "Flood", "Budget".
config.DebugLogs = true
config.DebugInit = true
config.DebugLifecycle = true
config.DebugApi = true
config.DebugTerrain = true
config.DebugWater = true
config.DebugTool = true
config.DebugUi = true
config.DebugRain = true
config.DebugDepth = false
config.DebugFlood = true
config.DebugBudget = true

-- ============================================================================
-- Typed config view: Rivers.Config
-- ============================================================================
-- The private `config` builder above is the single source of values. This view
-- re-exposes the same values under stable UPPERCASE names plus an ENABLE_MOD
-- master flag, with booleans/numbers coerced, so every module reads a clean
-- typed config (Rivers.Config.*). Edit the settings above, not this view.

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	Rivers = {}
	rawset(_G, "Rivers", Rivers)
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
C.DEFAULT_BANK_METERS = as_number(config.DefaultBankMeters, 15)
C.DEFAULT_DEPTH_METERS = as_number(config.DefaultDepthMeters, 8)
C.DEFAULT_WATER_LEVEL_METERS = as_number(config.DefaultWaterLevelMeters, 5)
C.DEFAULT_STEP_METERS = as_number(config.DefaultStepMeters, 15)

C.DEMO_PATH_PERCENTS = config.DemoPathPercents

C.DEFAULT_RAIN_PRESET = type(config.DefaultRainPreset) == "string" and config.DefaultRainPreset or "Normal_Low"

C.WATER_TOOL_START_LEVEL_METERS = as_number(config.WaterToolStartLevelMeters, 5)
C.WATER_TOOL_STEP_METERS = as_number(config.WaterToolStepMeters, 1)
C.WATER_TOOL_SELECT_RADIUS_M = as_number(config.WaterToolSelectRadiusM, 25)

C.MAX_PATH_POINTS = as_number(config.MaxPathPoints, 64)
C.MAX_STEPS_PER_SEGMENT = as_number(config.MaxStepsPerSegment, 512)

C.DEPTH_WET_M = as_number(config.DepthWetMeters, 0.01)
C.DEPTH_SHALLOW_M = as_number(config.DepthShallowMeters, 0.20)
C.DEPTH_DEEP_M = as_number(config.DepthDeepMeters, 0.75)
C.DEPTH_SUBMERGED_M = as_number(config.DepthSubmergedMeters, 2.00)

C.HYDRO_TICK_INTERVAL_MS = as_number(config.HydroTickIntervalMs, 1000)
C.HYDRO_DISCHARGE_STEP_M3S = as_number(config.HydroDischargeStepM3S, 0.5)
C.HYDRO_DISCHARGE_MAX_M3S = as_number(config.HydroDischargeMaxM3S, 100)
C.HYDRO_INITIAL_DISCHARGE_M3S = as_number(config.HydroInitialDischargeM3S, 0)
C.HYDRO_OUTFLOW_STEP_M3S = as_number(config.HydroOutflowStepM3S, 0.5)
C.HYDRO_OUTFLOW_MAX_M3S = as_number(config.HydroOutflowMaxM3S, 100)
C.HYDRO_INITIAL_OUTFLOW_M3S = as_number(config.HydroInitialOutflowM3S, 0)
C.HYDRO_LEVEL_STEP_M = as_number(config.HydroLevelStepMeters, 0.5)
C.HYDRO_LEVEL_MAX_M = as_number(config.HydroLevelMaxMeters, 50)
C.HYDRO_APPLY_STEP_M = as_number(config.HydroApplyStepMeters, 1.0)
C.HYDRO_BUTTON_REPEAT_START_MS = as_number(config.HydroButtonRepeatStartMs, 300)
C.HYDRO_BUTTON_REPEAT_INTERVAL_MS = as_number(config.HydroButtonRepeatIntervalMs, 150)
C.HYDRO_EVAPORATION_M_PER_SEC = as_number(config.HydroEvaporationMPerSec, 0.00005)
C.HYDRO_INFILTRATION_M_PER_SEC = as_number(config.HydroInfiltrationMPerSec, 0.00002)

C.FLOOD_TILE_SIZE_M = as_number(config.FloodTileSizeMeters, 5)
C.FLOOD_MAX_TILES = as_number(config.FloodMaxTiles, 5000)
C.FLOOD_SCAN_MARGIN_M = as_number(config.FloodScanMarginMeters, 50)

C.DEBUG_LOGS = as_bool(config.DebugLogs)
C.DEBUG_INIT = as_bool(config.DebugInit)
C.DEBUG_LIFECYCLE = as_bool(config.DebugLifecycle)
C.DEBUG_API = as_bool(config.DebugApi)
C.DEBUG_TERRAIN = as_bool(config.DebugTerrain)
C.DEBUG_WATER = as_bool(config.DebugWater)
C.DEBUG_TOOL = as_bool(config.DebugTool)
C.DEBUG_UI = as_bool(config.DebugUi)
C.DEBUG_RAIN = as_bool(config.DebugRain)
C.DEBUG_DEPTH = as_bool(config.DebugDepth)
C.DEBUG_FLOOD = as_bool(config.DebugFlood)
C.DEBUG_BUDGET = as_bool(config.DebugBudget)

Rivers.Config = C
