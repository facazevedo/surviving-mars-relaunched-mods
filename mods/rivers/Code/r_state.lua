-- Rivers -- runtime state owned by the mod.
--
-- Loaded first so every other module can rely on Rivers.State being present.
-- The canonical mod version lives in metadata.lua ('version'); this file owns
-- runtime state only and must not duplicate version information.
--
-- Top-level state:
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
--   Rivers.State.ui_rain_label    -- panel rain label     (r_ui.lua)
--   Rivers.State.rain_visual_on   -- visual rain override active (r_rain.lua)
--   Rivers.State.budget_thread    -- game-time ticker handle (r_budget.lua)
--   Rivers.State.rebuild_queue    -- FIFO of segment ids awaiting a heavy water-grid
--                                 --   rebuild; drained up to HYDRO_MAX_REBUILDS_PER_TICK
--                                 --   per tick (r_budget.lua)
--
-- A segment record (post-Phase-1 shape):
--   {
--     -- placement / engine handles
--     water_obj         = TerrainWaterObject,
--     bbox              = box,                 -- carved bowl bbox (world units)
--     marker_x, marker_y = wu int,             -- source point
--     floor_wu          = int,                 -- bowl floor height (world units)
--     spill_wu          = int,                 -- bowl rim height (world units), == carve baseline
--     bowl_area_wu2     = int,                 -- estimated bowl floor area (world units^2)
--
--     -- water budget (driven by r_budget.lua) -- all four rates are m^3/s
--     discharge_m3s     = number,              -- player-controlled inflow (adds)
--     drainage_m3s      = number,              -- player-controlled drain (removes)
--     evaporation_m3s   = number,              -- player-controlled evaporation loss (removes)
--     infiltration_m3s  = number,              -- player-controlled infiltration loss (removes)
--     volume_m3         = number,              -- accumulating water held in basin + spill
--     actual_level_m    = number,              -- meters above floor; what the marker reflects
--     applied_level_m   = number,              -- last level (m) pushed to the engine; the
--                                              --   budget tick skips the flood-fill + grid
--                                              --   rebuild until the level drifts at least
--                                              --   HYDRO_APPLY_STEP_M from this (perf gate)
--     rebuild_queued    = bool,                -- true while this segment sits in the
--                                              --   rebuild_queue (prevents double-enqueue)
--
--     -- flood-fill cache (set by r_flood.lua each tick)
--     flooded_tile_count = int,
--     flooded_area_wu2   = int,
--     surface_area_wu2   = int,                -- equals flooded_area_wu2 for Phase 1
--   }

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
