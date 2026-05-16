local mod_action_id = "TForTracks_T"
local patched_dialog_shortcuts = {}
local track_mode_requested
local patched_interface_shortcut
local patched_interface_set_mode

-- Relaunched train tracks may use a DLC-specific template name, so try known ids first.
local track_template_ids = {
	"Track",
	"TrainTrack",
	"TrainTracks",
	"RailTrack",
	"RailroadTrack",
}

local selection_modes = {
	"selection",
	"Selection",
}

local direct_shortcut_dialog_ids = {
	"SelectionModeDialog",
	"ConstructionModeDialog",
	"ConstructionModeDialogBase",
	"GridConstructionDialog",
	"GridConstructionModeDialog",
	"DemolishModeDialog",
	"TunnelConstructionDialog",
	"LandscapeConstructionDialog",
}

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

-- Return to normal selection mode from a construction tool.
local function StartSelectionMode()
	track_mode_requested = false
	if CloseModeDialog then
		CloseModeDialog()
		return true
	end

	for _, mode in ipairs(selection_modes) do
		if TrySetMode(mode) then
			return true
		end
	end

	return false
end

-- Check whether an id/string belongs to the train-track construction template.
local function LooksLikeTrackTemplateId(value, template)
	if not value then
		return false
	end

	local value_text = tostring(value)
	if template and template.id and value_text == tostring(template.id) then
		return true
	end

	for _, id in ipairs(track_template_ids) do
		if value_text == id then
			return true
		end
	end

	return TextMatches(value_text, "track")
		and (TextMatches(value_text, "train") or TextMatches(value_text, "rail"))
end

-- Check a possible template/context object for train-track identity fields.
local function ValueLooksLikeTrackTemplate(value, template)
	if LooksLikeTrackTemplateId(value, template) then
		return true
	end

	if type(value) ~= "table" then
		return false
	end

	return LooksLikeTrackTemplateId(value.id, template)
		or LooksLikeTrackTemplateId(value.name, template)
		or LooksLikeTrackTemplateId(value.template, template)
		or LooksLikeTrackTemplateId(value.template_id, template)
		or LooksLikeTrackTemplateId(value.template_name, template)
		or LooksLikeTrackTemplateId(value.building_template, template)
		or LooksLikeTrackTemplateId(value.construction_template, template)
end

-- Resolve the build menu template that behaves like the Train Tracks GUI button.
local function FindTrackTemplate()
	for _, id in ipairs(track_template_ids) do
		if BuildingTemplates and BuildingTemplates[id] then
			return BuildingTemplates[id]
		end
	end

	-- Prefer templates whose metadata says both "train" and "track".
	for _, template in pairs(BuildingTemplates or empty_table) do
		local id = tostring(template.id or "")
		local template_class = tostring(template.template_class or "")
		local display_name = GetTemplateText(template, "display_name")

		local looks_like_track = TextMatches(id, "track")
			or TextMatches(template_class, "track")
			or TextMatches(display_name, "track")
		local looks_like_train = TextMatches(id, "train")
			or TextMatches(template_class, "train")
			or TextMatches(display_name, "train")

		local is_tunnel = TextMatches(id, "tunnel")
			or TextMatches(template_class, "tunnel")
			or TextMatches(display_name, "tunnel")

		if looks_like_track and looks_like_train and not is_tunnel then
			return template
		end
	end

	-- Fallback for game builds that simply call the template "Track".
	for _, template in pairs(BuildingTemplates or empty_table) do
		local id = tostring(template.id or "")
		local template_class = tostring(template.template_class or "")
		local display_name = GetTemplateText(template, "display_name")

		if TextMatches(id, "track") or TextMatches(template_class, "track") or TextMatches(display_name, "track") then
			return template
		end
	end
end

-- Check whether a dialog/context currently points at the track template.
local function DialogUsesTrackTemplate(dialog, template)
	if not dialog then
		return false
	end

	return ValueLooksLikeTrackTemplate(dialog.template, template)
		or ValueLooksLikeTrackTemplate(dialog.template_id, template)
		or ValueLooksLikeTrackTemplate(dialog.template_name, template)
		or ValueLooksLikeTrackTemplate(dialog.building_template, template)
		or ValueLooksLikeTrackTemplate(dialog.construction_template, template)
		or ValueLooksLikeTrackTemplate(dialog.selected_template, template)
		or ValueLooksLikeTrackTemplate(dialog.context, template)
		or ValueLooksLikeTrackTemplate(dialog.params, template)
		or ValueLooksLikeTrackTemplate(dialog.mode_param, template)
end

-- Return true when the current mode name is a construction/build mode.
local function IsConstructionModeActive(mode, template)
	if not mode then
		return false
	end

	mode = string.lower(tostring(mode))
	return mode == string.lower(tostring(template.construction_mode or "construction"))
		or TextMatches(mode, "construction")
		or TextMatches(mode, "build")
end

-- Determine whether train-track construction is currently active.
local function IsTrackBuildModeActive(template, dialog)
	local template_id = template and template.id or "Track"
	local mode = GetCurrentMode()

	if DialogUsesTrackTemplate(dialog, template) and IsConstructionModeActive(mode, template) then
		return true
	end

	return IsConstructionModeActive(mode, template)
		and (track_mode_requested or g_LastBuildItem == template_id)
