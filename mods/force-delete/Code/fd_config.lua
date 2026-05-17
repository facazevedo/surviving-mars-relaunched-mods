-- Force Delete configuration.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Store all user-tunable switches in one table.
FD.Config = FD.Config or {}

-- Master switch for the bottom-right diagnostic panel.
if FD.Config.DISPLAY_ATTRIBUTES == nil then
	FD.Config.DISPLAY_ATTRIBUTES = true
end

-- Return whether the diagnostic panel should be visible.
function FD.Config.ShouldDisplayAttributes()
	return FD.Config.DISPLAY_ATTRIBUTES == true
end
