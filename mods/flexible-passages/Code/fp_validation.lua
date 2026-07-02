-- Flexible Passages -- runtime API availability checks.

local FlexiblePassages = rawget(_G, "FlexiblePassages")
if type(FlexiblePassages) ~= "table" then
	FlexiblePassages = {}
	rawset(_G, "FlexiblePassages", FlexiblePassages)
end

local Validation = {}

local function HasFunction(owner, name)
	return type(owner) == "table" and type(owner[name]) == "function"
end

function Validation.CheckRuntimeApi(reason)
	local controller = rawget(_G, "GridConstructionController")
	local terrain_api = rawget(_G, "terrain")

	local result = {
		has_controller = type(controller) == "table",
		has_activate = HasFunction(controller, "Activate"),
		has_update_cursor = HasFunction(controller, "UpdateCursor"),
		has_update_visuals = HasFunction(controller, "UpdateVisuals"),
		has_get_construction_terrain_pos = type(rawget(_G, "GetConstructionTerrainPos")) == "function",
		has_hex_get_nearest_center = type(rawget(_G, "HexGetNearestCenter")) == "function",
		has_fix_construct_pos = type(rawget(_G, "FixConstructPos")) == "function",
		has_terrain_bounds_check = HasFunction(terrain_api, "IsPointInBounds"),
	}

	local ok = result.has_controller == true
		and result.has_activate == true
		and result.has_update_cursor == true
		and result.has_update_visuals == true
		and result.has_hex_get_nearest_center == true

	local DebugLog = FlexiblePassages.DebugLog
	if DebugLog then
		DebugLog.Info("Validation", "Runtime API availability", {
			reason = reason,
			ok = ok,
			has_controller = result.has_controller,
			has_activate = result.has_activate,
			has_update_cursor = result.has_update_cursor,
			has_update_visuals = result.has_update_visuals,
			has_get_construction_terrain_pos = result.has_get_construction_terrain_pos,
			has_hex_get_nearest_center = result.has_hex_get_nearest_center,
			has_fix_construct_pos = result.has_fix_construct_pos,
			has_terrain_bounds_check = result.has_terrain_bounds_check,
		})
	end

	return ok, result
end

FlexiblePassages.Validation = Validation
