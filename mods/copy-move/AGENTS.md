# Professional Surviving Mars Relaunched Mod Development Prompt

You are working on a Surviving Mars Relaunched mod.

Your task is to implement, debug, refactor, extend, or review this mod using professional software architecture principles. Prioritize correctness, maintainability, reversibility, explicit ownership boundaries, reproducible debugging, and safe deployment.

Do not use hacks, brittle workarounds, silent fallbacks, broad error suppression, or invented game APIs.

## Core Objectives

- Keep the mod clean, maintainable, and easy to debug.
- Preserve vanilla game behavior unless the mod explicitly changes it.
- Make mod behavior reversible when possible.
- Keep code modular and domain-oriented.
- Use clear responsibility boundaries.
- Use explicit configuration and feature flags.
- Use explicit boolean debug flags.
- Add useful diagnostic logs behind those flags.
- Avoid invented Surviving Mars Relaunched APIs, globals, hooks, or assumptions.
- Keep changes scoped and reviewable.
- Protect vendored, third-party, generated, bundled, or external code from accidental edits.
- Update version information when behavior-changing code changes.
- Deploy the updated mod payload only after checking modified files.

## Project-Specific Variables

Before applying these rules, identify the project-specific values for this mod:

- mod display name;
- main entry file name;
- lowercase file prefix;
- canonical version location;
- mod payload source folder;
- local deployment destination;
- protected, vendored, bundled, generated, third-party, or read-only folders;
- load-order or metadata file that controls Lua script loading;
- known external integrations.

Do not assume example names such as `BiggerMaps.lua`, `bm_*.lua`, or `Code/vendor/` apply to every mod.

Use the actual project names and paths.

## Non-Negotiable Rules

- Do not use hacks.
- Do not hide real errors with broad fallbacks.
- Do not silently suppress failures.
- Do not invent Surviving Mars Relaunched APIs.
- Do not assume an API exists because its name sounds plausible.
- Do not reformat unrelated files.
- Do not rename unrelated symbols.
- Do not mix unrelated refactors with behavior changes.
- Do not modify vendored, bundled, third-party, generated, or read-only code unless the user explicitly identifies those files as editable.
- Do not claim testing, deployment, validation, or in-game behavior succeeded unless it was actually verified.

## Priority Order

When instructions conflict, follow this priority order:

1. Never modify protected, vendored, bundled, third-party, generated, or read-only source files.
2. Preserve the user-requested behavior.
3. Preserve vanilla game restoration after mod behavior is disabled or exits.
4. Keep changes scoped and reviewable.
5. Maintain explicit boolean debug logging.
6. Update version information when required.
7. Deploy only after protected files and working tree changes are checked.

## Stop Conditions

Stop and report instead of modifying or deploying when:

- protected source files would need to be edited;
- file ownership is unclear;
- the deployment destination is ambiguous;
- a destructive command could affect files outside the intended mod folder;
- the working tree contains unexpected changes;
- required engine APIs cannot be verified and no safe guarded path exists;
- load order cannot be updated safely;
- the requested change conflicts with vanilla restoration invariants.

## Agent Workflow

Before modifying code:

1. Read the relevant files.
2. Identify current behavior.
3. Identify requested behavior.
4. Identify expected behavior.
5. Identify ownership boundaries.
6. Check whether protected or third-party code is involved.
7. Check load-order and dependency implications.
8. Make the smallest clean change that solves the problem.
9. Add or update debug logs behind explicit boolean flags.
10. Update version information when required.
11. Inspect the working tree.
12. Verify that protected source files were not modified.
13. Deploy the updated mod payload when appropriate.
14. Report changed files, unchanged protected files, tests, deployment status, and manual verification steps.

Do not make large edits based only on filenames or assumptions.

Do not invent architecture without first checking the existing structure.

## Architecture Principle

Use:

```text
Modular, domain-oriented architecture using responsibility-driven boundaries.
```

Split code by domain or feature responsibility, not by arbitrary file size.

Good module boundaries:

```text
config
version
debug_logging
lifecycle
state
ui
shortcuts
terrain
map_generation
construction_rules
landscaping_rules
research_rules
resource_rules
colonist_rules
vehicle_rules
save_load
integrations
validation
deployment
```

Bad module boundaries:

```text
utils.lua
helpers.lua
misc.lua
stuff.lua
manager.lua
helpers2.lua
utils_final.lua
```

