-- MartianWaters -- water-tool mode and click handling.
--
-- The tool lives entirely in this module: the UI calls Tool.Activate() /
-- Tool.Deactivate() / Tool.AdjustLevel(delta_meters). When active, an
-- invisible XWindow overlay is attached to the HUD; left-clicks on terrain
-- become "place or select a water marker at the cursor" actions. When
-- inactive, the overlay is destroyed so normal game input is untouched.
--
-- "Most recently placed" rule: each placement (or click-within-radius select)
-- sets MartianWaters.State.current_marker. The +/- buttons in the UI act on that
-- marker by calling Water.SetMarkerLevel with (ground + level_meters * guim).
--
-- Public API (used by mw_ui.lua):
--   MartianWaters.Tool.IsActive()        -> bool
--   MartianWaters.Tool.Activate()        -> bool, err
--   MartianWaters.Tool.Deactivate()
--   MartianWaters.Tool.Toggle()
--   MartianWaters.Tool.AdjustLevel(d_m)  -> new_level_m or nil, err
--   MartianWaters.Tool.GetCurrentLevel() -> meters_above_ground or nil
--   MartianWaters.Tool.PlaceAtCursor()   -> segment_id or nil, err  (used by tests)

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Tool"

local Tool = {}

local OVERLAY_ID = "MartianWatersWaterToolOverlay"

local function config()
	return MartianWaters.Config or {}
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
	MartianWaters.State.current_marker = obj or false
	MartianWaters.State.current_marker_segment = seg_id or false
end

local function clear_current()
	MartianWaters.State.current_marker = false
	MartianWaters.State.current_marker_segment = false
end

local function find_nearby_segment(map, click_pt, radius_wu)
	if radius_wu <= 0 then
		return nil
	end
	local best_id, best_seg, best_dist2
	for id, seg in pairs(MartianWaters.State.segments) do
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

