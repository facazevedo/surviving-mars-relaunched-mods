-- Rivers -- right-side panel hosting the water tool and the rain buttons.
--
-- Layout:
--   ┌────────────────────────────┐
--   │           RIVERS           │   <- title
--   ├────────────────────────────┤
--   │  [ Activate Water Mode ]   │   <- toggle (changes label when active)
--   │  flow N m^3/s | lvl N m... │   <- current source: discharge, level, class, flooded tiles
--   │  [ - ]            [ + ]    │   <- discharge -/+ (m^3/s, step = HYDRO_DISCHARGE_STEP_M3S)
--   │  [ Clear All Water ]       │
--   │                            │
--   │           RAIN             │   <- section label
--   │  Rain: none                │   <- status (disaster preset / visual on)
--   │  [ Start Rain ] [ Stop ]   │   <- disaster start/stop
--   │  [ Visual On ] [ Off ]     │   <- visual override start/stop
--   └────────────────────────────┘
--
-- Lifecycle:
--   Rivers.UI.Show()      -- (re)create the panel and attach to GetHUD()
--   Rivers.UI.Hide()      -- destroy the panel
--   Rivers.UI.Refresh()   -- update labels (called by r_tool when state changes)
--
-- The panel is created on OnMsg.NewMapLoaded by r_lifecycle.lua and destroyed
-- on OnMsg.DoneMap. It is NOT shown on the main menu.

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	return
end

local DebugLog = Rivers.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "UI"

local UI = {}

local PANEL_ID = "RiversWaterToolPanel"

-- Colors / sizing borrowed from scenario-editor's panel for visual consistency.
local PANEL_BACKGROUND = RGBA(0, 0, 0, 190)
local BUTTON_BACKGROUND = RGBA(30, 40, 45, 230)
local BUTTON_ROLLOVER = RGBA(55, 70, 78, 240)
local BUTTON_ACTIVE = RGBA(80, 130, 90, 240)
local TEXT_COLOR = RGB(255, 255, 255)
local ROW_HEIGHT = 28
local ROW_SPACING = 4

local function is_window_alive(win)
	if not win then return false end
	if type(win.window_state) == "string" then
		return win.window_state ~= "destroying"
	end
	return true
end

local function get_panel_parent()
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

local function destroy_panel()
	local panel = Rivers.State.ui_panel
	if panel and is_window_alive(panel) then
		pcall(function()
			if panel.delete then panel:delete()
			elseif panel.Close then panel:Close()
			end
		end)
	end
	Rivers.State.ui_panel = false
	Rivers.State.ui_toggle_button = false
	Rivers.State.ui_level_label = false
	Rivers.State.ui_rain_label = false
end

local function update_toggle_visual()
	local btn = Rivers.State.ui_toggle_button
	if not is_window_alive(btn) then return end
	local Tool = Rivers.Tool
	local active = Tool and Tool.IsActive() == true or false
	local label = active and "Water Mode: ON  (click a hole)" or "Activate Water Mode"
	pcall(function() btn:SetText(label) end)
	pcall(function() btn:SetBackground(active and BUTTON_ACTIVE or BUTTON_BACKGROUND) end)
end

local function format_float(n, decimals)
	if type(n) ~= "number" then return "--" end
	local mult = 10 ^ (decimals or 2)
	local r = math.floor(n * mult + 0.5) / mult
	return tostring(r)
end

local function update_level_label()
	local label = Rivers.State.ui_level_label
	if not is_window_alive(label) then return end
	local Tool = Rivers.Tool
	if not (Tool and Tool.GetCurrentDischarge) then
		pcall(function() label:SetText("Click a hole to start") end)
		return
	end
	local discharge = Tool.GetCurrentDischarge()
	if not discharge then
		pcall(function() label:SetText("Click a hole to start") end)
		return
	end
	local level = Tool.GetCurrentLevel() or 0
	local class = Tool.GetCurrentDepthClass() or "dry"
	local seg_id = Rivers.State.current_marker_segment
	local seg = seg_id and Rivers.State.segments[seg_id] or nil
	local tiles = seg and seg.flooded_tile_count or 0
	local text = "flow " .. format_float(discharge, 2) .. " m^3/s  |  level " ..
		format_float(level, 2) .. " m (" .. class .. ")  |  flooded " .. tostring(tiles) .. " tiles"
	pcall(function() label:SetText(text) end)
end