A long file is acceptable if it owns one coherent responsibility. A short file is bad if it mixes unrelated responsibilities.

## File and Naming Conventions

Use consistent mod-owned file names.

### Main Entry File

Each mod may have one main entry file.

The main entry file should use the full mod name in PascalCase:

```text
<ModName>.lua
```

The main entry file should contain only high-level initialization, load-order wiring, and lifecycle entry points. It should not accumulate unrelated feature logic.

Examples:

```text
BiggerMaps.lua
ScenarioEditor.lua
ForceDelete.lua
CustomColonists.lua
```

### Supporting Code Files

All supporting mod-owned Lua files must start with the lowercase initials of the mod name, followed by an underscore.

Pattern:

```text
<mod_initials>_<responsibility>.lua
```

Examples:

For a mod named **Bigger Maps**:

```text
BiggerMaps.lua
bm_config.lua
bm_version.lua
bm_debug.lua
bm_lifecycle.lua
bm_state.lua
bm_map_generation.lua
bm_validation.lua
```

For a mod named **Scenario Editor**:

```text
ScenarioEditor.lua
se_config.lua
se_version.lua
se_debug.lua
se_scenario_mode.lua
se_mode_state.lua
se_validation.lua
```

For a mod named **Custom Colonists**:

```text
CustomColonists.lua
cc_config.lua
cc_version.lua
cc_debug.lua
cc_lifecycle.lua
cc_colonist_rules.lua
cc_validation.lua
```

Rules:

- The prefix must be derived from the specific mod name.
- Only the main entry file may omit the lowercase initials prefix.
- Every non-main mod-owned Lua file must use the lowercase initials prefix.
- Use clear responsibility names after the prefix.
- Do not use vague names such as `<prefix>_utils.lua`, `<prefix>_helpers.lua`, `<prefix>_misc.lua`, or `<prefix>_stuff.lua` unless the contents are genuinely shared, narrow, and unavoidable.
- Keep the prefix consistent across the whole mod.
- Do not mix prefixes from different mod names.
- When renaming files to follow this convention, update every load-order file, metadata file, manifest, mod definition, require/import call, and reference.
- Do not rename read-only, vendored, bundled, third-party, generated, or submodule files unless they are explicitly part of editable mod-owned code.

### Prefix Derivation

Derive the prefix from the mod name initials.

Examples:

```text
Bigger Maps        -> bm_
Scenario Editor    -> se_
Custom Colonists   -> cc_
Advanced Terraform -> at_
Rocket Logistics   -> rl_
```

If the mod name has only one word, use a short lowercase abbreviation from that word.

Examples:

```text
Terraforming -> tf_
Blackout     -> bo_
```

If two possible mod names produce the same initials, choose the clearest short lowercase prefix and use it consistently.

Examples:

```text
Bigger Maps       -> bm_
Better Mining     -> bmin_ or bettermining_
Rocket Logistics  -> rl_
Resource Loader   -> rload_
```

Do not change the prefix after files have been created unless the user explicitly requests a rename and all load-order references, metadata references, require/import calls, and file references are updated.

The chosen prefix must be short, clear, lowercase, and used consistently.

## Preferred Generic Structure

This is an example, not a mandatory file list:

```text
Code/
  <ModName>.lua
  <prefix>_config.lua
  <prefix>_version.lua
  <prefix>_debug.lua
  <prefix>_lifecycle.lua
  <prefix>_state.lua
  <prefix>_ui.lua
  <prefix>_shortcuts.lua
  <prefix>_validation.lua

  rules/
    <prefix>_construction_rules.lua
    <prefix>_landscaping_rules.lua
    <prefix>_research_rules.lua
    <prefix>_resource_rules.lua
    <prefix>_colonist_rules.lua
    <prefix>_vehicle_rules.lua

  terrain/
    <prefix>_terrain_generation.lua
    <prefix>_terrain_validation.lua
    <prefix>_heightmap_io.lua

  integrations/
    <prefix>_third_party_mod_integration.lua
    <prefix>_external_feature_integration.lua

  save_load/
    <prefix>_save_state.lua
    <prefix>_load_state.lua
    <prefix>_migration.lua
```

Create additional files or folders only when they improve ownership, readability, debugging, load order, or maintainability.

## Ownership Rules

Each module must own one coherent responsibility.

Examples:

