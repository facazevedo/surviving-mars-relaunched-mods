local mod_action_id = "SalvageToolShortcut_Delete"
local patched_direct_shortcut

local salvage_template_ids = {
	"Salvage",
	"Demolish",
	"Demolition",
	"Destroy",
}

local salvage_modes = {
	"demolish",
	"demolition",
	"salvage",
	"Demolish",
	"Demolition",
	"Salvage",
}

local selection_modes = {
	"selection",
	"Selection",
}

local salvage_mode_lookup = {}
for _, mode in ipairs(salvage_modes) do
	salvage_mode_lookup[string.lower(mode)] = true
end

-- Return true when a string-like value contains a case-insensitive fragment.
local function TextMatches(value, pattern)
	if not value then
		return false
	end

	return string.find(string.lower(tostring(value)), pattern, 1, true) ~= nil
end

-- Read template text fields, translating game T values when possible.
local function GetTemplateText(template, field)
	local value = template and template[field]
	if type(value) == "table" and _InternalTranslate then
		value = _InternalTranslate(value)
	end

	return value and tostring(value) or ""
end

-- Resolve the build-menu entry that behaves like the normal Salvage GUI button.
local function FindSalvageTemplate()
	for _, id in ipairs(salvage_template_ids) do
		if BuildingTemplates and BuildingTemplates[id] then
			return BuildingTemplates[id]
		end
	end

	for _, template in pairs(BuildingTemplates or empty_table) do
		local id = tostring(template.id or "")
		local template_class = tostring(template.template_class or "")
		local display_name = GetTemplateText(template, "display_name")

		if TextMatches(id, "salvage")
			or TextMatches(id, "demolish")
			or TextMatches(template_class, "salvage")
			or TextMatches(template_class, "demolish")
			or TextMatches(display_name, "salvage")
			or TextMatches(display_name, "demolish") then
			return template
		end
	end
end

-- Ask the in-game interface to switch modes and report whether it accepted it.
local function TrySetMode(mode, params)
	local igi = GetInGameInterface and GetInGameInterface()
	if not igi or not igi.SetMode then
		return false
	end

	local ok = pcall(igi.SetMode, igi, mode, params)
	return ok
end

-- Return the current in-game interface mode across known field names.
local function GetCurrentMode()
	local igi = GetInGameInterface and GetInGameInterface()
	if not igi then
		return false
	end

	return igi.mode or igi.Mode or igi.mode_name or igi.ModeName
end

-- Return true when the current mode is one of the game's salvage/demolish modes.
local function IsSalvageModeActive()
	local mode = GetCurrentMode()
	if not mode then
		return false
	end

	mode = string.lower(tostring(mode))
	return salvage_mode_lookup[mode] or TextMatches(mode, "salvage") or TextMatches(mode, "demolish")
end

-- Return to normal selection mode from salvage/demolish mode.
local function StartSelectionMode()
	for _, mode in ipairs(selection_modes) do
		if TrySetMode(mode) then
			return true
		end
	end

	return false
end

-- Toggle the same placement-style salvage mode used by the GUI. Delete exits
-- salvage mode when it is active; otherwise it enters salvage only when there
-- is no selected object for Delete to act on.
local function ToggleSalvageMode()
	if IsSalvageModeActive() then
		return StartSelectionMode()
	end

	if IsValid(SelectedObj) then
		return false
	end

	local dlg = GetHUD and GetHUD()
	if dlg and not dlg:GetVisible() then
		return false
	end

	FocusInfopanel = false
	if CloseXBuildMenu then
		CloseXBuildMenu()
	end
	if CloseXInfopanel then
		CloseXInfopanel()
	end
	SelectObj(false)

	local template = FindSalvageTemplate()
	if template then
		local template_id = template.id or "Salvage"
		local mode = template.construction_mode or template.mode or "demolish"

		g_LastBuildItem = template_id
		if TrySetMode(mode, { template = template_id }) then
			return true
		end
	end

	for _, mode in ipairs(salvage_modes) do
		if TrySetMode(mode) then
			return true
		end
	end

	return false
end

-- Also hook the active selection dialog; this catches Delete even when the
-- shortcut registry does not receive it.
local function PatchDirectDeleteShortcut()
	if patched_direct_shortcut or not SelectionModeDialog then
		return
	end

	if SelectionModeDialog.OnShortcut then
		local original_on_shortcut = SelectionModeDialog.OnShortcut

		-- Intercept symbolic Delete shortcuts while the selection dialog owns input.
		function SelectionModeDialog:OnShortcut(shortcut, source, ...)
			if shortcut == "Delete" and ToggleSalvageMode() then
				return "break"
			end

			return original_on_shortcut(self, shortcut, source, ...)
		end
	end

	if SelectionModeDialog.OnKbdKeyDown then
		local original_on_kbd_key_down = SelectionModeDialog.OnKbdKeyDown

		-- Intercept raw Delete key presses from dialogs that bypass shortcut dispatch.
		function SelectionModeDialog:OnKbdKeyDown(virtual_key, ...)
			if const and const.vkDelete and virtual_key == const.vkDelete and ToggleSalvageMode() then
				return "break"
			end

			return original_on_kbd_key_down(self, virtual_key, ...)
		end
	end

	patched_direct_shortcut = true
end

-- Register a bindable game action so Delete appears as a normal shortcut.
local function AddSalvageShortcutAction(parent, context)
	if not XAction then
		return
	end

	XAction:new({
		ActionId = mod_action_id,
		ActionMode = "Game",
		ActionTranslate = false,
		ActionName = "Salvage tool shortcut",
		ActionShortcut = "Delete",
		ActionBindable = true,
		-- Enable Delete when it will toggle salvage rather than delete a selected object.
		ActionState = function(self, host)
			return (IsSalvageModeActive() or not IsValid(SelectedObj)) and "enabled" or "disabled"
		end,
		-- Toggle salvage from the registered shortcut path.
		OnAction = function(self, host, source, ...)
			if ToggleSalvageMode() then
				return "break"
			end
		end,
		IgnoreRepeated = true,
	}, parent, context)
end

local patched
-- Patch direct Delete handling and register the bindable action once available.
local function PatchGameShortcuts()
	PatchDirectDeleteShortcut()

	if patched or not GameShortcuts or not GameShortcuts.Init then
		return
	end

	local original_init = GameShortcuts.Init

	-- Add the Delete shortcut action after the base shortcut container initializes.
	function GameShortcuts:Init(parent, context)
		original_init(self, parent, context)
		AddSalvageShortcutAction(parent, context)
	end

	patched = true
end

-- Preserve any existing OnMsg handler while adding this mod's retry hook.
local function ChainOnMsg(message_name, handler)
	local previous = OnMsg[message_name]

	-- Call the existing message handler first, then this mod's retry hook.
	OnMsg[message_name] = function(...)
		if previous then
			previous(...)
		end

		handler(...)
	end
end

ChainOnMsg("ClassesPostprocess", PatchGameShortcuts)
ChainOnMsg("DataLoaded", PatchGameShortcuts)
PatchGameShortcuts()
