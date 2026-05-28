-- Copy Move selection set + green-tint highlight.
-- Owns the mod's own selection set (independent of the game's Selection array)
-- and the reversible color tint applied to its members. Tints are stored per
-- object on add and restored on remove/clear so vanilla appearance is preserved.

CopyMove = rawget(_G, "CopyMove") or {}
local CM = CopyMove
_G.CopyMove = CM

local Selection = CM.Selection or {}
CM.Selection = Selection
local Object = CM.Object
local DebugLog = CM.DebugLog

-- set[obj]   = the object's original color modifier (a number, or false if it
--              could not be read). Presence of the key means "selected".
-- order[i]   = objects in selection order.
Selection.set = Selection.set or {}
Selection.order = Selection.order or {}

-- Build the configured tint color, or nil if RGB is unavailable.
local function tint_color()
	local rgb = rawget(_G, "RGB")
	if type(rgb) ~= "function" then
		return nil
	end
	local comps = (CM.Config and CM.Config.TINT_COLOR_RGB) or { 0, 220, 60 }
	return rgb(comps[1] or 0, comps[2] or 220, comps[3] or 60)
end

-- Whether tinting is currently allowed.
local function tint_enabled()
	return CM.Config and CM.Config.ENABLE_SELECT_TINT == true
end

-- Whether an object exposes the color-modifier API.
local function has_color_api(obj)
	return type(Object.ReadField(obj, "SetColorModifier")) == "function"
end

local function apply_tint(obj)
	if not has_color_api(obj) then
		return false
	end
	local color = tint_color()
	if color == nil then
		return false
	end
	return pcall(function()
		obj:SetColorModifier(color)
	end) and true or false
end

-- Restore an object's color. original may be a number (restore it) or false/nil
-- (fall back to the engine "no modifier" value).
local function restore_tint(obj, original)
	if not Object.IsValid(obj) or not has_color_api(obj) then
		return
	end
	local color = original
	if type(color) ~= "number" then
		local const = rawget(_G, "const")
		color = (const and const.clrNoModifier) or 0
	end
	pcall(function()
		obj:SetColorModifier(color)
	end)
end

-- Whether the object is in the selection set.
function Selection.Contains(obj)
	return Selection.set[obj] ~= nil
end

-- Number of objects currently selected.
function Selection.Count()
	return #Selection.order
end

-- Add one object to the selection set and tint it. No-op if already present.
function Selection.Add(obj)
	if not Object.IsValid(obj) or Selection.set[obj] ~= nil then
		return false
	end
	local original = Object.CallMethod(obj, "GetColorModifier")
	Selection.set[obj] = (type(original) == "number") and original or false
	Selection.order[#Selection.order + 1] = obj
	if tint_enabled() then
		apply_tint(obj)
	end
	DebugLog.Info("Selection", "Added object", {
		class = Object.ClassName(obj),
		count = #Selection.order,
	})
	return true
end

-- Remove one object from the selection set and restore its color.
function Selection.Remove(obj)
	local original = Selection.set[obj]
	if original == nil then
		return false
	end
	Selection.set[obj] = nil
	for i = #Selection.order, 1, -1 do
		if Selection.order[i] == obj then
			table.remove(Selection.order, i)
		end
	end
	restore_tint(obj, original)
	DebugLog.Info("Selection", "Removed object", {
		class = Object.ClassName(obj),
		count = #Selection.order,
	})
	return true
end

-- Toggle membership for one object.
function Selection.Toggle(obj)
	if Selection.Contains(obj) then
		return Selection.Remove(obj)
	end
	return Selection.Add(obj)
end

-- Restore every tint and empty the set.
function Selection.Clear()
	for i = #Selection.order, 1, -1 do
		local obj = Selection.order[i]
		restore_tint(obj, Selection.set[obj])
	end
	Selection.set = {}
	Selection.order = {}
	DebugLog.Info("Selection", "Cleared selection")
end

-- Replace the set with a single object (a plain, non-Ctrl click).
function Selection.SetSingle(obj)
	-- Avoid clearing+re-adding when the single object is already the only member.
	if #Selection.order == 1 and Selection.order[1] == obj and Object.IsValid(obj) then
		return
	end
	Selection.Clear()
	if Object.IsValid(obj) then
		Selection.Add(obj)
	end
end

-- Forget the set WITHOUT touching object colors. For map teardown, when the
-- objects are being destroyed and must not be touched.
function Selection.Reset()
	Selection.set = {}
	Selection.order = {}
end

-- Drop invalidated objects (e.g. deleted) from the set.
function Selection.PruneInvalid()
	for i = #Selection.order, 1, -1 do
		local obj = Selection.order[i]
		if not Object.IsValid(obj) then
			Selection.set[obj] = nil
			table.remove(Selection.order, i)
		end
	end
end

-- Return a pruned array of the currently-selected valid objects.
function Selection.List()
	Selection.PruneInvalid()
	local out = {}
	for i = 1, #Selection.order do
		out[#out + 1] = Selection.order[i]
	end
	return out
end

-- Re-apply tints to all selected objects (e.g. after toggling the tint flag on).
function Selection.RefreshTints()
	if not tint_enabled() then
		return
	end
	for i = 1, #Selection.order do
		apply_tint(Selection.order[i])
	end
end
