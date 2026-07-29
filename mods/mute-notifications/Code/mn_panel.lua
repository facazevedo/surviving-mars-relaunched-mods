-- mn_panel.lua
-- The searchable "Mute Notifications" panel. Built at runtime from base X UI
-- classes (XWindow/XList/XEdit/XTextButton/XText) parented to terminal.desktop,
-- so it works from both the main-menu and in-game options screens. All window
-- construction is guarded; if UI classes are missing the panel degrades to a
-- console catalog export instead of erroring.

MN_Panel = {
	root = false,
	list = false,
	search = "",
	search_edit = false,
	group_filter = "All", -- unified filter value: All / category label / game group
	filter_control = false,
	visible = false,    -- entries currently shown (for "visible" bulk actions)
}

----- small guarded helpers -----------------------------------------------------

local function Cls(name)
	return rawget(_G, name)
end

local function U(text)
	local fn = rawget(_G, "Untranslated")
	if type(fn) == "function" then return fn(text) end
	return text
end

local function Col(r, g, b, a)
	local fn = rawget(_G, "RGBA")
	if type(fn) == "function" then return fn(r, g, b, a) end
	return nil
end

local function WinValid(win)
	return win ~= nil and win ~= false and win.window_state ~= "destroying"
end

local function MN_SortedKeys(set)
	local list = {}
	if type(set) == "table" then
		for key in pairs(set) do
			list[#list + 1] = key
		end
	end
	table.sort(list)
	return list
end

-- Clear any highlighted (white) selection in the notifications list.
function MN_Panel.ClearSelection()
	local list = MN_Panel.list
	if WinValid(list) and type(list.SetSelection) == "function" then
		pcall(function() list:SetSelection(false) end)
	end
end

function MN_Panel.SetFilter(value)
	MN_Panel.group_filter = value or "All"
	local ctrl = MN_Panel.filter_control
	if WinValid(ctrl) then
		if type(ctrl.SetValueWithText) == "function" then
			pcall(function() ctrl:SetValueWithText(MN_Panel.group_filter, MN_Panel.group_filter, true) end)
		elseif type(ctrl.SetText) == "function" then
			ctrl:SetText("Filter: " .. MN_Panel.group_filter)
		end
	end
end

function MN_Panel.SetSearch(value)
	MN_Panel.search = value or ""
	local edit = MN_Panel.search_edit
	if WinValid(edit) then
		if type(edit.SetText) == "function" then
			edit:SetText(MN_Panel.search)
		elseif type(edit.SetTranslatedText) == "function" then
			edit:SetTranslatedText(MN_Panel.search, false)
		end
	end
end

local function MN_MakeText(parent, text, style, opts)
	local XText = Cls("XText")
	if not XText then return false end
	opts = opts or {}
	local t = XText:new({
		Translate = false,
		TextStyle = style or "PropValue",
		HAlign = opts.HAlign or "left",
		VAlign = opts.VAlign or "center",
		HandleMouse = opts.HandleMouse or false,
		WordWrap = opts.WordWrap or false,
		MinWidth = opts.MinWidth,
		MaxWidth = opts.MaxWidth,
		TextColor = opts.TextColor or Col(230, 230, 230, 255),
	}, parent)
	t:SetText(text or "")
	return t
end

local function MN_MakeButton(parent, text, on_press, opts)
	local XTextButton = Cls("XTextButton")
	if not XTextButton then return false end
	opts = opts or {}
	local b = XTextButton:new({
		Translate = false,
		TextStyle = opts.TextStyle or "ActionSmall",
		Padding = opts.Padding or box(10, 4, 10, 4),
		MinWidth = opts.MinWidth or 90,
		MinHeight = opts.MinHeight or 30,
		MaxHeight = opts.MaxHeight or 36,
		HAlign = opts.HAlign or "left",
		VAlign = opts.VAlign or "center",
		Background = opts.Background or Col(38, 46, 52, 235),
		RolloverBackground = opts.RolloverBackground or Col(54, 68, 74, 235),
		PressedBackground = opts.PressedBackground or Col(85, 101, 108, 245),
		TextColor = opts.TextColor or Col(255, 255, 255, 255),
		RolloverTextColor = Col(255, 255, 255, 255),
		OnPress = function(self, gamepad)
			if type(on_press) == "function" then
				local ok, err = pcall(on_press, self, gamepad)
				if ok ~= true then
					MN_Debug.Error("Panel", "Button handler error", { error = err })
				end
			end
		end,
	}, parent)
	b:SetText(text or "")
	return b
end

----- filtering -----------------------------------------------------------------

local function MN_FilterList()
	local filters = { "All" }
	local seen = {}
	local whitelist = MN_Catalog.CustomNamesActive()
	if MN_Catalog.IsBuilt() then
		for _, e in ipairs(MN_Catalog.entries) do
			if not whitelist or e.in_custom_list then
				if type(e.categories) == "table" then
					for _, label in ipairs(e.categories) do
						if type(label) == "string" and label ~= "" then
							seen[label] = true
						end
					end
				end
				if e.group then
					seen[e.group] = true
				end
			end
		end
	end
	for _, label in ipairs(MN_SortedKeys(seen)) do
		filters[#filters + 1] = label
	end
	return filters
end

local function MN_EntryMatches(entry)
	-- When MN_CustomNames is used as a whitelist, hide anything not listed
	-- (i.e. lines the user commented out / removed).
	if MN_Catalog.CustomNamesActive() and not entry.in_custom_list then
		return false
	end
	local filter = MN_Panel.group_filter
	if filter ~= "All" and entry.group ~= filter and MN_Catalog.EntryHasCategory(entry, filter) ~= true then
		return false
	end
	local q = MN_Panel.search
	if q == nil or q == "" then return true end
	q = string.lower(q)
	local hay = string.lower(table.concat({
		tostring(entry.title or ""), tostring(entry.id or ""),
		tostring(entry.group or ""), MN_Catalog.EntryCategoryText(entry),
		tostring(entry.game_title or ""), tostring(entry.item_text or ""),
		tostring(entry.voiced_text or ""),
	}, " "))
	return string.find(hay, q, 1, true) ~= nil
end

local function MN_EntryCountsInPanelTotal(entry, whitelist)
	return entry ~= nil and (whitelist ~= true or entry.in_custom_list == true)
end

local function MN_ToggleLabel(entry)
	return MN_Catalog.IsEntryMuted(entry) and "[X] Muted" or "[  ] Allowed"
end

----- row -----------------------------------------------------------------------

local function MN_RowDisplayName(entry)
	local voice = tostring(entry and entry.voiced_text or "")
	local name = entry and entry.title or ""
	if not name or name == "" or name == entry.id then
		name = voice
	end
	if tostring(name) == voice then
		local game_title = entry and entry.game_title or ""
		local item_text = entry and entry.item_text or ""
		if game_title ~= "" and game_title ~= entry.id and game_title ~= voice then
			name = game_title
		elseif item_text ~= "" and item_text ~= entry.id and item_text ~= voice then
			name = item_text
		end
	end
	return name
end

local function MN_PrimaryDisplayCategory(entry)
	if type(entry) ~= "table" then
		return ""
	end
	if type(entry.categories) == "table" and type(entry.categories[1]) == "string" and entry.categories[1] ~= "" then
		return entry.categories[1]
	end
	return tostring(entry.group or "")
end

local function MN_SortText(value)
	return string.lower(tostring(value or ""))
end

local function MN_ComparePanelEntries(a, b)
	local ac = MN_SortText(MN_PrimaryDisplayCategory(a))
	local bc = MN_SortText(MN_PrimaryDisplayCategory(b))
	if ac ~= bc then
		return ac < bc
	end

	local at = MN_SortText(MN_RowDisplayName(a))
	local bt = MN_SortText(MN_RowDisplayName(b))
	if at ~= bt then
		return at < bt
	end

	local ag = MN_SortText(a and a.group)
	local bg = MN_SortText(b and b.group)
	if ag ~= bg then
		return ag < bg
	end

	return tostring(a and a.id or "") < tostring(b and b.id or "")
end

local function MN_DisplayNumber(index)
	return string.format("%03d. ", tonumber(index) or 0)
end

local function MN_BuildRow(list, entry, display_index)
	local XWindow = Cls("XWindow")
	local row = XWindow:new({
		LayoutMethod = "HList",
		LayoutHSpacing = 8,
		HAlign = "stretch",
		MinHeight = 112,
		Padding = box(6, 4, 6, 4),
		Background = entry.protected and Col(40, 34, 28, 120) or Col(28, 34, 38, 90),
		HandleMouse = true,
		-- Swallow clicks on the row background so the parent XList never selects the
		-- item (which would highlight the whole row white). The toggle/Play buttons
		-- are separate children and still receive their own clicks.
		OnMouseButtonDown = function(self, pt, button)
			return "break"
		end,
	}, list)

	-- Mute toggle (checkbox-style). Display truth is strictly by id.
	local toggle = MN_MakeButton(row, MN_ToggleLabel(entry), function(self)
		MN_Catalog.SetEntryMuted(entry, not MN_Catalog.IsEntryMuted(entry))
		self:SetText(MN_ToggleLabel(entry))
		MN_Debug.Info("Panel", "Toggled mute", {
			id = entry.id, muted = MN_Catalog.IsEntryMuted(entry),
		}, "DEBUG_UI")
	end, { MinWidth = 130, MaxWidth = 130 })

	-- Play / preview (always audible; bypasses suppression). Match how the engine
	-- voices each source: notifications use their VoiceActor; popups/hints are
	-- played with no actor.
	if MN_Config.ENABLE_PLAY_PREVIEW == true then
		MN_MakeButton(row, "Play", function()
			local actor = (entry.source == "NotificationPreset") and entry.voice_actor or nil
			MN_VoiceSuppression.PlayPreview(entry.voiced_T or entry.voiced_text, actor)
		end, { MinWidth = 64, MaxWidth = 64,
			Background = Col(30, 52, 40, 235), RolloverBackground = Col(42, 74, 56, 235) })
	end

	-- Text cell: a human-readable name + group on one line, spoken line beneath.
	-- Never show the technical preset id; if the only "title" is the id, use the
	-- spoken line as the name instead.
	local cell = XWindow:new({
		LayoutMethod = "VList",
		LayoutVSpacing = 2,
		HAlign = "stretch",
		VAlign = "top",
		MinHeight = 104,
	}, row)
	local name = MN_RowDisplayName(entry)
	local category_text = MN_Catalog.EntryCategoryText(entry)
	local label_text = tostring(entry.group)
	if category_text ~= "" then
		label_text = label_text .. " | " .. category_text
	end
	MN_MakeText(cell,
		string.format("%s%s   (%s)%s", MN_DisplayNumber(display_index), tostring(name), label_text,
			entry.protected and "   *important*" or ""),
		"PropName", { TextColor = Col(255, 255, 255, 255) })
	-- Always show the spoken line so custom display names never hide the audio text.
	MN_MakeText(cell,
		"\"" .. tostring(entry.voiced_text) .. "\"",
		"PropValue", { TextColor = Col(180, 200, 210, 255), WordWrap = false })

	-- Rows are always added after the list is already open, and ChildJoining does
	-- not auto-open children, so open the row subtree explicitly.
	if row.window_state == "new" then
		row:Open()
	end
	return row
end

----- rebuild -------------------------------------------------------------------

function MN_Panel.Rebuild()
	if not WinValid(MN_Panel.list) then return end
	local list = MN_Panel.list
	if type(list.Clear) == "function" then
		list:Clear()
	end
	MN_Catalog.EnsureBuilt("panel_rebuild")

	local visible = {}
	if MN_Catalog.IsBuilt() then
		for _, entry in ipairs(MN_Catalog.entries) do
			if MN_EntryMatches(entry) then
				visible[#visible + 1] = entry
			end
		end
	end
	table.sort(visible, MN_ComparePanelEntries)
	for i, entry in ipairs(visible) do
		MN_BuildRow(list, entry, i)
	end
	MN_Panel.visible = visible

	-- Trailing spacer so the LAST real row can scroll clear of the bottom clip
	-- edge (otherwise its Play button sits half-clipped and is hard to click).
	if #visible > 0 then
		local XWindow = Cls("XWindow")
		if XWindow then
			local spacer = XWindow:new({ MinHeight = 48, HAlign = "stretch", HandleMouse = false }, list)
			if spacer.window_state == "new" then spacer:Open() end
		end
	end

	if WinValid(MN_Panel.count_text) then
		local total, muted = 0, 0
		if MN_Catalog.IsBuilt() then
			local whitelist = MN_Catalog.CustomNamesActive()
			for _, e in ipairs(MN_Catalog.entries) do
				if MN_EntryCountsInPanelTotal(e, whitelist) then
					total = total + 1
					if MN_Catalog.IsEntryMuted(e) then muted = muted + 1 end
				end
			end
		end
		MN_Panel.count_text:SetText(string.format("%d shown / %d total / %d muted",
			#visible, total, muted))
	end
	list:InvalidateLayout()
	MN_Debug.Info("Panel", "Rebuilt list", { shown = #visible }, "DEBUG_UI")
end

----- bulk actions --------------------------------------------------------------

local function MN_VisibleEntries()
	return type(MN_Panel.visible) == "table" and MN_Panel.visible or {}
end

----- open / close --------------------------------------------------------------

function MN_Panel.IsOpen()
	return WinValid(MN_Panel.root)
end

function MN_Panel.Close(reason)
	if WinValid(MN_Panel.root) then
		if type(MN_Panel.root.SetModal) == "function" then
			pcall(function() MN_Panel.root:SetModal(false) end)
		end
		MN_Panel.root:delete()
	end
	MN_Panel.root = false
	MN_Panel.list = false
	MN_Panel.count_text = false
	MN_Panel.search_edit = false
	MN_Panel.filter_control = false
	MN_Debug.Info("Panel", "Closed", { reason = reason }, "DEBUG_UI")
end

function MN_Panel.Open(reason)
	local XWindow = Cls("XWindow")
	local XList = Cls("XList")
	local XEdit = Cls("XEdit")
	local desktop = rawget(_G, "terminal") and terminal.desktop or nil

	if not XWindow or not XList or not desktop then
		MN_Debug.Error("Panel", "Required UI classes unavailable; exporting catalog to log instead", {
			has_XWindow = XWindow ~= nil, has_XList = XList ~= nil, has_desktop = desktop ~= nil,
		})
		MN_Catalog.Export("panel_fallback")
		return false
	end

	if MN_Panel.IsOpen() then
		MN_Panel.Rebuild()
		return true
	end

	MN_Panel.search = ""
	MN_Panel.group_filter = "All"
	MN_Catalog.EnsureBuilt(reason or "panel_open")

	-- Full-screen backdrop that blocks clicks to the screen behind.
	-- Escape closes ONLY this panel (returns to the Audio options page).
	local root = XWindow:new({
		Id = "idMNPanelRoot",
		Dock = "box",
		HandleMouse = true,
		Background = Col(0, 0, 0, 160),
		OnShortcut = function(self, shortcut, source, ...)
			if shortcut == "Escape" then
				MN_Panel.Close("escape")
				return "break"
			end
		end,
		OnMouseButtonDown = function(self, pt, button)
			if button == "R" then
				MN_Panel.ClearSelection()
				return "break"
			end
		end,
	}, desktop)
	MN_Panel.root = root

	-- Centered, fixed-size content box. Keep the panel dimensions stable while
	-- searches and filters rebuild rows with differently sized text.
	local content = XWindow:new({
		HAlign = "center",
		VAlign = "center",
		MinWidth = 1500,
		MaxWidth = 1500,
		MinHeight = 670,
		MaxHeight = 670,
		LayoutMethod = "VList",
		LayoutVSpacing = 8,
		Padding = box(16, 16, 16, 16),
		Background = Col(18, 22, 26, 250),
		BorderWidth = 1,
		BorderColor = Col(70, 84, 90, 255),
		HandleMouse = true,
		OnMouseButtonDown = function(self, pt, button)
			if button == "R" then
				MN_Panel.ClearSelection()
				return "break"
			end
		end,
	}, root)

	-- Header.
	MN_MakeText(content, "Mute Notifications - visual notifications are never hidden.",
		"PropName", { TextColor = Col(255, 255, 255, 255) })

	-- Toolbar: search + group filter + count.
	local toolbar = XWindow:new({
		LayoutMethod = "HList", LayoutHSpacing = 10, HAlign = "stretch",
		Padding = box(0, 4, 0, 4),
	}, content)
	MN_MakeText(toolbar, "Search:", "PropValue", { MinWidth = 64 })
	if XEdit then
		local edit = XEdit:new({
			Id = "idMNSearch",
			Translate = false,
			Hint = "type to filter...",
			TextStyle = "PropValue",
			MinWidth = 360,
			MaxWidth = 360,
			Background = Col(8, 10, 12, 255),
			FocusedBackground = Col(12, 15, 18, 255),
			BorderWidth = 1,
			BorderColor = Col(70, 84, 90, 255),
			FocusedBorderColor = Col(100, 118, 126, 255),
			Padding = box(6, 4, 6, 4),
			OnTextChanged = function(self)
				MN_Panel.search = (type(self.GetText) == "function") and (self:GetText() or "") or ""
				MN_Panel.Rebuild()
			end,
		}, toolbar)
		MN_Panel.search_edit = edit
	end
	-- Clear button: empties the search field and shows everything in the current group.
	MN_MakeButton(toolbar, "Clear", function()
		MN_Panel.search = ""
		local e = MN_Panel.search_edit
		if WinValid(e) then
			if type(e.SetText) == "function" then
				e:SetText("")
			elseif type(e.SetTranslatedText) == "function" then
				e:SetTranslatedText("", false)
			end
		end
		MN_Panel.Rebuild()
	end, { MinWidth = 80 })
	-- Unified filter: a traditional dropdown (XCombo). The panel is made modal on
	-- open (see root:SetModal below) so the combo's popup parents to our window and
	-- renders on top where it can be clicked.
	MN_MakeText(toolbar, "Filter:", "PropValue", { MinWidth = 56 })
	local XCombo = Cls("XCombo")
	if XCombo then
		local filter_combo = XCombo:new({
			Id = "idMNGroup",
			Translate = false,
			ArbitraryValue = false,
			TextStyle = "PropValue",
			Padding = box(6, 4, 1, 4),
			Background = Col(8, 10, 12, 255),
			FocusedBackground = Col(12, 15, 18, 255),
			BorderWidth = 1,
			BorderColor = Col(70, 84, 90, 255),
			FocusedBorderColor = Col(100, 118, 126, 255),
			PopupBackground = Col(18, 22, 26, 255),
			ListItemTemplate = "XComboXTextListItemDark",
			AutoSelectAll = false,
			-- MUST stay false: with RefreshItemsOnOpen=true, CloseCombo sets
			-- self.Items=nil, destroying our Items function so the combo never opens
			-- again. Items is a function, so it is re-evaluated on every open anyway.
			RefreshItemsOnOpen = false,
			MinWidth = 220,
			MaxWidth = 260,
			MinItems = 1,
			MaxItems = 25,
			Items = function() return MN_FilterList() end,
			Value = MN_Panel.group_filter,
			OnValueChanged = function(self, value)
				if value and value ~= "" then
					MN_Panel.group_filter = value
					MN_Panel.Rebuild()
				end
			end,
		}, toolbar)
		MN_Panel.filter_control = filter_combo

		-- XCombo creates an internal XEdit whose focused background defaults to
		-- white, independently of the combo's own colors. Force every edit state
		-- dark and remove the blue auto-selection background.
		local field_bg = Col(8, 10, 12, 255)
		local popup_bg = Col(18, 22, 26, 255)
		local edit = filter_combo.idEdit
		if edit then
			edit:SetBackground(field_bg)
			edit:SetFocusedBackground(field_bg)
			edit:SetDisabledBackground(field_bg)
			edit:SetSelectionBackground(field_bg)
			edit:SetSelectionColor(Col(255, 255, 255, 255))
		end

		-- The stock dark item template still uses white/gray focus and rollover
		-- colors. Restyle the popup and each concrete item after XCombo builds it.
		local stock_open_combo = filter_combo.OpenCombo
		filter_combo.OpenCombo = function(self, mode)
			local popup = stock_open_combo(self, mode)
			if not popup then return popup end

			local function SetColor(win, setter, color)
				local fn = win and win[setter]
				if type(fn) == "function" then fn(win, color) end
			end

			SetColor(popup, "SetBackground", popup_bg)
			SetColor(popup, "SetFocusedBackground", popup_bg)
			SetColor(popup, "SetBorderColor", Col(70, 84, 90, 255))
			SetColor(popup, "SetFocusedBorderColor", Col(70, 84, 90, 255))

			local container = popup.idContainer
			SetColor(container, "SetBackground", popup_bg)
			SetColor(container, "SetFocusedBackground", popup_bg)
			if container then
				for _, item in ipairs(container) do
					SetColor(item, "SetBackground", popup_bg)
					SetColor(item, "SetFocusedBackground", popup_bg)
					SetColor(item, "SetRolloverBackground", popup_bg)
					SetColor(item, "SetPressedBackground", popup_bg)
					SetColor(item, "SetDisabledBackground", popup_bg)
				end
			end
			return popup
		end

		-- XCombo's stock arrow button is bright blue. Restyle it to the same
		-- charcoal palette as the panel while preserving its built-in icon.
		local arrow = filter_combo.idButton
		if arrow then
			arrow:SetBackground(Col(38, 46, 52, 255))
			arrow:SetRolloverBackground(Col(54, 68, 74, 255))
			arrow:SetPressedBackground(Col(85, 101, 108, 255))
			arrow:SetDisabledBackground(Col(28, 34, 38, 255))
		end
	else
		MN_Panel.filter_control = MN_MakeButton(toolbar, "Filter: " .. MN_Panel.group_filter, function(self)
			local groups = MN_FilterList()
			local idx = 1
			for i, g in ipairs(groups) do if g == MN_Panel.group_filter then idx = i break end end
			idx = idx % #groups + 1
			MN_Panel.group_filter = groups[idx]
			self:SetText("Filter: " .. MN_Panel.group_filter)
			MN_Panel.Rebuild()
		end, { MinWidth = 200 })
	end
	MN_Panel.SetFilter("All")
	MN_Panel.count_text = MN_MakeText(toolbar, "", "PropValue", { HAlign = "right", MinWidth = 260 })

	-- Notifications list: a FIXED-height field below the toolbar (does not grow to
	-- fill the screen). Content beyond this height is clipped and scrolled with the
	-- mouse wheel. Bottom padding lets the last row scroll clear of the clip edge.
	local list = XList:new({
		Id = "idMNList",
		HAlign = "stretch",
		VAlign = "top",
		MinHeight = 480,
		MaxHeight = 480,
		LayoutMethod = "VList",
		LayoutVSpacing = 3,
		Padding = box(2, 2, 2, 40),
		BorderWidth = 1,
		BorderColor = Col(50, 60, 66, 255),
		Background = Col(12, 15, 18, 255),
		Clip = "parent & self",
		MouseScroll = true,
	}, content)
	MN_Panel.list = list

	-- Footer buttons.
	local footer = XWindow:new({
		LayoutMethod = "HList", LayoutHSpacing = 8, HAlign = "stretch",
		Padding = box(0, 6, 0, 0),
	}, content)
	MN_MakeButton(footer, "Mute group", function()
		MN_Catalog.SetEntriesMuted(MN_VisibleEntries(), true, "mute_visible"); MN_Panel.Rebuild()
	end)
	MN_MakeButton(footer, "Unmute group", function()
		MN_Catalog.SetEntriesMuted(MN_VisibleEntries(), false, "unmute_visible"); MN_Panel.Rebuild()
	end)
	MN_MakeButton(footer, "Reset", function()
		MN_Persistence.ResetAll({ no_save = true, defaults_applied = true })
		MN_Persistence.Save("panel_reset_all_unmuted")
		MN_Panel.SetSearch("")
		MN_Panel.SetFilter("All")
		MN_Panel.Rebuild()
	end)
	local back_button = MN_MakeButton(footer, "Back", function()
		MN_Panel.Close("back_button")
	end, { Background = Col(70, 40, 40, 235), RolloverBackground = Col(100, 56, 56, 235), HAlign = "right" })
	if back_button then
		-- XTextButton normally uses HList, which leaves all width above the label's
		-- measured width on its right. Box centers the unchanged, natural-size label
		-- in the complete button content area.
		back_button:SetLayoutMethod("Box")
		if back_button.idLabel then
			back_button.idLabel:SetHAlign("center")
		end

		-- Close on mouse-down instead of relying on the normal captured mouse-up
		-- path. Keep OnPress above for keyboard/gamepad activation.
		back_button.OnMouseButtonDown = function(self, pt, button)
			if button == "L" then
				local create_thread = rawget(_G, "CreateRealTimeThread")
				if type(create_thread) == "function" then
					create_thread(function()
						MN_Panel.Close("back_button_mouse")
					end)
				else
					MN_Panel.Close("back_button_mouse")
				end
				return "break"
			end
			return "break"
		end
	end

	root:Open()
	-- Make the panel modal so the filter XCombo's popup parents to OUR window and
	-- renders on top (otherwise it attaches to the Options dialog behind us and is
	-- unclickable). Must be done after Open (the window must be visible/on top).
	if type(root.SetModal) == "function" then
		pcall(function() root:SetModal(true) end)
	end
	-- Take keyboard focus so Escape reaches root:OnShortcut (and not the Options
	-- dialog behind us), making Esc close only this panel.
	if type(root.SetFocus) == "function" then
		local ok = pcall(function() root:SetFocus(true) end)
		if ok ~= true then pcall(function() root:SetFocus() end) end
	end
	MN_Panel.Rebuild()

	MN_Debug.Info("Panel", "Opened", {
		reason = reason, entries = MN_Catalog.IsBuilt() and #MN_Catalog.entries or 0,
	})
	return true
end

-- Global entry points (also usable from the console as a guaranteed fallback).
function MN_OpenPanel(reason)
	return MN_Panel.Open(reason or "global")
end

function MN_ClosePanel(reason)
	return MN_Panel.Close(reason or "global")
end
