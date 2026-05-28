-- Rivers -- right-side panel hosting the water tool and the rain buttons.
--
-- Layout:
--   ┌────────────────────────────┐
--   │           RIVERS           │   <- title
--   ├────────────────────────────┤
--   │  [ Activate Water Mode ]   │   <- toggle (changes label when active)
--   │  source depth: shallow     │   <- status: depth class at the source
--   │  height (lvl): [__] [-][+] │   <- instant water level in m (live)
--   │  inflow:       [__] [-][+] │   <- source discharge in m^3/s (live)
--   │  drainage:     [__] [-][+] │   <- player drain in m^3/s (live)
--   │  evaporation:  [__] [-][+] │   <- evaporation loss in m^3/s (live)
--   │  infiltration: [__] [-][+] │   <- infiltration loss in m^3/s (live)
--   │  volume:  N m^3             │   <- read-only live volume
--   │  surface: N m^2             │   <- read-only live water surface area
--   │  [ Apply ] [ Clear All ]   │   <- Apply commits all typed field values
--   │  [ Generate Sea ]          │   <- floods the whole map below a sea level
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
	Rivers.State.ui_flow_edit = false
	Rivers.State.ui_height_edit = false
	Rivers.State.ui_drainage_edit = false
	Rivers.State.ui_evaporation_edit = false
	Rivers.State.ui_infiltration_edit = false
	Rivers.State.ui_volume_label = false
	Rivers.State.ui_area_label = false
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

-- Push the segment's current discharge / level into the input fields. We only
-- write a field that does NOT currently hold keyboard focus -- otherwise we'd
-- clobber what the player is typing mid-keystroke. The check uses the global
-- GetKeyboardFocus() (XDesktop.lua:144); if it isn't available we err on the
-- side of not touching the field, which is the safe direction.
-- Each entry maps an input field's State handle to the segment field it
-- mirrors. The live refresh writes the current value into every field that
-- isn't being typed in.
local INPUT_FIELDS = {
	{ state_key = "ui_height_edit", seg_field = "actual_level_m" },
	{ state_key = "ui_flow_edit", seg_field = "discharge_m3s" },
	{ state_key = "ui_drainage_edit", seg_field = "drainage_m3s" },
	{ state_key = "ui_evaporation_edit", seg_field = "evaporation_m3s" },
	{ state_key = "ui_infiltration_edit", seg_field = "infiltration_m3s" },
}

-- Push the segment's current values into the input fields. We only write a
-- field that does NOT currently hold keyboard focus -- otherwise we'd clobber
-- what the player is typing mid-keystroke. The check uses the global
-- GetKeyboardFocus() (XDesktop.lua:144); if it isn't available we err on the
-- side of not touching the field, which is the safe direction.
local function refresh_input_fields(seg)
	local get_focus = rawget(_G, "GetKeyboardFocus")
	local focused = type(get_focus) == "function" and get_focus() or nil
	for i = 1, #INPUT_FIELDS do
		local edit = Rivers.State[INPUT_FIELDS[i].state_key]
		if is_window_alive(edit) and edit ~= focused then
			local text = seg and format_float(seg[INPUT_FIELDS[i].seg_field] or 0, 2) or ""
			pcall(function() edit:SetText(text) end)
		end
	end
end

-- Read-only readouts: volume (m^3) and water surface area (m^2). Surface area
-- is the flooded tile area; flooded_area_wu2 -> m^2 divides by guim^2.
local function update_readouts(seg)
	local vol_label = Rivers.State.ui_volume_label
	if is_window_alive(vol_label) then
		local text = seg and ("volume:  " .. format_float(seg.volume_m3 or 0, 1) .. " m^3") or "volume:  --"
		pcall(function() vol_label:SetText(text) end)
	end
	local area_label = Rivers.State.ui_area_label
	if is_window_alive(area_label) then
		local area_m2 = seg and ((seg.flooded_area_wu2 or 0) / (guim * guim)) or nil
		local text = area_m2 and ("surface: " .. format_float(area_m2, 1) .. " m^2") or "surface: --"
		pcall(function() area_label:SetText(text) end)
	end
end

local function update_level_label()
	local label = Rivers.State.ui_level_label
	local seg_id = Rivers.State.current_marker_segment
	local seg = seg_id and Rivers.State.segments[seg_id] or nil

	-- Keep the input fields + readouts live first; do this whether or not the
	-- status label exists, since they can survive a missing label.
	refresh_input_fields(seg)
	update_readouts(seg)

	if not is_window_alive(label) then return end
	-- The numeric values live in the fields/readouts below, so the status line
	-- only reports the water depth class at the source.
	if not seg then
		pcall(function() label:SetText("Click a hole to start") end)
		return
	end
	local Tool = Rivers.Tool
	local class = (Tool and Tool.GetCurrentDepthClass()) or "dry"
	pcall(function() label:SetText("source depth: " .. class) end)
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
	-- RepeatStart > 0 makes XButton auto-fire OnPress while the mouse stays
	-- pressed on the button: after RepeatStart ms it begins firing, then
	-- every RepeatInterval ms thereafter (see XButton.lua:119). We expose this
	-- through opts.repeat_start / opts.repeat_interval so the +/- buttons can
	-- opt in and discrete actions (Clear All, Activate, etc.) stay single-shot.
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
		RepeatStart = opts.repeat_start or 0,
		RepeatInterval = opts.repeat_interval or 0,
	}, parent)
	btn.OnPress = function() pcall(on_press) end
	return btn
