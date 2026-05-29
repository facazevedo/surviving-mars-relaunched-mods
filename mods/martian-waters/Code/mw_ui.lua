-- MartianWaters -- right-side panel hosting the water tool and the rain buttons.
--
-- Layout:
--   ┌────────────────────────────┐
--   │           MARTIAN WATERS           │   <- title
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
--   │  sea level:   [__] [-][+]  │   <- >0 generates/sets the sea; <=0 removes it
--   │                            │
--   │           RAIN             │   <- section label
--   │  Rain: none                │   <- status (disaster preset / visual on)
--   │  [ Start/Stop Rain ]       │   <- one toggle for the disaster
--   │  [ Visual Rain: On/Off ]   │   <- one toggle for the cosmetic override
--   └────────────────────────────┘
--
-- Lifecycle:
--   MartianWaters.UI.Show()      -- (re)create the panel and attach to GetHUD()
--   MartianWaters.UI.Hide()      -- destroy the panel
--   MartianWaters.UI.Refresh()   -- update labels (called by r_tool when state changes)
--
-- The panel is created on OnMsg.NewMapLoaded by mw_lifecycle.lua and destroyed
-- on OnMsg.DoneMap. It is NOT shown on the main menu.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "UI"

local UI = {}

local PANEL_ID = "MartianWatersWaterToolPanel"

-- ----------------------------------------------------------------------------
-- Theme: a modern, water-themed palette + a small typographic hierarchy built
-- from existing engine TextStyles (no custom-font registration needed):
--   TITLE_STYLE   "CommonMessageDescription" -- Source Sans Pro, 20
--   SECTION_STYLE "ConsoleLog"               -- Droid Sans Bold, 13
--   TEXT_STYLE    "EditorText"               -- Droid Sans, 13 (body/fields/buttons)
-- Every control overrides TextColor explicitly, so the styles' built-in colours
-- don't matter -- only their font + size do.
-- ----------------------------------------------------------------------------
local ACCENT = RGB(120, 210, 230)                -- cyan accent
local TEXT_COLOR = RGB(232, 240, 245)            -- primary text
local TEXT_MUTED = RGB(150, 172, 184)            -- status lines / readouts / hints

-- Use the vanilla infopanel's own TextStyles directly. (Registering custom
-- TextStyles at runtime crashes -- the font isn't put through the engine's
-- load-time pipeline, so GetFontId rejects it -- so we can't apply a "-1pt"
-- size this way; that would need a proper TextStyle Data preset shipped with
-- the mod.)
local TITLE_STYLE   = "InfopanelTitleR"     -- LibelSuit, 26
local SECTION_STYLE = "InfopanelTextBlueR"  -- cyan, 20
local READOUT_STYLE = "InfopanelTextR"      -- white, 18
local TEXT_STYLE    = "EditorText"          -- Droid Sans, 13 (compact rows)

local PANEL_BACKGROUND = RGBA(14, 22, 30, 232)   -- deep slate, mostly opaque for readability
local PANEL_WIDTH = 300                           -- fixed width so labels never clip

local BUTTON_BACKGROUND = RGBA(32, 46, 56, 235)  -- secondary button
local BUTTON_ROLLOVER = RGBA(48, 74, 90, 245)
local BUTTON_ACTIVE = RGB(40, 130, 110)          -- water-mode ON toggle
local BUTTON_PRIMARY = RGBA(26, 96, 120, 242)    -- accent action (Apply / Generate Sea)
local BUTTON_PRIMARY_ROLLOVER = RGBA(34, 122, 150, 250)

local ROW_HEIGHT = 26
local ROW_SPACING = 4
local TITLE_HEIGHT = 42
local SECTION_HEIGHT = 28

local function is_window_alive(win)
	if not win then return false end
	if type(win.window_state) == "string" then
		return win.window_state ~= "destroying"
	end
	return true
end

