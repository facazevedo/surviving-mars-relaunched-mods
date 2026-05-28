-- Rivers -- water-tool mode and click handling.
--
-- The tool lives entirely in this module: the UI calls Tool.Activate() /
-- Tool.Deactivate() / Tool.AdjustLevel(delta_meters). When active, an
-- invisible XWindow overlay is attached to the HUD; left-clicks on terrain
-- become "place or select a water marker at the cursor" actions. When
-- inactive, the overlay is destroyed so normal game input is untouched.
--
-- "Most recently placed" rule: each placement (or click-within-radius select)
-- sets Rivers.State.current_marker. The +/- buttons in the UI act on that
-- marker by calling Water.SetMarkerLevel with (ground + level_meters * guim).
--
-- Public API (used by r_ui.lua):
--   Rivers.Tool.IsActive()        -> bool
--   Rivers.Tool.Activate()        -> bool, err
--   Rivers.Tool.Deactivate()
--   Rivers.Tool.Toggle()
--   Rivers.Tool.AdjustLevel(d_m)  -> new_level_m or nil, err
--   Rivers.Tool.GetCurrentLevel() -> meters_above_ground or nil
--   Rivers.Tool.PlaceAtCursor()   -> segment_id or nil, err  (used by tests)

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	return
end

local DebugLog = Rivers.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Tool"

local Tool = {}

local OVERLAY_ID = "RiversWaterToolOverlay"

local function config()
	return Rivers.Config or {}
end

local function meters_to_wu(m)
	return MulDivRound(m, guim, 1)
end

local function wu_to_meters(wu)
	return MulDivRound(wu, 1, guim)
end

local function current_map()
	return rawget(_G, "CurrentMap")
end

local function is_window_alive(win)
	if not win then return false end
	if type(win.window_state) == "string" then
		return win.window_state ~= "destroying"
	end
	return true
end

-- ----------------------------------------------------------------------------
-- State accessors
-- ----------------------------------------------------------------------------

local function set_current(seg_id, obj)
	Rivers.State.current_marker = obj or false
	Rivers.State.current_marker_segment = seg_id or false
end

local function clear_current()
	Rivers.State.current_marker = false
	Rivers.State.current_marker_segment = false
end

local function find_nearby_segment(map, click_pt, radius_wu)
	if radius_wu <= 0 then
		return nil
	end
	local best_id, best_seg, best_dist2
	for id, seg in pairs(Rivers.State.segments) do
		if seg.water_obj and IsValid(seg.water_obj) then
			local dx = seg.marker_x - click_pt:x()
			local dy = seg.marker_y - click_pt:y()
			local d2 = dx * dx + dy * dy
			if d2 <= radius_wu * radius_wu and (not best_dist2 or d2 < best_dist2) then
				best_id, best_seg, best_dist2 = id, seg, d2
			end
		end
	end
	return best_id, best_seg
end

-- ----------------------------------------------------------------------------
-- Placement
-- ----------------------------------------------------------------------------

