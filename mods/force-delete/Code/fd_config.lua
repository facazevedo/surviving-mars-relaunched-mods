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

-- Force-delete object levels define which shortcut level may delete each type.
FD.Config.FORCE_DELETE_LEVELS = {
	colonist = 2,
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

-- Return the configured force-delete level for one object type.
function FD.Config.GetObjectLevel(object_type)
	if type(object_type) ~= "string" then
		return false
	end

	return FD.Config.FORCE_DELETE_LEVELS[object_type] or false
end

-- Return whether a shortcut level is allowed to delete one object type.
function FD.Config.CanForceDeleteAtLevel(object_type, requested_level)
	local object_level = FD.Config.GetObjectLevel(object_type)

	if type(object_level) ~= "number" or type(requested_level) ~= "number" then
		return false
	end

	return requested_level >= object_level
end
