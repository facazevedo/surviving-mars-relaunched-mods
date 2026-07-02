-- Flexible Passages -- passage construction behavior changes.

local FlexiblePassages = rawget(_G, "FlexiblePassages")
if type(FlexiblePassages) ~= "table" then
	FlexiblePassages = {}
	rawset(_G, "FlexiblePassages", FlexiblePassages)
end

local ConstructionRules = {}

local function Config()
	return FlexiblePassages.Config or {}
end

local function State()
	FlexiblePassages.State = FlexiblePassages.State or {}
	return FlexiblePassages.State
end

local function Debug()
	return FlexiblePassages.DebugLog
end

local function DebugVanilla(message, data)
	if Config().DEBUG_VANILLA_CONSTRUCTION ~= true then
		return
	end

	local log = Debug()
	if log then
		log.Info("Construction", "Vanilla " .. tostring(message), data)
	end
end

local function PointHexString(pt)
	local world_to_hex = rawget(_G, "WorldToHex")
	if type(world_to_hex) ~= "function" or pt == nil then
		return tostring(pt)
	end

	local q, r = world_to_hex(pt)
	return tostring(q) .. "," .. tostring(r)
end

local function CountTableValues(values)
	if type(values) ~= "table" then
		return 0
	end
	return #values
end

local function StatusName(status)
	if type(status) == "table" then
		if status.id ~= nil then
			return tostring(status.id)
		end
		if status.name ~= nil then
			return tostring(status.name)
		end
		if status.text ~= nil then
			return tostring(status.text)
		end
	end
	return tostring(status)
end

