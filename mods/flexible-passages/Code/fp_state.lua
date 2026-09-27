-- Flexible Passages -- runtime state owned by the mod.

local FlexiblePassages = rawget(_G, "FlexiblePassages")
if type(FlexiblePassages) ~= "table" then
	FlexiblePassages = {}
	rawset(_G, "FlexiblePassages", FlexiblePassages)
end

-- Mod environments can survive ReloadLua, but the engine rebuilds its classes.
-- Function ownership is transient and must never carry into that new class set.
FlexiblePassages.State = {
	active = false,
	original_activate = false,
	patched_activate = false,
	activate_patched = false,
	original_update_cursor = false,
	patched_update_cursor = false,
	update_cursor_patched = false,
}
