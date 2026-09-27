-- Standalone regression for release-build localized userdata. No game files changed.
local checks = 0
local function expect(value, message)
    checks = checks + 1
    assert(value, message)
end
local env = setmetatable({}, { __index = _G })
env._G = env
local logs, calls = {}, 0
env.print = function(message) logs[#logs + 1] = message end
assert(loadfile("mods/mute-notifications/Code/mn_config.lua", "t", env))()
assert(loadfile("mods/mute-notifications/Code/mn_debug.lua", "t", env))()
-- Lua's file userdata stands in for an engine localization handle; the ID API
-- determines its meaning. Any call to the formatter for this handle is a defect.
local handle = io.stdout
env.TGetID = function(value) return value == handle and 42 or false end
local template = "<ColonistName(colonist)>: <percentWithSign(reg_param1)> power"
env.TranslationTable = { [42] = template }
env._InternalTranslate = function(value, context, check, tags_off)
    calls = calls + 1
    assert(type(value) ~= "userdata", "release userdata reached the tag formatter")
    assert(context == false and check == false and tags_off == true)
    return value.text
end
assert(loadfile("mods/mute-notifications/Code/mn_catalog.lua", "t", env))()
local c = env.MN_Catalog
expect(c.Translate(handle) == template, "release catalog preserves literal context tags")
expect(calls == 0, "release text bypasses formatter entirely")
expect(c.VoiceTextKey(handle) == template:lower(), "voice keys retain existing normalization")
env.TranslationTable[42] = "Texte localise"
expect(c.Translate(handle) == "Texte localise", "uses current language rather than English fallback")
expect(c.Translate({ text = "Table <tag>" }) == "Table <tag>", "debug table translation stays tag-free")
expect(c.Translate("plain") == "plain" and c.Translate(nil) == "" and c.Translate(false) == "", "plain and empty text unchanged")
local before = calls
env.TranslationTable[42] = nil
expect(c.Translate(handle) == "" and calls == before, "missing templates never enter unsafe formatter")
expect(#logs == 0, "diagnostics disabled by default")
env.MN_Config.DEBUG = "true"
c.Translate(handle)
expect(#logs == 0, "string debug flag does not enable diagnostics")
env.MN_Config.DEBUG = true
c.Translate(handle)
expect(#logs == 1 and logs[1]:find("translation_id=42", 1, true), "missing template diagnosis includes ID")
env.TGetID = nil
expect(c.Translate(handle) == "", "missing ID API handled without translation")
env.TGetID = function() return 42 end
env.TranslationTable = nil
expect(c.Translate(handle) == "", "missing translation table handled without translation")
print("PASS: " .. checks .. " Mute Notifications catalog checks")