-- Used by the overlay's OnMouseButtonDown and by Rivers.Tool.PlaceAtCursor.
-- click_pt is a point() in world units. Returns segment_id or (nil, err).
local function place_or_select_at(click_pt)
	local map = current_map()
	if not map then
		return nil, "no current map"
	end

	local cfg = config()
	local select_radius_wu = meters_to_wu(cfg.WATER_TOOL_SELECT_RADIUS_M or 0)
	local nearby_id, nearby_seg = find_nearby_segment(map, click_pt, select_radius_wu)
	if nearby_seg then
		set_current(nearby_id, nearby_seg.water_obj)
		DebugLog.Info(SCOPE, "selected existing marker", {
			id = nearby_id,
			discharge_m3s = nearby_seg.discharge_m3s,
		})
		return nearby_id
	end

	-- New marker: drop one at the click point. Use a single-point "path" so the
	-- existing API/state-tracking path keeps working. The carve module is NOT
	-- invoked here; we only place a TerrainWaterObject.
	local Water = Rivers.Water
	if not Water then
		return nil, "Rivers.Water module not loaded"
	end

	local ground_wu = terrain.GetHeight(map, click_pt)
	local start_level_m = cfg.WATER_TOOL_START_LEVEL_METERS or 5
	local floor_wu = ground_wu
	-- bbox: a small box around the click. The engine expands it as needed when
	-- ApplyAllWaterObjects walks neighboring water objects.
	local radius_wu = meters_to_wu(cfg.DEFAULT_WIDTH_METERS or 30)
	local bbox = box(click_pt:x() - radius_wu, click_pt:y() - radius_wu, click_pt:x() + radius_wu, click_pt:y() + radius_wu)

	local obj, err = Water.PlaceMarker(map, click_pt, floor_wu, start_level_m, bbox)
	if not obj then
		return nil, err
	end

	-- Budget seed for a click-placed source. There's no real carved bowl here,
	-- so "spill" is set to start_level_m (the level the click visually places),
	-- and the bowl area is approximated from the bbox. The initial volume is
	-- whatever fills the bowl to start_level_m so the marker appears full at
	-- placement instead of slowly rising.
	local bowl_area_wu2 = (2 * radius_wu) * (2 * radius_wu)
	local bowl_area_m2 = bowl_area_wu2 / (guim * guim)
	local initial_volume_m3 = bowl_area_m2 * start_level_m
	local initial_discharge = cfg.HYDRO_INITIAL_DISCHARGE_M3S or 0

	local id = Rivers.State:RegisterSegment({
		water_obj = obj,
		bbox = bbox,
		floor_wu = floor_wu,
		marker_x = click_pt:x(),
		marker_y = click_pt:y(),
		spill_level_m = start_level_m,
		bowl_area_wu2 = bowl_area_wu2,
		discharge_m3s = initial_discharge,
		volume_m3 = initial_volume_m3,
		actual_level_m = start_level_m,
		flooded_tile_count = 0,
		flooded_area_wu2 = 0,
		surface_area_wu2 = 0,
	})
	set_current(id, obj)
	DebugLog.Info(SCOPE, "placed new marker", {
		id = id,
		level_m = start_level_m,
		discharge_m3s = initial_discharge,
		x = click_pt:x(),
		y = click_pt:y(),
	})
	return id
end

function Tool.PlaceAtCursor()
	local get_cursor = rawget(_G, "GetTerrainCursor")
	if type(get_cursor) ~= "function" then
		return nil, "GetTerrainCursor unavailable"
	end
	local pt = get_cursor()
	if not pt then
		return nil, "cursor returned nil"
	end
	return place_or_select_at(pt)
end

-- ----------------------------------------------------------------------------
-- + / - adjustments on the most-recent marker
-- ----------------------------------------------------------------------------

function Tool.GetCurrentDischarge()
	local seg_id = Rivers.State.current_marker_segment
	if not seg_id then return nil end
	local seg = Rivers.State.segments[seg_id]
	if not seg then return nil end
	return seg.discharge_m3s or 0
end

function Tool.GetCurrentLevel()
	local seg_id = Rivers.State.current_marker_segment
	if not seg_id then return nil end
	local seg = Rivers.State.segments[seg_id]
	if not seg then return nil end
	return seg.actual_level_m or 0
end

function Tool.GetCurrentDepthClass()
	local seg_id = Rivers.State.current_marker_segment
	if not seg_id then return nil end
	local seg = Rivers.State.segments[seg_id]
	if not seg or not Rivers.Depth then return nil end
	return Rivers.Depth.Classify(seg.actual_level_m or 0)
end

-- The +/- buttons now adjust source discharge (m^3/s). The actual water level
-- is driven by the budget ticker, not by this call.
function Tool.AdjustDischarge(delta_m3s)
	local seg_id = Rivers.State.current_marker_segment
	if not seg_id then
		return nil, "no current marker (click a hole first)"
	end
	local seg = Rivers.State.segments[seg_id]
	if not seg or not seg.water_obj or not IsValid(seg.water_obj) then
		clear_current()
		return nil, "current marker is gone"
	end
	if not Rivers.Budget or type(Rivers.Budget.AdjustDischarge) ~= "function" then
		return nil, "Rivers.Budget module not loaded"
	end
	return Rivers.Budget.AdjustDischarge(seg_id, delta_m3s or 0)
end

-- Used by the UI flow input field when the player types a number and hits
-- Enter. value_m3s is clamped to >= 0 by Budget.SetDischarge.
function Tool.SetDischarge(value_m3s)
	local seg_id = Rivers.State.current_marker_segment
	if not seg_id then
		return nil, "no current marker (click a hole first)"
	end
	local seg = Rivers.State.segments[seg_id]
	if not seg or not seg.water_obj or not IsValid(seg.water_obj) then
		clear_current()
		return nil, "current marker is gone"
	end
	if not Rivers.Budget or type(Rivers.Budget.SetDischarge) ~= "function" then
		return nil, "Rivers.Budget module not loaded"
	end
	return Rivers.Budget.SetDischarge(seg_id, value_m3s or 0)
