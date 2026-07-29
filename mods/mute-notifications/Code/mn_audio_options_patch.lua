-- mn_audio_options_patch.lua
-- Adds a single "Configure muted voice notifications..." row to the in-game
-- Options -> Audio page (both main-menu and in-game options use the same
-- OptionsObject + OptionsContentWindow, so one patch covers both).
--
-- Mechanism (verified from game source, no game files edited):
--   * OptionsContentWindow renders, per Audio property, every XDef in the
--     "MenuProp" group; each member's class decides (by prop_meta.editor) whether
--     it renders anything. (Data/XDef/OptionsContentWindow.lua, PropBool.lua)
--   * We append ONE property (category="Audio", a custom editor) to
--     OptionsObject.properties and register ONE MenuProp class.
--   * That class renders nothing for every property except ours (and drops out of
--     layout), so all vanilla option rows are unaffected.
--
-- Everything is guarded; if any step fails the Audio row is simply absent and the
-- panel remains reachable via MN_OpenPanel() (and the reason is logged).
--
-- DIAGNOSTICS: set MN_Config.DEBUG_AUDIO_PATCH = true to print a detailed trace of
-- every step (independent of the master DEBUG flag). Call MN_AudioPatch.Diagnose()
-- from the console at any time for an on-demand state dump.

MN_AudioPatch = {
	class_defined = false,
	group_registered = false,
	prop_added = false,
	bool_patch_applied = false,
	orig_PropBool_OnMouseButtonDown = false,
	orig_PropBool_OnPropUpdate = false,
	new_skipped = 0,     -- MN_OptionRow:new skips for non-matching properties
	init_calls = 0,      -- MN_OptionRow:Init invocations for OUR property
	init_matched = 0,    -- ...of which matched OUR property
}

local EDITOR = MN_Config.AUDIO_OPTION_EDITOR
local RENDER_EDITOR = "bool"
local OPT_ID = MN_Config.AUDIO_OPTION_ID
local CLASS_NAME = "MN_OptionRow"

-- Independent, always-visible-when-enabled diagnostic print.
local function APLog(msg, data)
	if MN_Config.DEBUG_AUDIO_PATCH ~= true then return end
	local suffix = ""
	if data ~= nil then
		if type(data) == "table" then
			local parts = {}
			for k, v in pairs(data) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
			suffix = " {" .. table.concat(parts, ", ") .. "}"
		else
			suffix = " " .. tostring(data)
		end
	end
	print("[Mute Notifications][AudioPatch] " .. tostring(msg) .. suffix)
end
MN_AudioPatch.Log = APLog

local function APBox(left, top, right, bottom)
	local fn = rawget(_G, "box")
	if type(fn) == "function" then
		return fn(left, top, right, bottom)
	end
	return nil
end

local function APColor(red, green, blue, alpha)
	local fn = rawget(_G, "RGBA")
	if type(fn) == "function" then
		return fn(red, green, blue, alpha)
	end
	return nil
end

----- Custom MenuProp row class -------------------------------------------------
-- Defined at code load so the class exists in g_Classes after ClassesBuilt.

