-- Rivers -- runtime state owned by the mod.
--
-- Loaded first so every other module can rely on Rivers.State being present.
-- The canonical mod version lives in metadata.lua ('version'); this file owns
-- runtime state only and must not duplicate version information.
--
-- State shape:
--   Rivers.State.segments         -- segment_id (string) -> segment record
--   Rivers.State.next_id          -- monotonic counter feeding segment ids
--   Rivers.State.enabled          -- lifecycle flag (false until Enable())
--   Rivers.State.tool_active      -- water-tool overlay attached (r_tool.lua)
--   Rivers.State.tool_overlay     -- overlay XWindow handle (r_tool.lua)
--   Rivers.State.current_marker   -- TerrainWaterObject targeted by +/-
--   Rivers.State.current_marker_segment -- segment id matching current_marker
--   Rivers.State.ui_panel         -- right-side panel handle (r_ui.lua)
--   Rivers.State.ui_toggle_button -- panel button handle  (r_ui.lua)
--   Rivers.State.ui_level_label   -- panel label handle   (r_ui.lua)
--
-- A segment record:
--   { water_obj = obj, bbox = box, floor_wu = int,
--     marker_x = int, marker_y = int, water_level_m = number }

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	Rivers = {}
	rawset(_G, "Rivers", Rivers)
end

Rivers.State = Rivers.State or {
	segments = {},
	next_id = 1,
	enabled = false,
}

-- Mint a fresh segment id and register the segment record. Both the batch
-- carve API (r_api.lua) and the click tool (r_tool.lua) call this, so the id
-- namespace and segment-table shape stay in one place.
function Rivers.State:RegisterSegment(seg)
	local id = "rv_" .. tostring(self.next_id)
	self.next_id = self.next_id + 1
	self.segments[id] = seg
	return id
end
