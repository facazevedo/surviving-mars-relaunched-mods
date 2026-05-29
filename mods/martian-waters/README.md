# Martian Waters

Player-driven river creation for Surviving Mars Relaunched. Carve a bowl-shaped depression along a path, then fill it with the engine's `TerrainWaterObject` water grid -- the terrain shapes the river.

The mod ships a stable **core** (carving + water markers + UI + rain controls) and a designed-but-not-yet-implemented **hydrology layer** that turns the river from cosmetic dressing into a terrain-aware system the rest of the colony has to live with. This README documents both. Items still in design are flagged **[planned]**.

The hydrology design deliberately rejects bbox-based gameplay: water effects are decided by **sampled water depth at the object's position** and **connected-tile flood spread**, not by membership in the carved bbox. The goal is a robust, simple, terrain-aware hydrology approximation -- **not** a full fluid simulation.

---

## Current Features

### Water tool

A right-side panel ("MARTIAN WATERS") appears once a map is loaded.

* **Activate Water Mode** -- enters click-to-place mode. Left-click on terrain drops a `TerrainWaterObject` marker at the cursor, filling the surrounding depression. Click within `WATER_TOOL_SELECT_RADIUS_M` of an existing marker to select it instead of placing a new one. Escape exits the mode.
* **`-` / `+`** -- adjust the water level of the most recently placed/selected marker. Step size is `WATER_TOOL_STEP_METERS` (default 1 m).
* **Clear All Water** -- removes every marker the mod placed. Water drains via `ApplyAllWaterObjects`. Terrain heights are **not** restored (prototype limitation -- the carved bowl stays).

### Rain

Two independent rain modes, both gated on `ENABLE_MOD`:

