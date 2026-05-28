-- Rivers -- right-side "Water Tool" panel.
--
-- Layout:
--   ┌────────────────────────────┐
--   │      RIVERS WATER TOOL     │   <- title
--   ├────────────────────────────┤
--   │  [ Activate Water Mode ]   │   <- toggle (changes label when active)
--   │                            │
--   │  Water level: N m          │   <- current marker's level
--   │  [ - ]            [ + ]    │   <- step buttons
--   │                            │
--   │  [ Clear All Water ]       │
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

local function update_level_label()
	local label = Rivers.State.ui_level_label
	if not is_window_alive(label) then return end
	local Tool = Rivers.Tool
	local level = Tool and Tool.GetCurrentLevel() or nil
	local text
	if level then
		text = "Water level: " .. tostring(level) .. " m"
	else
		text = "Water level: -- (click a hole)"
	end
	pcall(function() label:SetText(text) end)
end

function UI.Refresh()
	update_toggle_visual()
	update_level_label()
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
		Text = "RIVERS WATER TOOL",
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

	-- Level label
	local level_label = x_label:new({
		Text = "Water level: -- (click a hole)",
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
		local step = (Rivers.Config and Rivers.Config.WATER_TOOL_STEP_METERS) or 1
		Rivers.Tool.AdjustLevel(-step)
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120 })

	make_button(minus_plus_row, "  +  ", function()
		if not Rivers.Tool then return end
		local step = (Rivers.Config and Rivers.Config.WATER_TOOL_STEP_METERS) or 1
		Rivers.Tool.AdjustLevel(step)
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120 })

	-- Clear All
	make_button(panel, "Clear All Water", function()
		if type(Rivers.ClearAll) == "function" then
			Rivers.ClearAll()
		end
		UI.Refresh()
	end)

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
