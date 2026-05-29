-- MartianWaters -- a shipped TextStyle for the unit superscripts.
--
-- The panel's unit symbols (m^3 / m^2) use a Unicode superscript glyph. To control
-- its size/colour we register one TextStyle (SchemeBk-Regular -- the body font --
-- at ~60% size and the labels' colour) and wrap the digit in it via "<style ...>".
-- If registration doesn't land (mod-load timing), we fall back to a stock style
-- that is guaranteed present: an unknown "<style X>" renders tiny in this
-- asserts-disabled build, so the fallback keeps it sane.
-- Loaded before mw_ui.lua builds the panel (ordered early in metadata/items).

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	return
end

local DebugLog = MartianWaters.DebugLog or { Info = function() end, Warn = function() end, Error = function() end }
local SCOPE = "Init"

local STOCK_FALLBACK = "EditControl"   -- SchemeBk-Regular @ 22, registered by the game
local CUSTOM_ID = "MartianWatersSup"
MartianWaters.SUPERSCRIPT_STYLE = STOCK_FALLBACK

-- (Re)register every load so edits here take effect -- PlaceObj overwrites an
-- existing preset, otherwise a stale version would stick across reloads.
local place = rawget(_G, "PlaceObj")
if type(place) == "function" then
	pcall(function()
		place('TextStyle', {
			FontName = "SchemeBk-Regular",
			FontSize = 11,                  -- ~60% of the 18px body text
			TextColor = 4294966511,         -- InfopanelTextR's colour, to match the labels
			RolloverTextColor = 4294966511,
			group = "GameR",
			id = CUSTOM_ID,
		})
	end)
end

-- Prefer the custom style only if it actually registered into the global map.
local ts = rawget(_G, "TextStyles")
if type(ts) == "table" and ts[CUSTOM_ID] then
	MartianWaters.SUPERSCRIPT_STYLE = CUSTOM_ID
	DebugLog.Info(SCOPE, "superscript TextStyle registered", { id = CUSTOM_ID })
else
	DebugLog.Warn(SCOPE, "custom superscript style not registered; using stock fallback", {
		fallback = STOCK_FALLBACK,
	})
end
