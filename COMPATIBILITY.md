# Compatibility with Surviving Mars Relaunched 1.1.1.405907

## October 3 repository migration

Flexible Passages and its 12 lifecycle regression checks are now maintained in
[SMR-flexible-passages](https://github.com/facazevedo/SMR-flexible-passages).
The historical eight-mod results below describe the collection before that
move. This repository's compatibility suite now runs 44 regression checks;
the separate mod repository retains the Flexible Passages runtime check.

## September 27 follow-up: Mute Notifications Steam warning

Mute Notifications is now metadata version **62**, runtime **0.9.1**. The fix
was tested and deployed as version 61; the subsequent metadata update advances
the mod version to 62 and the Paradox version to 4 without changing runtime code.
This supersedes the version 60 result in the original compatibility pass below.

The Steam release log Mars.exe-20260927-09.18.08-6aad2d75.log confirmed a real
error during catalog construction: TFormat.percentWithSign compared a missing
scenario value with a number. The earlier debug-build checks did not exercise
the release build's localized lightuserdata. Read-only inspection of
CommonLua/Core/localization.lua showed that its userdata translation branch
drops tags_off, evaluating context-dependent tags despite the caller's request.
The engine reports that error even inside the mod's pcall.

The catalog now uses the verified TGetID and TranslationTable APIs to read
localized userdata templates without invoking formatters. Translation IDs,
preview inputs and saved mute settings are unchanged. The catalog cache schema
was advanced to rebuild old entries. Missing templates produce diagnostics
behind the existing exact-boolean MN_Config.DEBUG flag (false by default).
Opening the panel also exposed a debug-build localization assertion for the
search placeholder; mn_panel.lua now marks that literal with Untranslated.

Validation: 12 new standalone catalog regression checks and the existing 56
compatibility checks pass. Lua syntax checks pass. The real engine reproduced
the old failure using LocIdToLightUserdata, then verified the fix against 13
actual templates (2 percentage and 11 colonist-name templates). A full catalog
rebuild with release-style inputs produced 415 entries. Existing Mute
Notifications lifecycle checks and panel opening/closing passed. The fresh
MarsDebug.exe-20260927-09.23.26-6aad2de6.log contains no Lua, translation or mod
errors; the previously noted shader/video shutdown diagnostics remain. The
reproduction log ending 09.21.22 intentionally contains the original error and
the placeholder assertion. No logs were deleted.

All 13 payload files were hash-verified against the separate local copy in
%APPDATA%\Surviving Mars Relaunched\Mods\mute-notifications. Only mod-owned
catalog, config, panel and metadata files changed, plus tests and this report.
No game, third-party or asset files were edited. Tests restored the original
enabled-mod selection and exited. The actual Steam warning dialog was not
retested in a retail session: fully restart Steam's game, enable the local
version 62 (or the tested version 61), then open Audio settings and the panel to confirm the warning is
gone. Audible previews and colony save/load remain manual checks.

## Original compatibility pass

Checked on Windows on September 26, 2026 (September 27 UTC for the final run).
The installed game reported Lua revision **405907**. All eight mods were
deployed as separate folders under
**%APPDATA%\Surviving Mars Relaunched\Mods**.

Rechecked on September 27: every payload file matches its separate local copy
by SHA-256. The running engine reports source = appdata and the individual
AppData/Mods/<mod-folder>/ path for all eight mods, both individually and
together. All eight individual checks and the combined checks passed again,
as did all 69 Lua syntax checks and 56 regression checks. The original enabled
mod selection was restored and the test process exited normally. The completed
MarsDebug.exe-20260927-00.47.08-6aad2de6.log was reviewed with no error,
exception, undefined-global or stack-trace matches; it contains the same engine
shutdown diagnostics described below. No logs were deleted.

| Mod folder | Metadata version | Result |
| --- | ---: | --- |
| attribute-inspector | 13, unchanged | Individual and combined loading; inspector class/API checks |
| disable-all-mods | 12, unchanged | Individual and combined loading; button insertion/removal and disable-guard restoration |
| flexible-passages | **12**, runtime **1.0.4** | Fixed class initialization and reload ownership; apply/disable/reapply, feature flag and restoration checks |
| force-delete | 7, unchanged | Individual and combined loading; both shortcut actions and deletion modules available |
| mute-notifications | 60, unchanged | Individual and combined loading; voice wrapper restoration and one Audio options property after repeated enable |
| salvage-tool-shortcut | **4** | Verified salvage mode; shortcut registration, dispatch, disable and restoration checks |
| select-mixed-rovers | **4** | Deferred selection hook, single base-handler dispatch, registration and restoration checks |
| t-for-tracks | **4** | Verified track mode and restrictions; shortcut priority, dispatch, disable and restoration checks |

These are compatibility and lifecycle checks, not a claim that every gameplay
operation or save format was exercised. Unchanged mods retain their existing
versions because their behavior was not changed.

## Changes

- Flexible Passages installs its controller wrappers after ClassesBuilt.
  Runtime ownership state is recreated when code reloads: the mod environment
  can survive while engine classes are rebuilt. Disabled wrappers are dormant,
  required API failures prevent activation, and incomplete restoration is
  reported. Unload restores owned hooks.
- The three shortcut mods register with the official Shortcuts and
  ShortcutsReloaded events and register against an existing host when needed.
  They remove only their own actions on unload. Their original action IDs remain
  stable. T for Tracks and Salvage use the supported action sort order to take
  priority only when their actions are enabled; vanilla actions are not edited.
- T for Tracks uses track_grid and respects research, environment and tutorial
  restrictions. Salvage uses demolish; selected-object Delete remains vanilla.
  Guessed template/mode names, raw key interception and silent mode-switch
  exception handling were removed from these two mods.
- Mixed rover selection waits for finalized classes, preserves base event
  consumption, and invokes the base button-up handler once. A later mod's
  wrapper is preserved during restoration.
- Supporting files use tft_, sts_, and smr_; metadata and items.lua specify
  matching load order. Their main files contain lifecycle wiring.

New shortcut diagnostics use explicit boolean DEBUG_LOGS = false in the
corresponding config files. Enablement is controlled by ENABLE_MOD = true.
Diagnostics cover registration, action ownership, mode transitions and
selection patching/restoration. Flexible Passages uses its existing
DEBUG_LOGS and scoped flags, all still false by default.

The four changed mods record saved_with_revision = 405907. The minimum
lua_revision = 350453 remains unchanged: both the shipped loader and the
running game reported 350453 for the minimum/required mod Lua revision.
Publication IDs, assets and per-store versions were not changed.

## Validation

- Lua 5.4 compiler checks cover every payload Lua file and both test files.
- Each metadata code list matches items.lua in order and includes every
  owned code file.
- The original lua tests/compatibility_spec.lua run passed **56** regression checks.
  These use simulated engine boundaries for mode changes, restrictions, mixed
  selection, reload ownership, feature flags and exact-boolean diagnostics.
- Real-engine tests load each mod independently, then all eight together,
  through ModsReloadItems in a disposable hidden MarsDebug.exe session.
  [tests/game_compatibility.lua](tests/game_compatibility.lua) contains the
  runtime checks. Shortcut dispatch checks use the real action host with
  temporary test callbacks; they do not place tracks or demolish objects.
- Flexible Passages was additionally reloaded while already enabled to
  reproduce and verify the stale ownership fix.
- The runtime reported no mod code-load errors. The final runtime mod-message
  log search found no entries containing "error".
- Deployment verification compares SHA-256 hashes and the complete relative
  file lists for each source/destination pair.

Tests temporarily changed the in-memory enabled-mod list and restored the
original list after each reload. They did not intentionally save a different
enabled-mod preference, disable the user's installed mods through the UI, or
write a savegame.

## Read-only engine references and diagnostics

The game installation at C:\Games\Surviving Mars Relaunched was inspected
read-only. Relevant shipped sources under ModTools\Src included:

- CommonLua\Modding\Mod.lua: mod environments, loading, unload callbacks,
  revision rules and persistent-storage interfaces.
- CommonLua\Core\classes.lua: class rebuilding and ClassesBuilt.
- CommonLua\X\XShortcuts.lua and CommonLua\X\XActions.lua: registration,
  action ownership, sorting and dispatch.
- Lua\XDef\GameShortcuts.generated.lua, Lua\UI\InGameInterface.lua,
  Lua\UI\SelectionModeDialog.lua, Lua\Buildings\Track.lua and
  Lua\X\BuildMenu.lua: modes, native shortcut behavior and placement rules.
- CommonLua\Voice.lua and
  CommonLua\Libs\Notifications\NotificationUI.lua: voice function signatures.
- Construction-controller and mod-manager APIs were also checked in the live
  game. No game APIs were introduced based only on guessed names.

Recent game logs were read from
%APPDATA%\Surviving Mars Relaunched\logs, including the September 26
16:43:54, 16:47:23, 16:49:53 and 16:54:50 debug logs and the compatibility
sessions beginning at 17:00:30 and 22:57:54. Output was buffered during the
dedicated session; its completed log was reviewed after exit and contains the
mod-loading records without mod code-load errors. It also contains engine
shutdown diagnostics for a missing Shader::CompileEffect hook and one video
not cleaned up; those were not diagnosed as mod failures. Live code-load errors
and explicit test results were checked in addition to disk logs. No logs were
deleted. The original enabled-mod selection was restored and the dedicated
test process exited normally.

No game-installation, third-party, bundled, generated engine-source or asset
files were modified. Repository runtime changes are confined to the four
mods listed above; the other four payloads remain unchanged.

## Remaining gameplay checks

Use a disposable colony and restart the game after installing the payloads.

1. Enable each desired mod. Test T entering/exiting track placement from
   selection and another construction tool, including track mode entered
   through the build menu.
2. Test Delete entering/exiting salvage with no selection, normal Delete with a
   selected building, and Force Delete's Ctrl+Delete/Ctrl+Shift+Delete on
   disposable objects. Actual deletion was not exercised by automated checks.
3. Drag-select different rover types, use Ctrl+R, then confirm ordinary
   non-rover selection still works.
4. Complete a bent passage between domes and undo intermediate anchors.
   Completed construction was not exercised by the lifecycle tests.
5. Open the inspector and Audio settings. Mute/unmute a voice and preview it;
   check that its visual notification remains visible. Audible output was not
   manually assessed.
6. In a disposable mod-selection configuration, exercise Disable All Mods and
   restore the previous selection. The tests checked its UI and wrapper
   lifecycle, not the actual bulk change to user preferences.
7. Save and reload; disable/re-enable the mods and check for duplicate UI,
   actions or stale behavior. Review fresh logs. Save/load gameplay and visual
   layout were not part of this compatibility pass.
