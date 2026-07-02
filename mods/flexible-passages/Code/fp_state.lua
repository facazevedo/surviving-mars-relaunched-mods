-- Flexible Passages -- runtime state owned by the mod.

local FlexiblePassages = rawget(_G, "FlexiblePassages")
if type(FlexiblePassages) ~= "table" then
	FlexiblePassages = {}
	rawset(_G, "FlexiblePassages", FlexiblePassages)
end

FlexiblePassages.State = FlexiblePassages.State or {
	active = false,
	original_activate = false,
	patched_activate = false,
	activate_patched = false,
	original_update_cursor = false,
	patched_update_cursor = false,
	update_cursor_patched = false,
}
