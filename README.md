# Surviving Mars Relaunched Mods

- **`attribute-inspector`** - Shows a compact bottom-right inspector for the selected object, including attributes/properties and marker/deposit references.
- **`flexible-passages`** - Adds flexible dome passage placement. Left-click anchors the passage to a tile; right-click undoes the last anchor point.
- **`force-delete`** - Press `Ctrl+Delete` to force-delete selected demolishable objects, such as bugged train tracks.
- **`mute-notifications`** - Selectively mutes repeated Mission Control voice notifications without lowering voice volume or hiding visual notifications.
- **`salvage-tool-shortcut`** - Press `Delete` with no selected object to toggle salvage/demolish mode on or off.
- **`select-mixed-rovers`** - Allows drag selection of mixed rover types. Press `Ctrl+R` to select all rovers in the colony.
- **`t-for-tracks`** - Press `T` to toggle train track placement mode on or off.

## Install

Copy any mod folder from `mods/` into:

```text
%AppData%\Surviving Mars Relaunched\Mods
```

For example:

```text
mods\mute-notifications
```

should become:

```text
%AppData%\Surviving Mars Relaunched\Mods\mute-notifications
```

## Mod Structure

Each mod is self-contained:

- `metadata.lua` defines the mod title, id, author, version, tags, and code files.
- `items.lua` registers the code item for the in-game mod loader.
- `Code/*.lua` contains the runtime behavior.
- `Images/` contains thumbnails and other mod-owned art assets where used.
