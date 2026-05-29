-- MartianWaters -- mod entry point.
--
-- By the time this file loads, version/config/debug/terrain/water/api/lifecycle
-- have all loaded (see metadata.lua `code` order). This file does nothing but
-- log the active configuration and start the reversible lifecycle once.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local Config = MartianWaters.Config or {}
local DebugLog = MartianWaters.DebugLog
if DebugLog then
	DebugLog.Info("Init", "MartianWaters loaded", {
		enabled = Config.ENABLE_MOD ~= false,
		default_width_m = Config.DEFAULT_WIDTH_METERS,
		default_depth_m = Config.DEFAULT_DEPTH_METERS,
		default_water_level_m = Config.DEFAULT_WATER_LEVEL_METERS,
	})
end

if MartianWaters.Lifecycle and type(MartianWaters.Lifecycle.Enable) == "function" then
	MartianWaters.Lifecycle.Enable()
end