end

-- Attach a single-line XNumberEdit to `parent`. The edit is passive: it only
-- holds the typed value until a caller (the Apply button below) reads it via
-- `:GetNumber()`. Returns the edit handle, or nil if XNumberEdit is unavailable.
--
-- XControl's default TextColor is RGB(32,32,32) (near-black), which is unreadable
-- on this dark panel; we override TextColor + DisabledTextColor to the panel's
-- white so the typed value matches the labels. HintColor stays slightly
-- transparent so the hint reads as placeholder text rather than a real value.
local function make_number_edit(parent, opts)
	opts = opts or {}
	local x_number = rawget(_G, "XNumberEdit")
	if not x_number then return nil end
	return x_number:new({
		Translate = false,
		TextStyle = "ConsoleLog",
		HAlign = opts.halign or "stretch",
		MinWidth = opts.min_width or 100,
		MaxWidth = opts.max_width or 140,
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
		Padding = box(6, 2, 6, 2),
		Background = BUTTON_BACKGROUND,
		BorderColor = TEXT_COLOR,
		TextColor = TEXT_COLOR,
		DisabledTextColor = TEXT_COLOR,
		HintColor = RGBA(255, 255, 255, 128),
		IsInRange = true,
		MinValue = opts.min_value or 0,
		MaxValue = opts.max_value or 1000,
		Hint = opts.hint,
	}, parent)
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

	-- One row per source-parameter: [ label  input  -  + ]. The -/+ buttons
	-- commit immediately via on_adjust(delta). The input is passive: it just
	-- holds whatever the player has typed until the Apply button reads it.
	local repeat_start = (Rivers.Config and Rivers.Config.HYDRO_BUTTON_REPEAT_START_MS) or 300
	local repeat_interval = (Rivers.Config and Rivers.Config.HYDRO_BUTTON_REPEAT_INTERVAL_MS) or 150

	local function make_param_row(opts, on_adjust)
		local row = x_window:new({
			Id = opts.id,
			LayoutMethod = "HList",
			LayoutHSpacing = 4,
			HAlign = "stretch",
			MinWidth = 220,
			MaxWidth = 260,
		}, panel)

		x_label:new({
			Text = opts.label,
			Translate = false,
			TextStyle = "ConsoleLog",
			TextColor = TEXT_COLOR,
			HAlign = "left",
			VAlign = "center",
			MinWidth = 56,
			MaxWidth = 56,
			MinHeight = ROW_HEIGHT,
			MaxHeight = ROW_HEIGHT,
		}, row)

		local edit = make_number_edit(row, {
			halign = "stretch",
			min_width = 80,
			max_width = 110,
			min_value = 0,
			max_value = opts.max_value,
			hint = opts.hint,
		})

		make_button(row, "-", function()
			if not Rivers.Tool then return end
			on_adjust(-(opts.step or 1))
			UI.Refresh()
		end, {
			halign = "stretch", min_width = 32, max_width = 40,
			repeat_start = repeat_start, repeat_interval = repeat_interval,
		})

		make_button(row, "+", function()
			if not Rivers.Tool then return end
			on_adjust(opts.step or 1)
			UI.Refresh()
		end, {
			halign = "stretch", min_width = 32, max_width = 40,
			repeat_start = repeat_start, repeat_interval = repeat_interval,
		})

		return edit
	end

	-- Height row: instant water level in meters above the bowl floor. -/+
	-- snaps the level immediately via Budget.SetLevel (volume inverted from
	-- the new level), bypassing the rate-limited budget chase. The field
	-- itself is live -- update_level_label rewrites it each refresh from the
	-- segment's actual_level_m, so the value reflects what the budget tick
	-- is doing over time (e.g. drains back down when flow < losses).
	local height_edit = make_param_row({
		id = "RiversHeightRow",
		label = "height (lvl):",
		max_value = (Rivers.Config and Rivers.Config.HYDRO_LEVEL_MAX_M) or 50,
		step = (Rivers.Config and Rivers.Config.HYDRO_LEVEL_STEP_M) or 0.5,
		hint = "m",
	}, function(delta)
		Rivers.Tool.AdjustLevel(delta)
	end)
	if height_edit then
		Rivers.State.ui_height_edit = height_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, height input field omitted")
	end

	-- Inflow row: source discharge in m^3/s. -/+ adjusts how much water enters.
	local flow_edit = make_param_row({
		id = "RiversInflowRow",
		label = "inflow:",
		max_value = (Rivers.Config and Rivers.Config.HYDRO_DISCHARGE_MAX_M3S) or 100,
		step = (Rivers.Config and Rivers.Config.HYDRO_DISCHARGE_STEP_M3S) or 0.5,
		hint = "m^3/s",
	}, function(delta)
		Rivers.Tool.AdjustDischarge(delta)
	end)
	if flow_edit then
		Rivers.State.ui_flow_edit = flow_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, inflow input field omitted")
	end

	-- Drainage row: player-controlled drain in m^3/s (water leaving the system).
	local drainage_edit = make_param_row({
		id = "RiversDrainageRow",
		label = "drainage:",
		max_value = (Rivers.Config and Rivers.Config.HYDRO_DRAINAGE_MAX_M3S) or 100,
		step = (Rivers.Config and Rivers.Config.HYDRO_DRAINAGE_STEP_M3S) or 0.5,
		hint = "m^3/s",
	}, function(delta)
		Rivers.Tool.AdjustDrainage(delta)
	end)
	if drainage_edit then
		Rivers.State.ui_drainage_edit = drainage_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, drainage input field omitted")
	end

	-- Evaporation row: loss in m^3/s from the surface.
	local evaporation_edit = make_param_row({
		id = "RiversEvaporationRow",
		label = "evaporation:",
		max_value = (Rivers.Config and Rivers.Config.HYDRO_EVAPORATION_MAX_M3S) or 100,
		step = (Rivers.Config and Rivers.Config.HYDRO_EVAPORATION_STEP_M3S) or 0.1,
		hint = "m^3/s",
	}, function(delta)
		Rivers.Tool.AdjustEvaporation(delta)
	end)
	if evaporation_edit then
		Rivers.State.ui_evaporation_edit = evaporation_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, evaporation input field omitted")
	end

	-- Infiltration row: loss in m^3/s soaking into the ground.
	local infiltration_edit = make_param_row({
		id = "RiversInfiltrationRow",
		label = "infiltration:",
		max_value = (Rivers.Config and Rivers.Config.HYDRO_INFILTRATION_MAX_M3S) or 100,
		step = (Rivers.Config and Rivers.Config.HYDRO_INFILTRATION_STEP_M3S) or 0.1,
		hint = "m^3/s",
	}, function(delta)
		Rivers.Tool.AdjustInfiltration(delta)
	end)
	if infiltration_edit then
		Rivers.State.ui_infiltration_edit = infiltration_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, infiltration input field omitted")
	end

	-- Read-only readouts: live volume + water surface area of the current body.
	Rivers.State.ui_volume_label = x_label:new({
		Text = "volume:  --",
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)
	Rivers.State.ui_area_label = x_label:new({
		Text = "surface: --",
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)

	-- Apply + Clear All row: Apply commits every typed field value to the
	-- current source (no Enter shortcut -- only this button commits).
	local action_row = x_window:new({
		Id = "RiversActionRow",
		LayoutMethod = "HList",
		LayoutHSpacing = 8,
		HAlign = "stretch",
		MinWidth = 220,
		MaxWidth = 260,
	}, panel)

	-- Apply commits each field's typed value through the matching Tool setter.
	local apply_specs = {
		{ state_key = "ui_height_edit", setter = "SetLevel" },
		{ state_key = "ui_flow_edit", setter = "SetDischarge" },
		{ state_key = "ui_drainage_edit", setter = "SetDrainage" },
		{ state_key = "ui_evaporation_edit", setter = "SetEvaporation" },
		{ state_key = "ui_infiltration_edit", setter = "SetInfiltration" },
	}
	make_button(action_row, "Apply", function()
		if not Rivers.Tool then return end
		for i = 1, #apply_specs do
			local edit = Rivers.State[apply_specs[i].state_key]
			local fn = Rivers.Tool[apply_specs[i].setter]
			if edit and is_window_alive(edit) and type(fn) == "function" then
				local v = edit:GetNumber()
				if type(v) == "number" then
					fn(v)
				end
			end
		end
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120 })

	make_button(action_row, "Clear All Water", function()
		if type(Rivers.ClearAll) == "function" then
			Rivers.ClearAll()
		end
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 140 })

	-- Generate Sea: floods the whole map below a global sea level (one static,
	-- engine-managed body). Becomes the current source, so the height field then
	-- adjusts the sea level.
	make_button(panel, "Generate Sea", function()
		if Rivers.Sea and type(Rivers.Sea.Generate) == "function" then
			Rivers.Sea.Generate()
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
