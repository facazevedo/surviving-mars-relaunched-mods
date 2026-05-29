-- MartianWaters -- cloud controls.
--
-- Surviving Mars Relaunched ships two animated cloud systems (verified against
-- the game install, read-only reference):
--   * Cloud SHADOWS  -- a shadow layer projected on the terrain, a Lightmodel
--                       "clouds" feature driven by scene params CloudsCoverage,
--                       CloudsSpeed, CloudsDir, CloudsWindStrength, CloudsOsci*
--                       (CommonLua/Classes/Lightmodel.lua:440-463). Rendering is
--                       gated by the hardware flag hr.EnableCloudsShadow, which
--                       the in-game editor toggles directly
--                       (CommonLua/Editor/XEditor/XEditorSettings.lua:181).
--   * Placed cloud OBJECTS -- 3D "CloudPreset" props rotated each second by
--                       UpdateClouds (CommonLua/Classes/OutsiderObjects.lua:223).
--                       These are map-generation / preset driven and out of
--                       scope for this control panel.
--
-- This module exposes the cloud-SHADOW controls (the editor's "Show cloud
-- shadows" analog plus live coverage / speed), mirroring mw_rain.lua's visual
-- override pattern:
--   Clouds.AreShadowsEnabled()   -> bool      (hr.EnableCloudsShadow ~= 0)
--   Clouds.SetShadowsEnabled(on) -> true,err  (writes hr.EnableCloudsShadow)
--   Clouds.ToggleShadows()       -> true,err
--   Clouds.GetCoveragePct()      -> 0..100    (CloudsCoverage, raw 0..1000)
--   Clouds.SetCoveragePct(pct)   -> new_pct,err
--   Clouds.AdjustCoveragePct(d)  -> new_pct,err
--   Clouds.GetSpeedM()           -> m/s       (CloudsSpeed, raw value/1000)
--   Clouds.SetSpeedM(mps)        -> new_mps,err
--   Clouds.AdjustSpeedM(d)       -> new_mps,err
--
-- Coverage / speed are written with SetSceneParam, which the lightmodel system
-- overwrites on every transition (time-of-day, weather). So, like the visual
-- rain override, once the player changes either value we set cloud_override_active
-- and reapply the held values after the engine's own handler runs (see
-- OnLightmodelSetSceneParams, called from mw_lifecycle.lua). The hr shadow flag
-- is a persistent hardware setting and needs no reapply.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Clouds"

-- Engine uses view = 1 for the main viewport (same as mw_rain.lua).
local VIEW = 1

-- Scene-param raw ranges (from Lightmodel.lua property defs):
--   CloudsCoverage: 0..1000, scale 1000  -> 0..1.0 (we present 0..100 %)
--   CloudsSpeed:    0..(50*guim), scale 1000 -> value/1000 m/s
local COVERAGE_PARAM = "CloudsCoverage"
local SPEED_PARAM = "CloudsSpeed"
local STRENGTH_PARAM = "CloudsStrength"      -- shadow darkness; 0 = invisible
local SCALE_PARAM = "CloudsScale"            -- pattern scale; bigger => bigger clouds
local SMOOTHNESS_PARAM = "CloudsSmoothness"  -- edge softness
local OSCI_AMP_PARAM = "CloudsOsciAmplitude" -- drift wobble amplitude
local OSCI_PERIOD_PARAM = "CloudsOsciPeriod" -- drift wobble period
local COVERAGE_RAW_MAX = 1000

-- IMPORTANT: this build ships config.LightModelUnusedFeatures["clouds"] = true, so
-- the lightmodel system never writes cloud scene params. We set them directly
-- instead (which therefore also never get overwritten). The shadow DARKNESS
-- (CloudsStrength) defaults to 0, so without setting it the shadows are invisible
-- even with coverage > 0 -- that is what was hiding them.
--
-- The shadow pattern is a single tiled texture (CommonAssets/System/clouds.dds),
-- NOT discrete cloud objects, so "number of clouds / which rows" can't be set.
-- What we CAN do to kill the obvious grid-repeat look: enlarge each blob via a
-- big SCALE (here 5x the engine default => clouds ~5x bigger, tile repeats far
-- less often), soften the edges, and add a slow oscillation so the pattern
-- drifts organically instead of marching in lockstep.
local STRENGTH_RAW_ON = 700      -- 0.7 darkness when shadows are enabled
local SCALE_RAW = 5000           -- 5.0x the default 1000 => ~5x bigger clouds
local SMOOTHNESS_RAW = 600       -- 0.6 softer edges (default 300)
local OSCI_AMP_RAW = 1200        -- drift wobble (matches a shipped preset)
local OSCI_PERIOD_RAW = 2000000  -- ~2000s period -> slow, non-repetitive drift