-- A native infopanel-style section header: a hex section icon (the InHHex-masked
-- icon the game uses) next to a cyan title, over the infopanel's sub-pad frame
-- texture. Falls back to a plain banded label if the X classes are unavailable.
local function add_section(parent, text, icon)
	local x_window = rawget(_G, "XWindow")
	local x_label = rawget(_G, "XLabel")
	local x_image = rawget(_G, "XImage")
	if not x_label then return end

	-- The header row.
	local row = (x_window or x_label):new({
		Id = "MW_Section_" .. text,
		LayoutMethod = "HList",
		LayoutHSpacing = 6,
		HAlign = "stretch",
		MinHeight = SECTION_HEIGHT,
		MaxHeight = SECTION_HEIGHT,
		Margins = box(-12, 4, -12, 2),
		Padding = box(8, 0, 8, 0),
	}, parent)

	-- Subtle dark band + a cyan hairline underneath (like the vanilla section
	-- divider). The bright blue ip_sub_pad frame read as a solid bar, so we use a
	-- quiet translucent background instead -- the cyan title + hex icon carry it.
	pcall(function() row:SetBackground(RGBA(0, 0, 0, 50)) end)
	if x_window then
		x_window:new({
			Dock = "bottom",
			MinHeight = 1,
			MaxHeight = 1,
			Background = RGBA(120, 210, 230, 55),
			HandleMouse = false,
		}, row)
	end

	-- Hex section icon: the inactive-hex backing + the themed icon on top, both
	-- masked to the hexagon via Shape "InHHex" (exactly as InfopanelSection does).
	if x_image and icon then
		x_image:new({
			Dock = "left",
			VAlign = "center",
			MinWidth = 26, MaxWidth = 26, MinHeight = 26, MaxHeight = 26,
			Shape = "InHHex",
			Image = "UI/IconsRemaster/Sections/ip_sections_inactive.png",
			ImageFit = "smallest",
		}, row)
		x_image:new({
			Dock = "left",
			VAlign = "center",
			Margins = box(-26, 0, 0, 0),  -- overlay on the hex backing
			MinWidth = 26, MaxWidth = 26, MinHeight = 26, MaxHeight = 26,
			Shape = "InHHex",
			Image = icon,
			ImageFit = "smallest",
		}, row)
	end

	x_label:new({
		Text = text,
		Translate = false,
		TextStyle = SECTION_STYLE,    -- native cyan section title
		VAlign = "center",
		HAlign = "left",
		MinHeight = SECTION_HEIGHT,
		MaxHeight = SECTION_HEIGHT,
	}, row)
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
	local panel = MartianWaters.State.ui_panel
	if panel and is_window_alive(panel) then
		pcall(function()
			if panel.delete then panel:delete()
			elseif panel.Close then panel:Close()
			end
		end)
	end
	MartianWaters.State.ui_panel = false
	MartianWaters.State.ui_toggle_button = false
	MartianWaters.State.ui_level_label = false
	MartianWaters.State.ui_rain_label = false
	MartianWaters.State.ui_rain_disaster_button = false
	MartianWaters.State.ui_rain_visual_button = false
	MartianWaters.State.ui_flow_edit = false
	MartianWaters.State.ui_height_edit = false
	MartianWaters.State.ui_drainage_edit = false
	MartianWaters.State.ui_evaporation_edit = false
	MartianWaters.State.ui_infiltration_edit = false
	MartianWaters.State.ui_volume_label = false
	MartianWaters.State.ui_area_label = false
	MartianWaters.State.ui_sealevel_edit = false
end

local function update_toggle_visual()
	local btn = MartianWaters.State.ui_toggle_button
	if not is_window_alive(btn) then return end
	local Tool = MartianWaters.Tool
	local active = Tool and Tool.IsActive() == true or false
	local label = active and "Water Mode: ON  (click a hole)" or "Activate Water Mode"
	pcall(function() btn:SetText(label) end)
	pcall(function() btn:SetBackground(active and BUTTON_ACTIVE or BUTTON_BACKGROUND) end)
end