- `<prefix>_config.lua`: central configuration and feature flags.
- `<prefix>_version.lua`: canonical version information.
- `<prefix>_debug.lua`: debug flags and debug logging.
- `<prefix>_lifecycle.lua`: high-level enable/disable/load/unload flow.
- `<prefix>_state.lua`: runtime state owned by the mod.
- `<prefix>_ui.lua`: mod UI creation and cleanup.
- `<prefix>_shortcuts.lua`: shortcut registration and removal.
- `<prefix>_construction_rules.lua`: construction behavior changes and restoration.
- `<prefix>_terrain_generation.lua`: terrain creation or modification logic.
- `<prefix>_save_state.lua`: persistent mod state.
- `<prefix>_validation.lua`: runtime validation and diagnostics.
- `<prefix>_integrations/*`: integration with external or third-party systems.

Do not let unrelated modules control the same state.

## Explicit Interfaces

Use clear public functions between modules.

Preferred examples:

```lua
ModLifecycle.Enable()
ModLifecycle.Disable()
ModLifecycle.ApplyModBehavior()
ModLifecycle.RestoreVanillaBehavior()

ModState.IsActive()
ModState.SetActive(value)

DebugLog.Info(scope, message, data)
DebugLog.Warn(scope, message, data)
DebugLog.Error(scope, message, data)

ConstructionRules.Apply()
ConstructionRules.Restore()

TerrainGeneration.Apply()
TerrainGeneration.Validate()

SaveState.Load()
SaveState.Save()
SaveState.MigrateIfNeeded()

Validation.CheckRuntimeState()
Validation.CheckVanillaRestoration()
```

Avoid hidden cross-module side effects.

## Lifecycle Design

Any feature that changes vanilla behavior should have both:

```lua
ApplyModBehavior()
RestoreVanillaBehavior()
```

Do not implement apply-only behavior unless the change is intentionally permanent and documented.

Lifecycle operations must be idempotent:

- enabling twice must not duplicate hooks, UI, timers, shortcuts, or state changes;
- disabling twice must not fail;
- applying rules twice must not corrupt state;
- restoring rules twice must not fail;
- save/load transitions must not leave stale UI or hooks.

## Configuration and Feature Flags

All user-adjustable behavior must be controlled from central mod-owned configuration.

Use explicit booleans:

```lua
Config.ENABLE_MOD_FEATURE = true
Config.ENABLE_CUSTOM_UI = true
Config.ENABLE_TERRAIN_CHANGES = false
Config.DEBUG_LOGS = true
```

Rules:

- Keep configuration centralized.
- Do not duplicate config values across files.
- Do not hard-code important behavior in multiple places.
- Log important configuration values during mod initialization when debug logging is enabled.
- Disabled features must not partially activate.
- Exiting/disabling the mod must restore any behavior changed by enabled features.

## Debug Logging

All new or modified runtime logic must support debug logging through explicit boolean variables.

Preferred global flag:

```lua
Config.DEBUG_LOGS = true
```

Optional scoped flags:

```lua
Config.DEBUG_UI = true
Config.DEBUG_TERRAIN = true
Config.DEBUG_SAVE_LOAD = true
Config.DEBUG_RULES = true
Config.DEBUG_INTEGRATIONS = true
```

Rules:

- Debug flags must be real booleans: `true` or `false`.
- Debug output must only print when the relevant flag is exactly `true`.
- Do not use strings such as `"true"` or `"false"`.
- Do not use missing variables as implicit flags.
- Do not print unconditional debug output.
- Prefer a centralized logging helper.
- Logs must be useful for diagnosing real bugs.
- Structured table data must be converted to readable key-value output.

Good log messages include:

- subsystem;
- operation;
- object/type/name/id when available;
- current state;
- expected state;
- feature flag state;
- branch or skip reason;
- error reason.

Preferred pattern:

```lua
if Config.DEBUG_LOGS == true then
    DebugLog.Info("ConstructionRules", "Restore skipped", {
        reason = "vanilla_costs_already_active",
        mod_active = ModState.IsActive(),
    })
end
```

Do not write vague logs like:

```text
started
done
failed
nil
```

## Versioning

Always update the canonical mod version after behavior-changing code modifications.

Rules:

- Use the existing canonical version location.
- Do not create a second version source if one already exists.
- Do not leave the version unchanged after behavior changes.
- Mention the updated version in the final summary.
- Documentation-only changes do not require a version bump unless the project convention requires it.

## Vanilla Restoration

Preserve vanilla behavior unless the mod intentionally changes it.

Before overriding vanilla behavior:

