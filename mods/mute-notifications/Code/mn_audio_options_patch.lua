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
	new_skipped = 0,     -- MN_OptionRow:new skips for non-matching properties
	init_calls = 0,      -- MN_OptionRow:Init invocations for OUR property
	init_matched = 0,    -- ...of which matched OUR property
}

local EDITOR = MN_Config.AUDIO_OPTION_EDITOR
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

-- The class may survive a mod-code reload. Refresh the constructor every load so
-- non-matching properties return nil instead of creating hidden rows that can be
-- mistaken for the generated option row by OptionsContentWindow.
if rawget(_G, "XPropControl") ~= nil and rawget(_G, CLASS_NAME) ~= nil then
	function MN_OptionRow:new(args, parent, context)
		local pm = context and context.prop_meta
		if not (pm and pm.editor == EDITOR) then
			MN_AudioPatch.new_skipped = MN_AudioPatch.new_skipped + 1
			return nil
		end
		return XPropControl.new(self, args, parent, context)
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
	if MN_PropPresent() then
		MN_AudioPatch.prop_added = true
		return true
	end
	local U = rawget(_G, "Untranslated")
	local name = U and U("Mute Notifications") or "Mute Notifications"
	local help = U and U("Open the Mute Notifications panel to choose which Mission Control voice lines are silenced. Visual notifications are not affected.") or nil
	table.insert(OptionsObject.properties, {
		name = name,
		id = OPT_ID,
		category = "Audio",
		editor = EDITOR,
		default = false,
		dont_save = true,
		no_edit = false,
		help_text = help,
		SortKey = 100000,   -- keep it at the bottom of the Audio list
	})
	rawset(OptionsObject, "props_cache", false)
	MN_AudioPatch.prop_added = true
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
		EDITOR = EDITOR, OPT_ID = OPT_ID,
	})
	APLog("  class", {
		class_defined = MN_AudioPatch.class_defined,
		gClasses_has_row = rawget(_G, "g_Classes") and (rawget(_G, "g_Classes")[CLASS_NAME] ~= nil) or false,
		global_has_row = rawget(_G, CLASS_NAME) ~= nil,
	})
	APLog("  MenuProp group", {
		present = type(grp) == "table",
		count = type(grp) == "table" and #grp or -1,
		has_our_member = MN_GroupHasMember(),
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
end

-- Idempotent. Safe to call from several messages.
function MN_AudioPatch.Apply(reason)
	if MN_Config.PATCH_AUDIO_OPTIONS ~= true then
		APLog("Apply skipped: PATCH_AUDIO_OPTIONS=false", { reason = reason })
		return false
	end

	APLog("Apply begin", { reason = reason })

	local ok_group, err_group = pcall(MN_RegisterGroupMember)
	if ok_group ~= true then APLog("RegisterGroupMember threw", { error = err_group }) end

	local ok_prop, err_prop = pcall(MN_AddProperty)
	if ok_prop ~= true then APLog("AddProperty threw", { error = err_prop }) end

	local success = MN_AudioPatch.group_registered and MN_AudioPatch.prop_added and MN_AudioPatch.class_defined

	MN_AudioPatch.Diagnose("after Apply (" .. tostring(reason) .. ")")
	APLog(success and "Apply OK (row should appear in Options -> Audio)" or "Apply INCOMPLETE (use MN_OpenPanel() to open the panel)")

	return success
end