local function StatusSummary(controller)
	local statuses = controller and controller.construction_statuses
	if type(statuses) ~= "table" or #statuses == 0 then
		return "none"
	end

	local parts = {}
	for i = 1, #statuses do
		parts[#parts + 1] = StatusName(statuses[i])
	end
	return table.concat(parts, "|")
end

local function HasOnlyIntermediateStatuses(controller)
	local construction_status = rawget(_G, "ConstructionStatus")
	local statuses = controller and controller.construction_statuses
	if type(construction_status) ~= "table" or type(statuses) ~= "table" or #statuses == 0 then
		return false
	end

	local has_intermediate = false
	for i = 1, #statuses do
		local status = statuses[i]
		if status == construction_status.PassageDomeRequired or status == construction_status.PassageRequiresTwoDomes then
			has_intermediate = true
		elseif status ~= construction_status.NoDroneHub then
			return false
		end
	end

	return has_intermediate
end

local function ShouldSnapPassagePoint(controller)
	local cfg = Config()
	return cfg.ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION == true
		and cfg.ENABLE_TILE_SNAPPED_CONTROL_POINTS == true
		and controller ~= nil
		and controller.mode == "passage_grid"
end

local function SnapPointToHexCenter(controller, pt)
	if pt == nil then
		return pt, false, "no_point"
	end

	local hex_get_nearest_center = rawget(_G, "HexGetNearestCenter")
	if type(hex_get_nearest_center) ~= "function" then
		return pt, false, "HexGetNearestCenter_unavailable"
	end

	local snapped = hex_get_nearest_center(pt)
	local fix_construct_pos = rawget(_G, "FixConstructPos")
	if type(fix_construct_pos) == "function" and controller ~= nil and type(controller.GetMap) == "function" then
		local map = controller:GetMap()
		if map ~= nil then
			snapped = fix_construct_pos(map, snapped)
		end
	end

	return snapped, true
end

local function PointsEqual2D(a, b)
	if a == nil or b == nil then
		return false
	end
	if a == b then
		return true
	end
	if type(a.Equal2D) == "function" then
		return a:Equal2D(b)
	end
	local world_to_hex = rawget(_G, "WorldToHex")
	if type(world_to_hex) == "function" then
		local aq, ar = world_to_hex(a)
		local bq, br = world_to_hex(b)
		return aq == bq and ar == br
	end
	return false
end

local function FindFixedPointIndex(controller, pt)
	local placed_points = controller and controller.placed_points
	if type(placed_points) ~= "table" or pt == nil then
		return false
	end

	for i = 2, #placed_points do
		if PointsEqual2D(placed_points[i], pt) then
			return i
		end
	end

	return false
end

local function CurrentPointsDuplicatePlacedTail(controller)
	local placed_points = controller and controller.placed_points
	local current_points = controller and controller.current_points
	if type(placed_points) ~= "table" or type(current_points) ~= "table" or #current_points == 0 then
		return true
	end
	if #placed_points < #current_points then
		return false
	end

	local j = 1
	for i = #placed_points - #current_points + 1, #placed_points do
		if PointsEqual2D(placed_points[i], current_points[j]) ~= true then
			return false
		end
		j = j + 1
	end

	return true
end

local function AppendCurrentPointsAsFixedBend(controller, clicked_pt)
	local cfg = Config()
	if cfg.ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION ~= true then
		return false, "feature_disabled"
	end
	if controller == nil or controller.mode ~= "passage_grid" or controller.starting_point == nil then
		return false, "not_active_passage_construction"
	end
	if type(controller.current_points) ~= "table" or #controller.current_points == 0 then
		return false, "no_current_points"
	end
	if CurrentPointsDuplicatePlacedTail(controller) == true then
		return false, "duplicate_current_points"
	end
	local current_len = controller.current_len or 0
	local max_len = controller.max_hex_distance_to_allow_build or 0
	if current_len >= max_len then
		return true, "length_limit_reached"
	end
	if HasOnlyIntermediateStatuses(controller) ~= true then
		return false, "non_intermediate_status"
	end

	local count = #controller.current_points
	table.iappend(controller.placed_points, controller.current_points)
	table.insert(controller.last_placed_points_count, count)
	controller.current_points = {}
	controller.last_update_hex = false

	if type(controller.UpdateVisuals) == "function" then
		controller:UpdateVisuals(clicked_pt)
	end

	DebugVanilla("Fixed snapped passage bend", {
		click_hex = PointHexString(clicked_pt),
		added_points = count,
		placed_points = CountTableValues(controller.placed_points),
		last_group_count = CountTableValues(controller.last_placed_points_count),
		current_len = controller.current_len,
		max_len = controller.max_hex_distance_to_allow_build,
		statuses = StatusSummary(controller),
	})

	return true, "bend_fixed"
end

local function RemovePointGroupsFrom(controller, point_index)
	local placed_points = controller.placed_points
	local counts = controller.last_placed_points_count
	if type(placed_points) ~= "table" then
		return 0, 0
	end

	local old_count = #placed_points

	if type(counts) == "table" and #counts > 0 then
		local new_counts = {}
		local segment_start = 2

		for i = 1, #counts do
			local count = counts[i] or 0
			local segment_end = segment_start + count - 1

			if point_index > segment_end then
				new_counts[#new_counts + 1] = count
				segment_start = segment_end + 1
			else
				local keep_count = point_index - segment_start
				if keep_count > 0 then
					new_counts[#new_counts + 1] = keep_count
				end
				break
			end
		end

		for i = #placed_points, point_index, -1 do
			placed_points[i] = nil
		end

		for i = #counts, 1, -1 do
			counts[i] = nil
		end
		for i = 1, #new_counts do
			counts[i] = new_counts[i]
		end
	else
		for i = #placed_points, point_index, -1 do
			placed_points[i] = nil
		end
	end

	if #placed_points < 1 and old_count > 0 then
		placed_points[1] = controller.starting_point
	end

	return old_count - #placed_points, #placed_points
end

local function RefreshPassagePreview(controller, pt)
	controller.current_points = {}
	controller.last_update_hex = false

	local get_terrain_pos = rawget(_G, "GetConstructionTerrainPos")
	local terrain_api = rawget(_G, "terrain")
	local map = type(controller.GetMap) == "function" and controller:GetMap() or nil
	local update_pt = pt

	if type(get_terrain_pos) == "function" then
		update_pt = get_terrain_pos(controller)
	end
	update_pt = SnapPointToHexCenter(controller, update_pt)

	if map ~= nil and terrain_api ~= nil and type(terrain_api.IsPointInBounds) == "function" then
		if terrain_api.IsPointInBounds(map, update_pt) ~= true then
			return false, "point_out_of_bounds"
		end
	end

	if type(controller.UpdateVisuals) ~= "function" then
		return false, "UpdateVisuals_unavailable"
	end

	controller:UpdateVisuals(update_pt)
	return true
end

function ConstructionRules.TryReleaseFixedPoint(controller, pt)
	local cfg = Config()
	if cfg.ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION ~= true or cfg.ENABLE_FIXED_POINT_RELEASE ~= true then
		return false, "feature_disabled"
	end
	if controller == nil or controller.mode ~= "passage_grid" or controller.starting_point == nil then
		return false, "not_active_passage_construction"
	end

	local snapped_pt = SnapPointToHexCenter(controller, pt)
	local point_index = FindFixedPointIndex(controller, snapped_pt)
	if point_index == false then
		return false, "no_fixed_point_at_click"
	end

	local removed_count, remaining_count = RemovePointGroupsFrom(controller, point_index)
	local refreshed, refresh_reason = RefreshPassagePreview(controller, snapped_pt)

	local log = Debug()
	if log then
		log.Info("Construction", "Released fixed passage point", {
			point_index = point_index,
			removed_count = removed_count,
			remaining_count = remaining_count,
			refreshed = refreshed,
			refresh_reason = refresh_reason,
		})
	end

	return true
end

local function ClearActivateState(st)
	st.original_activate = false
	st.patched_activate = false
	st.activate_patched = false
end

local function ClearUpdateCursorState(st)
	st.original_update_cursor = false
	st.patched_update_cursor = false
	st.update_cursor_patched = false
end

local function RestoreOwnedPatches(controller, reason)
	local st = State()
	local ok = true
	local log = Debug()

	if st.activate_patched == true then
		if type(controller) == "table" and controller.Activate == st.patched_activate then
			controller.Activate = st.original_activate
			ClearActivateState(st)
		else
			ok = false
			if log then
				log.Warn("Construction", "Activate restore skipped because current owner changed", {
					reason = reason,
				})
			end
		end
	end

	if st.update_cursor_patched == true then
		if type(controller) == "table" and controller.UpdateCursor == st.patched_update_cursor then
			controller.UpdateCursor = st.original_update_cursor
			ClearUpdateCursorState(st)
		else
			ok = false
			if log then
				log.Warn("Construction", "UpdateCursor restore skipped because current owner changed", {
					reason = reason,
				})
			end
		end
	end

	return ok
end

function ConstructionRules.ApplyModBehavior(reason)
	local st = State()
	local controller = rawget(_G, "GridConstructionController")
	if type(controller) ~= "table" or type(controller.Activate) ~= "function" or type(controller.UpdateCursor) ~= "function" then
		local log = Debug()
		if log then
			log.Warn("Construction", "Construction patches skipped: required GridConstructionController functions unavailable", {
				reason = reason,
				has_activate = type(controller) == "table" and type(controller.Activate) == "function",
				has_update_cursor = type(controller) == "table" and type(controller.UpdateCursor) == "function",
			})
		end
		return false, "required GridConstructionController functions unavailable"
	end

	if (st.activate_patched == true or st.update_cursor_patched == true)
		and RestoreOwnedPatches(controller, reason or "reapply") ~= true then
		return false, "construction patch owned by another mod"
	end

	local original_activate = controller.Activate
	local original_update_cursor = controller.UpdateCursor

	local patched_update_cursor = function(self, pt, ...)
		if ShouldSnapPassagePoint(self) == true then
			local snapped_pt = SnapPointToHexCenter(self, pt)
			return original_update_cursor(self, snapped_pt, ...)
		end
		return original_update_cursor(self, pt, ...)
	end

	local patched_activate = function(self, pt)
		local activate_pt = pt
		if ShouldSnapPassagePoint(self) == true then
			activate_pt = SnapPointToHexCenter(self, pt)
			if self.starting_point ~= nil and type(self.UpdateVisuals) == "function" then
				self.last_update_hex = false
				self:UpdateVisuals(activate_pt)
			end
		end

		if ShouldSnapPassagePoint(self) == true then
			local can_complete = type(self.CanCompletePassage) == "function" and self:CanCompletePassage() == true
			DebugVanilla("Passage Activate after snapped preview", {
				click_hex = PointHexString(activate_pt),
				started = self.starting_point ~= nil,
				can_complete = can_complete,
				current_points = CountTableValues(self.current_points),
				placed_points = CountTableValues(self.placed_points),
				current_len = self.current_len,
				max_len = self.max_hex_distance_to_allow_build,
				statuses = StatusSummary(self),
			})

			if self.starting_point ~= nil and can_complete ~= true then
				local fixed, fix_reason = AppendCurrentPointsAsFixedBend(self, activate_pt)
				DebugVanilla("Passage intermediate click decision", {
					click_hex = PointHexString(activate_pt),
					fixed = fixed,
					reason = fix_reason,
					current_points = CountTableValues(self.current_points),
					placed_points = CountTableValues(self.placed_points),
					current_len = self.current_len,
					max_len = self.max_hex_distance_to_allow_build,
					statuses = StatusSummary(self),
				})
				if fixed == true then
					return true
				end
			end
		end

		local result = original_activate(self, activate_pt)
		DebugVanilla("Activate returned", {
			click_hex = PointHexString(activate_pt),
			result = result,
			current_points = CountTableValues(self.current_points),
			placed_points = CountTableValues(self.placed_points),
			current_len = self.current_len,
			max_len = self.max_hex_distance_to_allow_build,
			statuses = StatusSummary(self),
		})
		return result
	end

	st.original_activate = original_activate
	st.patched_activate = patched_activate
	st.activate_patched = true
	st.original_update_cursor = original_update_cursor
	st.patched_update_cursor = patched_update_cursor
	st.update_cursor_patched = true
	controller.Activate = patched_activate
	controller.UpdateCursor = patched_update_cursor

	local log = Debug()
	if log then
		log.Info("Construction", "Installed GridConstructionController passage snapping patches", {
			reason = reason,
			enable_flexible_passage_construction = Config().ENABLE_FLEXIBLE_PASSAGE_CONSTRUCTION,
			enable_tile_snapped_control_points = Config().ENABLE_TILE_SNAPPED_CONTROL_POINTS,
			enable_fixed_point_release = Config().ENABLE_FIXED_POINT_RELEASE,
			debug_vanilla_construction = Config().DEBUG_VANILLA_CONSTRUCTION,
		})
	end

	return true
end

function ConstructionRules.RestoreVanillaBehavior(reason)
	local controller = rawget(_G, "GridConstructionController")
	local restored = RestoreOwnedPatches(controller, reason)
	local log = Debug()
	if log then
		log.Info("Construction", "Restore owned GridConstructionController patches requested", {
			reason = reason,
			restored = restored,
		})
	end
	return restored
end

FlexiblePassages.ConstructionRules = ConstructionRules
