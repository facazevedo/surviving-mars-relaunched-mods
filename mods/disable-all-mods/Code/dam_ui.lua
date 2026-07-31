-- dam_ui.lua
-- Adds one namespaced button immediately after the Installed Mods count.
-- The mutation is idempotent and is explicitly removable on mod unload.

DAM_UI = {}

local injected_element = false
local injected_parent = false
local live_buttons = setmetatable({}, { __mode = "k" })

local HEADER_ACTION_TEXT_COLOR = RGBA(173, 173, 173, 255)
local HEADER_ACTION_ROLLOVER_TEXT_COLOR = RGBA(246, 246, 246, 255)

local function find_element(root, property_name, property_value)
	if type(root) ~= "table" then
		return nil
	end
	for index = 1, #root do
		local child = root[index]
		if type(child) == "table" then
			if rawget(child, property_name) == property_value then
				return child, root, index
			end
			local found, parent, child_index = find_element(child, property_name, property_value)
			if found then
				return found, parent, child_index
			end
		end
	end
	return nil
end

local function apply_header_action_text_colors(button)
	button:SetTextColor(HEADER_ACTION_TEXT_COLOR)
	button:SetRolloverTextColor(HEADER_ACTION_ROLLOVER_TEXT_COLOR)
end

function DAM_UI.UpdateButton(button)
	if button == nil or button.window_state == "destroying" then
		return
	end
	live_buttons[button] = true
	button:SetText(DAM_State.GetButtonText())
	button:SetEnabled(DAM_ModControl.IsBusy() ~= true)
	apply_header_action_text_colors(button)
end

function DAM_UI.RefreshButton(host)
	if type(host) ~= "table"
		or host.window_state == "destroying"
		or type(host.ResolveId) ~= "function"
	then
		return
	end
	local button = host:ResolveId(DAM_Config.BUTTON_ID)
	if button then
		DAM_UI.UpdateButton(button)
	end
end

local function create_button_element()
	return PlaceObj("XTemplateWindow", {
		"__class", "XTextButton",
		"Id", DAM_Config.BUTTON_ID,
		"Margins", box(30, 0, 0, 0),
		"Padding", box(0, 0, 0, 0),
		"VAlign", "center",
		"FoldWhenHidden", true,
		"Background", RGBA(0, 0, 0, 0),
		"RolloverBackground", RGBA(0, 0, 0, 0),
		"PressedBackground", RGBA(0, 0, 0, 0),
		"FocusedBackground", RGBA(0, 0, 0, 0),
		"TextStyle", "ModsUIText",
		"TextColor", HEADER_ACTION_TEXT_COLOR,
		"RolloverTextColor", HEADER_ACTION_ROLLOVER_TEXT_COLOR,
		"Translate", false,
		"Text", DAM_State.GetButtonText(),
		"OnContextUpdate", function(self, context, ...)
			XTextButton.OnContextUpdate(self, context, ...)
			DAM_UI.UpdateButton(self)
		end,
		"OnPress", function(self, gamepad)
			DAM_ModControl.Toggle(GetDialog(self))
		end,
	})
end

function DAM_UI.ApplyModBehavior()
	if DAM_Config.ENABLE_INSTALLED_MODS_BUTTON ~= true then
		DAM_Debug.Info("UI", "Installed Mods button is disabled by configuration", nil, "DEBUG_UI")
		return false
	end
	if type(XTemplates) ~= "table" or type(XTemplates.ModsUIMainContent) ~= "table" then
		DAM_Debug.Warn("UI", "ModsUIMainContent template is unavailable", nil, "DEBUG_UI")
		return false
	end

	local existing = find_element(XTemplates.ModsUIMainContent, "Id", DAM_Config.BUTTON_ID)
	if existing then
		DAM_Debug.Info("UI", "Installed Mods button already present", {
			button_id = DAM_Config.BUTTON_ID,
		}, "DEBUG_UI")
		return true
	end

	local anchor, parent, anchor_index = find_element(
		XTemplates.ModsUIMainContent,
		"Id",
		"idTextInstalled"
	)
	if anchor == nil or parent == nil then
		DAM_Debug.Error("UI", "Installed Mods count anchor was not found", {
			anchor_id = "idTextInstalled",
		}, "DEBUG_UI")
		return false
	end

	injected_element = create_button_element()
	injected_parent = parent
	table.insert(parent, anchor_index + 1, injected_element)

	DAM_Debug.Info("UI", "Added toggle after Installed Mods count", {
		anchor_id = "idTextInstalled",
		button_id = DAM_Config.BUTTON_ID,
	}, "DEBUG_UI")
	return true
end

function DAM_UI.RestoreVanillaBehavior()
	for button in pairs(live_buttons) do
		if button.window_state ~= "destroying" and type(button.delete) == "function" then
			button:delete()
		end
		live_buttons[button] = nil
	end

	local parent = injected_parent
	local element = injected_element

	if type(parent) == "table" and element then
		for index = #parent, 1, -1 do
			if parent[index] == element then
				table.remove(parent, index)
				injected_element = false
				injected_parent = false
				DAM_Debug.Info("UI", "Removed Installed Mods toggle", {
					button_id = DAM_Config.BUTTON_ID,
				}, "DEBUG_UI")
				return true
			end
		end
	end

	if type(XTemplates) == "table" and type(XTemplates.ModsUIMainContent) == "table" then
		local existing, existing_parent, existing_index = find_element(
			XTemplates.ModsUIMainContent,
			"Id",
			DAM_Config.BUTTON_ID
		)
		if existing and existing_parent then
			table.remove(existing_parent, existing_index)
		end
	end

	injected_element = false
	injected_parent = false
	return true
end
