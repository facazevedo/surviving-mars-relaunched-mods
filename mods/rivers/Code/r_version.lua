-- Rivers -- internal patch-guard version constants.
--
-- These are NOT the published mod version. The canonical mod version lives in
-- metadata.lua ('version'); this file must not duplicate it. The constants below
-- are hot-reload patch-identity guards: bump one when the corresponding apply or
-- restore closures change, so they reinstall cleanly on an in-session mod reload
-- instead of leaving stale state behind.

local Rivers = rawget(_G, "Rivers")
if type(Rivers) ~= "table" then
	Rivers = {}
	rawset(_G, "Rivers", Rivers)
end

-- Shared mod state: tracking placed river segments + their water markers so the
-- lifecycle can restore vanilla terrain/water on disable or before reapplying.
Rivers.State = Rivers.State or {
	-- segment_id (string) -> { water_obj = obj, height_box = box, original_heights = {...} }
	segments = {},
	next_id = 1,
	enabled = false,
}

-- Bumped when r_lifecycle.lua's OnMsg hook closure changes, so a hot reload can
-- detect a stale hook registration and refuse to double-install.
Rivers.LIFECYCLE_PATCH_VERSION = 1
