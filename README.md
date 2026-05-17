# Surviving Mars Relaunched Mods

Small quality-of-life mods for Surviving Mars: Relaunched.

## Mods

- `attribute-inspector` v3 - Shows a bottom-right debug panel for the selected object, including runtime handle, id, class, entity, position, angle, and related marker/deposit information.
- `force-delete` v3 - Press `Ctrl+Delete` to light force-delete selected demolishable objects, useful for bugged objects such as stuck train tracks. Press `Ctrl+Shift+Delete` to hard force-delete selected objects, including humans, animals, and drones. Xbox [not tested]: `LB+RB+X` light, `LB+RB+Y` hard. PS4/PS5 [not tested]: `L1+R1+Square` light, `L1+R1+Triangle` hard.
- `salvage-tool-shortcut` v3 - Press `Delete` with no selected object to toggle salvage/demolish mode on or off.
- `select-mixed-rovers` v9 - Allows drag selection of mixed rover types. Press `Ctrl+R` to select all rovers in the colony.
- `t-for-tracks` v9 - Press `T` to toggle train track placement mode on or off.

## Install

Copy any mod folder from `mods/` into:

```text
%AppData%\Surviving Mars Relaunched\Mods
```

For example:

```text
mods\t-for-tracks
```

should become:

```text
%AppData%\Surviving Mars Relaunched\Mods\t-for-tracks
```

## Development

Each mod is self-contained:

- `metadata.lua` defines the mod title, id, author, version, tags, and code files.
- `items.lua` registers the code item for the in-game mod loader.
- `Code/*.lua` contains the runtime behavior.

The code is written defensively for the Surviving Mars mod sandbox: optional game globals are checked before use, shortcut patches are retry-safe during game loading, and updated folders can be copied directly into the live Mods directory for testing.
