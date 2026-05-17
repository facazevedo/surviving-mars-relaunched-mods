-- Force Delete attribute display.
-- This module deliberately follows the Attribute Inspector panel pattern:
-- one persistent bottom-right XDialog, a title label, a body text control,
-- and direct refresh hooks that do not depend on object selection.

-- ============================================================================
-- Module setup
-- ============================================================================

local FD = ForceDelete
if not FD then return end

if FD.display_attributes_loaded then return end

-- Attribute Inspector defines its panel only when the UI class helpers exist.
-- If this file is loaded earlier, return without setting the guard so the main
-- loader can retry from ClassesPostprocess/DataLoaded.
if type(rawget(_G, "DefineClass")) ~= "table"
	or type(rawget(_G, "box")) ~= "function"
	or type(rawget(_G, "RGBA")) ~= "function" then
	return
end

FD.DisplayAttributes = FD.DisplayAttributes or {}
FD.display_attributes_loaded = true

local Display = FD.DisplayAttributes
local PANEL_ID = "ForceDeleteAttributesDialog"
local POLL_THREAD = "ForceDeleteAttributesPoll"
local POLL_INTERVAL_MS = 250
local PANEL_Z_ORDER = 10000

local ForceDeleteAttributesDialog = false

-- ============================================================================
-- Local safe helpers
-- ============================================================================

-- Return an optional engine global without triggering mod-environment errors.
local function Global(name)
	return rawget(_G, name)
end

-- Invoke an optional function and return false instead of propagating errors.
local function SafeCall(fn, ...)
	if type(fn) ~= "function" then
		return false
	end

	local ok, result = pcall(fn, ...)
	if ok then
		return result
	end

	return false
end

-- Check whether an X window can still be safely updated.
local function IsWindowAlive(win)
	return win
		and win.window_state ~= "destroying"
		and win.window_state ~= "destroyed"
end

-- Read a field safely from game UI userdata/table objects.
local function ReadField(obj, field)
	if not obj then
		return nil
	end

	local ok, value = pcall(function()
		return obj[field]
	end)

	return ok and value or nil
end

-- Update a text control while swallowing stale-window errors.
local function SetText(control, text)
	if type(ReadField(control, "SetText")) == "function" then
		pcall(function()
			control:SetText(text)
		end)
	end
end

-- Find a panel child control by id across engine versions.
local function PanelControl(id)
	if not ForceDeleteAttributesDialog then
		return false
	end

	local control = ReadField(ForceDeleteAttributesDialog, id)
	if control then
		return control
	end

	local resolve_id = ReadField(ForceDeleteAttributesDialog, "ResolveId")
	if type(resolve_id) == "function" then
		local ok, resolved = pcall(function()
			return ForceDeleteAttributesDialog:ResolveId(id)
		end)

		if ok then
			return resolved
		end
	end

	return false
end

-- Return the effective display setting. DISPLAY_ATTRIBUTES is the master switch
-- for whether this panel exists at all.
local function ShouldDisplay()
	return not FD.Config
		or not FD.Config.ShouldDisplayAttributes
		or FD.Config.ShouldDisplayAttributes()
end

-- Print fallback diagnostics if the UI cannot be created yet.
local function FallbackPrint(text)
	local print_fn = Global("print")
	if type(print_fn) == "function" then
		pcall(print_fn, "[ForceDelete] " .. tostring(text))
	end
end

-- ============================================================================
-- Panel text model
-- ============================================================================