end

-- Enter the same construction mode the build menu uses for this template.
local function SelectTrackBuildMode()
	local template = FindTrackTemplate()
	if not template then
		return
	end

	local template_id = template.id or "Track"
	local mode = template.construction_mode or "construction"

	g_LastBuildItem = template_id
	if CloseXBuildMenu then
		CloseXBuildMenu()
	end
	if CloseXInfopanel then
		CloseXInfopanel()
	end
	SelectObj(false)

	if TrySetMode(mode, { template = template_id }) then
		track_mode_requested = true
		return true
	end

	return false
end

-- Toggle between train-track construction and normal selection.
local function ToggleTrackBuildMode(dialog)
	local template = FindTrackTemplate()
	if not template then
		return
	end

	if track_mode_requested or IsTrackBuildModeActive(template, dialog) then
		return StartSelectionMode()
	end

	return SelectTrackBuildMode()
end

-- Track mode changes so the shortcut knows whether T should enter or exit build mode.
local function TrackSetMode(mode, context)
	if mode == "selection" then
		track_mode_requested = false
		return
	end

	if context and ValueLooksLikeTrackTemplate(context.template, FindTrackTemplate()) then
		track_mode_requested = true
	elseif TextMatches(mode, "construction") or TextMatches(mode, "build") then
		track_mode_requested = false
	end
end

-- Patch the in-game interface shortcut and SetMode methods once.
local function PatchInterfaceTShortcut()
	if not InGameInterface then
		return
	end

	if not patched_interface_shortcut and InGameInterface.OnShortcut then
		local original_on_shortcut = InGameInterface.OnShortcut

		-- Intercept T before the base interface handles shortcuts.
		function InGameInterface:OnShortcut(shortcut, source, ...)
			if shortcut == "T" and ToggleTrackBuildMode(self.mode_dialog) then
				return "break"
			end

			return original_on_shortcut(self, shortcut, source, ...)
		end

		patched_interface_shortcut = true
	end

	if not patched_interface_set_mode and InGameInterface.SetMode then
		local original_set_mode = InGameInterface.SetMode

		-- Observe mode changes while preserving the original SetMode behavior.
		function InGameInterface:SetMode(mode, context, ...)
			TrackSetMode(mode, context)
			return original_set_mode(self, mode, context, ...)
		end

		patched_interface_set_mode = true
	end
end

-- Patch a mode/dialog class so T works even when that dialog owns keyboard input.
local function PatchDialogTShortcut(dialog, marker)
	if not dialog or patched_dialog_shortcuts[marker] then
		return
	end

	if dialog.OnShortcut then
		local original_on_shortcut = dialog.OnShortcut

		-- Intercept symbolic shortcut events from the active dialog.
		function dialog:OnShortcut(shortcut, source, ...)
			if shortcut == "T" and ToggleTrackBuildMode(self) then
				return "break"
			end

			return original_on_shortcut(self, shortcut, source, ...)
		end
	end

	if dialog.OnKbdKeyDown then
		local original_on_kbd_key_down = dialog.OnKbdKeyDown

		-- Intercept raw keyboard events for dialogs that bypass shortcut dispatch.
		function dialog:OnKbdKeyDown(virtual_key, ...)
			if const and const.vkT and virtual_key == const.vkT and ToggleTrackBuildMode(self) then
				return "break"
			end

			return original_on_kbd_key_down(self, virtual_key, ...)
		end
	end

	patched_dialog_shortcuts[marker] = true
end

-- Also hook active mode dialogs; construction tools such as cables and valves
-- own keyboard input while active, so the normal game shortcut may not fire.
local function PatchDirectTShortcut()
	PatchInterfaceTShortcut()

	for _, dialog_id in ipairs(direct_shortcut_dialog_ids) do
		PatchDialogTShortcut(rawget(_G, dialog_id), dialog_id)
	end
end

-- Register a bindable game action so T appears as a normal shortcut.
local function AddTForTracksAction(parent, context)
	if not XAction then
		return
	end

	XAction:new({
		ActionId = mod_action_id,
		ActionMode = "Game",
		ActionTranslate = false,
		ActionName = "T for tracks",
		ActionShortcut = "T",
		ActionBindable = true,
		-- Enable the action only when a track template can be resolved.
		ActionState = function(self, host)
			return FindTrackTemplate() and "enabled" or "disabled"
		end,
		-- Toggle track mode from the registered shortcut path.
		OnAction = function(self, host, source, ...)
			local dlg = GetHUD()
			if not dlg or not dlg:GetVisible() then
				return
			end

			FocusInfopanel = false
			if ToggleTrackBuildMode(host) then
				return "break"
			end
		end,
		IgnoreRepeated = true,
	}, parent, context)
end

local patched
-- Patch direct dialog shortcuts and register the bindable action once available.
local function PatchGameShortcuts()
	PatchDirectTShortcut()

	-- GameShortcuts may not exist when the mod file first loads, so this function is retried by messages below.
	if patched or not GameShortcuts or not GameShortcuts.Init then
		return
	end

	local original_init = GameShortcuts.Init

	-- Add the T shortcut action after the base shortcut container initializes.
	function GameShortcuts:Init(parent, context)
		original_init(self, parent, context)
		AddTForTracksAction(parent, context)
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
