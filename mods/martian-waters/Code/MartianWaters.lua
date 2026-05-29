-- MartianWaters -- mod entry point.
--
-- By the time this file loads, every other module has loaded (see metadata.lua
-- `code` order). This file does nothing but log that the mod loaded and start the
-- reversible lifecycle once.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local Config = MartianWaters.Config or {}
local DebugLog = MartianWaters.DebugLog
if DebugLog then
	DebugLog.Info("Init", "MartianWaters loaded", {
		enabled = Config.ENABLE_MOD ~= false,
	})
end

if MartianWaters.Lifecycle and type(MartianWaters.Lifecycle.Enable) == "function" then
	MartianWaters.Lifecycle.Enable()
end