- identify the original value/function/state;
- store it safely;
- apply the modded behavior;
- provide a restore path;
- validate restoration when practical;
- log apply and restore operations behind debug flags.

Preferred override pattern:

```lua
if OriginalFunction == nil then
    OriginalFunction = SomeVanillaFunction
end

SomeVanillaFunction = function(...)
    DebugLog.Info("Subsystem", "Vanilla override called")
    return OriginalFunction(...)
end
```

Preferred restore pattern:

```lua
if OriginalFunction ~= nil then
    SomeVanillaFunction = OriginalFunction
    OriginalFunction = nil
end
```

## API and Engine Assumptions

Do not assume a Surviving Mars Relaunched API exists.

Before using a game API, hook, global, or object:

- search the existing project code;
- prefer APIs already used successfully;
- guard uncertain APIs with availability checks;
- log availability checks behind debug flags;
- report uncertainty in the final response.

Preferred pattern:

```lua
local has_api = SomeGameApi ~= nil and type(SomeGameApi.SomeFunction) == "function"

DebugLog.Info("ApiCheck", "API availability", {
    api = "SomeGameApi.SomeFunction",
    available = has_api,
})

if has_api ~= true then
    return false, "SomeGameApi.SomeFunction is unavailable"
end
```

## Lua and Game-Engine Compatibility

Write Lua code compatible with the Surviving Mars Relaunched mod runtime.

Rules:

- Do not assume standard Lua libraries are fully available unless already used by the project.
- Do not introduce dependencies on external Lua packages.
- Do not use syntax unsupported by the game runtime.
- Prefer explicit nil checks around game-engine objects.
- Treat engine userdata carefully.
- Avoid broad monkey-patching unless absolutely necessary.
- If monkey-patching is necessary, isolate it, document it, make it idempotent, and restore original behavior on mode exit when practical.
- Store original vanilla functions or values before overriding them.
- Never overwrite a vanilla function or value without preserving a restore path.
- Log monkey-patches and restorations behind explicit boolean debug flags.

## Error Handling

Do not use broad fallbacks to hide real defects.

Defensive handling is acceptable only when interacting with unstable engine state, game objects, UI objects, hooks, userdata, or save/load transitions.

Bad pattern:

```lua
pcall(function()
    DoImportantThing()
end)
```

Better pattern:

```lua
local ok, err = pcall(function()
    DoImportantThing()
end)

if ok ~= true then
    DebugLog.Error("Subsystem", "DoImportantThing failed", {
        error = err,
    })

    return false, err
end
```

## Save/Load Safety

Treat save/load behavior as high risk.

Rules:

- Do not store transient UI objects directly in persistent save data.
- Do not assume runtime hooks survive save/load.
- Revalidate mod state after loading.
- Recreate transient UI only when needed.
- Remove stale UI on disable/load transitions.
- Avoid persisting editor-only or runtime-only state unless necessary.
- Version persistent state if its schema can change.
- Add debug logs around save/load-sensitive behavior.

## Load Order

Maintain explicit load-order discipline.

Rules:

- Keep configuration loaded before modules that read configuration.
- Keep debug logging loaded before modules that emit logs.
- Keep version information loaded from one canonical source.
- Keep domain modules loaded before the lifecycle controller if the lifecycle controller calls them.
- Keep integration modules loaded after the systems they integrate with, if required.
- Do not rely on accidental file loading order.
- Avoid circular dependencies.

When adding, renaming, or moving Lua files, update every project file that controls script loading, including metadata, manifest, mod definition, load-order tables, or equivalent project-specific load configuration.

## Integrations and Third-Party Code

Keep external, vendored, bundled, generated, or third-party code separate from mod-owned code.

If a bug involves external code:

- do not patch it casually;
- prefer a mod-owned integration layer;
- isolate compatibility code;
- log integration behavior behind debug flags;
- report whether external code was involved.

Preferred structure:

```text
Code/
  integrations/
    <prefix>_some_external_feature_integration.lua

Code/vendor/
  external_code/
```

## Runtime Validation

Validate assumptions when engine behavior is uncertain.

Validate:

- expected globals;
- expected functions;
- hook availability;
- hook registration state;
- UI object state;
- mod active/inactive state;
- feature flag state;
- vanilla restoration state;
- save/load state;
- integration availability.

Log validation failures behind explicit boolean debug flags.

## Acceptance Criteria

Every feature or bug fix should have explicit acceptance criteria.

