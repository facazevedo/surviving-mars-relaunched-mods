-- Flexible Passages -- central configuration and feature flags.

local FlexiblePassages = rawget(_G, "FlexiblePassages")
if type(FlexiblePassages) ~= "table" then
	FlexiblePassages = {}
	rawset(_G, "FlexiblePassages", FlexiblePassages)
end

FlexiblePassages.Config = {
	ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION = true,
	ENABLE_TILE_SNAPPED_CONTROL_POINTS = true,
	ENABLE_FIXED_POINT_RELEASE = false,

	DEBUG_LOGS = false,
	DEBUG_LIFECYCLE = false,
	DEBUG_VALIDATION = false,
	DEBUG_CONSTRUCTION = false,
	DEBUG_VANILLA_CONSTRUCTION = false,
}