if rawget(_G, "XPropControl") ~= nil and rawget(_G, CLASS_NAME) == nil then
	DefineClass.MN_OptionRow = {
		__parents = { "XPropControl" },
		RolloverTemplate = "MarsRollover",
		RolloverAnchor = "right",
		LayoutMethod = "HList",
		RolloverOnFocus = true,
		MouseCursor = "UI/Cursors/Rollover.tga",
		HandleMouse = true,
		FXMouseIn = "MenuItemHover",
		FXPress = "MenuItemClick",
	}

	-- Init is a combined method (DefineCombinedMethod("Init","procall","InitDone")),
	-- so the whole chain runs base->derived: XWindow:Init has already parented the
	-- window and XPropControl:Init has already set self.prop_meta before this runs.
	function MN_OptionRow:Init(parent, context)
		local pm = self.prop_meta or (context and context.prop_meta)
		local matched = pm and pm.editor == EDITOR or false
		MN_AudioPatch.init_calls = MN_AudioPatch.init_calls + 1
		if matched then MN_AudioPatch.init_matched = MN_AudioPatch.init_matched + 1 end
		APLog("MN_OptionRow:Init", {
			has_prop_meta = pm ~= nil and pm ~= false,
			editor = pm and pm.editor,
			id = pm and pm.id,
			matched = matched,
		})

		if not matched then
			-- Not our property: contribute nothing, drop out of layout.
			self.Dock = "ignore"
			self.Visible = false
			self.HandleMouse = false
			return
		end

		local XText = rawget(_G, "XText")
		local XFrame = rawget(_G, "XFrame")
		if XFrame then
			XFrame:new({
				Id = "idRollover",
				ZOrder = 0,
				Dock = "box",
				HAlign = "left",
				MinWidth = 448,
				Visible = false,
				Image = "UI/CommonRemaster/row_rollover_shine.png",
				FrameBox = APBox(0, 0, 186, 0),
			}, self)
		end
		if XText then
			local name_ctrl = XText:new({
				Id = "idName",
				Padding = APBox(0, 0, 0, 0),
				Translate = true,
				TextStyle = "PropName",
				HAlign = "left",
				MinWidth = 400,
				MaxHeight = 35,
				HandleMouse = false,
				WordWrap = false,
				TextVAlign = "center",
			}, self)
			name_ctrl:SetText(pm.name or pm.id)
		end
		-- Row rollover is applied automatically by the options framework
		-- (SetupOptionRollover reads the property's help_text).
	end

	function MN_OptionRow:SetSelected(selected)
		local fn = rawget(_G, "IsUIStyleUsingGamepad")
		if type(fn) == "function" and fn() then
			self:SetFocus(selected)
		end
	end

	function MN_OptionRow:OnSetRollover(rollover)
		XPropControl.OnSetRollover(self, rollover)
		local name = self:ResolveId("idName")
		if name and type(name.SetRollover) == "function" then
			name:SetRollover(rollover)
		end
	end

	function MN_OptionRow:OnMouseButtonDown(pos, button)
		XPropControl.OnMouseButtonDown(self, pos, button)
		if button == "L" then
			APLog("Audio row clicked -> opening panel")
			local ok, err = pcall(MN_OpenPanel, "audio_options_row")
			if ok ~= true then
				MN_Debug.Error("AudioPatch", "Failed opening panel from Audio row", { error = err })
			end
			return "break"
		end
	end

	function MN_OptionRow:OnShortcut(shortcut, source, ...)
		if shortcut == "ButtonA" then
			self:OnMouseButtonDown(nil, "L")
		end
	end

	MN_AudioPatch.class_defined = true
	APLog("DefineClass.MN_OptionRow registered at code load")
end

-- The class may survive a mod-code reload. Refresh the constructor every load.
-- Return a stock XTextButton for our property instead of constructing the custom
-- XPropControl class directly. OptionsContentWindow assumes every visible
-- property produces a child and crashes at child:SetMargins when construction
-- fails; the stock button keeps this row on the engine's proven UI path.
if rawget(_G, "XPropControl") ~= nil and rawget(_G, CLASS_NAME) ~= nil then
	function MN_OptionRow:new(args, parent, context)
		local pm = context and context.prop_meta
		if not (pm and pm.editor == EDITOR) then
			MN_AudioPatch.new_skipped = MN_AudioPatch.new_skipped + 1
			return nil
		end

		local XTextButton = rawget(_G, "XTextButton")
		if not XTextButton then
			MN_Debug.Error("AudioPatch", "XTextButton unavailable for Audio options row", { id = pm.id })
			return nil
		end

		local row = XTextButton:new({
			Translate = true,
			TextStyle = "PropName",
			HAlign = "left",
			VAlign = "center",
			MinWidth = 448,
			MaxHeight = 35,
			Padding = APBox(0, 0, 0, 0),
			RolloverTemplate = "MarsRollover",
			RolloverAnchor = "right",
			RolloverOnFocus = true,
			MouseCursor = "UI/Cursors/Rollover.tga",
			Background = APColor(0, 0, 0, 0),
			RolloverBackground = APColor(54, 68, 74, 160),
			PressedBackground = APColor(85, 101, 108, 190),
			FXMouseIn = "MenuItemHover",
			FXPress = "MenuItemClick",
			OnPress = function()
				APLog("Audio row pressed -> opening panel")
				local ok, err = pcall(MN_OpenPanel, "audio_options_row")
				if ok ~= true then
					MN_Debug.Error("AudioPatch", "Failed opening panel from Audio row", { error = err })
				end
			end,
			SetSelected = function(button, selected)
				local fn = rawget(_G, "IsUIStyleUsingGamepad")
				if type(fn) == "function" and fn() then
					button:SetFocus(selected)
				end
			end,
		}, parent, context)
		row:SetText(pm.name or pm.id)
		if row.idLabel then
			row.idLabel:SetHAlign("left")
		end
		MN_AudioPatch.init_calls = MN_AudioPatch.init_calls + 1
		MN_AudioPatch.init_matched = MN_AudioPatch.init_matched + 1
		return row
	end

	MN_AudioPatch.class_defined = true
end

----- Patch application ----------------------------------------------------------

local function MN_GroupHasMember()
	local presets = rawget(_G, "Presets")
	local grp = presets and presets.XDef and presets.XDef["MenuProp"]
	if type(grp) ~= "table" then return nil end
	for _, d in ipairs(grp) do
		if d.id == CLASS_NAME then return true end
	end
	return false
end

local function MN_RegisterGroupMember()
	local presets = rawget(_G, "Presets")
	if not presets or not presets.XDef or not presets.XDef["MenuProp"] then
		return false, "Presets.XDef.MenuProp unavailable"
	end
	if rawget(_G, CLASS_NAME) == nil then
		return false, "row class not in g_Classes"
	end
	local grp = presets.XDef["MenuProp"]
	if MN_GroupHasMember() then
		MN_AudioPatch.group_registered = true
		return true
	end
	-- The engine sorts each preset group via Preset:Compare, which reads SortKey
	-- (numeric), id, and save_in. Provide all three so our render-only entry sorts
	-- cleanly alongside the real XDef presets (the render loop itself uses only .id).
	grp[#grp + 1] = {
		id = CLASS_NAME,
		group = "MenuProp",
		SortKey = 0,
		HasSortKey = false,
		save_in = "",
	}
	MN_AudioPatch.group_registered = true
	return true
end

-- Remove the legacy custom MenuProp renderer. The options template assumes each
-- property has a matching renderer and crashes if none returns a child. The
-- replacement path below uses the game's built-in PropBool renderer instead.
local function MN_RemoveLegacyGroupMember()
	local presets = rawget(_G, "Presets")
	local grp = presets and presets.XDef and presets.XDef["MenuProp"]
	if type(grp) ~= "table" then
		return false, "Presets.XDef.MenuProp unavailable"
	end
	local removed = 0
	for i = #grp, 1, -1 do
		if grp[i] and grp[i].id == CLASS_NAME then
			table.remove(grp, i)
			removed = removed + 1
		end
	end
	MN_AudioPatch.group_registered = false
	APLog("Removed legacy custom MenuProp renderer", { removed = removed, remaining = #grp })
	return true
end

-- Reuse the engine's proven boolean options row and intercept only this
-- property's activation. This guarantees OptionsContentWindow receives a child
-- for the property while keeping the row action-like (the On/Off labels are
-- hidden after the stock renderer updates them).
local function MN_InstallBoolRowPatch()
	if MN_AudioPatch.bool_patch_applied == true then
		APLog("PropBool hook already installed")
		return true
	end

	local PropBool = rawget(_G, "PropBool")
	if type(PropBool) ~= "table" then
		return false, "PropBool class unavailable"
	end
	local orig_mouse = PropBool.OnMouseButtonDown
	local orig_update = PropBool.OnPropUpdate
	if type(orig_mouse) ~= "function" or type(orig_update) ~= "function" then
		return false, "PropBool methods unavailable"
	end

	MN_AudioPatch.orig_PropBool_OnMouseButtonDown = orig_mouse
	MN_AudioPatch.orig_PropBool_OnPropUpdate = orig_update

	function PropBool:OnMouseButtonDown(pos, button)
		local pm = self.prop_meta
		if button == "L" and pm and pm.id == OPT_ID then
			APLog("Built-in Audio row activated", { id = pm.id, editor = pm.editor })
			local ok, err = pcall(MN_OpenPanel, "audio_options_row")
			if ok ~= true then
				MN_Debug.Error("AudioPatch", "Failed opening panel from built-in Audio row", { error = err })
			end
			return "break"
		end
		return orig_mouse(self, pos, button)
	end

	function PropBool:OnPropUpdate(context, prop_meta, value)
		orig_update(self, context, prop_meta, value)
		if prop_meta and prop_meta.id == OPT_ID then
			if self.idOn then self.idOn:SetVisible(false) end
			if self.idOff then self.idOff:SetVisible(false) end
			self:SetEnabled(true)
			self:SetHandleMouse(true)
			APLog("Built-in Audio row rendered", {
				id = prop_meta.id,
				editor = prop_meta.editor,
				value = value,
				has_name = self.idName ~= nil,
			})
		end
	end

	MN_AudioPatch.bool_patch_applied = true
	APLog("Installed built-in PropBool Audio-row hooks", {
		has_mouse = type(PropBool.OnMouseButtonDown) == "function",
		has_update = type(PropBool.OnPropUpdate) == "function",
	})
	return true
end

local function MN_PropPresent()
	local OptionsObject = rawget(_G, "OptionsObject")
	if not OptionsObject or type(OptionsObject.properties) ~= "table" then return nil end
	return table.find_value(OptionsObject.properties, "id", OPT_ID)
end

local function MN_AddProperty()
	local OptionsObject = rawget(_G, "OptionsObject")
	if not OptionsObject or type(OptionsObject.properties) ~= "table" then
		return false, "OptionsObject.properties unavailable"
	end
	local existing = MN_PropPresent()
	if existing then
		-- Repair metadata left by a prior live mod reload before reusing it. A
		-- stale editor value would leave this property with no MenuProp renderer.
		existing.category = "Audio"
		existing.editor = RENDER_EDITOR
		existing.default = false
		existing.dont_save = true
		existing.no_edit = false
		rawset(OptionsObject, "props_cache", false)
		MN_AudioPatch.prop_added = true
		APLog("Repaired existing Audio property", {
			id = existing.id,
			category = existing.category,
			editor = existing.editor,
		})
		return true
	end
	local U = rawget(_G, "Untranslated")
	local name = U and U("Mute Notifications") or "Mute Notifications"
	local help = U and U("Open the Mute Notifications panel to choose which Mission Control voice lines are silenced. Visual notifications are not affected.") or nil
	table.insert(OptionsObject.properties, {
		name = name,
		id = OPT_ID,
		category = "Audio",
		editor = RENDER_EDITOR,
		default = false,
		dont_save = true,
		no_edit = false,
		help_text = help,
		SortKey = 100000,   -- keep it at the bottom of the Audio list
	})
	rawset(OptionsObject, "props_cache", false)
	MN_AudioPatch.prop_added = true
	APLog("Added built-in-rendered Audio property", {
		id = OPT_ID,
		category = "Audio",
		editor = RENDER_EDITOR,
	})
	return true
end

-- Full on-demand state dump (also called at the end of Apply).
function MN_AudioPatch.Diagnose(reason)
	local presets = rawget(_G, "Presets")
	local grp = presets and presets.XDef and presets.XDef["MenuProp"]
	local OptionsObject = rawget(_G, "OptionsObject")
	local prop = MN_PropPresent()
	APLog("DIAGNOSE", { reason = reason })
	APLog("  config", {
		PATCH_AUDIO_OPTIONS = MN_Config.PATCH_AUDIO_OPTIONS,
		LEGACY_EDITOR = EDITOR, RENDER_EDITOR = RENDER_EDITOR, OPT_ID = OPT_ID,
	})
	APLog("  class", {
		class_defined = MN_AudioPatch.class_defined,
		gClasses_has_row = rawget(_G, "g_Classes") and (rawget(_G, "g_Classes")[CLASS_NAME] ~= nil) or false,
		global_has_row = rawget(_G, CLASS_NAME) ~= nil,
	})
	APLog("  MenuProp group", {
		present = type(grp) == "table",
		count = type(grp) == "table" and #grp or -1,
		has_legacy_member = MN_GroupHasMember(),
	})
	APLog("  PropBool hooks", {
		applied = MN_AudioPatch.bool_patch_applied,
		has_original_mouse = type(MN_AudioPatch.orig_PropBool_OnMouseButtonDown) == "function",
		has_original_update = type(MN_AudioPatch.orig_PropBool_OnPropUpdate) == "function",
	})
	APLog("  OptionsObject", {
		present = OptionsObject ~= nil,
		props_count = OptionsObject and type(OptionsObject.properties) == "table" and #OptionsObject.properties or -1,
		our_prop_present = prop ~= nil and prop ~= false,
		our_prop_category = prop and prop.category,
		our_prop_editor = prop and prop.editor,
		our_prop_no_edit = prop and tostring(prop.no_edit),
	})
	APLog("  render counters (since load)", {
		new_skipped = MN_AudioPatch.new_skipped,
		init_calls = MN_AudioPatch.init_calls,
		init_matched = MN_AudioPatch.init_matched,
	})
	if OptionsObject and type(OptionsObject.properties) == "table" then
		local audio_count = 0
		for index, meta in ipairs(OptionsObject.properties) do
			if type(meta) == "table" and meta.category == "Audio" then
				audio_count = audio_count + 1
				APLog("  Audio property", {
					index = index,
					id = meta.id,
					editor = meta.editor,
					no_edit = meta.no_edit,
					dont_save = meta.dont_save,
					is_mute_notifications = meta.id == OPT_ID,
				})
			end
		end
		APLog("  Audio property audit complete", { count = audio_count })
	end
end

-- Idempotent. Safe to call from several messages.
function MN_AudioPatch.Apply(reason)
	if MN_Config.PATCH_AUDIO_OPTIONS ~= true then
		APLog("Apply skipped: PATCH_AUDIO_OPTIONS=false", { reason = reason })
		return false
	end

	APLog("Apply begin", { reason = reason })

	local group_call_ok, group_ok, group_err = pcall(MN_RemoveLegacyGroupMember)
	if group_call_ok ~= true then
		APLog("RemoveLegacyGroupMember threw", { error = group_ok })
	elseif group_ok ~= true then
		APLog("RemoveLegacyGroupMember failed", { error = group_err })
	end

	local hook_call_ok, hook_ok, hook_err = pcall(MN_InstallBoolRowPatch)
	if hook_call_ok ~= true then
		APLog("InstallBoolRowPatch threw", { error = hook_ok })
	elseif hook_ok ~= true then
		APLog("InstallBoolRowPatch failed", { error = hook_err })
	end

	local prop_call_ok, prop_ok, prop_err = pcall(MN_AddProperty)
	if prop_call_ok ~= true then
		APLog("AddProperty threw", { error = prop_ok })
	elseif prop_ok ~= true then
		APLog("AddProperty failed", { error = prop_err })
	end

	local prop = MN_PropPresent()
	local success = group_call_ok and group_ok
		and hook_call_ok and hook_ok
		and prop_call_ok and prop_ok
		and MN_AudioPatch.bool_patch_applied
		and MN_AudioPatch.prop_added
		and prop and prop.editor == RENDER_EDITOR
		and MN_GroupHasMember() ~= true

	MN_AudioPatch.Diagnose("after Apply (" .. tostring(reason) .. ")")
	APLog(success and "Apply OK (row should appear in Options -> Audio)" or "Apply INCOMPLETE (use MN_OpenPanel() to open the panel)")

	return success
end
