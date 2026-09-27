-- dam_config.lua
-- Central configuration and explicit feature/debug flags.

DAM_Config = {
	MOD_ID = "DisableAllMods",
	MOD_DISPLAY_NAME = "Disable All Mods",

	ENABLE_MOD_CONTROL = true,
	ENABLE_INSTALLED_MODS_BUTTON = true,

	-- Publication defaults: all diagnostic and operation-audit output is silent.
	DEBUG_LOGS = false,
	DEBUG_CONTROL = false,
	DEBUG_STATE = false,
	DEBUG_UI = false,

	BUTTON_ID = "idDisableAllModsPreviousToggle",
	BUTTON_DISABLE_TEXT = "Disable all mods",
	BUTTON_RESTORE_TEXT = "Reenable previous mods",
}
