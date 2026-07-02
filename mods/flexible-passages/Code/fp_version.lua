-- Flexible Passages -- canonical runtime version information.

local FlexiblePassages = rawget(_G, "FlexiblePassages")
if type(FlexiblePassages) ~= "table" then
	FlexiblePassages = {}
	rawset(_G, "FlexiblePassages", FlexiblePassages)
end

FlexiblePassages.Version = {
	MOD_ID = "FlexiblePassages",
	MOD_TITLE = "Flexible Passages",
	MOD_FOLDER = "flexible-passages",
	METADATA_VERSION = 4,
	VERSION_TEXT = "1.0.3",
}
