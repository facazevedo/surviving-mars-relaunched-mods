-- MartianWaters -- the draggable right-side control panel.
--
-- Sections, top to bottom:
--   title bar (drag handle) + close (X)
--   [ Activate Waters Mode ]          -- toggles the click-to-place water tool
--   FRESH WATER  -- status line, then per-source rows: Height / Inflow / Drainage
--                   / Evaporation / Infiltration  [ (unit)  input  - + ], then the
--                   Volume / Surface / Flooded Tiles readouts
--   SEA          -- Sea Level row (>0 generates/sets the sea, <=0 removes it)
--   RAIN         -- disaster toggle + visual-only toggle
--   CLOUDS       -- cloud-shadow toggle + Coverage / Speed rows
--   footer       -- [ Clear Waters ] + info button (hover = field guide)
--
-- Lifecycle:
--   UI.Show()    -- (re)create the panel, attached to GetHUD()
--   UI.Hide()    -- destroy the panel
--   UI.Refresh() -- update labels/fields from live state
--
-- Created on OnMsg.NewMapLoaded (mw_lifecycle.lua), destroyed on OnMsg.DoneMap;
-- not shown on the main menu.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "UI"

local UI = {}

local PANEL_ID = "MartianWatersWaterToolPanel"

-- ----------------------------------------------------------------------------
-- Theme. Text uses the vanilla infopanel's own (already-loaded) TextStyles so it
-- matches the game's aesthetic; one extra style for the unit superscript ships in
-- mw_textstyles.lua. Controls override TextColor where needed.
-- ----------------------------------------------------------------------------
local ACCENT = RGB(120, 210, 230)                -- cyan accent
local TEXT_COLOR = RGB(232, 240, 245)            -- primary text
local TEXT_MUTED = RGB(150, 172, 184)            -- status lines / readouts / hints

local TITLE_STYLE   = "InfopanelTitleR"     -- LibelSuit, 26
local SECTION_STYLE = "InfopanelTextBlueR"  -- cyan, 20
local READOUT_STYLE = "InfopanelTextR"      -- white, 18
local TEXT_STYLE    = "InfopanelTextR"      -- white, 18 -- labels/buttons/fields share this

-- Transparent root: the panel body is the frosted XBlurRect + a translucent blue
-- tint (built in UI.Show), so a solid layer here would just kill the glassy look.
local PANEL_BACKGROUND = RGBA(0, 0, 0, 0)
local PANEL_WIDTH = 340                           -- fixed width (fits the label + "(unit)"
                                                  -- + input + steppers columns without clipping)

local BUTTON_BACKGROUND = RGBA(32, 46, 56, 235)  -- secondary button
local BUTTON_ROLLOVER = RGBA(48, 74, 90, 245)
local BUTTON_ACTIVE = RGB(40, 130, 110)          -- water-mode ON toggle

