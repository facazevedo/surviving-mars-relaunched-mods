-- mn_voice_suppression.lua
-- Suppresses ONLY the voice component of muted notifications, leaving the visual
-- notification (and all other audio) untouched.
--
-- How notification voices flow in the engine (verified from game source):
--   OnMsg.AddNotification -> QueueVoice(nil, voiced_text, actor, unique, cooldown,
--       should_play_fn, notification)   [CommonLua/Libs/Notifications/NotificationUI.lua]
--   the VoiceQueue thread later calls PlayVoicedText(voiced_text, actor, cb)
--                                       [CommonLua/Voice.lua]
--
-- We wrap the GLOBAL QueueVoice (primary, id-aware: the notification preset is the
-- trailing argument) and the GLOBAL PlayVoicedText (secondary, text-only: catches
-- directly-played voices such as hints/votes when the user muted that exact line).
-- Assigning a global from mod code writes through to real _G (ModEnvMeta.__newindex
-- -> rawset(original_G,...)), so these wraps take effect engine-wide and are fully
-- reversible. Originals are stored so vanilla behaviour is restored on disable.

MN_VoiceSuppression = {
	applied = false,
	active = false,           -- gates suppression without unwrapping
	orig_QueueVoice = false,
	orig_PlayVoicedText = false,
}

local IsKindOf = rawget(_G, "IsKindOf")

local function MN_IsNotification(obj)
	return type(obj) == "table" and type(IsKindOf) == "function" and IsKindOf(obj, "NotificationPreset")
end

-- Decide whether a voice should be suppressed. pid may be nil (no notification).
-- text_key is lazily computed by the caller only when needed.
function MN_VoiceSuppression.ShouldSuppress(pid, text_key)
	if MN_VoiceSuppression.active ~= true or MN_Config.ENABLE_MOD ~= true then
		return false
	end
	if pid and MN_Persistence.IsMutedById(pid) then
		return true, "id", pid
	end
	if MN_Persistence.UseTextFallback() and text_key and text_key ~= "" then
		if MN_Persistence.IsMutedByText(text_key) then
			return true, "text", text_key
		end
	end
	return false
end

local function MN_LogDecision(scope, suppressed, reason, pid, text_key)
	if MN_Config.DEBUG_SUPPRESSION ~= true then return end
	MN_Debug.Info("Suppression", suppressed and "Voice suppressed" or "Voice allowed", {
		hook = scope,
		reason = reason,
		id = pid,
		text = text_key,
	}, "DEBUG_SUPPRESSION")
end

-- QueueVoice(id, voiced_text, actor, unique, voice_cooldown, should_play, ...)
local function MN_QueueVoiceWrapper(id, voiced_text, actor, unique, voice_cooldown, should_play, ...)
	local orig = MN_VoiceSuppression.orig_QueueVoice
	local ok, notif_or_err = pcall(function(...)
		local notification = ...
		local pid = MN_IsNotification(notification) and notification.id or nil
		local text_key
		-- Only translate (cost) when a text-fallback decision is possible.
		if not (pid and MN_Persistence.IsMutedById(pid)) and MN_Persistence.UseTextFallback() then
			text_key = MN_Catalog.VoiceTextKey(voiced_text)
		end
		local suppress, reason = MN_VoiceSuppression.ShouldSuppress(pid, text_key)
		MN_LogDecision("QueueVoice", suppress == true, reason, pid, text_key)
		return suppress == true
	end, ...)

	if ok and notif_or_err == true then
		-- Suppress only the voice: do not enqueue. Visual notification is created
		-- independently by the notification system and is unaffected.
		return
	end
	if ok ~= true then
		-- Never let suppression break notifications: fall back to vanilla.
		MN_Debug.Error("Suppression", "QueueVoice wrapper error; passing through", { error = notif_or_err })
	end
	return orig(id, voiced_text, actor, unique, voice_cooldown, should_play, ...)
end

-- PlayVoicedText(voiced_text, actor, callback)
local function MN_PlayVoicedTextWrapper(voiced_text, actor, callback)
	local orig = MN_VoiceSuppression.orig_PlayVoicedText
	local suppress = false
	local ok, err = pcall(function()
		if not MN_Persistence.UseTextFallback() then return end
		local text_key = MN_Catalog.VoiceTextKey(voiced_text)
		local s, reason = MN_VoiceSuppression.ShouldSuppress(nil, text_key)
		if s then
			MN_LogDecision("PlayVoicedText", true, reason, nil, text_key)
			suppress = true
		end
	end)
	if ok and suppress then
		return
	end
	if ok ~= true then
		MN_Debug.Error("Suppression", "PlayVoicedText wrapper error; passing through", { error = err })
	end
	return orig(voiced_text, actor, callback)
