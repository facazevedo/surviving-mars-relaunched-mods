-- MartianWaters -- shipped TextStyle presets.
--
-- The panel's unit symbols (m^3 / m^2) use a Unicode superscript glyph, whose
-- size is fixed by the body font (SchemeBk-Regular @ 18, as InfopanelTextR), so
-- it renders quite small. To show a LARGER superscript we register one extra
-- TextStyle here -- same font family as the body text, just a bigger size -- and
-- wrap only the superscript digit in it via an XText "<style ...>" tag (see
-- mw_ui.lua update_readouts). The superscript Unicode glyph is already raised, so
-- rendering it in a bigger font yields a bigger *raised* glyph.
--
-- Why this is safe (and why an earlier runtime TextStyle attempt failed):
--   * TextStyle is a Preset with GlobalMap = "TextStyles"; PlaceObj() runs
--     obj:Register() (CommonLua/Preset.lua), which inserts it into the global
--     TextStyles[id] map immediately -- so a load-time registration is valid.
--   * GetFontIdHeightBaseline only WARNS (returns -1) on an unknown font; it does
--     not crash. The earlier crash came from naming a font that was never loaded.
--     Here we reuse SchemeBk-Regular, which the stock InfopanelTextR style already
--     loads, so the font id resolves.
--
-- This file must load before mw_ui.lua builds the panel (it is ordered early in
-- metadata.lua / items.lua). Guarded so it is a no-op if the API is unavailable.

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Init"

-- The id used by "<style ...>" runs. We TRY to register a custom SchemeBk-Regular
-- style at a bigger size; if that registration doesn't actually land in the global
-- TextStyles map (mod-load timing/sandbox can prevent it), we fall back to a stock
-- style that is GUARANTEED registered. "<style X>" with an unknown X silently
-- renders tiny in this (asserts-disabled) build -- which is what was happening --
-- so the fallback is what makes the bigger superscript reliable.
--
-- Stock fallback: "EditControl" = SchemeBk-Regular @ 22 (same font as the body @
-- 18), off-white TextColor 4294966511. A moderate bump that fits the row without
-- clipping; the custom style below tries SchemeBk @ 24 for a touch more.
local STOCK_FALLBACK = "EditControl"
local CUSTOM_ID = "MartianWatersSup"
MartianWaters.SUPERSCRIPT_STYLE = STOCK_FALLBACK

local place = rawget(_G, "PlaceObj")
local rgb = rawget(_G, "RGB")

local function text_styles()
	return rawget(_G, "TextStyles")
end

-- (Re)register the custom style every load. We do NOT skip when it already
-- exists: PlaceObj overwrites the existing preset, so edits here (size/colour)
-- actually take effect on a mod reload instead of being stuck on a stale version.
if type(place) == "function" then
	pcall(function()
		place('TextStyle', {
			FontName = "SchemeBk-Regular",
			FontSize = 11,   -- ~60% of the 18px main text (proper superscript size)
			-- Match InfopanelTextR's exact colour (4294966511 = warm near-white,
			-- RGB 255,252,239) so the digit is the SAME colour as the labels. The
			-- control-level TextColor override doesn't apply to these XText runs,
			-- so the style's own colour must match.
			TextColor = 4294966511,
			RolloverTextColor = 4294966511,
			group = "GameR",
			id = CUSTOM_ID,
		})
	end)
end

-- Use the custom style only if it really registered; otherwise keep the stock one.
local ts = text_styles()
if type(ts) == "table" and ts[CUSTOM_ID] then
	MartianWaters.SUPERSCRIPT_STYLE = CUSTOM_ID
	DebugLog.Info(SCOPE, "using custom superscript TextStyle", { id = CUSTOM_ID, size = 11 })
else
	local have_fallback = type(ts) == "table" and ts[STOCK_FALLBACK] ~= nil
	DebugLog.Warn(SCOPE, "custom superscript style did not register; using stock fallback", {
		fallback = STOCK_FALLBACK, fallback_present = have_fallback,
	})
end
