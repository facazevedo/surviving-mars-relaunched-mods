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
-- DEBUG_LOGS gates all log output. Scoped flags (DEBUG_<SCOPE>) can be set to
-- false to silence a specific scope while DEBUG_LOGS stays on. Scopes used in
-- this mod: "Init", "Lifecycle", "API", "Terrain", "Water".
config.DebugLogs = true
config.DebugTerrain = true
config.DebugWater = true
config.DebugTool = true
config.DebugUi = true

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

C.WATER_TOOL_START_LEVEL_METERS = as_number(config.WaterToolStartLevelMeters, 5)
C.WATER_TOOL_STEP_METERS = as_number(config.WaterToolStepMeters, 1)
C.WATER_TOOL_SELECT_RADIUS_M = as_number(config.WaterToolSelectRadiusM, 25)

C.MAX_PATH_POINTS = as_number(config.MaxPathPoints, 64)
C.MAX_STEPS_PER_SEGMENT = as_number(config.MaxStepsPerSegment, 512)

C.DEBUG_LOGS = as_bool(config.DebugLogs)
C.DEBUG_TERRAIN = as_bool(config.DebugTerrain)
C.DEBUG_WATER = as_bool(config.DebugWater)
C.DEBUG_TOOL = as_bool(config.DebugTool)
C.DEBUG_UI = as_bool(config.DebugUi)

Rivers.Config = C
