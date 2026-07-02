-- MuteNotifications.lua
-- Main entry point: version stamp, high-level lifecycle, and message wiring only.
-- Feature logic lives in the mn_* modules (config/debug/persistence/catalog/
-- voice_suppression/panel/audio_options_patch).

MN_Lifecycle = {
	booted = false,        -- load-time init done (persistence + suppression)
	classes_ready = false, -- catalog + audio patch done
}

local function MN_Try(label, fn, reason)
	local ok, err = pcall(fn, reason)
	if ok ~= true then
		MN_Debug.Error("Lifecycle", "Step failed: " .. tostring(label), { reason = reason, error = err })
		return false
	end
	return true
end

-- Load-time boot: only touches things that exist as soon as mod code runs
-- (per-mod storage + the global voice functions).
function MN_Lifecycle.Boot(reason)
	if MN_Lifecycle.booted == true then
		-- Make sure suppression is active (e.g. after a save/load cycle).
		MN_Try("suppression_reapply", MN_VoiceSuppression.Apply, reason)
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
	MN_Try("suppression_apply", MN_VoiceSuppression.Apply, reason)

	MN_Lifecycle.booted = true
end

-- After classes & presets are built: discover voices, apply default mutes once,
-- and patch the Audio options page.
function MN_Lifecycle.OnClassesReady(reason)
	MN_Lifecycle.Boot(reason)

	MN_Try("catalog_build", function(r) MN_Catalog.Build(r) end, reason)
	MN_Try("apply_defaults", function(r) MN_Catalog.ApplyDefaultMutes(r) end, reason)
	MN_Try("audio_patch", function(r) MN_AudioPatch.Apply(r) end, reason)

	MN_Lifecycle.classes_ready = true
end

-- Manual lifecycle (for console / debugging). Suppression intentionally stays
-- active in menus and in-game; Disable fully restores vanilla voice behaviour.
function MN_Enable(reason)
	MN_Config.ENABLE_MOD = true
	MN_VoiceSuppression.Apply(reason or "manual_enable")
	return true
end

function MN_Disable(reason)
	MN_VoiceSuppression.Restore(reason or "manual_disable")
	if MN_Panel.IsOpen() then MN_Panel.Close(reason or "manual_disable") end
	return true
end

----- Boot now and on the relevant engine messages ------------------------------

MN_Lifecycle.Boot("code_load")

function OnMsg.ClassesBuilt()
	MN_Lifecycle.OnClassesReady("ClassesBuilt")
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
