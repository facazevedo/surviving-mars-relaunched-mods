# Surviving Mars Relaunched Mods

1. **`attribute-inspector`** - Shows a compact bottom-right inspector for the selected object, including attributes/properties and marker/deposit references.
2. **`force-delete`** - Press `Ctrl+Delete` to force-delete selected demolishable objects, such as bugged train tracks.
3. **`mute-notifications`** - Selectively mutes repeated Mission Control voice notifications without lowering voice volume or hiding visual notifications.
4. **`salvage-tool-shortcut`** - Press `Delete` with no selected object to toggle salvage/demolish mode on or off.
5. **`select-mixed-rovers`** - Allows drag selection of mixed rover types. Press `Ctrl+R` to select all rovers in the colony.
6. **`t-for-tracks`** - Press `T` to toggle train track placement mode on or off.
7. **`disable-all-mods`** - Disable other enabled mods and restore the previous selection from the Installed Mods screen.

Flexible Passages is maintained separately in
[SMR-flexible-passages](https://github.com/facazevedo/SMR-flexible-passages).

## Install

Compatibility checks for game build **1.1.1.405907**, including Disable All Mods,
are recorded in [COMPATIBILITY.md](COMPATIBILITY.md).

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
