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
local PANEL_ID = "ForceDeleteAttributesDialog"
local PANEL_Z_ORDER = 10000
local POLL_THREAD = "ForceDeleteAttributesPoll"
local POLL_INTERVAL_MS = 250
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

-- Read UI/object fields defensively.
local function ReadField(obj, field)
	if not obj then
		return nil
	end

	local ok, value = pcall(function()
		return obj[field]
	end)

	return ok and value or nil
end

-- Find a child control by id across engine versions.
local function PanelControl(id)
	if not dialog then
		return false
	end

	local control = ReadField(dialog, id)
	if control then
		return control
	end

	local resolve_id = ReadField(dialog, "ResolveId")
	if type(resolve_id) == "function" then
		local ok, resolved = pcall(function()
			return dialog:ResolveId(id)
		end)
		return ok and resolved or false
	end

	return false
end

-- Update a text control without surfacing stale-window errors.
local function SetControlText(control, text)
	if type(ReadField(control, "SetText")) == "function" then
		pcall(function()
			control:SetText(text)
		end)
	end
end

-- Split stored text into a fixed title and panel body.
local function SplitText(text)
	text = tostring(text or "No object selected.")
	local prefix = "Force Delete\n\n"

	if text:sub(1, #prefix) == prefix then
		return "Force Delete", text:sub(#prefix + 1)
	end

	return "Force Delete", text
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
	Background = RGBA(0, 0, 0, 230),
	HandleMouse = true,
}

-- Build the panel controls and keep text refreshed while the panel exists.
function ForceDeleteAttributesPanel:Init()
	dialog = self

	self.idTitle = XLabel:new({
		Id = "idTitle",
		Text = "Force Delete",
		Translate = false,
		TextStyle = "ConsoleLog",
		TextColor = RGB(255, 255, 255),
		HAlign = "stretch",
		VAlign = "top",
	}, self)

	self.idBody = XText:new({
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
	}, self)

	if self.CreateThread then
		-- Keep the panel text synchronized while the window exists.
		self:CreateThread(POLL_THREAD, function(panel)
			local sleep = rawget(_G, "Sleep")

			while IsWindowAlive(panel) do
				dialog = panel
				pcall(Display.UpdatePanel)

				if type(sleep) ~= "function" then
					break
				end

				sleep(POLL_INTERVAL_MS)
			end
		end, self)
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

	local title, body = SplitText(Display.last_text)
	SetControlText(PanelControl("idTitle"), title)
	SetControlText(PanelControl("idBody"), body)
	return true
end

-- Format a table of rows for display.
function Display.FormatAttributes(attributes)
	local lines = { "Force Delete", "" }

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
	Display.last_text = tostring(text or "No object selected.")
	Display.EnsurePanel()
	Display.UpdatePanel()
end

-- Show structured attributes.
function Display.Show(attributes)
	Display.SetText(Display.FormatAttributes(attributes))
end

-- Show a simple message.
function Display.ShowMessage(message)
	Display.SetText("Force Delete\n\n" .. tostring(message or ""))
end

-- Create the default panel text.
function Display.ShowInitialMessage()
	Display.ShowMessage("No object selected.")
end

-- Start visible by default when DISPLAY_ATTRIBUTES is enabled.
Display.ShowInitialMessage()