local function update_rain_label()
	local label = Rivers.State.ui_rain_label
	if not is_window_alive(label) then return end
	local Rain = Rivers.Rain
	local parts = {}
	local disaster = Rain and Rain.GetDisasterType() or nil
	if disaster then
		parts[#parts + 1] = "disaster=" .. tostring(disaster)
	end
	if Rain and Rain.IsVisualActive() then
		parts[#parts + 1] = "visual=on"
	end
	local text = "Rain: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
	pcall(function() label:SetText(text) end)
end

function UI.Refresh()
	update_toggle_visual()
	update_level_label()
	update_rain_label()
end

-- ----------------------------------------------------------------------------
-- Button factory
-- ----------------------------------------------------------------------------

local function make_button(parent, label, on_press, opts)
	opts = opts or {}
	local x_button = rawget(_G, "XTextButton")
	if not x_button then return nil end
	local btn = x_button:new({
		Text = label,
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = TEXT_COLOR,
		RolloverTextColor = TEXT_COLOR,
		PressedTextColor = TEXT_COLOR,
		HAlign = opts.halign or "stretch",
		MinWidth = opts.min_width or 220,
		MaxWidth = opts.max_width or 260,
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
		Padding = box(6, 2, 6, 2),
		Background = BUTTON_BACKGROUND,
		FocusedBackground = BUTTON_ROLLOVER,
		RolloverBackground = BUTTON_ROLLOVER,
		PressedBackground = BUTTON_ROLLOVER,
	}, parent)
	btn.OnPress = function() pcall(on_press) end
	return btn
end

-- ----------------------------------------------------------------------------
-- Show / Hide
-- ----------------------------------------------------------------------------

function UI.Show()
	destroy_panel()
	local parent = get_panel_parent()
	if not parent then
		DebugLog.Warn(SCOPE, "Show: no HUD parent yet")
		return false
	end
	local x_dialog = rawget(_G, "XDialog")
	local x_label = rawget(_G, "XLabel")
	local x_window = rawget(_G, "XWindow")
	if not x_dialog or not x_label or not x_window then
		DebugLog.Warn(SCOPE, "Show: required X-classes unavailable", {
			XDialog = x_dialog and "yes" or "no",
			XLabel = x_label and "yes" or "no",
			XWindow = x_window and "yes" or "no",
		})
		return false
	end

	-- Match scenario-editor's anchor: top-right, with a vertical margin below
	-- the resource bar so we don't collide with vanilla HUD chrome.
	local panel = x_dialog:new({
		Id = PANEL_ID,
		ZOrder = 9900,
		IdNode = true,
		Dock = "box",
		HAlign = "right",
		VAlign = "top",
		Margins = box(0, 320, 18, 0),
		Padding = box(8, 8, 8, 8),
		LayoutMethod = "VList",
		LayoutVSpacing = ROW_SPACING,
		Background = PANEL_BACKGROUND,
		FocusedBackground = PANEL_BACKGROUND,
		HandleMouse = true,
		ChildrenHandleMouse = true,
	}, parent)

	x_label:new({
		Text = "RIVERS",
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)

	-- Toggle button
	local toggle = make_button(panel, "Activate Water Mode", function()
		if Rivers.Tool then Rivers.Tool.Toggle() end
	end)
	Rivers.State.ui_toggle_button = toggle

	-- Status label (filled in by update_level_label on Refresh)
	local level_label = x_label:new({
		Text = "Click a hole to start",
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)
	Rivers.State.ui_level_label = level_label

	-- +/- row
	local minus_plus_row = x_window:new({
		Id = "RiversLevelRow",
		LayoutMethod = "HList",
		LayoutHSpacing = 8,
		HAlign = "stretch",
		MinWidth = 220,
		MaxWidth = 260,
	}, panel)

	make_button(minus_plus_row, "  -  ", function()
		if not Rivers.Tool then return end
		local step = (Rivers.Config and Rivers.Config.HYDRO_DISCHARGE_STEP_M3S) or 0.5
		Rivers.Tool.AdjustDischarge(-step)
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120 })

	make_button(minus_plus_row, "  +  ", function()
		if not Rivers.Tool then return end
		local step = (Rivers.Config and Rivers.Config.HYDRO_DISCHARGE_STEP_M3S) or 0.5
		Rivers.Tool.AdjustDischarge(step)
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120 })

	-- Clear All
	make_button(panel, "Clear All Water", function()
		if type(Rivers.ClearAll) == "function" then
			Rivers.ClearAll()
		end
		UI.Refresh()
	end)

	-- Rain section
	x_label:new({
		Text = "RAIN",
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)

	local rain_label = x_label:new({
		Text = "Rain: none",
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)
	Rivers.State.ui_rain_label = rain_label

	-- Disaster row: Start uses Rivers.Config.DEFAULT_RAIN_PRESET.
	local disaster_row = x_window:new({
		Id = "RiversRainDisasterRow",
		LayoutMethod = "HList",
		LayoutHSpacing = 8,
		HAlign = "stretch",
		MinWidth = 220,
		MaxWidth = 260,
	}, panel)

	make_button(disaster_row, "Start Rain", function()
		if Rivers.Rain then Rivers.Rain.StartDisaster() end
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120 })

	make_button(disaster_row, "Stop Rain", function()
		if Rivers.Rain then Rivers.Rain.StopDisaster() end
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120 })

	-- Visual row: cosmetic-only override.
	local visual_row = x_window:new({
		Id = "RiversRainVisualRow",
		LayoutMethod = "HList",
		LayoutHSpacing = 8,
		HAlign = "stretch",
		MinWidth = 220,
		MaxWidth = 260,
	}, panel)

	make_button(visual_row, "Visual On", function()
		if Rivers.Rain then Rivers.Rain.StartVisual() end
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120 })

	make_button(visual_row, "Visual Off", function()
		if Rivers.Rain then Rivers.Rain.StopVisual() end
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120 })

	Rivers.State.ui_panel = panel
	UI.Refresh()
	DebugLog.Info(SCOPE, "panel shown")
	return panel
end

function UI.Hide()
	-- Make sure the tool is off (tears down the click overlay too) before hiding.
	if Rivers.Tool and Rivers.Tool.IsActive() then
		Rivers.Tool.Deactivate()
	end
	destroy_panel()
	DebugLog.Info(SCOPE, "panel hidden")
end

Rivers.UI = UI