local Clouds = {}

local function config()
	return MartianWaters.Config or {}
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function scene_api_available()
	local has_set = type(rawget(_G, "SetSceneParam")) == "function"
	if not has_set then
		DebugLog.Warn(SCOPE, "SetSceneParam unavailable")
		return false
	end
	return true
end

-- Read a scene param's current raw value, or nil if unavailable.
local function get_param_raw(name)
	local get = rawget(_G, "GetSceneParam")
	if type(get) ~= "function" then return nil end
	local ok, v = pcall(get, VIEW, name)
	if ok and type(v) == "number" then return v end
	-- Some builds expose the no-view form; try it before giving up.
	ok, v = pcall(get, name)
	if ok and type(v) == "number" then return v end
	return nil
end

-- ----------------------------------------------------------------------------
-- Cloud shadow rendering (hr.EnableCloudsShadow)
-- ----------------------------------------------------------------------------

function Clouds.AreShadowsEnabled()
	local v = MartianWaters.State.cloud_shadows_on
	if v == nil then
		-- First read: seed the mod flag from the live hardware flag. If hr or the
		-- field is absent we assume shadows are on (the in-game default).
		local hr = rawget(_G, "hr")
		v = not (type(hr) == "table" and hr.EnableCloudsShadow == 0)
		MartianWaters.State.cloud_shadows_on = v
	end
	return v == true
end

function Clouds.SetShadowsEnabled(on)
	local hr = rawget(_G, "hr")
	if type(hr) ~= "table" then
		DebugLog.Warn(SCOPE, "hr table unavailable, cannot toggle cloud shadows")
		return nil, "hr (hardware render settings) unavailable"
	end
	on = on and true or false
	-- Same write the editor uses (XEditorSettings.lua:181).
	hr.EnableCloudsShadow = on and 1 or 0
	MartianWaters.State.cloud_shadows_on = on

	-- When enabling, push the params the lightmodel would normally set but doesn't
	-- (clouds is an "unused" feature here): a non-zero darkness (strength), a sane
	-- scale, and the current coverage/speed. Without strength > 0 the shadows are
	-- invisible. We do this directly via SetSceneParam.
	if on and scene_api_available() then
		MartianWaters.State.cloud_override_active = true
		SetSceneParam(VIEW, STRENGTH_PARAM, STRENGTH_RAW_ON, 0, 0)
		SetSceneParam(VIEW, SCALE_PARAM, SCALE_RAW, 0, 0)
		SetSceneParam(VIEW, SMOOTHNESS_PARAM, SMOOTHNESS_RAW, 0, 0)
		SetSceneParam(VIEW, OSCI_AMP_PARAM, OSCI_AMP_RAW, 0, 0)
		SetSceneParam(VIEW, OSCI_PERIOD_PARAM, OSCI_PERIOD_RAW, 0, 0)
		-- Re-assert coverage / speed from our held values (seeds them if needed).
		Clouds.SetCoveragePct(Clouds.GetCoveragePct())
		Clouds.SetSpeedM(Clouds.GetSpeedM())
		DebugLog.Info(SCOPE, "cloud shadow params pushed", {
			strength = STRENGTH_RAW_ON, scale = SCALE_RAW, smoothness = SMOOTHNESS_RAW,
		})
	end

	DebugLog.Info(SCOPE, "cloud shadows toggled", { enabled = on })
	return true
end

function Clouds.ToggleShadows()
	return Clouds.SetShadowsEnabled(not Clouds.AreShadowsEnabled())
end

-- ----------------------------------------------------------------------------
-- Coverage (CloudsCoverage scene param, presented as a percentage)
-- ----------------------------------------------------------------------------

function Clouds.GetCoveragePct()
	local raw = MartianWaters.State.cloud_coverage_raw
	if raw == nil then
		raw = get_param_raw(COVERAGE_PARAM)
		if type(raw) ~= "number" then raw = 500 end  -- engine default
		MartianWaters.State.cloud_coverage_raw = raw
	end
	return MulDivRound(raw, 100, COVERAGE_RAW_MAX)  -- 0..1000 -> 0..100
end

