-- MartianWaters -- rain controls.
--
-- Two independent rain modes, exposed as four buttons in mw_ui.lua:
--
--   Disaster:
--     Rain.StartDisaster(preset_id) -- delegates to engine CheatRainsDisaster.
--                                      Real gameplay disaster: soil changes,
--                                      possibly toxic pools (Toxic_* presets),
--                                      blocks terraforming while active.
--                                      `preset_id` defaults to MartianWaters.Config
--                                      DEFAULT_RAIN_PRESET ("Normal_Low").
--     Rain.StopDisaster()           -- delegates to engine StopRainsDisaster.
--                                      No-op if nothing is active.
--     Rain.GetDisasterType()        -- string preset name or nil.
--
--   Visual:
--     Rain.StartVisual()            -- SetSceneParam(view, "RainEnable", 1).
--                                      Purely cosmetic: no soil change, no
--                                      pools. To survive lightmodel transitions
--                                      (time-of-day, weather), the OnMsg hook
--                                      below reapplies RainEnable=1 after the
--                                      engine sets its own value. Reversible:
--                                      when rain_visual_on flips false, the
--                                      hook is a no-op and the engine value
--                                      stands again.
--     Rain.StopVisual()             -- clears the flag and forces RainEnable=0.
--     Rain.IsVisualActive()         -- mod-owned flag (boolean).
--
-- Disaster state lives in the engine (g_RainDisaster) and persists across
-- save/load by design. The visual flag is in-memory only; on load the override
-- resets to off, which matches the player's expectation that a cosmetic toggle
-- doesn't sneak past a save boundary.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Rain"

-- Engine uses view = 1 for the main viewport (see Lightmodel.lua line 1691-1692
-- in the install where DoSetLightmodel passes 1). All our SetSceneParam calls
-- target the same view.
local VIEW = 1

local Rain = {}

local function config()
	return MartianWaters.Config or {}
end

local function current_map()
	return rawget(_G, "CurrentMap")
end

-- ----------------------------------------------------------------------------
-- API availability
-- ----------------------------------------------------------------------------

local function disaster_api_available()
	local has_start = type(rawget(_G, "CheatRainsDisaster")) == "function"
	local has_stop = type(rawget(_G, "StopRainsDisaster")) == "function"
	if not has_start or not has_stop then
		DebugLog.Warn(SCOPE, "disaster API unavailable", {
			CheatRainsDisaster = has_start and "present" or "missing",
			StopRainsDisaster = has_stop and "present" or "missing",
		})
		return false
	end
	return true
end

local function visual_api_available()
	local has_set = type(rawget(_G, "SetSceneParam")) == "function"
	if not has_set then
		DebugLog.Warn(SCOPE, "SetSceneParam unavailable")
		return false
	end
	return true
end

local function preset_exists(id)
	local presets = rawget(_G, "Presets")
	if type(presets) ~= "table" then return false end
	local ms = presets.MapSettings
	if type(ms) ~= "table" then return false end
	local rd = ms.RainsDisaster
	if type(rd) ~= "table" then return false end
	return rd[id] ~= nil
end

-- ----------------------------------------------------------------------------
-- Disaster rain
-- ----------------------------------------------------------------------------

function Rain.GetDisasterType()
	local v = rawget(_G, "g_RainDisaster")
	if type(v) == "string" then return v end
	return nil
end

function Rain.IsDisasterActive()
	return Rain.GetDisasterType() ~= nil
end

function Rain.StartDisaster(preset_id)
	if config().ENABLE_MOD ~= true then
		DebugLog.Warn(SCOPE, "StartDisaster: ENABLE_MOD is false")
		return nil, "MartianWaters mod disabled in config"
	end
	if not current_map() then
		return nil, "no current map (start or load a game first)"
	end
	if not disaster_api_available() then
		return nil, "CheatRainsDisaster / StopRainsDisaster unavailable"
	end
	local id = preset_id or config().DEFAULT_RAIN_PRESET or "Normal_Low"
	if not preset_exists(id) then
		DebugLog.Warn(SCOPE, "StartDisaster: preset not found", { id = id })
		return nil, "rain preset '" .. tostring(id) .. "' not found"
	end
	-- CheatRainsDisaster calls CheatStopDisaster() first, so consecutive starts
	-- swap presets cleanly instead of stacking disaster threads.
	CheatRainsDisaster(id)
	DebugLog.Info(SCOPE, "disaster started", {
		preset = id,
		previous = Rain.GetDisasterType() or "none",
	})
	return true
end

function Rain.StopDisaster()
	if not disaster_api_available() then
		return nil, "StopRainsDisaster unavailable"
	end
	local active = Rain.GetDisasterType()
	if not active then
		DebugLog.Info(SCOPE, "StopDisaster: none active, no-op")
		return true
	end
	StopRainsDisaster()
	DebugLog.Info(SCOPE, "disaster stopped", { was = active })
	return true
end

-- ----------------------------------------------------------------------------
-- Visual rain
-- ----------------------------------------------------------------------------

function Rain.IsVisualActive()
	return MartianWaters.State.rain_visual_on == true
end

function Rain.StartVisual()
	if config().ENABLE_MOD ~= true then
		DebugLog.Warn(SCOPE, "StartVisual: ENABLE_MOD is false")
		return nil, "MartianWaters mod disabled in config"
	end
	if not visual_api_available() then
		return nil, "SetSceneParam unavailable"
	end
	MartianWaters.State.rain_visual_on = true
	SetSceneParam(VIEW, "RainEnable", 1, 0, 0)
	DebugLog.Info(SCOPE, "visual rain on")
	return true
end

function Rain.StopVisual()
	if not visual_api_available() then
		return nil, "SetSceneParam unavailable"
	end
	MartianWaters.State.rain_visual_on = false
	SetSceneParam(VIEW, "RainEnable", 0, 0, 0)
	DebugLog.Info(SCOPE, "visual rain off")
	return true
end

-- Called from mw_lifecycle.lua's OnMsg.LightmodelSetSceneParams. The engine's
-- own handler in Lightmodel.lua runs first and writes RainEnable from the
-- active lightmodel; ours runs after and reapplies our override iff the mod
-- visual flag is set. When the flag is false, this is a no-op and the engine
-- value stands -- that is the restore path.
function Rain.OnLightmodelSetSceneParams(_map, view, _lm_buf, _time, start_offset)
	if MartianWaters.State.rain_visual_on ~= true then return end
	if not visual_api_available() then return end
	SetSceneParam(view or VIEW, "RainEnable", 1, 0, start_offset or 0)
end

MartianWaters.Rain = Rain
