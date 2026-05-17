-- Bottom-right Force Delete diagnostic panel.

-- Attach to the shared Force Delete namespace created by ForceDelete.lua.
local FD = ForceDelete
if not FD then return end

-- Prevent duplicate panel classes and hooks if the mod reloads.
if FD.display_attributes_loaded then return end
FD.display_attributes_loaded = true

-- Create the display namespace used by other modules.
FD.DisplayAttributes = FD.DisplayAttributes or {}
local Display = FD.DisplayAttributes

-- Panel constants mirror the working Attribute Inspector approach.
local PANEL_ID = "ForceDeleteInspectorDialog"
local PANEL_TITLE = "Force-delete Inspector"
local PANEL_BACKGROUND = RGBA(0, 0, 0, 230)
local TRANSPARENT = RGBA(0, 0, 0, 0)
local PANEL_Z_ORDER = 10000
local dialog = false

-- Keep this panel fully controlled by the config switch.
local function ShouldDisplay()
	return not FD.Config
		or not FD.Config.ShouldDisplayAttributes
		or FD.Config.ShouldDisplayAttributes()
end

-- Check whether a UI window can still be updated.
local function IsWindowAlive(win)
	return win
		and win.window_state ~= "destroying"
		and win.window_state ~= "destroyed"
end

-- Find a child control by id across engine versions.
local function PanelControl(id)
	if not dialog then
		return false
	end

	local ok, control = pcall(function()
		return dialog[id]
	end)

	return ok and control or false
end

-- Update a text control without surfacing stale-window errors.
local function SetControlText(control, text)
	if control and type(control.SetText) == "function" then
		pcall(function()
			control:SetText(text)
		end)
	end
end

-- Reset the scroll position only after new text is installed.
local function ResetScroll()
	local scroll_area = PanelControl("idScrollArea")

	if scroll_area and type(scroll_area.ScrollTo) == "function" then
		pcall(function()
			scroll_area:ScrollTo(0, 0, true)
		end)
	end
end

DefineClass.ForceDeleteAttributesPanel = {
	__parents = { "XDialog" },
	IdNode = true,
	Dock = "box",
	HAlign = "right",
	VAlign = "bottom",
	Margins = box(0, 0, 20, 80),
	Padding = box(8, 8, 8, 8),
	LayoutMethod = "VList",
	LayoutVSpacing = 4,
	Clip = "self",
	MinWidth = 520,
	MaxWidth = 680,
	MinHeight = 300,
	MaxHeight = 600,
	Background = PANEL_BACKGROUND,
	FocusedBackground = PANEL_BACKGROUND,
	DisabledBackground = PANEL_BACKGROUND,
	HandleMouse = false,
	ChildrenHandleMouse = true,
}

-- Create a plain text body when scroll controls are unavailable.
local function CreatePlainBody(panel)
	panel.idBody = XText:new({
		Id = "idBody",
		Text = "No object selected.",
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = RGB(255, 255, 255),
		HAlign = "stretch",
		VAlign = "top",
		WordWrap = true,
		MinHeight = 220,
		MaxHeight = 500,
		UseClipBox = true,
		HandleMouse = false,
	}, panel)
end

-- Create a scrollable text body using the engine's standard XScrollArea pattern.
local function CreateScrollableBody(panel)
	if not XWindow or not XScrollArea or not XText then
		return false
	end

	local scroll_class = XSleekScroll or Scrollbar
	if not scroll_class then
		return false
	end

	local ok = pcall(function()
		local body_container = XWindow:new({
			Id = "idBodyContainer",
			HAlign = "stretch",
			VAlign = "stretch",
			LayoutMethod = "HList",
			MinWidth = 480,
			MaxWidth = 640,
			MinHeight = 220,
			MaxHeight = 500,
			Background = TRANSPARENT,
			FocusedBackground = TRANSPARENT,
			DisabledBackground = TRANSPARENT,
			HandleMouse = false,
			ChildrenHandleMouse = true,
		}, panel)

		local scroll_area = XScrollArea:new({
			Id = "idScrollArea",
			IdNode = false,
			HAlign = "stretch",
			VAlign = "stretch",
			MinWidth = 480,
			MaxWidth = 640,
			MinHeight = 220,
			MaxHeight = 500,
			VScroll = "idScroll",
			MouseScroll = true,
			Background = TRANSPARENT,
			FocusedBackground = TRANSPARENT,
			DisabledBackground = TRANSPARENT,
			HandleMouse = true,
		}, body_container)
		panel.idScrollArea = scroll_area

		panel.idBody = XText:new({
			Id = "idBody",
			Text = "No object selected.",
			Translate = false,
			TextStyle = "ConsoleLog",
			TextColor = RGB(255, 255, 255),
			HAlign = "stretch",
			VAlign = "top",
			WordWrap = true,
			MinHeight = 220,
			HandleMouse = false,
		}, scroll_area)

		panel.idScroll = scroll_class:new({
			Id = "idScroll",
			Dock = "right",
			Target = "idScrollArea",
			AutoHide = true,
		}, body_container)
	end)

	return ok
