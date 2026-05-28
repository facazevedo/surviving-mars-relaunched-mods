-- Rivers -- mod entry point.
--
-- By the time this file loads, version/config/debug/terrain/water/api/lifecycle
-- have all loaded (see metadata.lua `code` order). This file does nothing but
-- log the active configuration and start the reversible lifecycle once.

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	return
end

local Config = Rivers.Config or {}
local DebugLog = Rivers.DebugLog
if DebugLog then
	DebugLog.Info("Init", "Rivers loaded", {
		enabled = Config.ENABLE_MOD ~= false,
		default_width_m = Config.DEFAULT_WIDTH_METERS,
		default_depth_m = Config.DEFAULT_DEPTH_METERS,
		default_water_level_m = Config.DEFAULT_WATER_LEVEL_METERS,
	})
end

if Rivers.Lifecycle and type(Rivers.Lifecycle.Enable) == "function" then
	Rivers.Lifecycle.Enable()
end