local ROW_HEIGHT = 26
-- Input row height: snug around the number font (same style as the labels) with a
-- little headroom for the nudged-up superscript digit.
local FIELD_HEIGHT = 28
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
local function add_section(parent, text, icon, icon_pad)
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
		Margins = box(-20, 4, -20, 2),   -- match the frost's full-width extent
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
		-- icon_pad shrinks the drawn glyph inside the 26px hex (ImageFit fits the
		-- image into the box minus padding), so icons whose art fills the frame
		-- (e.g. the Sea water-drop) can be brought down to match the smaller-looking
		-- glyphs whose art already has built-in margin (e.g. the Rain drop).
		local pad = icon_pad or 0
		x_image:new({
			Dock = "left",
			VAlign = "center",
			Margins = box(-26, 0, 0, 0),  -- overlay on the hex backing
			MinWidth = 26, MaxWidth = 26, MinHeight = 26, MaxHeight = 26,
			Padding = box(pad, pad, pad, pad),
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
	MartianWaters.State.ui_rain_disaster_button = false
	MartianWaters.State.ui_rain_visual_button = false
	MartianWaters.State.ui_flow_edit = false
	MartianWaters.State.ui_height_edit = false
	MartianWaters.State.ui_drainage_edit = false
	MartianWaters.State.ui_evaporation_edit = false
	MartianWaters.State.ui_infiltration_edit = false
	MartianWaters.State.ui_volume_label = false
	MartianWaters.State.ui_volume_digit = false
	MartianWaters.State.ui_area_label = false
	MartianWaters.State.ui_area_digit = false
	MartianWaters.State.ui_tiles_label = false
	MartianWaters.State.ui_sealevel_edit = false
	MartianWaters.State.ui_cloud_toggle_button = false
	MartianWaters.State.ui_cloud_coverage_edit = false
	MartianWaters.State.ui_cloud_speed_edit = false
end

local function update_toggle_visual()
	local btn = MartianWaters.State.ui_toggle_button
	if not is_window_alive(btn) then return end
	local Tool = MartianWaters.Tool
	local active = Tool and Tool.IsActive() == true or false
	local label = active and "Waters Mode: ON" or "Activate Waters Mode"
	pcall(function() btn:SetText(label) end)
	pcall(function() btn:SetBackground(active and BUTTON_ACTIVE or BUTTON_BACKGROUND) end)
	-- Re-assert the centred caption: SetText re-measures the embedded label and can
	-- drop it back to a content-width, left-packed layout, so re-apply the fill +
	-- centre that make_button's center_text set at creation.
	local lbl = btn.idLabel
	if lbl then
		pcall(function() lbl:SetDock("box") end)
		if lbl.SetTextHAlign then pcall(function() lbl:SetTextHAlign("center") end) end
		if lbl.SetTextVAlign then pcall(function() lbl:SetTextVAlign("center") end) end
	end
end

local function format_float(n, decimals)
	if type(n) ~= "number" then return "--" end
	-- string.format keeps the trailing decimals (tostring(8.0) drops to "8" in
	-- this engine's Lua, which made the fields look integer-only).
	return string.format("%." .. tostring(decimals or 2) .. "f", n)
end

-- Each entry maps an input field's State handle to the segment field it mirrors.
local INPUT_FIELDS = {
	{ state_key = "ui_height_edit", seg_field = "actual_level_m" },
	{ state_key = "ui_flow_edit", seg_field = "discharge_m3s" },
	{ state_key = "ui_drainage_edit", seg_field = "drainage_m3s" },
	{ state_key = "ui_evaporation_edit", seg_field = "evaporation_m3s" },
	{ state_key = "ui_infiltration_edit", seg_field = "infiltration_m3s" },
}

-- Push each segment field's value into its input field, except one that currently
-- holds keyboard focus (don't clobber mid-typing). GetKeyboardFocus is a global;
-- if it's unavailable we err on not touching the field.
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

	-- Cloud fields mirror the global cloud-shadow scene params (also independent
	-- of the current marker). Tool.GetCloudCoverage/GetCloudSpeed return nil if
	-- the Clouds module isn't loaded, in which case the field stays blank.
	local Tool = MartianWaters.Tool
	local cov_edit = MartianWaters.State.ui_cloud_coverage_edit
	if is_window_alive(cov_edit) and cov_edit ~= focused then
		local cov = Tool and Tool.GetCloudCoverage and Tool.GetCloudCoverage() or nil
		pcall(function() cov_edit:SetText(cov and format_float(cov, 1) or "") end)
	end
	local spd_edit = MartianWaters.State.ui_cloud_speed_edit
	if is_window_alive(spd_edit) and spd_edit ~= focused then
		local spd = Tool and Tool.GetCloudSpeed and Tool.GetCloudSpeed() or nil
		pcall(function() spd_edit:SetText(spd and format_float(spd, 1) or "") end)
	end
end

-- A superscript readout is a prefix text ("Volume: N m") plus a separate small
-- raised unit digit (same approach as the field units). Set the prefix and show
-- the digit only when there's a value (hidden on the "--" placeholder).
local function set_super_readout(prefix_key, digit_key, prefix_text, has_value)
	local prefix = MartianWaters.State[prefix_key]
	if is_window_alive(prefix) then pcall(function() prefix:SetText(prefix_text) end) end
	local digit = MartianWaters.State[digit_key]
	if is_window_alive(digit) then pcall(function() digit:SetVisible(has_value and true or false) end) end
end

local function update_readouts(seg)
	set_super_readout("ui_volume_label", "ui_volume_digit",
		seg and ("Volume: " .. format_float(seg.volume_m3 or 0, 1) .. " m") or "Volume: --", seg ~= nil)
	set_super_readout("ui_area_label", "ui_area_digit",
		seg and ("Surface: " .. format_float((seg.flooded_area_wu2 or 0) / (guim * guim), 1) .. " m") or "Surface: --", seg ~= nil)
	local tiles_label = MartianWaters.State.ui_tiles_label
	if is_window_alive(tiles_label) then
		pcall(function() tiles_label:SetText(seg and ("Flooded Tiles: " .. tostring(seg.flooded_tile_count or 0)) or "Flooded Tiles: --") end)
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
	pcall(function() label:SetText("Source Depth: " .. class) end)
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

	-- Toggle buttons reflect live state.
	set_toggle_button(MartianWaters.State.ui_rain_disaster_button, disaster ~= nil, "Stop Rain", "Start Rain")
	set_toggle_button(MartianWaters.State.ui_rain_visual_button, visual,
		"Stop Rain (only visual effect)", "Start Rain (only visual effect)")
end

local function update_cloud_label()
	local Tool = MartianWaters.Tool
	local on = Tool and Tool.AreCloudShadowsEnabled and Tool.AreCloudShadowsEnabled() or false
	set_toggle_button(MartianWaters.State.ui_cloud_toggle_button, on,
		"Cloud Shadows: On", "Cloud Shadows: Off")
end

function UI.Refresh()
	update_toggle_visual()
	update_level_label()
	update_rain_label()
	update_cloud_label()
end

-- ----------------------------------------------------------------------------
-- Button factory
-- ----------------------------------------------------------------------------

local function make_button(parent, label, on_press, opts)
	opts = opts or {}
	local x_button = rawget(_G, "XTextButton")
	if not x_button then return nil end
	-- RepeatStart > 0 makes XButton auto-fire OnPress while the mouse stays pressed
	-- (see XButton.lua); the +/- steppers opt in via opts.repeat_start/interval,
	-- discrete actions stay single-shot.
	local bg = BUTTON_BACKGROUND
	local hover = BUTTON_ROLLOVER
	-- Icon buttons (the +/- spinbox arrows) show only the arrow glyph -- no dark
	-- box behind it. A faint translucent rollover keeps press feedback.
	if opts.icon then
		bg = RGBA(0, 0, 0, 0)
		hover = RGBA(255, 255, 255, 30)
	end
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
		MinHeight = opts.height or ROW_HEIGHT,
		MaxHeight = opts.height or ROW_HEIGHT,
		Padding = box(6, 3, 6, 3),
		Background = bg,
		FocusedBackground = bg,
		RolloverBackground = hover,
		PressedBackground = hover,
		RepeatStart = opts.repeat_start or 0,
		RepeatInterval = opts.repeat_interval or 0,
		-- opts.center_text horizontally centres the caption. A plain XLabel can't
		-- centre text inside an over-wide box, so switch the embedded label to an
		-- XText (UseXTextControl) which supports TextHAlign, stretch it to fill the
		-- button, and centre the text within it.
		UseXTextControl = opts.center_text and true or nil,
	}, parent)
	if opts.center_text and btn.idLabel then
		-- Dock the XText to fill the whole button box, then centre the caption
		-- within it. (A stretch HAlign alone does NOT fill inside the button's
		-- HList layout -- the label stays content-width and packs left -- so we
		-- Dock "box" to make it span the button.) WordWrap off keeps it one line.
		pcall(function() btn.idLabel:SetDock("box") end)
		if btn.idLabel.SetTextHAlign then pcall(function() btn.idLabel:SetTextHAlign("center") end) end
		if btn.idLabel.SetTextVAlign then pcall(function() btn.idLabel:SetTextVAlign("center") end) end
		if btn.idLabel.SetWordWrap then pcall(function() btn.idLabel:SetWordWrap(false) end) end
	end
	btn.OnPress = function() pcall(on_press) end
	return btn
end

-- Attach a single-line XNumberEdit to `parent`. The +/- steppers commit changes
-- live; the field shows the current value. XControl's default text colour is
-- near-black, so we override TextColor/DisabledTextColor to the panel white.
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
		MinHeight = FIELD_HEIGHT,
		MaxHeight = FIELD_HEIGHT,
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
	-- No Dock: the panel is a free-floating, alignment-positioned window (top-
	-- right initially) so the XMoveControl title bar can reposition it by setting
	-- HAlign/VAlign + margins when dragged.
	local panel = x_dialog:new({
		Id = PANEL_ID,
		ZOrder = 9900,
		IdNode = true,
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

	-- Panel body: a plain rectangular frosted XBlurRect filling the ENTIRE panel
	-- (negative margins cancel the padding), with a cool-dark tint for the glassy
	-- infopanel look. No mask and no bordered frame -- the blue reaches the panel
	-- edges, the same width as the full-width title/footer banners. (x_frame is
	-- still resolved here; the title's left cap below uses it.)
	local fill_margins = box(-20, -10, -20, -18)
	local x_frame = rawget(_G, "XFrame")
	local x_blur = rawget(_G, "XBlurRect")
	if x_blur then
		x_blur:new({
			Id = "MartianWatersBlur",
			Dock = "box",
			Margins = fill_margins,
			BlurRadius = 18,
			HandleMouse = false,
		}, panel)
	end
	-- Translucent blue tint across the whole panel (a plain full-rect fill that
	-- reaches the edges), giving the frost its cool infopanel-blue colour.
	x_window:new({
		Id = "MartianWatersTint",
		Dock = "box",
		Margins = fill_margins,
		Background = RGBA(26, 52, 80, 140),
		HandleMouse = false,
	}, panel)

	-- Title, mirroring the vanilla Infopanel "Title" structure (the "Drone Hub"
	-- banner): a left group = rounded cap (rollover_title_left, XFrame) + cyan
	-- accent bar + cyan title, docked left and sized to content; then a right
	-- group filling the rest = the stretched angled banner (rollover_title_right,
	-- XImage stretch-x) + a bright underline. Both images ~half transparent
	-- (Transparency 128) so the frost shows through, exactly as the infopanel.
	-- The title bar doubles as the drag handle: XMoveControl moves its IdNode
	-- ancestor (the panel) when dragged. ChildrenHandleMouse=false so the banner
	-- art/labels don't intercept the drag. Falls back to a static XWindow if
	-- XMoveControl is unavailable.
	local x_image = rawget(_G, "XImage")
	local x_move = rawget(_G, "XMoveControl")
	local title_row = (x_move or x_window):new({
		Id = "MW_TitleRow",
		HAlign = "stretch",
		MinHeight = TITLE_HEIGHT,
		MaxHeight = TITLE_HEIGHT,
		Margins = box(-20, -10, -20, 2),
		HandleMouse = true,
		ChildrenHandleMouse = false,
	}, panel)

	-- Left group: cap + accent bar + title (docked left, content-sized).
	local left_group = x_window:new({ Dock = "left", MaxHeight = TITLE_HEIGHT }, title_row)
	if x_frame then
		x_frame:new({
			Dock = "box",
			Image = "UI/CommonRemaster/rollover_title_left.png",
			FrameBox = box(10, 0, 20, 20),
			Transparency = 128,
			HandleMouse = false,
		}, left_group)
	end
	x_window:new({
		Dock = "left",
		MinWidth = 5, MaxWidth = 5,
		Margins = box(8, 8, 0, 8),
		Background = ACCENT,
		HandleMouse = false,
	}, left_group)
	x_label:new({
		Text = "MARTIAN WATERS",
		Translate = false,
		TextStyle = TITLE_STYLE,
		TextColor = ACCENT,
		Dock = "left",
		VAlign = "center",
		Margins = box(10, 0, 18, 0),
	}, left_group)

	-- Right group: stretched angled banner + underline (fills the rest).
	local right_group = x_window:new({ Dock = "box", MaxHeight = TITLE_HEIGHT }, title_row)
	if x_image then
		x_image:new({
			Dock = "box",
			Image = "UI/CommonRemaster/rollover_title_right.png",
			ImageFit = "stretch-x",
			Transparency = 128,
			Background = RGBA(255, 255, 255, 0),
			HandleMouse = false,
		}, right_group)
	end
	x_window:new({
		Dock = "bottom",
		HAlign = "stretch",
		VAlign = "bottom",
		MinHeight = 1, MaxHeight = 1,
		Margins = box(0, 0, 0, 8),
		Background = RGBA(255, 252, 239, 255),
		Transparency = 220,
		HandleMouse = false,
	}, right_group)

	-- Close (X) button floating in the top-right corner. Dock "ignore" lifts it out
	-- of the panel's VList so it overlays the title bar; it's a direct panel child
	-- (not under the XMoveControl), so clicking it closes rather than drags. A high
	-- ZOrder keeps it above the title banner.
	local close_btn = make_button(panel, "", function()
		UI.Hide()
	end, { icon = "UI/InfopanelRemaster/close.png", min_width = 20, max_width = 20, height = 20 })
	if close_btn then
		pcall(function() close_btn:SetDock("ignore") end)
		pcall(function() close_btn:SetHAlign("right") end)
		pcall(function() close_btn:SetVAlign("top") end)
		pcall(function() close_btn:SetZOrder(50) end)
		pcall(function() close_btn:SetMargins(box(0, -6, -12, 0)) end)
	end

	-- Toggle button, placed above the FRESH WATER banner.
	-- Wrap the toggle in a fixed-height holder and dock the button to "box" inside
	-- it -- same structure as the Clear Waters button in the footer. A box-docked
	-- button gets a full-size content box, which is what lets its centred XText
	-- label actually centre (a plain stretch VList child sizes its content box to
	-- the label, so the caption packs left).
	local toggle_holder = x_window:new({
		HAlign = "stretch",
		MinHeight = ROW_HEIGHT + 6,
		MaxHeight = ROW_HEIGHT + 6,
	}, panel)
	local toggle = make_button(toggle_holder, "Activate Waters Mode", function()
		if MartianWaters.Tool then MartianWaters.Tool.Toggle() end
	end, { center_text = true, height = ROW_HEIGHT + 6 })
	if toggle then
		pcall(function() toggle:SetDock("box") end)
		pcall(function() toggle:SetVAlign("center") end)
	end
	MartianWaters.State.ui_toggle_button = toggle

	add_section(panel, "FRESH WATER", "UI/IconsRemaster/Sections/terraforming.png")

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

	-- One row per parameter: [ label  (unit)  input  -  + ]. The -/+ buttons commit
	-- immediately via on_adjust(delta); the input mirrors the live value.
	local repeat_start = (MartianWaters.Config and MartianWaters.Config.HYDRO_BUTTON_REPEAT_START_MS) or 300
	local repeat_interval = (MartianWaters.Config and MartianWaters.Config.HYDRO_BUTTON_REPEAT_INTERVAL_MS) or 150

	-- Column widths sum to the panel's inner width (PANEL_WIDTH - 32 padding = 304):
	-- 110 label + 52 unit + 66 input + 28 + 28 + 4*4 spacing = 304. The unit
	-- "(m3/s)" sits in its own column between the label (field name) and the input
	-- (field value), rendered as XText so its superscript can use the larger style.
	local LABEL_W, UNIT_W, INPUT_W, STEP_W = 110, 58, 64, 28
	local x_text_row = rawget(_G, "XText")
	local function make_param_row(opts, on_adjust)
		local row = x_window:new({
			Id = opts.id,
			LayoutMethod = "HList",
			LayoutHSpacing = 4,
			HAlign = "stretch",
		}, panel)

		-- Field name (base font).
		local name = (opts.label or ""):gsub(":%s*$", "")
		local label_cls = x_text_row or x_label
		local name_props = {
			Text = name,
			Translate = false,
			TextStyle = TEXT_STYLE,
			TextColor = TEXT_COLOR,
			HAlign = "left",
			VAlign = "center",
			MinWidth = LABEL_W,
			MaxWidth = LABEL_W,
			MinHeight = FIELD_HEIGHT,
			MaxHeight = FIELD_HEIGHT,
			HandleMouse = false,
		}
		if x_text_row then name_props.WordWrap = false end
		label_cls:new(name_props, row)

		-- Unit slot, e.g. "(m3/s)". The superscript digit is rendered as its OWN
		-- small control nudged UP (the inline <style> size tag has no effect in this
		-- build, but a control's own TextStyle does -- as the labels prove). Pieces
		-- sit tight in a zero-spacing HList so they read as one "(m3/s)".
		local hint = opts.hint or ""
		local unit_holder = x_window:new({
			LayoutMethod = "HList",
			LayoutHSpacing = 0,
			HAlign = "left",
			VAlign = "center",
			MinWidth = UNIT_W,
			MaxWidth = UNIT_W,
			MinHeight = FIELD_HEIGHT,
			MaxHeight = FIELD_HEIGHT,
		}, row)
		local function unit_piece(text, opt)
			opt = opt or {}
			local cls = x_text_row or x_label
			local p = {
				Text = text,
				Translate = false,
				TextStyle = opt.style or TEXT_STYLE,
				TextColor = TEXT_COLOR,   -- whole unit (incl. the superscript) = main text colour
				HAlign = "left",
				VAlign = "center",
				Margins = opt.margins or box(0, 0, 0, 0),
				Padding = box(0, 0, 0, 0),
				MinHeight = FIELD_HEIGHT,
				MaxHeight = FIELD_HEIGHT,
				HandleMouse = false,
			}
			if x_text_row then p.WordWrap = false end
			cls:new(p, unit_holder)
		end
		if hint ~= "" then
			local pos = hint:find("³") or hint:find("²")
			if pos then
				local digit = hint:find("³") and "3" or "2"
				local prefix = hint:sub(1, pos - 1)      -- e.g. "m"
				local suffix = hint:sub(pos + 2)         -- the "³"/"²" is 2 UTF-8 bytes
				unit_piece("(" .. prefix)
				-- Superscript digit: SAME font as the labels, sized ~60% of the main
				-- text (SchemeBk @11 via the custom style) and baseline-shifted up ~33%
				-- of the main text (~6px) -- standard superscript proportions.
				unit_piece(digit, { style = MartianWaters.SUPERSCRIPT_STYLE, margins = box(0, -6, 0, 0) })
				unit_piece(suffix .. ")")
			else
				unit_piece("(" .. hint .. ")")
			end
		end

		local edit = make_number_edit(row, {
			halign = "left",
			min_width = INPUT_W,
			max_width = INPUT_W,
			min_value = 0,
			max_value = opts.max_value,
		})

		make_button(row, "-", function()
			if not MartianWaters.Tool then return end
			on_adjust(-(opts.step or 1))
			UI.Refresh()
		end, {
			halign = "left", min_width = STEP_W, max_width = STEP_W, height = FIELD_HEIGHT,
			icon = "UI/CommonRemaster/arrow_remove.png",
			repeat_start = repeat_start, repeat_interval = repeat_interval,
		})

		make_button(row, "+", function()
			if not MartianWaters.Tool then return end
			on_adjust(opts.step or 1)
			UI.Refresh()
		end, {
			halign = "left", min_width = STEP_W, max_width = STEP_W, height = FIELD_HEIGHT,
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
		label = "Height:",
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
		label = "Inflow:",
		max_value = (MartianWaters.Config and MartianWaters.Config.HYDRO_DISCHARGE_MAX_M3S) or 100,
		step = (MartianWaters.Config and MartianWaters.Config.HYDRO_DISCHARGE_STEP_M3S) or 0.5,
		hint = "m³/s",
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
		label = "Drainage:",
		max_value = (MartianWaters.Config and MartianWaters.Config.HYDRO_DRAINAGE_MAX_M3S) or 100,
		step = (MartianWaters.Config and MartianWaters.Config.HYDRO_DRAINAGE_STEP_M3S) or 0.5,
		hint = "m³/s",
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
		label = "Evaporation:",
		max_value = (MartianWaters.Config and MartianWaters.Config.HYDRO_EVAPORATION_MAX_M3S) or 100,
		step = (MartianWaters.Config and MartianWaters.Config.HYDRO_EVAPORATION_STEP_M3S) or 0.1,
		hint = "m³/s",
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
		label = "Infiltration:",
		max_value = (MartianWaters.Config and MartianWaters.Config.HYDRO_INFILTRATION_MAX_M3S) or 100,
		step = (MartianWaters.Config and MartianWaters.Config.HYDRO_INFILTRATION_STEP_M3S) or 0.1,
		hint = "m³/s",
	}, function(delta)
		MartianWaters.Tool.AdjustInfiltration(delta)
	end)
	if infiltration_edit then
		MartianWaters.State.ui_infiltration_edit = infiltration_edit
	else
		DebugLog.Warn(SCOPE, "XNumberEdit unavailable, infiltration input field omitted")
	end

	-- Read-only readouts: volume, surface area, flooded tile count -- each on its
	-- own line. Volume/Surface carry a unit superscript rendered the SAME way as the
	-- field units: a prefix XText plus a separate small raised digit.
	local x_text = rawget(_G, "XText")
	local READOUT_HEIGHT = 34
	-- A plain single-control readout line (Flooded Tiles, and the no-XText fallback).
	local function make_readout(initial)
		local cls = x_text or x_label
		local props = {
			Text = initial,
			Translate = false,
			TextStyle = READOUT_STYLE,
			TextColor = TEXT_COLOR,
			HAlign = "stretch",
			MinHeight = READOUT_HEIGHT,
			MaxHeight = READOUT_HEIGHT,
		}
		if x_text then props.WordWrap = false end
		return cls:new(props, panel)
	end
	-- "<prefix> m" + a small raised unit digit. Returns (prefix, digit) so
	-- update_readouts can set the text and show/hide the digit. The digit starts
	-- hidden (the initial value is the "--" placeholder).
	local function make_super_readout(digit_char)
		if not x_text then return make_readout(""), nil end
		local row = x_window:new({
			LayoutMethod = "HList", LayoutHSpacing = 0,
			HAlign = "stretch", VAlign = "center",
			MinHeight = READOUT_HEIGHT, MaxHeight = READOUT_HEIGHT,
		}, panel)
		local function piece(props)
			props.Translate = false
			props.TextStyle = props.TextStyle or READOUT_STYLE
			props.TextColor = TEXT_COLOR
			props.HAlign = "left"
			props.VAlign = "center"
			props.WordWrap = false
			props.Padding = box(0, 0, 0, 0)
			props.MinHeight = READOUT_HEIGHT
			props.MaxHeight = READOUT_HEIGHT
			props.HandleMouse = false
			return x_text:new(props, row)
		end
		local prefix = piece({ Text = "" })
		local digit = piece({ Text = digit_char, TextStyle = MartianWaters.SUPERSCRIPT_STYLE,
			Margins = box(0, -6, 0, 0), Visible = false })
		return prefix, digit
	end
	MartianWaters.State.ui_volume_label, MartianWaters.State.ui_volume_digit = make_super_readout("3")
	MartianWaters.State.ui_area_label, MartianWaters.State.ui_area_digit = make_super_readout("2")
	MartianWaters.State.ui_tiles_label = make_readout("Flooded Tiles: --")

	-- Sea section: its own banner, separating the map-wide sea control from the
	-- per-source fresh-water controls above.
	add_section(panel, "SEA", "UI/Icons/res_water.png", 3)  -- shrink the drop to match the Rain glyph

	-- Sea level row: the sole sea control. A positive level auto-generates the sea
	-- (flooding the whole map below it) or sets it; <= 0 removes the sea. -/+ adjust
	-- it live, independent of which marker is selected.
	local sealevel_edit = make_param_row({
		id = "MartianWatersSeaLevelRow",
		label = "Sea Level:",
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
	add_section(panel, "RAIN", "UI/IconsRemaster/CommandCenter/water_on.png")

	-- Single toggle for the rain disaster: label/colour reflect the live state
	-- (set by update_rain_label on Refresh). Press toggles start/stop.
	MartianWaters.State.ui_rain_disaster_button = make_button(panel, "Start Rain", function()
		local Rain = MartianWaters.Rain
		if not Rain then return end
		if Rain.GetDisasterType() then Rain.StopDisaster() else Rain.StartDisaster() end
		UI.Refresh()
	end)

	-- Single toggle for the cosmetic-only visual rain override.
	MartianWaters.State.ui_rain_visual_button = make_button(panel, "Start Rain (only visual effect)", function()
		local Rain = MartianWaters.Rain
		if not Rain then return end
		if Rain.IsVisualActive() then Rain.StopVisual() else Rain.StartVisual() end
		UI.Refresh()
	end)

	-- Clouds section: drives the engine cloud-shadow system (mw_clouds.lua).
	add_section(panel, "CLOUDS", "UI/IconsRemaster/CommandCenter/atmosphere_on.png")

	-- Toggle for cloud-shadow rendering (hr.EnableCloudsShadow); label reflects
	-- live state via update_cloud_label on Refresh.
	MartianWaters.State.ui_cloud_toggle_button = make_button(panel, "Cloud Shadows: On", function()
		if MartianWaters.Tool and MartianWaters.Tool.ToggleCloudShadows then
			MartianWaters.Tool.ToggleCloudShadows()
		end
		UI.Refresh()
	end)

	-- Coverage row: how much of the surface the cloud shadows cover (0..100 %).
	local cloud_coverage_edit = make_param_row({
		id = "MartianWatersCloudCoverageRow",
		label = "Coverage:",
		max_value = (MartianWaters.Config and MartianWaters.Config.CLOUD_COVERAGE_MAX_PCT) or 100,
		step = (MartianWaters.Config and MartianWaters.Config.CLOUD_COVERAGE_STEP_PCT) or 10,
		hint = "%",
	}, function(delta)
		if MartianWaters.Tool and MartianWaters.Tool.AdjustCloudCoverage then
			MartianWaters.Tool.AdjustCloudCoverage(delta)
		end
	end)
	if cloud_coverage_edit then
		MartianWaters.State.ui_cloud_coverage_edit = cloud_coverage_edit
	end

	-- Speed row: cloud movement speed in meters / second.
	local cloud_speed_edit = make_param_row({
		id = "MartianWatersCloudSpeedRow",
		label = "Speed:",
		max_value = (MartianWaters.Config and MartianWaters.Config.CLOUD_SPEED_MAX_M) or 50,
		step = (MartianWaters.Config and MartianWaters.Config.CLOUD_SPEED_STEP_M) or 0.5,
		hint = "m/s",
	}, function(delta)
		if MartianWaters.Tool and MartianWaters.Tool.AdjustCloudSpeed then
			MartianWaters.Tool.AdjustCloudSpeed(delta)
		end
	end)
	if cloud_speed_edit then
		MartianWaters.State.ui_cloud_speed_edit = cloud_speed_edit
	end

	-- Footer action bar: Clear Waters (fills the toggle-width column) plus a small
	-- info button on its right whose hover tooltip explains every field. The band
	-- has a 20px inner padding so its content lines up with the Activate Waters
	-- Mode button's column above.
	local footer = x_window:new({
		Id = "MW_Footer",
		HAlign = "stretch",
		MinHeight = 61,   -- tall enough for the enlarged info button
		MaxHeight = 61,
		Margins = box(-20, 6, -20, -18),   -- span to the panel edges; bottom -18
		                                   -- matches the background fill's bottom edge
		Padding = box(20, 0, 20, 0),       -- align content with the toggle column
		Background = RGBA(6, 12, 20, 160), -- darker than the body, like the vanilla footer
	}, panel)

	-- Info button (docked right). Hovering shows the field guide via the game's
	-- standard "MarsRollover" tooltip template.
	local INFO_TEXT = table.concat({
		"FRESH WATER (per source -- click a hole first):",
		"Height: water level in metres above the basin floor; +/- snaps it instantly.",
		"Inflow: water added per second (m3/s).",
		"Drainage: water removed per second (m3/s).",
		"Evaporation: surface loss per second (m3/s).",
		"Infiltration: ground-soak loss per second (m3/s).",
		"   Level rises when Inflow exceeds Drainage + Evaporation + Infiltration.",
		"Volume / Surface / Flooded Tiles: live readouts of the selected body.",
		"",
		"SEA:",
		"Sea Level: metres above the map's lowest point. A positive value floods the",
		"   whole map below it (auto-generates the sea); <= 0 removes the sea.",
		"",
		"CLOUDS (cloud-shadow layer):",
		"Cloud Shadows: toggles shadow rendering on the ground.",
		"Coverage: how much of the surface the shadows cover (%).",
		"Speed: how fast the shadows drift (m/s).",
	}, "\n")

	-- info.png is a 2-COLUMN icon (left = normal, right = hover). The ICON (not the
	-- frame) supports column splitting via IconColumns/IconColumn, so we show
	-- column 1 normally and swap to column 2 on rollover. (Using it as the frame
	-- Image made the button vanish; using it as a plain icon showed both frames.)
	local INFO_SIZE = 57   -- ~30% larger again, matching the HUD info button
	local info_btn = make_button(footer, "", function() end, {
		icon = "UI/HUDRemaster/info.png",
		min_width = INFO_SIZE, max_width = INFO_SIZE, height = INFO_SIZE,
	})
	if info_btn then
		pcall(function() info_btn:SetPadding(box(2, 2, 2, 2)) end)
		-- No background box at all (the HUD's no-frame button has none). The faint
		-- rollover square that make_button adds for icon buttons is removed here so
		-- the only hover feedback is the honeycomb glow.
		pcall(function() info_btn:SetBackground(RGBA(0, 0, 0, 0)) end)
		pcall(function() info_btn:SetFocusedBackground(RGBA(0, 0, 0, 0)) end)
		pcall(function() info_btn:SetRolloverBackground(RGBA(0, 0, 0, 0)) end)
		pcall(function() info_btn:SetPressedBackground(RGBA(0, 0, 0, 0)) end)
		-- Keep the plain info circle ALWAYS (column 1). info.png's column 2 is a
		-- circle-inside-a-hexagon hover frame -- swapping to it is what drew the
		-- unwanted hexagon. We never swap; the hover effect is the honeycomb behind.
		pcall(function() info_btn:SetIconColumns(2) end)
		pcall(function() info_btn:SetIconColumn(1) end)
		-- Dock the icon to "box" so it's centred over the (also box-docked) glow.
		-- Otherwise it sits in the button's HList layout and packs left, off-centre
		-- from the honeycomb. Scale it up to fill, kept above the honeycomb.
		pcall(function() info_btn:SetIconDock("box") end)
		if info_btn.idIcon then
			pcall(function() info_btn.idIcon:SetImageFit("smallest") end)
			pcall(function() info_btn.idIcon:SetZOrder(1) end)
		end
		-- Honeycomb hover glow (HUD no-frame button uses autosave_shine.png). Docked
		-- to fill the button so it renders reliably; shown only on rollover, behind
		-- the icon. Transparency 80 like the HUD.
		local x_image = rawget(_G, "XImage")
		local hex = x_image and x_image:new({
			Id = "MW_InfoHex",
			Dock = "box",
			Margins = box(-10, -10, -10, -10),  -- glow a bit larger than the icon
			Visible = false,
			Transparency = 80,
			Image = "UI/CommonRemaster/autosave_shine.png",
			ImageFit = "smallest",
			HandleMouse = false,
			ZOrder = 0,
			Clip = false,
		}, info_btn)
		-- On hover: show the honeycomb glow AND swap the icon to its lighter column-2
		-- frame. Override SetRollover -- the exact hook the HUD's no-frame button
		-- overrides -- so it reliably tracks the mouse.
		local base_sr = info_btn.SetRollover
		info_btn.SetRollover = function(self, rollover)
			if base_sr then base_sr(self, rollover) end
			if hex then pcall(function() hex:SetVisible(rollover and true or false) end) end
			pcall(function() self:SetIconColumn(rollover and 2 or 1) end)
		end
		pcall(function() info_btn:SetDock("right") end)
		pcall(function() info_btn:SetVAlign("center") end)
		pcall(function() info_btn:SetMargins(box(8, 0, 0, 0)) end)
		pcall(function() info_btn:SetRolloverTemplate("MarsRollover") end)
		pcall(function() info_btn:SetRolloverText(INFO_TEXT) end)
	end

	-- Clear Waters fills the rest of the band to the left of the info button.
	local clear_btn = make_button(footer, "Clear Waters", function()
		if type(MartianWaters.ClearAll) == "function" then
			MartianWaters.ClearAll()
		end
		UI.Refresh()
	end, { min_width = 0, max_width = PANEL_WIDTH, center_text = true })
	if clear_btn then
		pcall(function() clear_btn:SetDock("box") end)
		pcall(function() clear_btn:SetVAlign("center") end)
	end

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
