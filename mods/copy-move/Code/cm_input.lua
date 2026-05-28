-- Copy Move input wiring.
-- Mirrors the game's normal selection into the mod's selection set, and adds a
-- Ctrl+click multi-select that toggles arbitrary objects (including decorations)
-- in/out of the set. Hooks are reversible: when the mod is inactive the wrapped
-- handler passes straight through to the original, leaving vanilla intact.

CopyMove = rawget(_G, "CopyMove") or {}
local CM = CopyMove
_G.CopyMove = CM

local Input = CM.Input or {}
CM.Input = Input
local Object = CM.Object
local Selection = CM.Selection
local DebugLog = CM.DebugLog

-- Whether the configured multi-select modifier (Ctrl) is currently held.
local function multiselect_modifier_down()
	local terminal = rawget(_G, "terminal")
	local const = rawget(_G, "const")
	if type(terminal) ~= "table" or type(terminal.IsKeyPressed) ~= "function" or type(const) ~= "table" then
		return false
	end
	return terminal.IsKeyPressed(const.vkControl) and true or false
end

-- Resolve the object under the cursor using the engine's own selection picker
-- (raycast + hex-grid enumeration), then selection-propagate it as the game does.
local function cursor_object()
	local pick = rawget(_G, "SelectionMouseObj")
	if type(pick) ~= "function" then
		return false
	end
	local obj = Object.SafeCall(pick)
	if not obj then
		return false
	end
	local propagate = rawget(_G, "SelectionPropagate")
	if type(propagate) == "function" then
		obj = Object.SafeCall(propagate, obj) or obj
	end
	return Object.IsValid(obj) and obj or false
end

-- True when the mod should actively intercept input.
local function mod_active()
	return type(CM.IsActive) == "function" and CM.IsActive() == true
end

-- Mirror a plain (non-Ctrl) selection change into the mod's selection set.
-- A Ctrl multi-select is handled in the mouse hook below (it consumes the click
-- and does not change SelectedObj), so a SelectedObjChange reaching here means a
-- plain single selection or a deselection.
function OnMsg.SelectedObjChange(obj, prev)
	if not mod_active() or not (CM.Config and CM.Config.ENABLE_SELECT_TINT) then
		return
	end
	if multiselect_modifier_down() then
		return -- don't disturb a multi-select in progress
	end
	if Object.IsValid(obj) then
		Selection.SetSingle(obj)
	else
		Selection.Clear()
	end
end

-- Install the Ctrl+click multi-select hook on the selection interface mode.
-- Idempotent: the true original is captured once and re-wrapping is skipped.
function Input.InstallSelectionHook()
	local dlg = rawget(_G, "SelectionModeDialog")
	if type(dlg) ~= "table" then
		return false
	end
	if Input.selection_hook_installed then
		return true
	end
	if Input.orig_OnMouseButtonDown == nil then
		Input.orig_OnMouseButtonDown = dlg.OnMouseButtonDown
	end
	local orig = Input.orig_OnMouseButtonDown

	dlg.OnMouseButtonDown = function(self, pt, button)
		if button == "L"
			and mod_active()
			and CM.Config and CM.Config.ENABLE_MULTISELECT == true
			and multiselect_modifier_down()
		then
			local obj = cursor_object()
			if obj then
				Selection.Toggle(obj)
				DebugLog.Info("Selection", "Ctrl multi-select toggle", {
					class = Object.ClassName(obj),
					count = Selection.Count(),
				})
				return "break" -- consume; keep the game's SelectedObj unchanged
			end
		end
		if type(orig) == "function" then
			return orig(self, pt, button)
		end
	end

	Input.selection_hook_installed = true
	DebugLog.Info("Selection", "Installed selection mouse hook")
	return true
end

-- Restore the original selection handler (used by lifecycle teardown).
function Input.RemoveSelectionHook()
	local dlg = rawget(_G, "SelectionModeDialog")
	if type(dlg) == "table" and Input.orig_OnMouseButtonDown ~= nil then
		dlg.OnMouseButtonDown = Input.orig_OnMouseButtonDown
	end
	Input.selection_hook_installed = false
	DebugLog.Info("Selection", "Removed selection mouse hook")
end
