-- Rivers -- lifecycle: enable, disable, OnMsg wiring.
--
-- The prototype is intentionally minimal:
--   * Enable() flips an internal flag and logs. It does NOT touch the map on
--     its own -- river creation is player-driven via Rivers.Create / Demo /
--     CreateAtCursor.
--   * Disable() calls Rivers.ClearAll() so any markers placed by the mod are
--     removed (water drains via ApplyAllWaterObjects). Terrain carving is not
--     reverted -- see r_terrain.lua for the prototype caveat.
--   * OnMsg.DoneMap fires when a map is unloaded; we clear in-memory segment
--     handles because the engine destroys the marker objects with the map.
--
-- Idempotency: Enable/Disable can be called twice without ill effect. The
-- only "patch" we install is a single hook closure stored in Rivers.State.

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	return
end

local DebugLog = Rivers.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Lifecycle"

-- Patch-identity guard: bump when the OnMsg hook closures below change so a
-- hot-reload of the mod can detect a stale hook registration and refuse to
-- double-install. Logged on Enable() so reload diagnostics show the version
-- that registered the live hooks.
local PATCH_VERSION = 1

local Lifecycle = {}

function Lifecycle.Enable()
	local cfg = Rivers.Config or {}
	if cfg.ENABLE_MOD ~= true then
		DebugLog.Info(SCOPE, "Enable: ENABLE_MOD is false, staying passive")
		Rivers.State.enabled = false
		return false
	end
	if Rivers.State.enabled == true then
		DebugLog.Info(SCOPE, "Enable: already enabled, no-op")
		return true
	end
	Rivers.State.enabled = true
	DebugLog.Info(SCOPE, "Enable: ready", {
		patch_version = PATCH_VERSION,
	})
	return true
end

function Lifecycle.Disable()
	if Rivers.State.enabled ~= true then
		DebugLog.Info(SCOPE, "Disable: already disabled, no-op")
		return true
	end
	if Rivers.UI and type(Rivers.UI.Hide) == "function" then
		Rivers.UI.Hide()
	end
	-- Visual rain is a mod-owned scene-param override -- clear it so vanilla
	-- weather rendering returns. The disaster (g_RainDisaster) is engine game
	-- state and is intentionally left alone: the player can stop it via the UI
	-- if they want it gone.
	if Rivers.Rain and type(Rivers.Rain.StopVisual) == "function" then
		Rivers.Rain.StopVisual()
	end
	if type(Rivers.ClearAll) == "function" then
		Rivers.ClearAll()
	end
	Rivers.State.enabled = false
	DebugLog.Info(SCOPE, "Disable: done")
	return true
end

-- OnMsg.NewMapLoaded: the in-game HUD now exists, so we can attach the panel.
function OnMsg.NewMapLoaded(map, mapdata)
	if Rivers.State.enabled ~= true then return end
	if Rivers.UI and type(Rivers.UI.Show) == "function" then
		Rivers.UI.Show()
	end
end

-- OnMsg.LightmodelSetSceneParams fires every time the engine writes its scene
-- params from the active lightmodel (time-of-day shifts, weather transitions,
-- override pushes). We register after the engine's own handler in Lightmodel.lua
-- so r_rain.lua can reapply its visual override AFTER the engine wrote the
-- vanilla value. When the override flag is off, our hook is a no-op and the
-- vanilla value stands.
function OnMsg.LightmodelSetSceneParams(map, view, lm_buf, time, start_offset)
	if Rivers.State.enabled ~= true then return end
	if not Rivers.Rain or type(Rivers.Rain.OnLightmodelSetSceneParams) ~= "function" then return end
	Rivers.Rain.OnLightmodelSetSceneParams(map, view, lm_buf, time, start_offset)
end

-- OnMsg.DoneMap: the engine has destroyed every map-owned object, including
-- our markers. Drop our in-memory handles so a follow-up placement on the
-- next map doesn't try to clean up dead references, and tear down the panel
-- / click-overlay so they don't outlive the map.
function OnMsg.DoneMap(map)
	if Rivers.Tool and type(Rivers.Tool.OnMapUnloaded) == "function" then
		Rivers.Tool.OnMapUnloaded()
	end
	if Rivers.UI and type(Rivers.UI.Hide) == "function" then
		Rivers.UI.Hide()
	end
	local state = Rivers.State
	if not state or not state.segments then
		return
	end
	local n = 0
	for id in pairs(state.segments) do
		state.segments[id] = nil
		n = n + 1
	end
	if n > 0 then
		DebugLog.Info(SCOPE, "DoneMap: cleared in-memory segments", { count = n })
	end
end

Rivers.Lifecycle = Lifecycle
