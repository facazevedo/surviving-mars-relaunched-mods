-- mn_persistence.lua
-- Owns the persistent user settings (which voices are muted). Backed by the
-- per-mod persistent storage that the game provides to a mod's environment:
--   CurrentModStorageTable        - a table auto-loaded from per-mod storage
--   WriteModPersistentStorageTable() - serializes that table back to disk
-- (see ModDef:SetupEnv in CommonLua/Classes/Mod.lua). These live in the mod env,
-- not in _G; we read them with rawget(_G, ...) so a missing helper degrades to an
-- in-memory table instead of raising the "undefined global" sandbox assert.

MN_Persistence = {}

-- Created as a real global here (plain write; the mod sandbox forbids READING an
-- as-yet-undefined global, so never reference MN_UserSettings before this line).
MN_UserSettings = false

local SETTINGS_SCHEMA = 1

local function MN_StorageTable()
	-- env._G == env, and safe rawget falls through to the env value.
	return rawget(_G, "CurrentModStorageTable")
end

local function MN_StorageWriter()
	return rawget(_G, "WriteModPersistentStorageTable")
end

function MN_Persistence.IsAvailable()
	return type(MN_StorageTable()) == "table" and type(MN_StorageWriter()) == "function"
end

-- Ensure the settings table exists and has every expected sub-field. Returns the
-- table (the persistent one when available, otherwise a private in-memory one).
function MN_Persistence.Load()
	local store = MN_StorageTable()
	if type(store) ~= "table" then
		store = MN_UserSettings == false and {} or MN_UserSettings
		MN_Debug.Warn("Persistence", "Per-mod storage unavailable; settings will not persist", nil)
	end

	store.schema = store.schema or SETTINGS_SCHEMA
	store.muted_by_id = store.muted_by_id or {}
	store.muted_by_voice_text = store.muted_by_voice_text or {}
	if store.use_text_fallback == nil then
		store.use_text_fallback = MN_Config.USE_TEXT_FALLBACK == true
	end
	if store.defaults_applied == nil then
		store.defaults_applied = false
	end

	MN_UserSettings = store

	MN_Debug.Info("Persistence", "Loaded user settings", {
		available = MN_Persistence.IsAvailable(),
		muted_ids = MN_Persistence.CountKeys(store.muted_by_id),
		muted_texts = MN_Persistence.CountKeys(store.muted_by_voice_text),
		defaults_applied = store.defaults_applied,
		use_text_fallback = store.use_text_fallback,
	}, "DEBUG_PERSISTENCE")

	return store
end

function MN_Persistence.CountKeys(t)
	local n = 0
	if type(t) == "table" then
		for _ in pairs(t) do n = n + 1 end
	end
	return n
end

-- Persist current settings. Safe to call often; the engine debounces the disk
-- write. Wrapped in pcall so a serialization failure cannot break gameplay.
function MN_Persistence.Save(reason)
	local writer = MN_StorageWriter()
	if type(writer) ~= "function" then
		MN_Debug.Warn("Persistence", "Save skipped: storage writer unavailable", { reason = reason }, "DEBUG_PERSISTENCE")
		return false
	end
	local ok, err = pcall(writer)
	if ok ~= true then
		MN_Debug.Error("Persistence", "Save failed", { reason = reason, error = err })
		return false
	end
	MN_Debug.Info("Persistence", "Saved user settings", { reason = reason }, "DEBUG_PERSISTENCE")
	return true
end

----- Accessors -----------------------------------------------------------------

function MN_Persistence.IsMutedById(id)
	if not id then return false end
	return MN_UserSettings and MN_UserSettings.muted_by_id[id] == true
end

function MN_Persistence.IsMutedByText(text_key)
	if not text_key or text_key == "" then return false end
	return MN_UserSettings and MN_UserSettings.muted_by_voice_text[text_key] == true
end

function MN_Persistence.UseTextFallback()
	if not MN_UserSettings then return MN_Config.USE_TEXT_FALLBACK == true end
	return MN_UserSettings.use_text_fallback == true
end

function MN_Persistence.SetMutedById(id, muted, opts)
	if not id then return end
	MN_UserSettings.muted_by_id[id] = muted == true or nil
	if not (opts and opts.no_save) then
		MN_Persistence.Save("set_id")
	end
end

function MN_Persistence.SetMutedByText(text_key, muted, opts)
	if not text_key or text_key == "" then return end
	MN_UserSettings.muted_by_voice_text[text_key] = muted == true or nil
	if not (opts and opts.no_save) then
		MN_Persistence.Save("set_text")
	end
end

function MN_Persistence.ResetAll(opts)
	opts = opts or {}
	MN_UserSettings.muted_by_id = {}
	MN_UserSettings.muted_by_voice_text = {}
	if opts.defaults_applied ~= nil then
		MN_UserSettings.defaults_applied = opts.defaults_applied == true
	else
		MN_UserSettings.defaults_applied = false
	end
	if not opts.no_save then
		MN_Persistence.Save("reset_all")
	end
end
