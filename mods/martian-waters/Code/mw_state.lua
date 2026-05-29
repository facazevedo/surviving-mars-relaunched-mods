-- MartianWaters -- runtime state owned by the mod.
--
-- Loaded first so every other module can rely on MartianWaters.State being present.
-- The canonical mod version lives in metadata.lua ('version'); this file owns
-- runtime state only and must not duplicate version information.
--
-- Top-level state:
--   MartianWaters.State.segments         -- segment_id (string) -> segment record
--   MartianWaters.State.next_id          -- monotonic counter feeding segment ids
--   MartianWaters.State.enabled          -- lifecycle flag (false until Enable())
--   MartianWaters.State.tool_active      -- water-tool overlay attached (mw_tool.lua)
--   MartianWaters.State.tool_overlay     -- overlay XWindow handle (mw_tool.lua)
--   MartianWaters.State.current_marker   -- TerrainWaterObject targeted by +/-
--   MartianWaters.State.current_marker_segment -- segment id matching current_marker
--   MartianWaters.State.ui_panel         -- right-side panel handle (mw_ui.lua)
--   MartianWaters.State.ui_toggle_button -- panel button handle  (mw_ui.lua)
--   MartianWaters.State.ui_level_label   -- panel label handle   (mw_ui.lua)
--   MartianWaters.State.ui_rain_label    -- panel rain label     (mw_ui.lua)
--   MartianWaters.State.rain_visual_on   -- visual rain override active (mw_rain.lua)
--   MartianWaters.State.budget_thread    -- game-time ticker handle (mw_budget.lua)
--   MartianWaters.State.rebuild_queue    -- FIFO of segment ids awaiting a heavy water-grid
--                                 --   rebuild; drained up to HYDRO_MAX_REBUILDS_PER_TICK
--                                 --   per tick (mw_budget.lua)
--
-- A segment record (post-Phase-1 shape):
--   {
--     is_sea            = bool,                -- true for a whole-map sea (mw_sea.lua):
--                                              --   engine-managed, skipped by the budget
--                                              --   tick, level changed via MartianWaters.Sea
--     -- placement / engine handles
--     water_obj         = TerrainWaterObject,
--     bbox              = box,                 -- carved bowl bbox (world units)
--     marker_x, marker_y = wu int,             -- source point
--     floor_wu          = int,                 -- bowl floor height (world units)
--     spill_wu          = int,                 -- bowl rim height (world units), == carve baseline
--     bowl_area_wu2     = int,                 -- estimated bowl floor area (world units^2)
--
--     -- water budget (driven by mw_budget.lua) -- all four rates are m^3/s
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
--     -- flood-fill cache (set by mw_flood.lua each tick)
--     flooded_tile_count = int,
--     flooded_area_wu2   = int,
--     surface_area_wu2   = int,                -- equals flooded_area_wu2 for Phase 1
--   }

local MartianWaters = rawget(_G, "MartianWaters")
if type(MartianWaters) ~= "table" then
	MartianWaters = {}
	rawset(_G, "MartianWaters", MartianWaters)
end

MartianWaters.State = MartianWaters.State or {
	segments = {},
	next_id = 1,
	enabled = false,
}

-- Mint a fresh segment id and register the segment record. Both the batch
-- carve API (mw_api.lua) and the click tool (mw_tool.lua) call this, so the id
-- namespace and segment-table shape stay in one place.
function MartianWaters.State:RegisterSegment(seg)
	local id = "mw_" .. tostring(self.next_id)
	self.next_id = self.next_id + 1
	self.segments[id] = seg
	return id
end
