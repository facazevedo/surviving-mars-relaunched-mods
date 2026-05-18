-- Force Delete configuration.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Store all user-tunable switches in one table.
FD.Config = FD.Config or {}

-- ============================================================================
-- Config values
-- ============================================================================

-- Master switch for the bottom-right diagnostic panel.
FD.Config.DISPLAY_ATTRIBUTES = true

-- Attribute refresh speed while an object remains selected.
FD.Config.ATTRIBUTE_REFRESH_INTERVAL_MS = 250

-- Demolishable objects default to Level 1 because the game has a normal demolition path.
FD.Config.DEMOLISHABLE_OBJECT_LEVEL = 1

-- Non-demolishable objects default to Level 2 because they need safer staged handling.
FD.Config.NON_DEMOLISHABLE_OBJECT_LEVEL = 2

-- Optional per-type overrides can pin a type to a specific level when needed.
-- Domes are always Level 2 because passages and internal buildings must be
-- staged before the dome itself, even when the dome is demolishable.
FD.Config.FORCE_DELETE_LEVELS = {
	dome = 2,
	deposit = 2,
	rocket = 2,
	rover = 2,
}

-- ============================================================================
-- Config helpers
-- ============================================================================

-- Return whether the diagnostic panel should be visible.
function FD.Config.ShouldDisplayAttributes()
	return FD.Config.DISPLAY_ATTRIBUTES == true
end

-- Return the configured diagnostic refresh interval.
function FD.Config.GetAttributeRefreshInterval()
	return FD.Config.ATTRIBUTE_REFRESH_INTERVAL_MS or 250
end

-- Return the default level for one concrete selected object.
function FD.Config.GetDefaultObjectLevel(obj)
	if FD.IsDemolishable and FD.IsDemolishable(obj) then
		return FD.Config.DEMOLISHABLE_OBJECT_LEVEL
	end

	return FD.Config.NON_DEMOLISHABLE_OBJECT_LEVEL
end

-- Return the configured force-delete level for one object type and object.
function FD.Config.GetObjectLevel(object_type, obj)
	if type(object_type) ~= "string" then
		return false
	end

	return FD.Config.FORCE_DELETE_LEVELS[object_type]
		or FD.Config.GetDefaultObjectLevel(obj)
end

-- Return whether a shortcut level is allowed to delete one object type.
function FD.Config.CanForceDeleteAtLevel(object_type, requested_level, obj)
	local object_level = FD.Config.GetObjectLevel(object_type, obj)

	if type(object_level) ~= "number" or type(requested_level) ~= "number" then
		return false
	end

	return requested_level >= object_level
end
