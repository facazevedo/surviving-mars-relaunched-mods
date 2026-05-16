local ACTION_ID = "ForceDelete_CtrlDelete"

local shortcuts_patched = false

-- Return an optional global without creating sandbox assertion noise.
local function Global(name)
	return rawget(_G, name)
end

-- Run an optional function safely and return false on failure.
local function SafeCall(fn, ...)
	if type(fn) ~= "function" then
		return false
	end

	local ok, result = pcall(fn, ...)
	return ok and result or false
end

-- Check whether a map/game object is still valid.
local function IsObjectValid(obj)
	local is_valid = Global("IsValid")

	if type(is_valid) == "function" then
		return SafeCall(is_valid, obj) and true or false
	end

	return obj and true or false
end

-- Check whether the selected object can use the normal demolish pipeline.
local function CanForceDelete(obj)
	return IsObjectValid(obj)
		and SafeCall(Global("IsKindOf"), obj, "Demolishable")
		and SafeCall(obj.CanDemolish, obj)
end

-- Stop any pending demolition countdown thread before forcing demolition now.
local function StopDemolitionThread(obj)
	local thread = obj.demolishing_thread

	if SafeCall(Global("IsValidThread"), thread) then
		SafeCall(Global("DeleteThread"), thread)
	end

	obj.demolishing_thread = false
end

-- Run the selected object's normal demolition cleanup immediately.
local function ForceDeleteSelectedObject()
	local obj = Global("SelectedObj")

	if not CanForceDelete(obj) then
		return false
	end

	obj.demolishing = true
	obj.demolishing_countdown = 0
	StopDemolitionThread(obj)
	SafeCall(Global("SelectObj"), false)

	local ok = pcall(function()
		obj:DoDemolish()
	end)

	return ok
end

-- Check whether the HUD is visible enough to process gameplay shortcuts.
local function IsHudVisible()
	local hud = SafeCall(Global("GetHUD"))

	return hud and type(hud.GetVisible) == "function" and hud:GetVisible()
end

-- Register the bindable Ctrl+Delete action in the game shortcut container.
local function AddForceDeleteAction(parent, context)
	local x_action = Global("XAction")

	if not x_action then
		return
	end

	x_action:new({
		ActionId = ACTION_ID,
		ActionMode = "Game",
		ActionTranslate = false,
		ActionName = "Force Delete Selected",
		ActionShortcut = "Ctrl-Delete",
		ActionBindable = true,
		-- Enable Ctrl+Delete only for selected objects that can be demolished.
		ActionState = function()
			return CanForceDelete(Global("SelectedObj")) and "enabled" or "disabled"
		end,
		-- Force-delete the selected object from the registered shortcut path.
		OnAction = function()
			if not IsHudVisible() then
				return
			end

			FocusInfopanel = false

			if ForceDeleteSelectedObject() then
				return "break"
			end
		end,
		IgnoreRepeated = true,
	}, parent, context)
end

-- Patch GameShortcuts once; the function is safe to retry while classes load.
local function PatchGameShortcuts()
	local game_shortcuts = Global("GameShortcuts")

	if shortcuts_patched or not game_shortcuts or type(game_shortcuts.Init) ~= "function" then
		return
	end

	local original_init = game_shortcuts.Init

	-- Add the Ctrl+Delete shortcut action after the base shortcut container initializes.
	function game_shortcuts:Init(parent, context)
		original_init(self, parent, context)
		AddForceDeleteAction(parent, context)
	end

	shortcuts_patched = true
end

-- Preserve any existing OnMsg handler while also retrying shortcut registration.
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

-- Retry shortcut registration after class post-processing.
ChainOnMsg("ClassesPostprocess", PatchGameShortcuts)

-- Retry shortcut registration after data loading.
ChainOnMsg("DataLoaded", PatchGameShortcuts)

PatchGameShortcuts()
