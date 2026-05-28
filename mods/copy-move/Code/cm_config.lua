-- Copy Move configuration.
-- Central, mod-owned switches. All flags are explicit booleans. Edit these
-- values then reload the mod (or restart the game) to apply.

CopyMove = rawget(_G, "CopyMove") or {}
local CM = CopyMove
_G.CopyMove = CM

local Config = CM.Config or {}
CM.Config = Config

-- ============================================================================
-- Master / feature flags
-- ============================================================================
-- ENABLE_MOD is the master switch. The per-feature flags below let individual
-- behaviors be turned off without disabling the whole mod. Features marked
-- "(later phase)" are inert until their module is implemented.
Config.ENABLE_MOD = true
Config.ENABLE_SELECT_TINT = true   -- tint the current selection green
Config.ENABLE_MULTISELECT = true   -- hold Ctrl + click to add objects to the selection
Config.ENABLE_COPY_PASTE = true    -- (later phase) Ctrl+C / Ctrl+V
Config.ENABLE_MOVE = true          -- (later phase) click-and-hold to relocate
Config.ENABLE_DOME_MOVE = true     -- (later phase) move a whole dome with its contents

-- ============================================================================
-- Copy / move inclusion rules
-- ============================================================================
-- When copying a dome (or a group), these decide what comes along.
Config.COPY_INCLUDE_ANIMALS = true
Config.COPY_INCLUDE_COLONISTS = false
Config.COPY_INCLUDE_DRONES = false
-- Moving a dome takes its colonists along (per design).
Config.MOVE_DOME_INCLUDE_COLONISTS = true
-- A dome's passages are bound to BOTH connected domes; relocating one end is
-- geometrically unsound, so by default connected passages are disconnected and
-- the user is warned to rebuild them.
Config.DOME_MOVE_DISCONNECT_PASSAGES = true

-- ============================================================================
-- Selection highlight
-- ============================================================================
-- Stored as R,G,B components (0-255). The selection module builds the engine
-- color via RGB() at use time, so this file has no hard dependency on RGB.
Config.TINT_COLOR_RGB = { 0, 220, 60 }

-- ============================================================================
-- Input bindings
-- ============================================================================
Config.KEY_MULTISELECT = "Ctrl"   -- modifier held to add to the selection set
Config.SHORTCUT_COPY = "Ctrl-C"
Config.SHORTCUT_PASTE = "Ctrl-V"

-- ============================================================================
-- Debug flags (explicit booleans; logs print only when the gate is true)
-- ============================================================================
-- DEBUG_LOGS is the master logging gate. Scoped flags refine which subsystems
-- print when the master is on. Set DEBUG_LOGS = false for a fully silent mod.
Config.DEBUG_LOGS = true
Config.DEBUG_SELECTION = true
Config.DEBUG_COPY = false
Config.DEBUG_MOVE = false
Config.DEBUG_DOME = false

-- Map a debug scope name to its scoped flag (nil = uncategorized/general).
local scope_flags = {
	Selection = "DEBUG_SELECTION",
	Copy = "DEBUG_COPY",
	Move = "DEBUG_MOVE",
	Dome = "DEBUG_DOME",
}

-- Return whether debug output should print for a scope.
function Config.DebugEnabled(scope)
	if Config.DEBUG_LOGS ~= true then
		return false
	end
	local flag_name = scope_flags[scope]
	if flag_name == nil then
		return true -- general/uncategorized logs follow the master gate only
	end
	return Config[flag_name] == true
end

-- Return whether the mod master switch is on.
function Config.IsModEnabled()
	return Config.ENABLE_MOD == true
end