end

-- ----------------------------------------------------------------------------
-- Overlay (only exists while tool is active)
-- ----------------------------------------------------------------------------

local function get_overlay_parent()
	local get_hud = rawget(_G, "GetHUD")
	if type(get_hud) == "function" then
		local ok, hud = pcall(get_hud)
		if ok and is_window_alive(hud) then
			return hud
		end
	end
	local terminal_table = rawget(_G, "terminal")
	if terminal_table and is_window_alive(terminal_table.desktop) then
		return terminal_table.desktop
	end
	return nil
end

local function destroy_overlay()
	local overlay = Rivers.State.tool_overlay
	if overlay and is_window_alive(overlay) then
		pcall(function()
			if overlay.delete then overlay:delete()
			elseif overlay.Close then overlay:Close()
			end
		end)
	end
	Rivers.State.tool_overlay = false
end

local function create_overlay()
	destroy_overlay()
	local parent = get_overlay_parent()
	if not parent then
		return false, "no HUD parent for overlay"
	end
	local x_window = rawget(_G, "XWindow")
	if not x_window then
		return false, "XWindow class unavailable"
	end
	-- The overlay covers the screen but is BELOW the Rivers panel (which uses a
	-- higher ZOrder). Clicks on the panel itself are consumed by the panel and
	-- never reach the overlay. Clicks anywhere else fall to the overlay, which
	-- reads the terrain cursor and drops/selects a marker there.
	local overlay = x_window:new({
		Id = OVERLAY_ID,
		ZOrder = 9890,
		Dock = "box",
		HandleMouse = true,
		ChildrenHandleMouse = false,
		HandleKeyboard = true,
	}, parent)
	overlay.OnMouseButtonDown = function(self, _, button)
		if button == "L" then
			local get_cursor = rawget(_G, "GetTerrainCursor")
			if type(get_cursor) ~= "function" then
				return "continue"
			end
			local pt = get_cursor()
			if not pt then
				return "continue"
			end
			place_or_select_at(pt)
			return "break"
		end
		return "continue"
	end
	overlay.OnKbdKeyDown = function(_, virtual_key, repeated)
		if repeated then return "continue" end
		local const_table = rawget(_G, "const") or {}
		if virtual_key == const_table.vkEscape then
			Tool.Deactivate()
			return "break"
		end
		return "continue"
	end
	if type(overlay.SetFocus) == "function" then
		pcall(function() overlay:SetFocus(true) end)
	end
	Rivers.State.tool_overlay = overlay
	return overlay
end

-- ----------------------------------------------------------------------------
-- Activate / Deactivate / Toggle
-- ----------------------------------------------------------------------------

function Tool.IsActive()
	return Rivers.State.tool_active == true
end

function Tool.Activate()
	if config().ENABLE_MOD ~= true then
		return false, "Rivers mod disabled in config"
	end
	if not current_map() then
		return false, "no current map (start or load a game first)"
	end
	if Tool.IsActive() then
		return true
	end
	local overlay, err = create_overlay()
	if not overlay then
		return false, err
	end
	Rivers.State.tool_active = true
	DebugLog.Info(SCOPE, "activated")
	if Rivers.UI and type(Rivers.UI.Refresh) == "function" then
		Rivers.UI.Refresh()
	end
	return true
end

function Tool.Deactivate()
	if not Tool.IsActive() then
		return
	end
	destroy_overlay()
	Rivers.State.tool_active = false
	DebugLog.Info(SCOPE, "deactivated")
	if Rivers.UI and type(Rivers.UI.Refresh) == "function" then
		Rivers.UI.Refresh()
	end
end

function Tool.Toggle()
	if Tool.IsActive() then
		Tool.Deactivate()
	else
		Tool.Activate()
	end
end

-- Called by r_lifecycle.lua on OnMsg.DoneMap to drop overlay + current marker.
function Tool.OnMapUnloaded()
	destroy_overlay()
	Rivers.State.tool_active = false
	clear_current()
end

Rivers.Tool = Tool