end

----- Lifecycle -----------------------------------------------------------------

function MN_VoiceSuppression.Apply(reason)
	if MN_VoiceSuppression.applied ~= true then
		local qv = rawget(_G, "QueueVoice")
		local pvt = rawget(_G, "PlayVoicedText")
		if type(qv) ~= "function" or type(pvt) ~= "function" then
			MN_Debug.Error("Suppression", "Voice globals unavailable; cannot apply", {
				reason = reason,
				has_QueueVoice = type(qv) == "function",
				has_PlayVoicedText = type(pvt) == "function",
			})
			return false
		end
		MN_VoiceSuppression.orig_QueueVoice = qv
		MN_VoiceSuppression.orig_PlayVoicedText = pvt
		QueueVoice = MN_QueueVoiceWrapper
		PlayVoicedText = MN_PlayVoicedTextWrapper
		MN_VoiceSuppression.applied = true
		MN_Debug.Info("Suppression", "Voice wrappers installed", { reason = reason })
	end
	MN_VoiceSuppression.active = true
	return true
end

function MN_VoiceSuppression.Restore(reason)
	-- Keep the wrappers but go dormant (active=false) so behaviour is vanilla.
	-- Only fully unwrap when no other code replaced our wrapper in the meantime.
	MN_VoiceSuppression.active = false
	if MN_VoiceSuppression.applied == true then
		local current_queue = rawget(_G, "QueueVoice")
		local current_play = rawget(_G, "PlayVoicedText")
		local queue_owned = current_queue == MN_QueueVoiceWrapper
			or current_queue == MN_VoiceSuppression.orig_QueueVoice
		local play_owned = current_play == MN_PlayVoicedTextWrapper
			or current_play == MN_VoiceSuppression.orig_PlayVoicedText
		local can_fully_unwrap = queue_owned and play_owned
		if can_fully_unwrap then
			if current_queue == MN_QueueVoiceWrapper then
				QueueVoice = MN_VoiceSuppression.orig_QueueVoice
			end
			if current_play == MN_PlayVoicedTextWrapper then
				PlayVoicedText = MN_VoiceSuppression.orig_PlayVoicedText
			end
			MN_VoiceSuppression.orig_QueueVoice = false
			MN_VoiceSuppression.orig_PlayVoicedText = false
			MN_VoiceSuppression.applied = false
		else
			-- Restore atomically. If either function has a later owner, leave both
			-- dormant wrappers and original references intact until the engine reload.
			MN_Debug.Warn("Suppression", "Restore deferred for functions owned by a later wrapper", {
				queue_owned = queue_owned,
				play_owned = play_owned,
			}, "DEBUG_SUPPRESSION")
		end
		MN_Debug.Info("Suppression", "Voice wrappers set to vanilla behavior", {
			reason = reason,
			fully_unwrapped = can_fully_unwrap,
		})
		return can_fully_unwrap
	end
	MN_Debug.Info("Suppression", "Voice wrappers already restored to vanilla", { reason = reason })
	return true
end

-- Play a voiced line on demand for the panel preview button, ALWAYS audible
-- (uses the stored original so muting never silences the preview). The engine
-- voices notifications WITH an actor (QueueVoice) but popups/hints WITHOUT one
-- (a bare PlayVoicedText), so the caller passes actor=nil for those; do NOT
-- substitute a default actor here or the voice file lookup can miss.
function MN_VoiceSuppression.PlayPreview(voiced_text, actor)
	local fn = MN_VoiceSuppression.orig_PlayVoicedText
	if type(fn) ~= "function" then
		fn = rawget(_G, "PlayVoicedText")
	end
	if type(fn) ~= "function" then
		MN_Debug.Warn("Suppression", "PlayVoicedText unavailable for preview", nil)
		return false
	end
	local ok, err = pcall(fn, voiced_text, actor)
	if ok ~= true then
		MN_Debug.Error("Suppression", "Preview playback failed", { error = err })
		return false
	end
	return true
end