* **Start Rain / Stop Rain** -- starts/stops a real game rain disaster via `CheatRainsDisaster` / `StopRainsDisaster`. Preset configurable via `DefaultRainPreset` (default `Normal_Low`; valid: `Normal_VeryLow/Low/High`, `Toxic_VeryLow/Low/High`). Affects soil and (Toxic only) spawns toxic pools.
* **Visual On / Visual Off** -- cosmetic-only rain via `SetSceneParam("RainEnable", 1/0)`. No soil change, no disaster threads. Persists across day/night and weather transitions (the mod's `OnMsg.LightmodelSetSceneParams` hook reapplies the override after the engine writes its own value). Mod disable / map unload clears the override.

### Console API

```lua
MartianWaters.Create(path, params)        -- carve + fill along a path of {x,y} points
MartianWaters.Demo()                      -- build the configured demo river across the map
MartianWaters.CreateAtCursor(opts)        -- short river through the terrain cursor
MartianWaters.ClearAll()                  -- remove every placed marker
MartianWaters.List()                      -- print active segment ids
MartianWaters.Rain.StartDisaster(preset?) -- defaults to Config.DEFAULT_RAIN_PRESET
MartianWaters.Rain.StopDisaster()
MartianWaters.Rain.StartVisual()
MartianWaters.Rain.StopVisual()
```

All public functions respect `MartianWaters.Config.ENABLE_MOD`.

---

## Hydrology Model **[planned]**

### Water-depth classification

Every effect (movement, placement, damage, dome sealing) is decided by sampling

```
water_depth = actual_water_level - terrain_height
```

at the object's position, and looking the result up in this classification:

| Range | Class | Meaning |
| --- | --- | --- |
| `0.00 m` | dry | normal terrain |
| `0.01 - 0.20 m` | wet | damp ground, puddles |
| `0.20 - 0.75 m` | shallow | walkable but slow |
| `0.75 - 2.00 m` | deep | impassable on foot |
| `> 2.00 m` | submerged | fully flooded |

The river bbox is used **only** as a broad scan region (an optimization for "which tiles might be wet this tick") -- never as the gameplay rule itself.

### Connected flood spread

A tile is flooded only if both:

1. `terrain_height < actual_water_level` (it's below the local water surface), AND
2. it's reachable from the source through a chain of other flooded/floodable tiles.

Isolated depressions elsewhere on the map that happen to sit below the same global level **do not** flood -- spread is locally connected, not globally level-based.

### Per-source water budget

Each water source (river segment, lake, spring, rain runoff pool) tracks:

```
source_discharge       inflow from the source (m^3/s)
water_volume           volume currently held
actual_level           computed from volume + basin shape
spill_level            bowl rim elevation
evaporation_rate       m/s, multiplied by surface_area
infiltration_rate      m/s, multiplied by flooded_area
outlet_capacity        drainage to neighbor basin / map edge (m^3/s)
flooded_tiles          current connected wet set
```

Each game-time tick:

```
volume += (source_discharge + rainfall_runoff) * dt
volume -= (evaporation_rate * surface_area)    * dt
volume -= (infiltration_rate * flooded_area)   * dt
volume -= (outlet_capacity * overflow_factor)  * dt
actual_level   = volume_to_level(volume)
flooded_tiles  = connected tiles where terrain_height < actual_level
```

A flood persists naturally when inflow exceeds losses and recedes naturally when losses exceed inflow. **The player does not have to hold a button.**

### Controls

`+` and `-` adjust the **source discharge** of the most recently placed/selected marker -- not the water level directly. The water budget decides what level falls out of that discharge.

```
+   increases source discharge
-   decreases source discharge
```

A `target_level` / `actual_level` smoothing layer is retained as a rate-limit on visible marker motion (so a sudden discharge spike doesn't snap the visual level), not as the core physical model.

### Source types

| Source | Behavior |
| --- | --- |
| Rain runoff | Temporary pulse during/after a rain disaster |
| Aquifer spring | Constant low inflow |
| Terraforming lake | Stable basin water once Mars is wet enough |
| Dam failure / artificial release | Sudden high inflow burst |
| Toxic rain | Hazardous temporary pools |

### Drainage and outflow

| Condition | Outcome |
| --- | --- |
| Water reaches a lower connected basin | Spills into that basin |
| Water reaches the map edge | Drains off-map |
| No outlet exists | Forms or expands a lake |
| Inflow exceeds outlet capacity | Flood grows |
| Losses exceed inflow | Flood recedes |

### Movement (depth-based)

| Mover | dry | wet | shallow | deep | submerged |
| --- | --- | --- | --- | --- | --- |
| Rover | normal | normal | reduced speed | heavy penalty / damage | blocked or disabled |
| Drone | normal | normal | normal | normal | normal |
| Train (locomotive tile) | normal | normal | reduced speed | drastic speed reduction | blocked or disabled (if feasible) |
| Colonist | normal | normal | blocked / strongly discouraged | blocked or lethal | blocked or lethal |
| Shuttle | normal | normal | normal | reject pickup/dropoff | reject pickup/dropoff |

Drones hover and are **unaffected by ordinary water depth**. Toxic water is the only optional drone hazard (off by default). Shuttle flight is never blocked -- only pickup/dropoff at the target tile is rejected when that tile is deep, submerged, or hazardous.

Train speed depends solely on the **locomotive tile**; cars do not contribute.

### Placement (depth-based)

| Buildable | wet | shallow | deep | submerged |
| --- | --- | --- | --- | --- |
| Cables | yes | yes | yes | yes |
| Pipes | yes | yes | yes | yes |
| Train tracks | yes | yes | yes | yes |
| Passages | yes | yes | yes | yes |
| Domes | yes (sealed) | yes (sealed) | yes (sealed) | yes (sealed) |
| Everything else | yes | no | no | no |

"Meaningful depth" = the placement footprint contains any tile classified shallow or deeper. Wet/puddle ground does not block ordinary placement.

### Domes

Dome sealing is decided by sampled water depth over the **dome footprint**, not bbox membership.

* While any footprint tile is at least shallow:
  * The dome cannot transition to the post-terraforming open state.
  * Colonists cannot exit through exposed airlocks.
  * Colonists may still move through connected sealed **passages**.
* Once every footprint tile is dry again, vanilla dome behavior resumes (including post-terraforming opening when applicable).

### Flood damage (delayed states)

First contact with water does not destroy. Damage is staged and time-gated.

| State | Trigger | Effect |
| --- | --- | --- |
| Wet | depth >= wet | none |
| Shallow flooded | depth >= shallow | warning + reduced output |
| Deep flooded | depth >= deep | **disabled** -- output stops, no power/resource draw, no condition loss. Reversible: the building re-enables when its footprint recedes to wet or dry. |
| Prolonged submerged | depth >= deep for `FLOOD_DAMAGE_DELAY` continuously | destroyed |

If water recedes before `FLOOD_DAMAGE_DELAY` expires, the building survives without permanent damage -- a transient spill is never fatal. Cables, pipes, passages, train tracks, and domes are exempt from the destroyed state regardless of duration.

The rule is **uniform across non-exempt buildings**: solar panels, wind turbines, mines, factories, depots, RTGs, water extractors, etc. all share the same wet/shallow/deep/prolonged ladder. No per-class overrides for now.

### Coverage cap

A configurable per-scenario ceiling caps **total flooded coverage** (fraction of the map). When the cap is hit, additional source discharge is throttled rather than ignored, so the player can redistribute water sources but cannot exceed the global limit.

---

## Terrain Carving Improvements **[planned]**

Make carved channels feel less like rectangular trenches:

* Width varies slightly along the river.
* Bank slope differs between left and right banks.
* Outside of curves is deeper and steeper.
* Inside of curves is shallower, forming sediment bars.
* Bowl smoothing uses noise so the channel is not perfectly uniform.

Optional later features:

* Delta where a river enters a lake or flat basin.
* Alluvial fan where a river exits a canyon onto open terrain.
* Dry riverbed retained when the source is removed.
* Marsh/wetland on shallow flat terrain after terraforming.

---

## Configuration

All knobs live in `Code/mw_config.lua`. The most user-relevant:

| Key | Default | Purpose |
| --- | --- | --- |
| `EnableMod` | `true` | Master switch. `false` -> mod stays passive on load. |
| `DefaultWidthMeters` | `30` | Inner half-width of the carved bowl. |
| `DefaultBankMeters` | `15` | Outer smoothing ring beyond inner width. |
| `DefaultDepthMeters` | `8` | Floor depth below the lowest natural ground on the path. |
| `DefaultWaterLevelMeters` | `5` | Initial water height above the bowl floor. Must be < depth. |
| `WaterToolStartLevelMeters` | `5` | Level a new click-placed marker starts at. |
| `WaterToolStepMeters` | `1` | Source-discharge step per `-` / `+` press once hydrology is wired in (currently: level step). |
| `DefaultRainPreset` | `"Normal_Low"` | Preset id for the Start Rain button. |
| `DebugLogs` | `true` | Master debug-log gate. |
| `Debug<Scope>` | `true` | Per-scope gate. Scopes: `Init`, `Lifecycle`, `Api`, `Terrain`, `Water`, `Tool`, `Ui`, `Rain`. |

Set `DebugLogs = false` to silence everything; keep it on and flip a scope flag to silence one subsystem.

---

## Architecture

```
mods/rivers/
  metadata.lua          ModDef + canonical mod version + Lua load order
  items.lua             ModItemCode entries (matches metadata.lua order)
  Code/
    mw_state.lua         MartianWaters.State table + RegisterSegment helper
    mw_config.lua        all configuration + typed MartianWaters.Config view
    mw_debug.lua         scoped logging helper
    mw_terrain.lua       SetHeightCircle bowl carve + path normalization
    mw_water.lua         TerrainWaterObject marker placement / level / removal
    mw_rain.lua          disaster + visual rain controls
    mw_api.lua           public MartianWaters.Create / Demo / CreateAtCursor / ClearAll / List
    mw_tool.lua          water-tool overlay + click-to-place/select + +/- adjust
    mw_ui.lua            right-side panel (water tool + rain section)
    mw_lifecycle.lua     Enable/Disable + OnMsg wiring (NewMapLoaded, DoneMap,
                        LightmodelSetSceneParams)
    MartianWaters.lua          entry point: logs config + calls Lifecycle.Enable()
```

The hydrology layer is expected to land as new modules (e.g. `mw_hydrology.lua` for the depth/flood-spread model, `mw_budget.lua` for the per-source water budget, `mw_effects.lua` for movement/placement/damage application). Each new module must be added to **both** `metadata.lua` and `items.lua`.

---

## Implementation Priority **[planned]**

1. **Sampled water depth.** Replace bbox water membership with `terrain.GetWaterHeight(map, x, y) - terrain.GetHeight(map, x, y)` lookups and the depth classification table.
2. **Connected flooded-tile detection.** Local flood-fill from each source, bounded by the source's `actual_level`.
3. **Depth-based effects.** Movement, placement, and damage rules from this README, all reading the depth class -- no bbox checks in gameplay code.
4. **Water budget.** Replace the previous "hold `+` to keep flood alive" sketch with the inflow/loss model and source-discharge controls.
5. **Channel naturalism.** Asymmetric carving, noise, sediment-bar pass.
6. **Advanced visuals.** Deltas, alluvial fans, dry riverbeds, marshes -- only after the core hydrology is stable.

---

## Concepts Kept From Earlier Designs

* Rate-limited water level rise on the visible marker (smoothing).
* Rate-limited drain on the visible marker (symmetry).
* Per-scenario coverage cap.
* Domes sealed while their footprint is under water.
* Cables, pipes, passages, train tracks legal under water and exempt from flood-destroy.
* Rain disaster controls.
* Visual-only rain override controls.

## Concepts Removed

* Gameplay decisions based on bbox membership.
* Drone slowdown from ordinary water (drones hover; only optional toxic-water hazard remains).
* Instant destruction on first water contact.
* Flood persistence requiring the player to continuously hold `+`.
* Treating all non-special flooded objects identically (replaced by depth + duration states).

---

## Known Limitations

* **Terrain carving is not reversible.** The carved bowl stays after `MartianWaters.ClearAll()` or mod disable. Water markers are reversible (they drain), but the channel is baked into the heightfield. This mirrors how vanilla landscape buildings (e.g. `LandscapeLake`) work and would require a heightmap snapshot to undo.
* **The hydrology layer is not yet implemented.** Depth sampling, connected flood spread, water budget, movement/placement/damage rules, and dome sealing are designed but not coded.
* **Disaster rain is engine-owned game state** and is intentionally not cancelled on mod disable. The visual override is mod-owned and is cleared on disable.
* **Not a fluid simulation.** The model is a discrete, terrain-aware, budget-driven approximation. It will not produce realistic flow vectors, waves, or pressure -- by design.
