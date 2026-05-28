# Rivers -- Implementation Phases

This file is the long-form roadmap that `README.md` summarises. Each phase is a single mergeable unit; the file is updated as phases land so it stays a forward-looking ledger.

---

## Phase 1 -- Hydrology core *(in progress)*

**Goal:** prove the depth + connected-flood + per-source water budget loop runs cleanly in-game without writing any code that depends on engine APIs we have not yet verified. No gameplay effects yet; the river just behaves more naturally.

**Deliverables:**

* `Code/r_depth.lua` -- `Depth.Classify(depth_m)` and `Depth.SampleAt(map, pt)` returning `(depth_m, class)`. Classes: `dry`, `wet`, `shallow`, `deep`, `submerged`. Thresholds in `r_config.lua`.
* `Code/r_flood.lua` -- per-segment connected flood-fill from the source tile, bounded by `actual_level`. Returns flooded-tile list + bbox + total flooded area. Safety cap via `FLOOD_MAX_TILES`.
* `Code/r_budget.lua` -- per-segment water budget (`discharge`, `volume`, `actual_level`, `spill_level`, `evap_rate`, `infiltration_rate`, `outlet_capacity`). Game-time ticker advances volume each tick; `actual_level` follows.
* `Code/r_state.lua` extended with new per-segment fields.
* `Code/r_tool.lua` -- `+` / `-` rewired to `AdjustDischarge` (m^3/s); `AdjustLevel` removed.
* `Code/r_ui.lua` -- status label shows `discharge`, `volume`, `flooded area`, and `level class` at the source.
* `Code/r_lifecycle.lua` -- spawns the budget ticker on `Enable`, kills it on `Disable`; ticker re-spawns on `NewMapLoaded`.
* `Code/r_api.lua` -- exposes `Rivers.Depth.At(x, y)`, `Rivers.Flood.Get(seg_id)`, `Rivers.Budget.Get(seg_id)` for console debugging.

**Out of scope for Phase 1:**

* Gameplay effects (movement penalties, placement blocks, dome sealing, flood damage, shuttle pickup rejection). Deferred to Phase 3.
* Debug tile overlay. Deferred to Phase 1.5.

**Acceptance:**

* `Rivers.Create(path)` still works; a created segment now reports a budget the console can query.
* Pressing `+` raises `discharge`; level rises gradually as volume accumulates. Pressing `-` lowers discharge; level recedes naturally when losses exceed inflow. No "hold the button" mechanic.
* Spilled water stops at connected tiles only -- an isolated low spot elsewhere on the map does **not** flood.
* `luac -p` passes on every changed file.
* Live `Mods\rivers` payload deployed.

---

## Phase 1.5 -- Debug tile overlay *(deferred)*

**Goal:** make the depth/flood model visually observable in-game so we can verify it before wiring gameplay effects.

**Deliverables:**

* `Code/r_overlay.lua` -- a toggleable overlay that paints each flooded tile with a colour matching its depth class.
* `r_ui.lua` -- a button to toggle the overlay.

Worth doing before Phase 3 if any behaviour in Phase 1 looks off in-game.

---

## Phase 2 -- API recon *(pending user approval)*

Targeted Glob/Grep pass over the game-specific Lua tree (the parts of `C:\Games\Surviving Mars Relaunched\` outside `ModTools/Src/CommonLua/`) to find the engine hooks needed by Phase 3. The first research agent only covered `CommonLua` and concluded "not found" for many classes that almost certainly live in the game-specific Lua.

**Targets:**

* `Dome.lua` -- open/sealed states, airlock exit logic, post-terraforming "open" transition.
* `Train.lua` / `Locomotive` -- speed property, locomotive vs. car distinction.
* `Shuttle.lua` / `ShuttleHub.lua` -- pickup task assignment, ability to reject a target tile.
* `BaseRover.lua` / `Rover.lua` -- runtime speed modifier hooks (already partly found via `Movable.lua`).
* `Drone.lua` / `Flight.lua` -- whether drone hover speed is moddable at runtime.
* `Construction.lua` / `ConstructionController.lua` -- placement validation hook for "is this tile buildable".
* `DestroyObj` / building destruction primitive -- how vanilla buildings are destroyed by disasters.

**Output:** an updated version of the earlier research report with the missing classes mapped to `file:line`.

---

## Phase 3 -- Gameplay effects *(blocked on Phase 2)*

**Goal:** wire the depth-classified state into actual in-game consequences, one effect at a time, each behind an explicit feature flag so a broken hook can be turned off without losing the rest.

**Order of implementation:**

1. Construction blocker (placement validator hook). Exempt list: cables, pipes, train tracks, passages, domes.
2. Colonist passability (block `shallow+` tiles from colonist paths; passages bypass).
3. Rover speed modifier (depth-based via `Movable:SetMoveSpeed`).
4. Train locomotive speed (depth at locomotive tile).
5. Dome sealing (depth over footprint; block post-terraforming "open" transition; route colonists through passages).
6. Flood damage timer + destruction (wet/shallow/deep/prolonged ladder; exempt list).
7. Shuttle pickup-target rejection.

Each gets its own commit. Each starts with a "is this hook actually wired in this game version?" availability check, logged behind `DEBUG_<scope>`.

---

## Phase 4 -- Channel naturalism *(stretch)*

* Variable width along the path.
* Asymmetric left/right bank slope.
* Curve-aware depth (outside of curves deeper, inside shallower / sediment bar).
* Noise on the smoothing pass so channels are not perfectly uniform.

Pure terrain-carving work; no engine hook dependencies.

---

## Phase 5 -- Advanced visuals *(stretch, dependent on Phase 4)*

* Delta where a river enters a flat basin.
* Alluvial fan where a river exits a canyon.
* Dry riverbed retained when the source is removed.
* Marsh / wetland on shallow flat terrain after terraforming.

---

## Ledger

| Phase | Status | Notes |
| --- | --- | --- |
| 1 | in progress | depth + flood + budget + UI rewire |
| 1.5 | deferred | debug overlay |
| 2 | pending approval | API recon over game-specific Lua tree |
| 3 | blocked on Phase 2 | gameplay effects, one commit per effect |
| 4 | stretch | channel naturalism |
| 5 | stretch | advanced visuals |
