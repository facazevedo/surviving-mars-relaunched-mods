-- mn_catalog.lua
-- Discovers every voiced notification from the live notification-preset system
-- (the global NotificationPresets map populated from NotificationPreset data) and
-- builds a searchable catalog. Also owns default-spam matching and the one-time
-- application of default mutes.

local MN_CATALOG_SCHEMA_VERSION = 9
local MN_REPEATED_CATEGORY = "Repeated"

local function MN_CurrentConfigVersion()
	return type(MN_Config) == "table" and tostring(MN_Config.VERSION or "") or ""
end

MN_Catalog = rawget(_G, "MN_Catalog") or {}
MN_Catalog.entries = MN_Catalog.entries or false   -- array of catalog entries (sorted)
MN_Catalog.by_id = MN_Catalog.by_id or false       -- id -> entry
MN_Catalog.built = MN_Catalog.built or false
MN_Catalog.schema_version = MN_Catalog.schema_version or 0
MN_Catalog.config_version = MN_Catalog.config_version or false
MN_Catalog.scenarios_included = MN_Catalog.scenarios_included or false

----- Text helpers --------------------------------------------------------------

-- Translate a T value (or pass through a plain string) to a displayable string.
-- Guarded so an unexpected T form can never raise.
function MN_Catalog.Translate(t)
	if t == nil or t == false then return "" end
	if type(t) == "string" then return t end
	-- tags_off=true: do NOT resolve TFormat tags like <ColonistName>. Resolving
	-- them with no context spams "Invalid argument supplied to ColonistName(): nil"
	-- (an uncatchable printf). For catalog display we only need the literal text;
	-- voiced lines themselves are tag-free, so matching is unaffected.
	local fn = rawget(_G, "_InternalTranslate")
	if type(fn) == "function" then
		local ok, s = pcall(fn, t, false, false, true)
		if ok and type(s) == "string" then return s end
	end
	local fn2 = rawget(_G, "TTranslate")
	if type(fn2) == "function" then
		local ok, s = pcall(fn2, t, false, false, true)
		if ok and type(s) == "string" then return s end
	end
	return tostring(t)
end

function MN_Catalog.CleanDisplayText(text)
	text = tostring(text or "")
	text = text:gsub("<icon_[^>]+>", "")
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return text
end

-- Normalize text into a stable lowercase key used for text-fallback matching and
-- as the persistent muted_by_voice_text key.
function MN_Catalog.NormalizeText(s)
	if type(s) ~= "string" then s = tostring(s or "") end
	s = string.lower(s)
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	return s
end

function MN_Catalog.VoiceTextKey(t)
	return MN_Catalog.NormalizeText(MN_Catalog.Translate(t))
end

function MN_Catalog.SpokenText(voiced_text)
	local source_text = tostring(voiced_text or "")
	local overrides = rawget(_G, "MN_SpokenTextOverrides")
	local override = type(overrides) == "table" and overrides[source_text] or nil
	if type(override) == "string" and override ~= "" then
		return override, true
	end
	return source_text, false
end

----- Matching ------------------------------------------------------------------

function MN_Catalog.IsGroupProtected(group)
	return group ~= nil and MN_ProtectedVoiceGroups[group] == true
end

-- MN_CustomNames is the visibility whitelist for the original preset families.
-- Verified HUD, direct and scenario entries explicitly opt in during discovery.
function MN_Catalog.CustomNamesActive()
	local c = rawget(_G, "MN_CustomNames")
	return type(c) == "table" and next(c) ~= nil
end

-- Returns rule_key, matched_on ("id"|"text"), matched_value when (id, text_key)
-- matches a default-spam rule; otherwise nil.
function MN_Catalog.MatchDefaultRule(id, text_key)
	for rule_key, rule in pairs(MN_DefaultSpamVoiceRules) do
		if rule.match_ids then
			for _, rid in ipairs(rule.match_ids) do
				if rid == id then
					return rule_key, "id", rid
				end
			end
		end
	end
	if text_key and text_key ~= "" then
		for rule_key, rule in pairs(MN_DefaultSpamVoiceRules) do
			if rule.match_text then
				for _, frag in ipairs(rule.match_text) do
					if frag ~= "" and string.find(text_key, frag, 1, true) then
						return rule_key, "text", frag
					end
				end
			end
		end
	end
	return nil