local function format_float(n, decimals)
	if type(n) ~= "number" then return "--" end
	-- string.format keeps the trailing decimals (tostring(8.0) drops to "8" in
	-- this engine's Lua, which made the fields look integer-only).
	return string.format("%." .. tostring(decimals or 2) .. "f", n)
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
		local edit = MartianWaters.State[INPUT_FIELDS[i].state_key]
		if is_window_alive(edit) and edit ~= focused then
			local text = seg and format_float(seg[INPUT_FIELDS[i].seg_field] or 0, 1) or ""
			pcall(function() edit:SetText(text) end)
		end
	end

	-- Sea-level field mirrors the SEA (independent of the current marker); blank
	-- when no sea exists. Tool.GetSeaLevel returns nil if there's no sea.
	local sea_edit = MartianWaters.State.ui_sealevel_edit
	if is_window_alive(sea_edit) and sea_edit ~= focused then
		local Tool = MartianWaters.Tool
		local lvl = Tool and Tool.GetSeaLevel and Tool.GetSeaLevel() or nil
		local text = lvl and format_float(lvl, 1) or ""
		pcall(function() sea_edit:SetText(text) end)
	end
end

-- Read-only readouts: volume (m^3) and water surface area (m^2). Surface area
-- is the flooded tile area; flooded_area_wu2 -> m^2 divides by guim^2.
local function update_readouts(seg)
	local vol_label = MartianWaters.State.ui_volume_label
	if is_window_alive(vol_label) then
		local text = seg and ("volume:  " .. format_float(seg.volume_m3 or 0, 1) .. " m^3") or "volume:  --"
		pcall(function() vol_label:SetText(text) end)
	end
	local area_label = MartianWaters.State.ui_area_label
	if is_window_alive(area_label) then
		local area_m2 = seg and ((seg.flooded_area_wu2 or 0) / (guim * guim)) or nil
		local text = area_m2 and ("surface: " .. format_float(area_m2, 1) .. " m^2") or "surface: --"
		pcall(function() area_label:SetText(text) end)
	end
end

local function update_level_label()
	local label = MartianWaters.State.ui_level_label
	local seg_id = MartianWaters.State.current_marker_segment
	local seg = seg_id and MartianWaters.State.segments[seg_id] or nil

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
	local Tool = MartianWaters.Tool
	local class = (Tool and Tool.GetCurrentDepthClass()) or "dry"
	pcall(function() label:SetText("source depth: " .. class) end)
end

-- Set a toggle button's label + background to reflect an on/off state.
local function set_toggle_button(btn, active, on_text, off_text)
	if not is_window_alive(btn) then return end
	pcall(function() btn:SetText(active and on_text or off_text) end)
	pcall(function() btn:SetBackground(active and BUTTON_ACTIVE or BUTTON_BACKGROUND) end)
end

local function update_rain_label()
	local Rain = MartianWaters.Rain
	local disaster = Rain and Rain.GetDisasterType() or nil
	local visual = Rain and Rain.IsVisualActive() or false

	-- Status line.
	local label = MartianWaters.State.ui_rain_label
	if is_window_alive(label) then
		local parts = {}
		if disaster then parts[#parts + 1] = "disaster=" .. tostring(disaster) end
		if visual then parts[#parts + 1] = "visual=on" end
		local text = "Rain: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
		pcall(function() label:SetText(text) end)
	end

	-- Toggle buttons reflect live state.
	set_toggle_button(MartianWaters.State.ui_rain_disaster_button, disaster ~= nil, "Stop Rain", "Start Rain")
	set_toggle_button(MartianWaters.State.ui_rain_visual_button, visual, "Visual Rain: On", "Visual Rain: Off")
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
	-- opts.primary picks the accent palette for headline actions (Apply, Generate
	-- Sea); everything else uses the muted secondary palette.
	local bg = opts.primary and BUTTON_PRIMARY or BUTTON_BACKGROUND
	local hover = opts.primary and BUTTON_PRIMARY_ROLLOVER or BUTTON_ROLLOVER
	local btn = x_button:new({
		Text = opts.icon and "" or label,
		Translate = false,
		TextStyle = TEXT_STYLE,
		TextColor = TEXT_COLOR,
		RolloverTextColor = RGB(255, 255, 255),
		PressedTextColor = RGB(255, 255, 255),
		Icon = opts.icon,                    -- native arrow image for spinbox steppers
		IconScale = opts.icon and point(700, 700) or nil,
		HAlign = opts.halign or "stretch",
		MinWidth = opts.min_width or 120,
		MaxWidth = opts.max_width or PANEL_WIDTH,
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
		Padding = box(6, 3, 6, 3),
		Background = bg,
		FocusedBackground = bg,
		RolloverBackground = hover,
		PressedBackground = hover,
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
		TextStyle = TEXT_STYLE,
		HAlign = opts.halign or "stretch",
		MinWidth = opts.min_width or 100,
		MaxWidth = opts.max_width or 140,
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
		Padding = box(6, 2, 6, 2),
		Background = RGBA(0, 0, 0, 100),
		FocusedBackground = RGBA(20, 40, 52, 170),
		RolloverBackground = RGBA(0, 0, 0, 100),
		SelectionColor = RGB(255, 255, 255),
		SelectionBackground = RGBA(34, 122, 150, 180),  -- teal, not the default bright blue
		BorderWidth = 1,
		BorderColor = RGBA(120, 210, 230, 90),
		TextColor = TEXT_COLOR,
		DisabledTextColor = TEXT_COLOR,
		HintColor = TEXT_MUTED,
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
		Margins = box(0, 460, 18, 0),
		Padding = box(16, 6, 16, 14),
		MinWidth = PANEL_WIDTH,
		MaxWidth = PANEL_WIDTH,
		LayoutMethod = "VList",
		LayoutVSpacing = ROW_SPACING,
		Background = PANEL_BACKGROUND,
		FocusedBackground = PANEL_BACKGROUND,
		HandleMouse = true,
		ChildrenHandleMouse = true,
	}, parent)

	-- Native infopanel body, reproduced exactly as InfopanelSection builds it:
	--   1) a frosted XBlurRect that blurs the map behind the panel (the dark,
	--      glassy look), masked to the ip_background frame shape;
	--   2) the ip_background 9-slice XFrame drawn semi-transparent (Transparency
	--      102, same as vanilla) ON TOP -- this is the subtle blue frame, NOT a
	--      solid fill, so it tints rather than blocks.
	-- Both are created before any content so they sit behind it. Each is guarded;
	-- the flat PANEL_BACKGROUND remains as a fallback if a class/texture is absent.
	local x_blur = rawget(_G, "XBlurRect")
	if x_blur then
		x_blur:new({
			Id = "MartianWatersBlur",
			Dock = "box",
			BlurRadius = 18,
			Mask = "UI/InfopanelRemaster/ip_background.png",
			FrameLeft = 12, FrameTop = 12, FrameRight = 12, FrameBottom = 12,
			HandleMouse = false,
		}, panel)
	end
	local x_frame = rawget(_G, "XFrame")
	if x_frame then
		x_frame:new({
			Id = "MartianWatersFrame",
			Dock = "box",
			Image = "UI/InfopanelRemaster/ip_background.png",
			FrameBox = box(12, 12, 12, 12),
			Transparency = 102,
			HandleMouse = false,
		}, panel)
	end

	-- Title, vanilla-infopanel style: cyan, left-aligned, on a subtly darker band
	-- at the top of the frosted body, with a hairline separator beneath it.
	x_label:new({
		Text = "MARTIAN WATERS",
		Translate = false,
		TextStyle = TITLE_STYLE,
		TextColor = ACCENT,
		TextHAlign = "left",
		TextVAlign = "center",
		HAlign = "stretch",
		MinHeight = TITLE_HEIGHT,
		MaxHeight = TITLE_HEIGHT,
		Margins = box(-16, -6, -16, 0),   -- span to the frame edges + top
		Padding = box(16, 4, 10, 4),
		Background = RGBA(0, 0, 0, 70),
	}, panel)
	x_window:new({                         -- hairline separator under the title
		HAlign = "stretch",
		MinHeight = 2,
		MaxHeight = 2,
		Margins = box(-12, 0, -12, 4),
		Background = RGBA(120, 210, 230, 70),
	}, panel)

	add_section(panel, "WATER", "UI/IconsRemaster/Sections/terraforming.png")

	-- Toggle button
	local toggle = make_button(panel, "Activate Water Mode", function()
		if MartianWaters.Tool then MartianWaters.Tool.Toggle() end
	end)
	MartianWaters.State.ui_toggle_button = toggle

	-- Status label (filled in by update_level_label on Refresh)
	local level_label = x_label:new({
		Text = "Click a hole to start",
		Translate = false,
		TextStyle = READOUT_STYLE,
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)
	MartianWaters.State.ui_level_label = level_label

	-- One row per source-parameter: [ label  input  -  + ]. The -/+ buttons
	-- commit immediately via on_adjust(delta). The input is passive: it just
	-- holds whatever the player has typed until the Apply button reads it.
	local repeat_start = (MartianWaters.Config and MartianWaters.Config.HYDRO_BUTTON_REPEAT_START_MS) or 300
	local repeat_interval = (MartianWaters.Config and MartianWaters.Config.HYDRO_BUTTON_REPEAT_INTERVAL_MS) or 150

	-- Column widths sum to the panel's inner width (PANEL_WIDTH - 20 padding):
	-- 96 label + 100 input + 30 + 30 + 3*4 spacing = 268 <= 280.
	local LABEL_W, INPUT_W, STEP_W = 96, 100, 30
	local function make_param_row(opts, on_adjust)
		local row = x_window:new({
			Id = opts.id,
			LayoutMethod = "HList",
			LayoutHSpacing = 4,
			HAlign = "stretch",
		}, panel)

		x_label:new({
			Text = opts.label,
			Translate = false,
			TextStyle = TEXT_STYLE,
			TextColor = TEXT_COLOR,
			HAlign = "left",
			VAlign = "center",
			MinWidth = LABEL_W,
			MaxWidth = LABEL_W,
			MinHeight = ROW_HEIGHT,
			MaxHeight = ROW_HEIGHT,
		}, row)

		local edit = make_number_edit(row, {
			halign = "left",
			min_width = INPUT_W,
			max_width = INPUT_W,
			min_value = 0,
			max_value = opts.max_value,
			hint = opts.hint,
		})

		make_button(row, "-", function()
			if not MartianWaters.Tool then return end
			on_adjust(-(opts.step or 1))
			UI.Refresh()
		end, {
			halign = "left", min_width = STEP_W, max_width = STEP_W,
			icon = "UI/CommonRemaster/arrow_remove.png",
			repeat_start = repeat_start, repeat_interval = repeat_interval,
		})

		make_button(row, "+", function()
			if not MartianWaters.Tool then return end
			on_adjust(opts.step or 1)
			UI.Refresh()
		end, {
			halign = "left", min_width = STEP_W, max_width = STEP_W,
			icon = "UI/CommonRemaster/arrow_add.png",
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
		id = "MartianWatersHeightRow",
		label = "height (lvl):",
		max_value = (MartianWaters.Config and MartianWaters.Config.HYDRO_LEVEL_MAX_M) or 50,
		step = (MartianWaters.Config and MartianWaters.Config.HYDRO_LEVEL_STEP_M) or 0.5,
		hint = "m",
	}, function(delta)
		MartianWaters.Tool.AdjustLevel(delta)
	end)
	if height_edit then
		MartianWaters.State.ui_height_edit = height_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, height input field omitted")
	end

	-- Inflow row: source discharge in m^3/s. -/+ adjusts how much water enters.
	local flow_edit = make_param_row({
		id = "MartianWatersInflowRow",
		label = "inflow:",
		max_value = (MartianWaters.Config and MartianWaters.Config.HYDRO_DISCHARGE_MAX_M3S) or 100,
		step = (MartianWaters.Config and MartianWaters.Config.HYDRO_DISCHARGE_STEP_M3S) or 0.5,
		hint = "m^3/s",
	}, function(delta)
		MartianWaters.Tool.AdjustDischarge(delta)
	end)
	if flow_edit then
		MartianWaters.State.ui_flow_edit = flow_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, inflow input field omitted")
	end

	-- Drainage row: player-controlled drain in m^3/s (water leaving the system).
	local drainage_edit = make_param_row({
		id = "MartianWatersDrainageRow",
		label = "drainage:",
		max_value = (MartianWaters.Config and MartianWaters.Config.HYDRO_DRAINAGE_MAX_M3S) or 100,
		step = (MartianWaters.Config and MartianWaters.Config.HYDRO_DRAINAGE_STEP_M3S) or 0.5,
		hint = "m^3/s",
	}, function(delta)
		MartianWaters.Tool.AdjustDrainage(delta)
	end)
	if drainage_edit then
		MartianWaters.State.ui_drainage_edit = drainage_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, drainage input field omitted")
	end

	-- Evaporation row: loss in m^3/s from the surface.
	local evaporation_edit = make_param_row({
		id = "MartianWatersEvaporationRow",
		label = "evaporation:",
		max_value = (MartianWaters.Config and MartianWaters.Config.HYDRO_EVAPORATION_MAX_M3S) or 100,
		step = (MartianWaters.Config and MartianWaters.Config.HYDRO_EVAPORATION_STEP_M3S) or 0.1,
		hint = "m^3/s",
	}, function(delta)
		MartianWaters.Tool.AdjustEvaporation(delta)
	end)
	if evaporation_edit then
		MartianWaters.State.ui_evaporation_edit = evaporation_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, evaporation input field omitted")
	end

	-- Infiltration row: loss in m^3/s soaking into the ground.
	local infiltration_edit = make_param_row({
		id = "MartianWatersInfiltrationRow",
		label = "infiltration:",
		max_value = (MartianWaters.Config and MartianWaters.Config.HYDRO_INFILTRATION_MAX_M3S) or 100,
		step = (MartianWaters.Config and MartianWaters.Config.HYDRO_INFILTRATION_STEP_M3S) or 0.1,
		hint = "m^3/s",
	}, function(delta)
		MartianWaters.Tool.AdjustInfiltration(delta)
	end)
	if infiltration_edit then
		MartianWaters.State.ui_infiltration_edit = infiltration_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, infiltration input field omitted")
	end

	-- Read-only readouts: live volume + water surface area of the current body.
	MartianWaters.State.ui_volume_label = x_label:new({
		Text = "volume:  --",
		Translate = false,
		TextStyle = READOUT_STYLE,
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)
	MartianWaters.State.ui_area_label = x_label:new({
		Text = "surface: --",
		Translate = false,
		TextStyle = READOUT_STYLE,
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)

	-- Apply + Clear All row: Apply commits every typed field value to the
	-- current source (no Enter shortcut -- only this button commits).
	local action_row = x_window:new({
		Id = "MartianWatersActionRow",
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
		{ state_key = "ui_sealevel_edit", setter = "SetSeaLevel" },
	}
	make_button(action_row, "Apply", function()
		if not MartianWaters.Tool then return end
		for i = 1, #apply_specs do
			local edit = MartianWaters.State[apply_specs[i].state_key]
			local fn = MartianWaters.Tool[apply_specs[i].setter]
			if edit and is_window_alive(edit) and type(fn) == "function" then
				local v = edit:GetNumber()
				if type(v) == "number" then
					fn(v)
				end
			end
		end
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 120, primary = true })

	make_button(action_row, "Clear All Water", function()
		if type(MartianWaters.ClearAll) == "function" then
			MartianWaters.ClearAll()
		end
		UI.Refresh()
	end, { halign = "stretch", min_width = 100, max_width = 140 })

	-- Sea level row: the sole sea control. A positive level auto-generates the
	-- sea (flooding the whole map below it) or sets it; dropping to <= 0 removes
	-- the sea. -/+ adjust it live; Apply commits a typed value. Acts on the sea
	-- regardless of which marker is selected.
	local sealevel_edit = make_param_row({
		id = "MartianWatersSeaLevelRow",
		label = "sea level:",
		max_value = (MartianWaters.Config and MartianWaters.Config.SEA_LEVEL_MAX_M) or 200,
		step = (MartianWaters.Config and MartianWaters.Config.SEA_LEVEL_STEP_M) or 1,
		hint = "m",
	}, function(delta)
		MartianWaters.Tool.AdjustSeaLevel(delta)
	end)
	if sealevel_edit then
		MartianWaters.State.ui_sealevel_edit = sealevel_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, sea level field omitted")
	end

	-- Rain section
	add_section(panel, "RAIN", "UI/IconsRemaster/Sections/dust.png")

	local rain_label = x_label:new({
		Text = "Rain: none",
		Translate = false,
		TextStyle = READOUT_STYLE,
		TextColor = TEXT_COLOR,
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT,
		MaxHeight = ROW_HEIGHT,
	}, panel)
	MartianWaters.State.ui_rain_label = rain_label

	-- Single toggle for the rain disaster: label/colour reflect the live state
	-- (set by update_rain_label on Refresh). Press toggles start/stop.
	MartianWaters.State.ui_rain_disaster_button = make_button(panel, "Start Rain", function()
		local Rain = MartianWaters.Rain
		if not Rain then return end
		if Rain.GetDisasterType() then Rain.StopDisaster() else Rain.StartDisaster() end
		UI.Refresh()
	end)

	-- Single toggle for the cosmetic-only visual rain override.
	MartianWaters.State.ui_rain_visual_button = make_button(panel, "Visual Rain: Off", function()
		local Rain = MartianWaters.Rain
		if not Rain then return end
		if Rain.IsVisualActive() then Rain.StopVisual() else Rain.StartVisual() end
		UI.Refresh()
	end)

	MartianWaters.State.ui_panel = panel
	UI.Refresh()
	DebugLog.Info(SCOPE, "panel shown")
	return panel
end

function UI.Hide()
	-- Make sure the tool is off (tears down the click overlay too) before hiding.
	if MartianWaters.Tool and MartianWaters.Tool.IsActive() then
		MartianWaters.Tool.Deactivate()
	end
	destroy_panel()
	DebugLog.Info(SCOPE, "panel hidden")
end

MartianWaters.UI = UI