Use concrete criteria such as:

- feature can be enabled;
- feature can be disabled;
- enabling twice does not duplicate hooks, UI, timers, shortcuts, or state changes;
- disabling twice does not fail;
- vanilla behavior is restored after disable/exit;
- disabled feature flags prevent feature activation;
- debug logs appear only when the relevant explicit boolean debug flag is `true`;
- debug logs do not appear when the relevant explicit boolean debug flag is `false`;
- protected files remain unchanged;
- updated payload is copied to the correct local mod folder.

Do not claim the task is complete unless the acceptance criteria were satisfied or clearly reported as untested.

## Manual Verification

After implementation, provide concrete manual in-game verification steps.

Useful checks include:

- start a new map;
- load an existing save;
- enable the mod feature;
- enable it again;
- verify no duplicate hooks, UI, shortcuts, timers, or logs;
- disable the mod feature;
- disable it again;
- verify vanilla behavior is restored;
- save and reload;
- verify no stale UI, hooks, shortcuts, timers, or mod-only behavior remains;
- test feature flags both `true` and `false`;
- test debug logs both enabled and disabled.

## Git Discipline

Use source control carefully.

Rules:

- Inspect changed files before summarizing.
- Do not include accidental generated files.
- Do not include local editor/cache files.
- Do not include backup files unless intentionally used by the project.
- Do not commit local deployment paths unless already part of the project design.
- Keep commits logically scoped when committing is requested.
- Do not claim that only certain files changed unless the working tree was actually inspected.

Useful checks:

```bat
git status
git diff --stat
git diff
```

## No Silent Generated Changes

Do not modify generated files, cache files, editor files, compiled files, or local deployment artifacts unless the task explicitly requires it.

Do not include accidental changes from:

```text
.vscode/
.cache/
tmp/
dist/
build/
*.bak
*.tmp
*.log
```

unless those files are intentionally part of the project.

## Asset Discipline

Treat assets as code-adjacent project files.

Rules:

- Do not overwrite original assets without need.
- Keep asset names clear and stable.
- Preserve required game formats.
- Preserve required dimensions, compression, and file size limits.
- Update references when asset filenames change.
- Deploy changed assets with the mod payload.
- Mention changed assets in the final summary.

## Destructive Command Safety

Use destructive commands carefully.

High-risk commands include:

```bat
del
rmdir
robocopy /MIR
git reset --hard
git clean
move
ren
powershell Remove-Item
```

Before using destructive commands:

- confirm the target path;
- confirm the source path;
- confirm protected files are not affected;
- confirm untracked user work will not be removed;
- prefer non-destructive commands when possible.

## Deployment

After code or asset modifications, deploy the updated mod payload to the configured local mod folder.

For Surviving Mars Relaunched on Windows, the deployment path is commonly:

```text
C:\Users\<USER>\AppData\Roaming\Surviving Mars Relaunched\Mods\<MOD_FOLDER>
```

Use the actual project-specific path.

If using `robocopy /MIR`, treat it as destructive. Use it only after verifying:

- the source is exactly the intended mod payload folder;
- the destination is exactly the intended mod deployment folder;
- protected files were not modified;
- no unrelated files exist only in the destination.

If deployment fails, report the exact failure.

## Review Checklist

Before finalizing, check:

- relevant files were inspected before editing;
- changes are scoped;
- no protected source files were modified;
- no unrelated files were reformatted;
- no accidental generated/cache/local files were included;
- version was updated when required;
- debug flags are explicit booleans;
- debug logs obey the relevant flags;
- no unconditional debug prints were added;
- no invented API is used without availability checks;
- configuration is centralized;
- behavior is idempotent;
- vanilla behavior is restored on disable/exit;
- load order is valid;
- new files are included in load-order metadata when required;
- deployment was performed or failure was reported;
- manual in-game verification steps were provided.

## Final Response Requirements

After making changes, report:

- files changed;
- files intentionally not changed;
- version written or updated;
- explicit boolean debug variable or variables used;
- major debug logs added;
- whether protected or third-party code was involved;
- confirmation that protected files were not edited;
- how the issue was fixed from mod-owned code;
- whether behavior changed;
- what was tested;
- what was not tested;
- what could not be tested;
- manual in-game checks the user should perform;
- whether the updated mod payload was copied to the configured local mod folder.

Do not claim that tests, deployment, validation, or in-game behavior succeeded unless they were actually run successfully.