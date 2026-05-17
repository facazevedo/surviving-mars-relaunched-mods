-- Force Delete configuration.
-- This module centralizes small user-tunable switches so behavior changes do
-- not get scattered across object-specific diagnostic modules.

-- ============================================================================
-- Module setup
-- ============================================================================

local FD = ForceDelete
if not FD then return end

if FD.config_loaded then return end
FD.config_loaded = true

FD.Config = FD.Config or {}

-- ============================================================================
-- Display options
-- ============================================================================

-- Controls whether selected-object attribute payloads are shown in the panel.
-- Set this to false to keep shortcut feedback available while hiding attributes.
if FD.Config.DISPLAY_ATTRIBUTES == nil then
	FD.Config.DISPLAY_ATTRIBUTES = true
end

-- Return the effective attribute display setting. Keeping this behind a helper
-- lets future config sources override the value without changing callers.
function FD.Config.ShouldDisplayAttributes()
	return FD.Config.DISPLAY_ATTRIBUTES == true
end