-- Split full display text into the fixed panel title and the body content.
local function SplitPanelText(text)
	local full_text = tostring(text or "No object selected.")
	local prefix = "Force Delete\n\n"

	if full_text:sub(1, #prefix) == prefix then
		return "Force Delete", full_text:sub(#prefix + 1)
	end

	return "Force Delete", full_text
end

-- Store the full text that should appear in the panel body.
local function SetStoredText(text)
	Display.last_text = tostring(text or "No object selected.")
end

-- ============================================================================
-- Attribute Inspector-style panel
-- ============================================================================

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

-- Construct child controls and start a lightweight polling fallback thread.
function ForceDeleteAttributesPanel:Init()
	ForceDeleteAttributesDialog = self

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
		self:CreateThread(POLL_THREAD, function(dialog)
			local sleep = Global("Sleep")

			while IsWindowAlive(dialog) do
				ForceDeleteAttributesDialog = dialog
				pcall(Display.UpdatePanel)

				if type(sleep) ~= "function" then
					break
				end

				sleep(POLL_INTERVAL_MS)
			end
		end, self)
	end
end

-- ============================================================================
-- Panel lifecycle
-- ============================================================================

-- Create the Force Delete panel once the in-game UI parent is available.
function Display.EnsurePanel()
	if not ShouldDisplay() then
		Display.DestroyPanel()
		return false
	end

	local parent = false
	local ok = pcall(function()
		local get_interface = Global("GetInGameInterface")
		local terminal = Global("terminal")

		parent = type(get_interface) == "function" and get_interface() or false
		parent = parent or (terminal and terminal.desktop)
	end)

	if not ok or not parent or IsWindowAlive(ForceDeleteAttributesDialog) then
		return ForceDeleteAttributesDialog
	end

	pcall(function()
		ForceDeleteAttributesDialog = ForceDeleteAttributesPanel:new({
			Id = PANEL_ID,
			ZOrder = PANEL_Z_ORDER,
		}, parent)
	end)

	pcall(Display.UpdatePanel)
	return ForceDeleteAttributesDialog
end

-- Close the panel when the config disables it or during manual refreshes.
function Display.DestroyPanel()
	if not IsWindowAlive(ForceDeleteAttributesDialog) then
		ForceDeleteAttributesDialog = false
		return
	end

	pcall(function()
		if ForceDeleteAttributesDialog.Close then
			ForceDeleteAttributesDialog:Close()
		elseif ForceDeleteAttributesDialog.Delete then
			ForceDeleteAttributesDialog:Delete()
		end
	end)

	ForceDeleteAttributesDialog = false
	Display.panel = false
end

-- Hide the panel without changing the stored text.
function Display.Hide()
	Display.DestroyPanel()
end

-- Report whether the panel exists and can still be written to.
function Display.HasPanel()
	return IsWindowAlive(ForceDeleteAttributesDialog)
end

-- Refresh the panel with the stored text, or close it when disabled.
function Display.UpdatePanel()
	if not ShouldDisplay() then
		Display.DestroyPanel()
		return false
	end

	if not IsWindowAlive(ForceDeleteAttributesDialog) then
		return false
	end

	local title_text, body_text = SplitPanelText(Display.last_text or "No object selected.")
	SetText(PanelControl("idTitle"), title_text)
	SetText(PanelControl("idBody"), body_text)
	Display.panel = ForceDeleteAttributesDialog
	return true
end

-- Ensure the panel exists and then update it.
function Display.RefreshPanel()
	Display.EnsurePanel()
	Display.UpdatePanel()
end

-- Retry panel creation without changing the current diagnostic message.
function Display.RefreshPanelIfMissing()
	if Display.HasPanel() then
		Display.UpdatePanel()
		return true
	end

	Display.RefreshPanel()
	return Display.HasPanel()
end

-- ============================================================================
-- Text formatting and updates
-- ============================================================================

-- Format a structured attributes table into compact readable text.
function Display.FormatAttributes(attributes)
	local lines = { "Force Delete", "" }

	if type(attributes) ~= "table" then
		lines[#lines + 1] = tostring(attributes)
		return table.concat(lines, "\n")
	end

	if attributes.title then
		lines[#lines + 1] = tostring(attributes.title)
		lines[#lines + 1] = ""
	end

	for _, row in ipairs(attributes.rows or {}) do
		lines[#lines + 1] = tostring(row[1]) .. ": " .. tostring(row[2])
	end

	return table.concat(lines, "\n")
end

-- Set panel text, falling back to the log if UI creation is unavailable.
function Display.SetText(text)
	SetStoredText(text)

	if not ShouldDisplay() then
		Display.DestroyPanel()
		return false
	end

	Display.RefreshPanel()

	if not Display.HasPanel() then
		FallbackPrint(Display.last_text)
		return false
	end

	return true
end

-- Show structured attributes from an object-specific diagnostic module.
function Display.Show(attributes)
	return Display.SetText(Display.FormatAttributes(attributes))
end

-- Show a simple diagnostic message.
function Display.ShowMessage(message)
	return Display.SetText("Force Delete\n\n" .. tostring(message or ""))
end

-- Ensure the default empty-selection message exists before selection monitoring
-- runs. If DISPLAY_ATTRIBUTES is true, this creates the panel immediately when
-- the UI parent is available.
function Display.ShowInitialMessage()
	if not Display.last_text then
		SetStoredText("Force Delete\n\nNo object selected.")
	end

	Display.RefreshPanel()
end

-- Install direct refresh hooks for common UI lifecycle messages.
function Display.InstallPanelRefreshHooks()
	if Display.panel_refresh_hooks_installed then
		return
	end

	Display.panel_refresh_hooks_installed = true

	local function refresh_panel()
		Display.ShowInitialMessage()
	end

	if FD.ChainOnMsg then
		FD.ChainOnMsg("ClassesPostprocess", "display_attributes_panel", refresh_panel)
		FD.ChainOnMsg("DataLoaded", "display_attributes_panel", refresh_panel)
		FD.ChainOnMsg("InGameInterfaceCreated", "display_attributes_panel", refresh_panel)
		FD.ChainOnMsg("SelectedObjChange", "display_attributes_panel", refresh_panel)
		FD.ChainOnMsg("SelectionChange", "display_attributes_panel", refresh_panel)
		FD.ChainOnMsg("SelectionAdded", "display_attributes_panel", refresh_panel)
		FD.ChainOnMsg("SelectionRemoved", "display_attributes_panel", refresh_panel)
		FD.ChainOnMsg("GameEnterEditor", "display_attributes_panel", refresh_panel)
		FD.ChainOnMsg("GameExitEditor", "display_attributes_panel", refresh_panel)
	end
end

-- Start a bounded startup retry, matching the Attribute Inspector idea that the
-- panel should keep trying until the in-game UI parent exists.
function Display.StartPanelRetry()
	if Display.panel_retry_started then
		return
	end

	Display.panel_retry_started = true

	local create_thread = Global("CreateRealTimeThread") or Global("CreateGameTimeThread")
	if type(create_thread) ~= "function" then
		Display.ShowInitialMessage()
		Display.panel_retry_started = false
		return
	end

	create_thread(function()
		local sleep = Global("Sleep")

		for _ = 1, 120 do
			Display.ShowInitialMessage()

			if Display.HasPanel() or not ShouldDisplay() then
				Display.panel_retry_started = false
				return
			end

			if type(sleep) ~= "function" then
				Display.panel_retry_started = false
				return
			end

			sleep(POLL_INTERVAL_MS)
		end

		Display.panel_retry_started = false
	end)
end

-- Bootstrap the display independently from selection changes.
Display.ShowInitialMessage()
Display.InstallPanelRefreshHooks()
Display.StartPanelRetry()