end

-- Build the panel controls and keep text refreshed while the panel exists.
function ForceDeleteAttributesPanel:Init()
	dialog = self

	self.idTitle = XLabel:new({
		Id = "idTitle",
		Text = PANEL_TITLE,
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = RGB(255, 255, 255),
		RolloverTextColor = RGB(255, 255, 255),
		HAlign = "stretch",
		VAlign = "top",
		HandleMouse = false,
	}, self)

	-- Prefer a scrollable body, but keep the simple panel working if scrolling fails.
	if not CreateScrollableBody(self) then
		CreatePlainBody(self)
	end
end

-- Create the panel when the game UI parent is available.
function Display.EnsurePanel()
	if not ShouldDisplay() then
		Display.Hide()
		return false
	end

	if IsWindowAlive(dialog) then
		return dialog
	end

	local get_interface = rawget(_G, "GetInGameInterface")
	local terminal = rawget(_G, "terminal")
	local parent = type(get_interface) == "function" and get_interface() or false
	parent = parent or (terminal and terminal.desktop)

	if not parent then
		return false
	end

	pcall(function()
		dialog = ForceDeleteAttributesPanel:new({
			Id = PANEL_ID,
			ZOrder = PANEL_Z_ORDER,
		}, parent)
	end)

	Display.UpdatePanel()
	return dialog
end

-- Close the panel.
function Display.Hide()
	if not IsWindowAlive(dialog) then
		dialog = false
		return
	end

	pcall(function()
		if dialog.Close then
			dialog:Close()
		elseif dialog.Delete then
			dialog:Delete()
		end
	end)

	dialog = false
end

-- Update the visible text.
function Display.UpdatePanel()
	if not ShouldDisplay() then
		Display.Hide()
		return false
	end

	if not IsWindowAlive(dialog) then
		return false
	end

	SetControlText(PanelControl("idTitle"), PANEL_TITLE)
	SetControlText(PanelControl("idBody"), Display.last_text or "No object selected.")

	if Display.needs_scroll_reset then
		ResetScroll()
		Display.needs_scroll_reset = false
	end

	return true
end

-- Format a table of rows for display.
function Display.FormatAttributes(attributes)
	local lines = {}

	if type(attributes) == "table" then
		if attributes.title then
			lines[#lines + 1] = tostring(attributes.title)
			lines[#lines + 1] = ""
		end

		-- Rows are intentionally flat key/value pairs to keep the panel readable.
		for _, row in ipairs(attributes.rows or {}) do
			lines[#lines + 1] = tostring(row[1]) .. ": " .. tostring(row[2])
		end
	else
		lines[#lines + 1] = tostring(attributes)
	end

	return table.concat(lines, "\n")
end

-- Store and show panel text.
function Display.SetText(text)
	local next_text = tostring(text or "No object selected.")

	-- Avoid needless text writes and scroll resets during periodic refreshes.
	if Display.last_text == next_text then
		Display.EnsurePanel()
		Display.UpdatePanel()
		return
	end

	Display.last_text = next_text
	Display.needs_scroll_reset = true
	Display.EnsurePanel()
	Display.UpdatePanel()
end

-- Show structured attributes.
function Display.Show(attributes)
	Display.SetText(Display.FormatAttributes(attributes))
end

-- Show a simple message.
function Display.ShowMessage(message)
	Display.SetText(tostring(message or ""))
end

-- Create the default panel text.
function Display.ShowInitialMessage()
	Display.ShowMessage("No object selected.")
end

-- Start visible by default when DISPLAY_ATTRIBUTES is enabled.
Display.ShowInitialMessage()
