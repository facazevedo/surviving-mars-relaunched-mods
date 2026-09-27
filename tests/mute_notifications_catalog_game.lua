-- Run with Mute Notifications loaded in a disposable MarsDebug session.
-- Use real localization userdata to exercise the Steam release representation.
local translated, percentages, names = 0, 0, 0
for id, text in pairs(TranslationTable) do
    if type(id) == "number" and type(text) == "string" then
        local percent = text:find("<percentWithSign(reg_param1)>", 1, true)
        local name = text:find("<ColonistName", 1, true)
        if percent or name then
            local value = LocIdToLightUserdata(id)
            assert(type(value) == "userdata", "release representation unavailable")
            assert(MN_Catalog.Translate(value) == text, "localized template altered: " .. id)
            translated = translated + 1
            percentages = percentages + (percent and 1 or 0)
            names = names + (name and 1 or 0)
        end
    end
end
assert(percentages > 0 and names > 0, "regression templates missing")

-- Debug presets contain T tables. Convert only catalog inputs to their real
-- release representation for a full build without changing engine presets.
local original_translate = MN_Catalog.Translate
MN_Catalog.Translate = function(value)
    local id = TGetID(value)
    if id and TranslationTable[id] then value = LocIdToLightUserdata(id) end
    return original_translate(value)
end
local ok, err = pcall(MN_Catalog.Build, "release_userdata_regression")
MN_Catalog.Translate = original_translate
assert(ok, err)
assert(MN_Catalog.built and #MN_Catalog.entries > 0, "catalog did not build")
return string.format("PASS: %d release templates (%d percentage, %d colonist); %d catalog entries",
    translated, percentages, names, #MN_Catalog.entries)