function Clouds.SetCoveragePct(pct)
	if config().ENABLE_MOD ~= true then
		return nil, "MartianWaters mod disabled in config"
	end
	if not scene_api_available() then
		return nil, "SetSceneParam unavailable"
	end
	pct = clamp(type(pct) == "number" and pct or 0, 0, 100)
	local raw = MulDivRound(pct, COVERAGE_RAW_MAX, 100)  -- 0..100 -> 0..1000
	MartianWaters.State.cloud_coverage_raw = raw
	MartianWaters.State.cloud_override_active = true
	SetSceneParam(VIEW, COVERAGE_PARAM, raw, 0, 0)
	DebugLog.Info(SCOPE, "coverage set", { pct = pct, raw = raw })
	return Clouds.GetCoveragePct()
end

function Clouds.AdjustCoveragePct(delta)
	return Clouds.SetCoveragePct(Clouds.GetCoveragePct() + (delta or 0))
end

-- ----------------------------------------------------------------------------
-- Speed (CloudsSpeed scene param, presented in meters / second)
-- ----------------------------------------------------------------------------

function Clouds.GetSpeedM()
	local raw = MartianWaters.State.cloud_speed_raw
	if raw == nil then
		raw = get_param_raw(SPEED_PARAM)
		if type(raw) ~= "number" then raw = 3000 end  -- engine default (3 m/s)
		MartianWaters.State.cloud_speed_raw = raw
	end
	return raw / 1000  -- scale 1000 -> m/s
end

function Clouds.SetSpeedM(mps)
	if config().ENABLE_MOD ~= true then
		return nil, "MartianWaters mod disabled in config"
	end
	if not scene_api_available() then
		return nil, "SetSceneParam unavailable"
	end
	local max_m = config().CLOUD_SPEED_MAX_M or 50
	mps = clamp(type(mps) == "number" and mps or 0, 0, max_m)
	-- m/s -> raw (scale 1000). mps can be fractional (the field is 1-decimal and
	-- the step is 0.5), so round to a clean integer rather than risk MulDivRound
	-- truncating the fractional argument. math.floor is available in this runtime.
	local raw = math.floor(mps * 1000 + 0.5)
	MartianWaters.State.cloud_speed_raw = raw
	MartianWaters.State.cloud_override_active = true
	SetSceneParam(VIEW, SPEED_PARAM, raw, 0, 0)
	DebugLog.Info(SCOPE, "speed set", { mps = mps, raw = raw })
	return Clouds.GetSpeedM()
end

function Clouds.AdjustSpeedM(delta)
	return Clouds.SetSpeedM(Clouds.GetSpeedM() + (delta or 0))
end

-- ----------------------------------------------------------------------------
-- Lightmodel reapply (mirrors Rain.OnLightmodelSetSceneParams)
-- ----------------------------------------------------------------------------

-- Called from mw_lifecycle.lua's OnMsg.LightmodelSetSceneParams, AFTER the
-- engine wrote the active lightmodel's cloud params. We reapply the player's
-- held coverage / speed only once they've actually changed something
-- (cloud_override_active); otherwise this is a no-op and the lightmodel values
-- stand, which is the restore path.
function Clouds.OnLightmodelSetSceneParams(_map, view, _lm_buf, _time, start_offset)
	if MartianWaters.State.cloud_override_active ~= true then return end
	if not scene_api_available() then return end
	view = view or VIEW
	start_offset = start_offset or 0
	if type(MartianWaters.State.cloud_coverage_raw) == "number" then
		SetSceneParam(view, COVERAGE_PARAM, MartianWaters.State.cloud_coverage_raw, 0, start_offset)
	end
	if type(MartianWaters.State.cloud_speed_raw) == "number" then
		SetSceneParam(view, SPEED_PARAM, MartianWaters.State.cloud_speed_raw, 0, start_offset)
	end
	-- Keep a visible darkness + big, soft, drifting pattern while shadows are on.
	if MartianWaters.State.cloud_shadows_on == true then
		SetSceneParam(view, STRENGTH_PARAM, STRENGTH_RAW_ON, 0, start_offset)
		SetSceneParam(view, SCALE_PARAM, SCALE_RAW, 0, start_offset)
		SetSceneParam(view, SMOOTHNESS_PARAM, SMOOTHNESS_RAW, 0, start_offset)
		SetSceneParam(view, OSCI_AMP_PARAM, OSCI_AMP_RAW, 0, start_offset)
		SetSceneParam(view, OSCI_PERIOD_PARAM, OSCI_PERIOD_RAW, 0, start_offset)
	end
end

MartianWaters.Clouds = Clouds
