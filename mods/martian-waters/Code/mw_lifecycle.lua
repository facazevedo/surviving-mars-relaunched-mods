-- MartianWaters -- lifecycle: enable, disable, OnMsg wiring.
--
-- The prototype is intentionally minimal:
--   * Enable() flips an internal flag and logs. It does NOT touch the map on
--     its own -- river creation is player-driven via MartianWaters.Create / Demo /
--     CreateAtCursor.
--   * Disable() calls MartianWaters.ClearAll() so any markers placed by the mod are
--     removed (water drains via ApplyAllWaterObjects). Terrain carving is not
--     reverted -- see mw_terrain.lua for the prototype caveat.
--   * OnMsg.DoneMap fires when a map is unloaded; we clear in-memory segment
--     handles because the engine destroys the marker objects with the map.
--
-- Idempotency: Enable/Disable can be called twice without ill effect. The
-- only "patch" we install is a single hook closure stored in MartianWaters.State.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Lifecycle"

-- Patch-identity guard: bump when the OnMsg hook closures below change so a
-- hot-reload of the mod can detect a stale hook registration and refuse to
-- double-install. Logged on Enable() so reload diagnostics show the version
-- that registered the live hooks.
local PATCH_VERSION = 1

local Lifecycle = {}

function Lifecycle.Enable()
	local cfg = MartianWaters.Config or {}
	if cfg.ENABLE_MOD ~= true then
		DebugLog.Info(SCOPE, "Enable: ENABLE_MOD is false, staying passive")
		MartianWaters.State.enabled = false
		return false
	end
	if MartianWaters.State.enabled == true then
		DebugLog.Info(SCOPE, "Enable: already enabled, no-op")
		return true
	end
	MartianWaters.State.enabled = true
	-- Start the hydrology ticker. StartTicker is idempotent; if no map is
	-- loaded yet the ticker just no-ops until OnMsg.NewMapLoaded fires (which
	-- also calls StartTicker after a map change, in case the old thread died).
	if MartianWaters.Budget and type(MartianWaters.Budget.StartTicker) == "function" then
		MartianWaters.Budget.StartTicker()
	end
	DebugLog.Info(SCOPE, "Enable: ready", {
		patch_version = PATCH_VERSION,
	})
	return true
end

function Lifecycle.Disable()
	if MartianWaters.State.enabled ~= true then
		DebugLog.Info(SCOPE, "Disable: already disabled, no-op")
		return true
	end
	if MartianWaters.UI and type(MartianWaters.UI.Hide) == "function" then
		MartianWaters.UI.Hide()
	end
	-- Stop the hydrology ticker first so the budget can't push a level change
	-- onto a marker that ClearAll is about to delete.
	if MartianWaters.Budget and type(MartianWaters.Budget.StopTicker) == "function" then
		MartianWaters.Budget.StopTicker()
	end
	-- Visual rain is a mod-owned scene-param override -- clear it so vanilla
	-- weather rendering returns. The disaster (g_RainDisaster) is engine game
	-- state and is intentionally left alone: the player can stop it via the UI
	-- if they want it gone.
	if MartianWaters.Rain and type(MartianWaters.Rain.StopVisual) == "function" then
		MartianWaters.Rain.StopVisual()
	end
	if type(MartianWaters.ClearAll) == "function" then
		MartianWaters.ClearAll()
	end
	MartianWaters.State.enabled = false
	DebugLog.Info(SCOPE, "Disable: done")
	return true
end

-- OnMsg.NewMapLoaded: the in-game HUD now exists, so we can attach the panel.
-- This also (re)starts the hydrology ticker: a GameTimeThread does not survive
-- a map change, so a fresh map needs a fresh thread.
function OnMsg.NewMapLoaded(map, mapdata)
	if MartianWaters.State.enabled ~= true then return end
	if MartianWaters.UI and type(MartianWaters.UI.Show) == "function" then
		MartianWaters.UI.Show()
	end
	if MartianWaters.Budget and type(MartianWaters.Budget.StartTicker) == "function" then
		MartianWaters.Budget.StartTicker()
	end
end

-- OnMsg.LightmodelSetSceneParams fires every time the engine writes its scene
-- params from the active lightmodel (time-of-day shifts, weather transitions,
-- override pushes). We register after the engine's own handler in Lightmodel.lua
-- so mw_rain.lua can reapply its visual override AFTER the engine wrote the
-- vanilla value. When the override flag is off, our hook is a no-op and the
-- vanilla value stands.
function OnMsg.LightmodelSetSceneParams(map, view, lm_buf, time, start_offset)
	if MartianWaters.State.enabled ~= true then return end
	if not MartianWaters.Rain or type(MartianWaters.Rain.OnLightmodelSetSceneParams) ~= "function" then return end
	MartianWaters.Rain.OnLightmodelSetSceneParams(map, view, lm_buf, time, start_offset)
end

-- OnMsg.DoneMap: the engine has destroyed every map-owned object, including
-- our markers. Drop our in-memory handles so a follow-up placement on the
-- next map doesn't try to clean up dead references, and tear down the panel
-- / click-overlay so they don't outlive the map.
function OnMsg.DoneMap(map)
	-- Stop the ticker first; otherwise it would race the segment teardown.
	if MartianWaters.Budget and type(MartianWaters.Budget.StopTicker) == "function" then
		MartianWaters.Budget.StopTicker()
	end
	if MartianWaters.Tool and type(MartianWaters.Tool.OnMapUnloaded) == "function" then
		MartianWaters.Tool.OnMapUnloaded()
	end
	if MartianWaters.UI and type(MartianWaters.UI.Hide) == "function" then
		MartianWaters.UI.Hide()
	end
	local state = MartianWaters.State
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

MartianWaters.Lifecycle = Lifecycle
