-- MuteNotifications.lua
-- Main entry point: version stamp, high-level lifecycle, and message wiring only.
-- Feature logic lives in the mn_* modules (config/debug/persistence/catalog/
-- voice_suppression/panel/audio_options_patch).

MN_Lifecycle = {
	booted = false,        -- load-time init done (persistence + suppression)
	classes_ready = false, -- catalog + audio patch done
	shutting_down = false,
}

local function MN_Try(label, fn, reason)
	local ok, result = pcall(fn, reason)
	if ok ~= true then
		MN_Debug.Error("Lifecycle", "Step failed: " .. tostring(label), { reason = reason, error = result })
		return false
	end
	if result == false then
		MN_Debug.Warn("Lifecycle", "Step reported incomplete cleanup: " .. tostring(label), { reason = reason })
		return false
	end
	return true
end

-- Load-time boot: only touches things that exist as soon as mod code runs
-- (per-mod storage + the global voice functions).
function MN_Lifecycle.Boot(reason)
	if MN_Lifecycle.booted == true then
		-- Revalidate the configured state after save/load or a manual lifecycle call.
		if MN_Config.ENABLE_MOD == true then
			MN_Try("suppression_reapply", MN_VoiceSuppression.Apply, reason)
		else
			MN_Try("suppression_restore", MN_VoiceSuppression.Restore, reason)
		end
		return
	end

	MN_Debug.Info("Lifecycle", "Mute Notifications loading", {
		version = MN_Config.VERSION,
		reason = reason,
		enable_mod = MN_Config.ENABLE_MOD,
		patch_audio_options = MN_Config.PATCH_AUDIO_OPTIONS,
		use_text_fallback = MN_Config.USE_TEXT_FALLBACK,
		default_mute_spam = MN_Config.DEFAULT_MUTE_SPAM,
	})

	MN_Try("persistence_load", MN_Persistence.Load, reason)
	if MN_Config.ENABLE_MOD == true then
		MN_Try("suppression_apply", MN_VoiceSuppression.Apply, reason)
	else
		MN_Try("suppression_restore", MN_VoiceSuppression.Restore, reason)
	end

	MN_Lifecycle.booted = true
end

-- After classes & presets are built: discover voices, apply default mutes once,
-- and patch the Audio options page.
function MN_Lifecycle.OnClassesReady(reason)
	MN_Lifecycle.Boot(reason)
	if MN_Config.ENABLE_MOD ~= true then
		MN_Try("audio_restore", MN_AudioPatch.Restore, reason)
		MN_Lifecycle.classes_ready = false
		return
	end

	MN_Try("catalog_build", function(r) MN_Catalog.Build(r) end, reason)
	MN_Try("apply_defaults", function(r) MN_Catalog.ApplyDefaultMutes(r) end, reason)
	MN_Try("audio_patch", function(r) MN_AudioPatch.Apply(r) end, reason)

	MN_Lifecycle.classes_ready = true
end

-- Idempotently undo every runtime mutation. Persistent settings are cleared only
-- for a verified uninstall, not when the player temporarily disables the mod.
function MN_Lifecycle.Shutdown(reason, clear_persistent_state)
	if MN_Lifecycle.shutting_down == true then
		return true
	end
	MN_Lifecycle.shutting_down = true
	local restored = true

	if MN_Panel.IsOpen() then
		restored = MN_Try("panel_close", MN_Panel.Close, reason) and restored
	end
	restored = MN_Try("suppression_restore", MN_VoiceSuppression.Restore, reason) and restored
	restored = MN_Try("audio_restore", MN_AudioPatch.Restore, reason) and restored
	if clear_persistent_state == true then
		restored = MN_Try("persistence_clear", MN_Persistence.ClearAll, reason) and restored
	end

	MN_Lifecycle.booted = false
	MN_Lifecycle.classes_ready = false
	MN_Lifecycle.shutting_down = false
	return restored
end

-- CurrentModPath is provided by ModDef:SetupEnv. The official uninstall flows
-- remove that path before ModUnloadLua/OnGedUnloadMod; a normal disable leaves it
-- present. If availability cannot be verified, preserve settings to avoid data loss.
local function MN_ModFilesAreGone()
	local current_path = rawget(_G, "CurrentModPath")
	local io_api = rawget(_G, "io")
	if type(current_path) ~= "string" or current_path == ""
		or type(io_api) ~= "table" or type(io_api.exists) ~= "function" then
		return false
	end
	return io_api.exists(current_path) ~= true
end

-- Manual lifecycle (for console / debugging). Suppression intentionally stays
-- active in menus and in-game; Disable fully restores vanilla voice behaviour.
function MN_Enable(reason)
	MN_Config.ENABLE_MOD = true
	MN_Lifecycle.booted = false
	MN_Lifecycle.OnClassesReady(reason or "manual_enable")
	return true
end

function MN_Disable(reason)
	MN_Config.ENABLE_MOD = false
	return MN_Lifecycle.Shutdown(reason or "manual_disable", false)
end

----- Boot now and on the relevant engine messages ------------------------------

MN_Lifecycle.Boot("code_load")

function OnMsg.ClassesBuilt()
	MN_Lifecycle.OnClassesReady("ClassesBuilt")
end

-- Scenarios is populated by the game's DataLoaded handlers. Rebuild here so the
-- verified scenario voices are already present when Audio options first opens.
function OnMsg.DataLoaded()
	MN_Lifecycle.OnClassesReady("DataLoaded")
end

function OnMsg.CityStart()
	MN_Lifecycle.OnClassesReady("CityStart")
end

function OnMsg.LoadGame()
	MN_Lifecycle.OnClassesReady("LoadGame")
end

-- Close the panel on map teardown so no stale window survives a transition.
function OnMsg.ChangeMap()
	if MN_Panel.IsOpen() then
		MN_Panel.Close("ChangeMap")
	end
end

function OnMsg.DoneGame()
	if MN_Panel.IsOpen() then
		MN_Panel.Close("DoneGame")
	end
end

-- Official engine callback fired immediately before an enabled Lua mod is
-- unloaded. Runtime behavior is always restored; settings are cleared only when
-- the content path is already gone, which identifies an actual uninstall.
function OnMsg.ModUnloadLua(mod_id)
	if mod_id ~= MN_Config.MOD_ID then return end
	local uninstalling = MN_ModFilesAreGone()
	MN_Lifecycle.Shutdown(uninstalling and "ModUnloadLua_uninstall" or "ModUnloadLua_disable", uninstalling)
end

-- The local Mod Editor delete flow removes the mod from ModsLoaded before the
-- normal ModUnloadLua pass, but emits this verified callback after deleting the
-- files. Use the same guarded cleanup path.
function OnMsg.OnGedUnloadMod(mod_id)
	if mod_id ~= MN_Config.MOD_ID then return end
	local uninstalling = MN_ModFilesAreGone()
	MN_Lifecycle.Shutdown(uninstalling and "OnGedUnloadMod_delete" or "OnGedUnloadMod_disable", uninstalling)
end