end

----- Category labels -----------------------------------------------------------

local function MN_AddCategoryLabel(list, seen, label)
	if type(label) ~= "string" then return end
	label = label:gsub("^%s+", ""):gsub("%s+$", "")
	if label == "" or seen[label] == true then return end
	seen[label] = true
	list[#list + 1] = label
end

function MN_Catalog.RuleCategories(rule_key)
	local categories = {}
	local seen = {}
	local rule = rule_key and MN_DefaultSpamVoiceRules[rule_key] or nil
	if type(rule) ~= "table" then
		return categories
	end
	if type(rule.categories) == "table" then
		for _, label in ipairs(rule.categories) do
			MN_AddCategoryLabel(categories, seen, label)
		end
	end
	-- Compatibility with older single-label rules.
	MN_AddCategoryLabel(categories, seen, rule.category)
	return categories
end

function MN_Catalog.CategoryLookup(categories)
	local lookup = {}
	if type(categories) == "table" then
		for _, label in ipairs(categories) do
			lookup[label] = true
		end
	end
	return lookup
end

function MN_Catalog.EntryHasCategory(entry, category)
	return type(entry) == "table"
		and type(entry.category_lookup) == "table"
		and entry.category_lookup[category] == true
end

function MN_Catalog.EntryCategoryText(entry)
	if type(entry) ~= "table" or type(entry.categories) ~= "table" or #entry.categories == 0 then
		return ""
	end
	return table.concat(entry.categories, ", ")
end

----- Discovery -----------------------------------------------------------------

local function MN_SortEntries(a, b)
	if a.group ~= b.group then
		return tostring(a.group) < tostring(b.group)
	end
	if a.title ~= b.title then
		return tostring(a.title) < tostring(b.title)
	end
	return tostring(a.id) < tostring(b.id)
end

local function MN_MarkRepeatedEntries(entries)
	local groups = {}
	local custom_names_active = MN_Catalog.CustomNamesActive()
	for _, entry in ipairs(entries) do
		if not custom_names_active or entry.in_custom_list == true then
			local key = entry.voiced_text_key
			if key and key ~= "" then
				local group = groups[key]
				if group == nil then
					group = {}
					groups[key] = group
				end
				group[#group + 1] = entry
			end
		end
	end

	local repeated_count = 0
	for _, group in pairs(groups) do
		if #group > 1 then
			for i, entry in ipairs(group) do
				repeated_count = repeated_count + 1
				entry.repeated = true
				entry.repeat_index = i
				entry.repeat_total = #group
				entry.repeat_key = entry.voiced_text_key
				entry.repeat_base_title = entry.title
				entry.repeat_voiced_text = entry.voiced_text

				entry.categories = entry.categories or {}
				entry.category_lookup = entry.category_lookup or {}
				MN_AddCategoryLabel(entry.categories, entry.category_lookup, MN_REPEATED_CATEGORY)

				entry.title = string.format("%02d. %s", i, tostring(entry.title or entry.id or ""))
			end
		end
	end

	return repeated_count
end

function MN_Catalog.Build(reason)
	local presets = rawget(_G, "NotificationPresets")
	local popups = rawget(_G, "PopupNotificationPresets")
	local hints = rawget(_G, "OnScreenHintPresets")
	local hud = rawget(_G, "HUDNotifications")
	local scenarios = rawget(_G, "Scenarios")
	if type(presets) ~= "table" and type(popups) ~= "table" and type(hints) ~= "table"
		and type(hud) ~= "table" and type(scenarios) ~= "table" then
		MN_Debug.Warn("Catalog", "No notification preset maps available; cannot build catalog", { reason = reason })
		return 0
	end

	local entries = {}
	local by_id = {}
	local spoken_text_override_count = 0

	-- Discover every preset or synthetic source that carries a non-empty voiced
	-- line. The game routes all sources below through QueueVoice or PlayVoicedText.
	local function AddEntry(id, preset, opts)
		if type(preset) ~= "table" or type(id) ~= "string" then return false end
		local entry_id = (opts.id_prefix or "") .. id
		if by_id[entry_id] then return false end

		local voiced = preset[opts.voiced_field]
		local voiced_str = MN_Catalog.Translate(voiced)
		local spoken_text, spoken_text_overridden = MN_Catalog.SpokenText(voiced_str)
		local group = preset.group or opts.default_group
		local excluded = MN_ExcludedVoiceIds[id] == true or MN_ExcludedVoiceGroups[group] == true
		local text_key = MN_Catalog.NormalizeText(voiced_str)
		if voiced == nil or voiced == false or voiced_str == "" or excluded then return false end

		local rule_key, matched_on, matched_value = MN_Catalog.MatchDefaultRule(id, text_key)
		local protected = MN_Catalog.IsGroupProtected(group)
		local title_src = preset[opts.title_field]
			or (opts.alt_title_field and preset[opts.alt_title_field]) or id
		local game_title = MN_Catalog.Translate(title_src)
		local display_title = game_title
		-- MN_CustomNames remains the editable whitelist for the original preset
		-- families. Verified HUD/direct/scenario sources opt in with force_visible.
		local custom = rawget(_G, "MN_CustomNames")
		local in_custom_list = opts.force_visible == true
		if type(custom) == "table" and custom[voiced_str] ~= nil then
			in_custom_list = true
			local cn = custom[voiced_str]
			if type(cn) == "string" and cn ~= "" then display_title = cn end
		end
		local categories = MN_Catalog.RuleCategories(rule_key)
		local category_lookup = MN_Catalog.CategoryLookup(categories)
		if type(opts.categories) == "table" then
			for _, label in ipairs(opts.categories) do
				MN_AddCategoryLabel(categories, category_lookup, label)
			end
		end
		local entry = {
			id = entry_id,
			preset_id = id,
			preset = preset,
			group = group,
			categories = categories,
			category_lookup = category_lookup,
			title = display_title,
			game_title = game_title,
			item_text = MN_Catalog.CleanDisplayText(MN_Catalog.Translate(preset.ItemText or preset.item_text)),
			in_custom_list = in_custom_list,
			text = MN_Catalog.Translate(preset.Text or preset.text),
			voiced_text = voiced_str,
			spoken_text = spoken_text,
			spoken_text_overridden = spoken_text_overridden,
			voiced_T = voiced,            -- raw T, used for accurate preview playback
			voiced_text_key = text_key,
			voice_actor = preset[opts.actor_field] or "narrator",
			source = opts.source,
			default_rule = rule_key,
			default_matched_on = matched_on,
			default_matched_value = matched_value,
			mute_by_default = (rule_key ~= nil) and (not protected),
			protected = protected,
		}
		if spoken_text_overridden == true then
			spoken_text_override_count = spoken_text_override_count + 1
			MN_Debug.Info("Catalog", "Applied recorded-voice transcript override", {
				id = entry_id,
				source_text = voiced_str,
				spoken_text = spoken_text,
			}, "DEBUG_CATALOG")
		end
		entries[#entries + 1] = entry
		by_id[entry_id] = entry
		return true
	end

	--   * NotificationPreset  (on-screen notification cards) - field VoicedText,
	--     played via QueueVoice -> suppressed by notification id.
	--   * PopupNotificationPreset (full popups: Welcome to Mars, tutorials, system,
	--     challenge/story intros) - field voiced_text, played via a direct
	--     PlayVoicedText -> suppressed by voiced-text fallback.
	local function AddFromMap(map, opts)
		if type(map) ~= "table" then return end
		for id, preset in pairs(map) do
			AddEntry(id, preset, opts)
		end
	end

	AddFromMap(presets, {
		voiced_field = "VoicedText", actor_field = "VoiceActor",
		title_field = "Title", alt_title_field = "RolloverTitle",
		source = "NotificationPreset", default_group = "Default",
	})
	AddFromMap(popups, {
		voiced_field = "voiced_text", actor_field = "actor",
		title_field = "title", alt_title_field = nil,
		source = "PopupNotificationPreset", default_group = "Popup",
	})
	-- Gameplay hints (Hints.lua plays preset.voiced_text via PlayVoicedText).
	AddFromMap(hints, {
		voiced_field = "voiced_text", actor_field = "actor",
		title_field = "title", alt_title_field = nil,
		source = "OnScreenHintPreset", default_group = "Hints",
	})
	-- Compact HUD alerts are not NotificationPreset objects, so they are muted
	-- through the existing normalized-text fallback.
	AddFromMap(hud, {
		voiced_field = "voiced_text", actor_field = "actor",
		title_field = "text", alt_title_field = nil,
		source = "HUDNotificationPreset", default_group = "HUD",
		id_prefix = "HUD:", force_visible = true, categories = { "HUD" },
	})

	-- Literal gameplay calls (building destroyed, vote passed, etc.) do not live
	-- in a preset map. Recreate their T values so previews retain the real voice id.
	local make_t = rawget(_G, "T")
	local direct = rawget(_G, "MN_AdditionalVoices")
	if type(make_t) == "function" and type(direct) == "table" then
		for _, spec in ipairs(direct) do
			if type(spec) == "table" and type(spec.id) == "string"
				and type(spec.translation_id) == "number" and type(spec.voiced_text) == "string" then
				local preset = {
					voiced_text = make_t(spec.translation_id, spec.voiced_text),
					actor = spec.actor or "aide",
					title = spec.title or spec.voiced_text,
					text = spec.voiced_text,
					group = spec.group or "System",
				}
				AddEntry(spec.id, preset, {
					voiced_field = "voiced_text", actor_field = "actor",
					title_field = "title", alt_title_field = nil,
					source = "DirectVoice", default_group = "System",
					force_visible = true, categories = { "System" },
				})
			end
		end
	end

	-- Scenario popup actions are nested under Scenarios -> sequences -> actions.
	-- Only ids verified in the installed English voice pack are admitted; this
	-- deliberately excludes hundreds of StoryBit-style voiced_text fields with no
	-- recording. The T id also provides a stable persistence id across sessions.
	local recorded_ids = rawget(_G, "MN_RecordedScenarioVoiceIds")
	local get_t_id = rawget(_G, "TGetID")
	local scenario_voice_count = 0
	if type(scenarios) == "table" and type(recorded_ids) == "table" and type(get_t_id) == "function" then
		for _, scenario in ipairs(scenarios) do
			if type(scenario) == "table" then
				local scenario_id = tostring(scenario.id or "Scenario")
				local mystery_number = string.match(scenario_id, "^Mystery%s+(%d+)$")
				if mystery_number then
					scenario_id = string.format("Mystery %02d", tonumber(mystery_number))
				end
				for _, sequence in ipairs(scenario) do
					if type(sequence) == "table" then
						for _, action in ipairs(sequence) do
							if type(action) == "table" then
								local voiced = action.voiced_text
								local ok, translation_id = pcall(get_t_id, voiced)
								if ok and translation_id and (recorded_ids[translation_id] == true
									or recorded_ids[tonumber(translation_id)] == true) then
									local title = action.title
									if title == nil or title == "" then title = sequence.name or scenario_id end
									local preset = {
										voiced_text = voiced,
										actor = action.actor or "narrator",
										title = title,
										text = action.text,
										group = scenario_id,
									}
									if AddEntry(tostring(translation_id), preset, {
										voiced_field = "voiced_text", actor_field = "actor",
										title_field = "title", alt_title_field = nil,
										source = "Scenario", default_group = "Scenario",
										id_prefix = "Scenario:", force_visible = true,
										categories = { "Scenario" },
									}) then
										scenario_voice_count = scenario_voice_count + 1
									end
								end
							end
						end
					end
				end
			end
		end
	end

	table.sort(entries, MN_SortEntries)
	local repeated_count = MN_MarkRepeatedEntries(entries)
	table.sort(entries, MN_SortEntries)
	MN_Catalog.entries = entries
	MN_Catalog.by_id = by_id
	MN_Catalog.built = true
	MN_Catalog.schema_version = MN_CATALOG_SCHEMA_VERSION
	MN_Catalog.config_version = MN_CurrentConfigVersion()
	MN_Catalog.scenarios_included = type(scenarios) == "table" and #scenarios > 0
	MN_Catalog.scenario_voice_count = scenario_voice_count

	MN_Debug.Info("Catalog", "Built voice-notification catalog", {
		reason = reason,
		count = #entries,
		repeated_count = repeated_count,
		spoken_text_override_count = spoken_text_override_count,
		scenario_voice_count = scenario_voice_count,
		schema_version = MN_Catalog.schema_version,
		config_version = MN_Catalog.config_version,
	})

	if MN_Config.DEBUG_CATALOG == true then
		MN_Catalog.Export("build")
	end

	return #entries
end

function MN_Catalog.IsBuilt()
	return MN_Catalog.built == true
		and type(MN_Catalog.entries) == "table"
		and MN_Catalog.schema_version == MN_CATALOG_SCHEMA_VERSION
		and MN_Catalog.config_version == MN_CurrentConfigVersion()
end

function MN_Catalog.EnsureBuilt(reason)
	if MN_Catalog.IsBuilt() and #MN_Catalog.entries > 0 then
		local scenarios = rawget(_G, "Scenarios")
		if not (type(scenarios) == "table" and #scenarios > 0 and MN_Catalog.scenarios_included ~= true) then
			return true
		end
	end
	if MN_Catalog.built == true and type(MN_Catalog.entries) == "table" and #MN_Catalog.entries > 0 then
		MN_Debug.Info("Catalog", "Rebuilding stale voice-notification catalog", {
			reason = reason,
			stored_schema_version = MN_Catalog.schema_version,
			expected_schema_version = MN_CATALOG_SCHEMA_VERSION,
			stored_config_version = MN_Catalog.config_version,
			current_config_version = MN_CurrentConfigVersion(),
		}, "DEBUG_CATALOG")
	end
	MN_Catalog.Build(reason or "ensure")
	return MN_Catalog.IsBuilt()
end

----- Mute mutation (owns the id + text-fallback bookkeeping) --------------------

-- Display/state truth for a catalog row is strictly by id, so toggling one row
-- never silently flips another row's checkbox.
function MN_Catalog.IsEntryMuted(entry)
	return entry ~= nil and MN_Persistence.IsMutedById(entry.id) == true
end

-- Keep muted_by_voice_text in sync with the id mutes: a text key is considered
-- muted iff at least one catalog entry with that voiced text is muted by id. This
-- gives the runtime text fallback coverage for same-line variants (incl. DLC/mod
-- ids) without the panel having to write the text set directly.
local function MN_RecomputeTextKey(text_key)
	if not text_key or text_key == "" then return end
	local any = false
	if type(MN_Catalog.entries) == "table" then
		for _, e in ipairs(MN_Catalog.entries) do
			if e.voiced_text_key == text_key and MN_Persistence.IsMutedById(e.id) then
				any = true
				break
			end
		end
	end
	MN_Persistence.SetMutedByText(text_key, any, { no_save = true })
end

function MN_Catalog.SetEntryMuted(entry, muted, opts)
	if not entry then return end
	muted = muted == true
	MN_Persistence.SetMutedById(entry.id, muted, { no_save = true })
	MN_RecomputeTextKey(entry.voiced_text_key)
	if not (opts and opts.no_save) then
		MN_Persistence.Save("set_entry")
	end
end

-- Apply muted=value to a list of entries, saving once at the end.
function MN_Catalog.SetEntriesMuted(list, muted, reason)
	if type(list) ~= "table" then return 0 end
	local n = 0
	for _, entry in ipairs(list) do
		if MN_Catalog.IsEntryMuted(entry) ~= (muted == true) then
			MN_Catalog.SetEntryMuted(entry, muted, { no_save = true })
			n = n + 1
		end
	end
	MN_Persistence.Save(reason or "set_entries")
	MN_Debug.Info("Catalog", "Bulk mute change", { reason = reason, changed = n, muted = muted == true }, "DEBUG_UI")
	return n
end

----- Default mutes -------------------------------------------------------------

-- Apply the default spam mutes ONCE per user (tracked by defaults_applied), only
-- to entries that exist, match a rule with mute_by_default, and are not in a
-- protected group. Respects the user's later unmutes (never re-applied).
function MN_Catalog.ApplyDefaultMutes(reason)
	if MN_Config.DEFAULT_MUTE_SPAM ~= true then
		return 0
	end
	if not MN_UserSettings then
		return 0
	end
	if MN_UserSettings.defaults_applied == true then
		MN_Debug.Info("Catalog", "Default mutes already applied; skipping", { reason = reason })
		return 0
	end
	if not MN_Catalog.EnsureBuilt(reason) then
		return 0
	end

	local applied = 0
	for _, entry in ipairs(MN_Catalog.entries) do
		local rule = MN_DefaultSpamVoiceRules[entry.default_rule or ""]
		if entry.mute_by_default and rule and rule.mute_by_default then
			if MN_UserSettings.muted_by_id[entry.id] ~= true then
				MN_Catalog.SetEntryMuted(entry, true, { no_save = true })
				applied = applied + 1
				MN_Debug.Info("Catalog", "Default-muted voice", {
					id = entry.id,
					group = entry.group,
					rule = entry.default_rule,
					matched_on = entry.default_matched_on,
					matched_value = entry.default_matched_value,
				})
			end
		end
	end

	MN_UserSettings.defaults_applied = true
	MN_Persistence.Save("apply_defaults")

	MN_Debug.Info("Catalog", "Applied default spam mutes", { reason = reason, applied = applied })
	return applied
end

----- Export --------------------------------------------------------------------

function MN_Catalog.Export(reason)
	if not MN_Catalog.EnsureBuilt(reason or "export") then
		print("[Mute Notifications][Export] Catalog unavailable.")
		return
	end
	print(string.format("[Mute Notifications][Export] Voice-notification catalog (%d entries, reason=%s):",
		#MN_Catalog.entries, tostring(reason)))
	for _, entry in ipairs(MN_Catalog.entries) do
		local muted = MN_Persistence.IsMutedById(entry.id)
			or (MN_Persistence.UseTextFallback() and MN_Persistence.IsMutedByText(entry.voiced_text_key))
		print(string.format("  [%s] id=%s muted=%s default=%s protected=%s repeated=%s repeat=%s/%s categories=%q title=%q voice=%q spoken=%q",
			tostring(entry.group), tostring(entry.id), tostring(muted == true),
			tostring(entry.mute_by_default), tostring(entry.protected),
			tostring(entry.repeated == true), tostring(entry.repeat_index or ""), tostring(entry.repeat_total or ""),
			MN_Catalog.EntryCategoryText(entry), tostring(entry.title), tostring(entry.voiced_text),
			tostring(entry.spoken_text or entry.voiced_text)))
	end
end

-- Print the current catalog as a ready-to-paste MN_CustomNames table (keyed by
-- spoken line -> current display name). Run MN_ExportCustomNames() in the console,
-- copy the output into Code/mn_custom_names.lua, edit the names, and reload.
function MN_Catalog.ExportCustomNames(reason)
	if not MN_Catalog.EnsureBuilt(reason or "export_names") then
		print("[Mute Notifications] Catalog unavailable.")
		return
	end
	print("-- Paste the block below into Code/mn_custom_names.lua and edit the values:")
	print("MN_CustomNames = {")
	for _, entry in ipairs(MN_Catalog.entries) do
		print(string.format("\t[%q] = %q,", tostring(entry.voiced_text), tostring(entry.title)))
	end
	print("}")
end

function MN_ExportCustomNames()
	MN_Catalog.ExportCustomNames("console")
end
