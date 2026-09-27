-- DisableAllMods.lua
-- Main entry: startup diagnostics and lifecycle wiring only.

DAM_Main = {}

function DAM_Main.Initialize()
	DAM_Debug.Info("Init", "Disable All Mods loaded", {
		debug_control = DAM_Config.DEBUG_CONTROL,
		debug_logs = DAM_Config.DEBUG_LOGS,
		debug_state = DAM_Config.DEBUG_STATE,
		debug_ui = DAM_Config.DEBUG_UI,
		restore_available = DAM_State.HasPreviousLoadOrder(),
		version = CurrentModDef and CurrentModDef.version or "unknown",
	}, "DEBUG_LOGS")

	DAM_ModControl.ValidateRuntime()
	DAM_Lifecycle.ApplyModBehavior()
end

DAM_Main.Initialize()