-- Used by the overlay's OnMouseButtonDown and by MartianWaters.Tool.PlaceAtCursor.
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

	-- Don't stack a new body on a tile that already has water (the sea, or
	-- another lake): water bodies must not overlap. We read the live water grid
	-- via the depth sampler -- anything wetter than "dry" here is rejected.
	if MartianWaters.Depth and type(MartianWaters.Depth.SampleAt) == "function" then
		local depth_m = MartianWaters.Depth.SampleAt(map, click_pt)
		if type(depth_m) == "number" and depth_m > 0 then
			DebugLog.Info(SCOPE, "placement blocked: already underwater", {
				x = click_pt:x(), y = click_pt:y(), depth_m = depth_m,
			})
			return nil, "can't place water here -- this spot is already underwater"
		end
	end

	-- New marker: drop one at the click point. Use a single-point "path" so the
	-- existing API/state-tracking path keeps working. The carve module is NOT
	-- invoked here; we only place a TerrainWaterObject.
	local Water = MartianWaters.Water
	if not Water then
		return nil, "MartianWaters.Water module not loaded"
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
	local id = MartianWaters.State:RegisterSegment({
		water_obj = obj,
		bbox = bbox,
		floor_wu = floor_wu,
		marker_x = click_pt:x(),
		marker_y = click_pt:y(),
		spill_level_m = start_level_m,
		bowl_area_wu2 = bowl_area_wu2,
		discharge_m3s = cfg.HYDRO_INITIAL_DISCHARGE_M3S or 0,
		drainage_m3s = cfg.HYDRO_INITIAL_DRAINAGE_M3S or 0,
		evaporation_m3s = cfg.HYDRO_INITIAL_EVAPORATION_M3S or 0,
		infiltration_m3s = cfg.HYDRO_INITIAL_INFILTRATION_M3S or 0,
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

-- Read a numeric field off the current segment, or nil if there's no current
-- marker. Used by the UI to populate the live input fields + readouts.
local function get_current_field(field)
	local seg_id = MartianWaters.State.current_marker_segment
	if not seg_id then return nil end
	local seg = MartianWaters.State.segments[seg_id]
	if not seg then return nil end
	return seg[field] or 0
end

function Tool.GetCurrentDischarge() return get_current_field("discharge_m3s") end
function Tool.GetCurrentDrainage() return get_current_field("drainage_m3s") end
function Tool.GetCurrentEvaporation() return get_current_field("evaporation_m3s") end
function Tool.GetCurrentInfiltration() return get_current_field("infiltration_m3s") end
function Tool.GetCurrentLevel() return get_current_field("actual_level_m") end
function Tool.GetCurrentVolume() return get_current_field("volume_m3") end
function Tool.GetCurrentFloodedAreaWu2() return get_current_field("flooded_area_wu2") end

function Tool.GetCurrentDepthClass()
	local seg_id = MartianWaters.State.current_marker_segment
	if not seg_id then return nil end
	local seg = MartianWaters.State.segments[seg_id]
	if not seg or not MartianWaters.Depth then return nil end
	return MartianWaters.Depth.Classify(seg.actual_level_m or 0)
end

-- Route a Budget setter/adjuster to the current segment. All the field controls
-- (inflow/drainage/evaporation/infiltration discharge rates AND the instant
-- height level) share this: validate there's a live marker, then call the named
-- MartianWaters.Budget function with (seg_id, value). The budget ticker drives the
-- actual water level from the rates; SetLevel/AdjustLevel snap it instantly.
local function route(budget_fn_name, value)
	local seg_id = MartianWaters.State.current_marker_segment
	if not seg_id then
		return nil, "no current marker (click a hole first)"
	end
	local seg = MartianWaters.State.segments[seg_id]
	if not seg or not seg.water_obj or not IsValid(seg.water_obj) then
		clear_current()
		return nil, "current marker is gone"
	end
	local fn = MartianWaters.Budget and MartianWaters.Budget[budget_fn_name]
	if type(fn) ~= "function" then
		return nil, "MartianWaters.Budget module not loaded"
	end
	return fn(seg_id, value or 0)
end

-- Sea-level controls operate on "the sea" (not the current marker), so they go
-- straight to MartianWaters.Sea rather than through route(). No-op if no sea exists.
function Tool.GetSeaLevel()
	return MartianWaters.Sea and MartianWaters.Sea.GetLevel and MartianWaters.Sea.GetLevel() or nil
end
function Tool.SetSeaLevel(v)
	if not (MartianWaters.Sea and MartianWaters.Sea.SetLevelOrGenerate) then return nil, "MartianWaters.Sea not loaded" end
	return MartianWaters.Sea.SetLevelOrGenerate(v)
end
function Tool.AdjustSeaLevel(d)
	if not (MartianWaters.Sea and MartianWaters.Sea.AdjustLevel) then return nil, "MartianWaters.Sea not loaded" end
	return MartianWaters.Sea.AdjustLevel(d)
end

-- Cloud controls operate on the global sky (not a marker, not the sea), so they
-- delegate straight to MartianWaters.Clouds. No-op-safe if the module is missing.
function Tool.AreCloudShadowsEnabled()
	return MartianWaters.Clouds and MartianWaters.Clouds.AreShadowsEnabled and MartianWaters.Clouds.AreShadowsEnabled() or false
end
function Tool.ToggleCloudShadows()
	if not (MartianWaters.Clouds and MartianWaters.Clouds.ToggleShadows) then return nil, "MartianWaters.Clouds not loaded" end
	return MartianWaters.Clouds.ToggleShadows()
end
function Tool.GetCloudCoverage()
	return MartianWaters.Clouds and MartianWaters.Clouds.GetCoveragePct and MartianWaters.Clouds.GetCoveragePct() or nil
end
function Tool.SetCloudCoverage(v)
	if not (MartianWaters.Clouds and MartianWaters.Clouds.SetCoveragePct) then return nil, "MartianWaters.Clouds not loaded" end
	return MartianWaters.Clouds.SetCoveragePct(v)
end
function Tool.AdjustCloudCoverage(d)
	if not (MartianWaters.Clouds and MartianWaters.Clouds.AdjustCoveragePct) then return nil, "MartianWaters.Clouds not loaded" end
	return MartianWaters.Clouds.AdjustCoveragePct(d)
end
function Tool.GetCloudSpeed()
	return MartianWaters.Clouds and MartianWaters.Clouds.GetSpeedM and MartianWaters.Clouds.GetSpeedM() or nil
end
function Tool.SetCloudSpeed(v)
	if not (MartianWaters.Clouds and MartianWaters.Clouds.SetSpeedM) then return nil, "MartianWaters.Clouds not loaded" end
	return MartianWaters.Clouds.SetSpeedM(v)
end
function Tool.AdjustCloudSpeed(d)
	if not (MartianWaters.Clouds and MartianWaters.Clouds.AdjustSpeedM) then return nil, "MartianWaters.Clouds not loaded" end
	return MartianWaters.Clouds.AdjustSpeedM(d)
end

function Tool.SetDischarge(v) return route("SetDischarge", v) end
function Tool.AdjustDischarge(d) return route("AdjustDischarge", d) end
function Tool.SetDrainage(v) return route("SetDrainage", v) end
function Tool.AdjustDrainage(d) return route("AdjustDrainage", d) end
function Tool.SetEvaporation(v) return route("SetEvaporation", v) end
function Tool.AdjustEvaporation(d) return route("AdjustEvaporation", d) end
function Tool.SetInfiltration(v) return route("SetInfiltration", v) end
function Tool.AdjustInfiltration(d) return route("AdjustInfiltration", d) end
function Tool.SetLevel(v) return route("SetLevel", v) end
function Tool.AdjustLevel(d) return route("AdjustLevel", d) end

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
	local overlay = MartianWaters.State.tool_overlay
	if overlay and is_window_alive(overlay) then
		pcall(function()
			if overlay.delete then overlay:delete()
			elseif overlay.Close then overlay:Close()
			end
		end)
	end
	MartianWaters.State.tool_overlay = false
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
	-- The overlay covers the screen but is BELOW the MartianWaters panel (which uses a
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
	MartianWaters.State.tool_overlay = overlay
	return overlay
end

-- ----------------------------------------------------------------------------
-- Activate / Deactivate / Toggle
-- ----------------------------------------------------------------------------

function Tool.IsActive()
	return MartianWaters.State.tool_active == true
end

function Tool.Activate()
	if config().ENABLE_MOD ~= true then
		return false, "MartianWaters mod disabled in config"
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
	MartianWaters.State.tool_active = true
	DebugLog.Info(SCOPE, "activated")
	if MartianWaters.UI and type(MartianWaters.UI.Refresh) == "function" then
		MartianWaters.UI.Refresh()
	end
	return true
end

function Tool.Deactivate()
	if not Tool.IsActive() then
		return
	end
	destroy_overlay()
	MartianWaters.State.tool_active = false
	DebugLog.Info(SCOPE, "deactivated")
	if MartianWaters.UI and type(MartianWaters.UI.Refresh) == "function" then
		MartianWaters.UI.Refresh()
	end
end

function Tool.Toggle()
	if Tool.IsActive() then
		Tool.Deactivate()
	else
		Tool.Activate()
	end
end

-- Called by mw_lifecycle.lua on OnMsg.DoneMap to drop overlay + current marker.
function Tool.OnMapUnloaded()
	destroy_overlay()
	MartianWaters.State.tool_active = false
	clear_current()
end

MartianWaters.Tool = Tool
