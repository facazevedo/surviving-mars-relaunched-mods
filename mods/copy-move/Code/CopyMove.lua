-- Copy Move main entry.
-- High-level lifecycle (Enable/Disable), startup hook installation, and load-time
-- diagnostics. Loaded LAST so every module it wires already exists.

CopyMove = rawget(_G, "CopyMove") or {}
local CM = CopyMove
_G.CopyMove = CM

local DebugLog = CM.DebugLog
local Config = CM.Config

CM.Lifecycle = CM.Lifecycle or {}
local Lifecycle = CM.Lifecycle

-- Runtime on/off state, seeded from the master config flag on first load.
if Lifecycle.enabled == nil then
	Lifecycle.enabled = (Config and Config.ENABLE_MOD == true) or false
end

-- Whether the mod should actively intercept input / tint selections right now.
function CM.IsActive()
	return Lifecycle.enabled == true and Config ~= nil and Config.ENABLE_MOD == true
end

-- Apply mod behavior (idempotent).
function Lifecycle.Enable()
	Lifecycle.enabled = true
	if CM.Input then
		CM.Input.InstallSelectionHook()
	end
	if CM.Selection then
		CM.Selection.RefreshTints()
	end
	DebugLog.Info("Lifecycle", "Copy Move enabled", { version = CM.VersionString() })
end

-- Restore vanilla behavior (idempotent): clear tints and stop intercepting.
function Lifecycle.Disable()
	Lifecycle.enabled = false
	if CM.Selection then
		CM.Selection.Clear()
	end
	-- The mouse hook stays installed but is inert while inactive (it forwards to
	-- the original handler), so vanilla selection is fully restored.
	DebugLog.Info("Lifecycle", "Copy Move disabled")
end

-- Install hooks once classes/data are ready (the class may not exist yet at the
-- moment this code file is loaded). Multiple OnMsg handlers across files coexist.
function OnMsg.ClassesPostprocess()
	if CM.Input then
		CM.Input.InstallSelectionHook()
	end
end

function OnMsg.DataLoaded()
	if CM.Input then
		CM.Input.InstallSelectionHook()
	end
end

-- Drop selection references when a map is torn down (objects are being deleted;
-- do not touch their colors).
function OnMsg.DoneMap()
	if CM.Selection then
		CM.Selection.Reset()
	end
end

-- Try immediately in case the selection class already exists (mod reloaded mid-game).
if CM.Input then
	CM.Input.InstallSelectionHook()
end

-- Load-time diagnostics.
DebugLog.Info("Lifecycle", "Copy Move loaded", {
	version = CM.VersionString(),
	active = CM.IsActive(),
	tint = Config and Config.ENABLE_SELECT_TINT,
	multiselect = Config and Config.ENABLE_MULTISELECT,
})
