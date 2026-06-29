# `layout/hyprland_adapter.lua`

## Purpose

`hyprland_adapter.lua` owns the boundary between Fit Scroller and the Hyprland
Lua custom layout API.

It is the only module that should know the shape of Hyprland objects such as
`ctx`, `target`, `target.window`, workspace objects and Hyprland area tables.

## Responsibilities

- expose `recalculate(ctx)`;
- expose `layout_msg(ctx, msg)`;
- safely handle `nil` or empty `ctx.targets`;
- safely handle missing `ctx.area`;
- convert Hyprland targets into normalized descriptors;
- resolve workspace state from `target.window.workspace`;
- resolve display configuration;
- synchronize target order;
- run the solver for structural changes;
- apply viewport offsets for focus-only changes;
- place each target using `target:place(area)`;
- focus targets through Hyprland's in-process Lua dispatcher;
- report command and integration errors as readable strings.

## Public API

### `recalculate(ctx)`

Recomputes and applies the current layout.

Expected behavior:

1. Read `ctx.targets`.
2. If there are no targets, commit an empty layout state and return without
   error.
3. Read `ctx.area`.
4. Resolve display configuration.
5. Synchronize target descriptors with workspace state.
6. Solve structural layouts when target order, target count or dimension modes
   changed.
7. Reuse `state.last_layout` for viewport-only updates.
8. Convert logical rectangles to Hyprland area tables.
9. Place every managed target.

### `layout_msg(ctx, msg)`

Handles layout messages sent through Hyprland's `layoutmsg` dispatcher.

Unsupported messages should return a readable string such as:

```text
fit-scroller: unsupported command: <command>
```

If `msg` is empty or missing, the error should still be readable:

```text
fit-scroller: expected command
```

## Runtime Checks

The adapter should keep these integration questions documented:

- Does returning `true` from `layout_msg` trigger `recalculate(ctx)`?
- What exact value is present in `ctx.area`?
- Can `target:place(area)` accept only Hyprland helper areas, or also plain Lua
  rectangle tables?
- Which fields are available on each `target` and `target.window`?
- Which window workspace fields are available for state keys?

Observed answers should be documented here and in
`references/hyprland-custom-layout-api.md`.

## Unknown Command Behavior

Unknown command handling gives keybindings a predictable failure mode and keeps
the `layoutmsg` dispatch path diagnosable.

Example:

```lua
local function parse_command(msg)
    return msg and msg:match("^(%S+)")
end

function M.layout_msg(ctx, msg)
    local command = parse_command(msg)

    if not command then
        return "fit-scroller: expected command"
    end

    return "fit-scroller: unsupported command: " .. command
end
```

## Failure Handling

`recalculate(ctx)` should fail softly where possible:

- no targets: return without error;
- missing `ctx.area`: return a readable diagnostic if Hyprland allows it, or
  skip placement and log during development;
- missing `target:place`: skip that target and log during development.

Last-valid-layout recovery belongs to the recovery flow described below.

## Guarantees

- With zero tiled windows, `recalculate(ctx)` returns without error.
- With one tiled window, the target is placed according to solver output.
- With multiple tiled windows, targets are placed in Fit Scroller logical order.
- Unsupported layout messages return readable errors.
- Observed Hyprland API behavior is documented.

## Target Normalization

The adapter keeps raw Hyprland object access out of core modules by producing
normalized target descriptors for state, command and solver modules.

### Target Descriptors

The adapter should convert each Hyprland target into:

```lua
TargetDescriptor = {
    id = "stable-window-id",
    target = <hyprland target>,
    active = true or false,
}
```

The descriptor is passed to `target_sync.lua`. Other core modules should not
read raw Hyprland target fields.

### Target Identity

Identity resolution should prefer fields in this order:

1. `target.window.stable_id`;
2. `target.window.address`;
3. `target.index` as a last-resort fallback.

`target.index` is not stable enough for persistent per-window state. If it is
used, the limitation must be documented and treated as a runtime integration
gap. `target.window.address` is available in the inspected Hyprland Lua bindings
and is more stable than the per-layout target index.

### Active Target

The adapter should set `active = true` when `target.window.active` is truthy.

If no active target is visible in `ctx.targets`, `target_sync.lua` will preserve
or clear focus according to its state rules.

### Workspace Key

The adapter should provide a workspace key to `state.lua`.

Resolution order:

1. `target.window.workspace.id`;
2. `target.window.workspace.config_name`;
3. `target.window.workspace.name`;
4. an explicit fallback key only when no target exposes a workspace.

Hyprland's Lua layout context does not expose `ctx.workspace`; the source builds
`ctx` from `area`, `targets` and layout helper functions only. Workspace
identity is exposed through `target.window.workspace` and through global query
helpers such as `hl.get_workspaces()` and `hl.get_workspace_windows(workspace)`.

The adapter must not use a single global key for normal workspace state. A
global key makes windows from the previous workspace appear removed when the
current `ctx.targets` changes, which deletes their forced dimension state during
target synchronization.

### Hyprland Binding Support

The verified Hyprland Lua bindings support these fields:

- target id prefers `target.window.stable_id`, then `target.window.address`,
  then a synthetic index-based id for smoke tests;
- active focus is read from `target.window.active`;
- workspace key is derived from `target.window.workspace`;
- display id probes common monitor/output fields, then falls back to
  `default`.

Index-based and global fallbacks are acceptable for local smoke tests only. They
are not correct for state persistence across workspace switches.

### Command Dispatch

`layout_msg(ctx, msg)` delegates supported command parsing to `commands.lua`.

Expected flow:

```text
layout_msg(ctx, msg)
    -> get workspace state
    -> commands.execute(workspace_state, config, msg)
    -> apply simple valid mutations
    -> return true when state changed
    -> return readable error string when command failed
```

Commands still do not place windows directly. Any resulting placement happens
through the next `recalculate(ctx)` call.

### Target Synchronization Context

When synchronizing targets, the adapter must pass the effective
`config.placement_priority` and `config.insert_mode` to `target_sync.lua`.

For `placement_priority = "spatial"`, `target_sync.lua` ignores
`insert_mode`, but the adapter still passes the normalized value so the sync
context is complete and mode-aware.

For `insert_mode = "view"`, the adapter is responsible for computing the last
currently visible target id before synchronization. It should use:

- `state.last_layout`;
- `state.viewport_offset`;
- the current scroll direction and viewport size.

`target_sync.lua` receives this as host-independent metadata and does not
inspect Hyprland geometry directly.

### Target Sync Guarantees

- Each live target is converted to a descriptor with an id.
- Workspace state is retrieved through a workspace key.
- Recalculation synchronizes target order before placement.
- Placement follows Fit Scroller logical order.
- `move previous` and `move next` visibly change placement order.
- `toggle dimension` updates state and is reflected by solver output.

## Solver Placement

The adapter applies solver-produced placements.

The adapter still owns all Hyprland object interaction. The solver must return
plain logical rectangles, and the adapter must convert those rectangles into
the shape accepted by `target:place(area)`.

### Recalculate Flow

Expected flow:

```text
structural recalculate(ctx)
    -> read display id
    -> resolve config for display
    -> collect target descriptors
    -> get workspace state
    -> synchronize targets
    -> call solver.solve(...) or spatial_solver.solve(...)
    -> validate complete layout output
    -> convert placements to Hyprland areas
    -> call target:place(area)
    -> store state.last_layout
    -> validate draft workspace state
    -> commit workspace state
```

The adapter must not call the solver for focus-only or viewport-only updates.
Those updates reuse `state.last_layout`.

For structural updates, the adapter selects the solver from
`config.placement_priority`:

- `order`: call `solver.solve(...)` without focus or viewport input;
- `spatial`: call `spatial_solver.solve(...)` with `last_layout`,
  `viewport_offset` and an explicit spatial event.

Hyprland may call `recalculate(ctx)` after a successful `layout_msg(ctx, msg)`,
including after viewport-only messages such as `follow`. The adapter must
therefore preserve the intent of the triggering message. If the pending intent
is viewport-only, the next placement pass must reuse `state.last_layout`
instead of calling `solver.solve(...)`.

Structural `layout_msg(ctx, msg)` commands use the same transaction boundary as
`recalculate(ctx)`: command mutation is applied to a draft state, the selected
solver is run, viewport and rectangle conversion are validated, all targets are
placeable, and only then is the draft committed. This prevents a failed spatial
move or dimension toggle from committing `dimension_mode_by_id`,
`pending_spatial_event`, `viewport_offset` or `last_layout`.

Before placement, the adapter validates that solver output is complete:

- every current target has a placement and dimension;
- no unknown placements or dimensions are present;
- all rectangles are finite and positive;
- `workspace_extent` is finite and non-negative.

### Applying Placements

The solver output is keyed by target id:

```lua
layout.placements_by_id[id] = rect
```

The adapter should:

1. iterate ordered target descriptors;
2. look up each descriptor's rectangle;
3. convert the rectangle to a Hyprland-compatible area;
4. call `descriptor.target:place(area)`.

Targets without a placement should not be silently ignored. During development,
that condition should produce a diagnostic because it indicates a solver or
sync bug.

### Rectangle Conversion

The core rectangle type is:

```lua
{ x = number, y = number, w = number, h = number }
```

The adapter must verify whether `target:place` accepts plain Lua tables or
requires objects created by Hyprland helpers.

The current implementation uses adapter-owned rectangle conversion:

- the solver returns normalized logical rectangles;
- the adapter expects `ctx.area` to expose numeric `x`, `y`, `w`/`width` and
  `h`/`height` fields;
- the adapter converts logical rectangles to rounded pixel rectangle tables;
- the adapter passes those tables to `target:place`.

If `ctx.area` does not expose numeric fields, the adapter returns a readable
error instead of falling back to a helper-based layout. This keeps the
unverified integration point visible and prevents solver behavior from being
silently bypassed.

Until verified, implementation should prefer the safest Hyprland-supported
path:

- use helper-produced areas when possible;
- keep all direct area construction in this adapter;
- do not expose Hyprland area objects to `geometry.lua` or `solver.lua`.

### Solver Errors

If the solver returns an error, the adapter should avoid applying partial
placements.

The adapter may return a readable error or keep the previous visible placement if
available. Partial application of invalid solver output must be avoided.

### Guarantees

- Recalculation calls the solver with normalized config, ordered targets and
  dimension modes.
- Solver output is the primary placement path.
- Solver rectangles are applied to the matching Hyprland targets.
- Adapter-specific rectangle conversion is isolated in this file.
- Solver errors do not produce partial placement updates.

## Hardening

The adapter connects logical focus commands and viewport offsets to Hyprland.

The adapter remains the only module allowed to:

- inspect Hyprland target objects;
- resolve a Fit Scroller target id to a Hyprland window selector;
- call a Hyprland focus mechanism;
- convert viewport-adjusted logical rectangles into Hyprland placement areas.

Hyprland `0.55.4` source inspection confirms that `target.window.address` is
available as `0x...`. The adapter should build an `address:` selector and use
the internal Lua API:

```lua
hl.dispatch(hl.dsp.focus({ window = "address:" .. descriptor.window.address }))
```

The adapter must not use `hyprctl`, `os.execute` or `io.popen` from
`layout_msg(ctx, msg)` or `recalculate(ctx)`.

## Focus Command Flow

Expected `layout_msg(ctx, msg)` flow for focus commands:

```text
layout_msg(ctx, "focus next")
    -> collect target descriptors
    -> get workspace state
    -> commands.execute(...) returns focus_target_id
    -> adapter focuses the Hyprland target for that id
    -> return true when focus was requested successfully
```

`commands.lua` chooses the logical target id. The adapter performs the
Hyprland-specific focus action.

If Hyprland focus control is unavailable from the custom layout environment in
a future version, the adapter must return a readable unsupported error and
leave state unchanged.

Recommended error:

```text
fit-scroller: focus commands are unsupported by the current Hyprland adapter
```

## Resolving Focus Targets

The adapter should keep a descriptor lookup table during command handling:

```lua
descriptors_by_id[id] = descriptor
```

To focus a target, prefer mechanisms in this order:

1. `descriptor.window.address` converted to `address:<address>` and passed to
   `hl.dsp.focus({ window = selector })`;
2. a future direct focus method exposed by the target or window object;
3. no implementation, with a readable unsupported-command error.

Using Hyprland's default `cyclenext` is not sufficient because Fit Scroller
focus commands follow Fit Scroller's logical order, not Hyprland's internal
focus order.

If no valid window address or direct focus method is available, focus commands
return a readable error such as:

```text
fit-scroller: focus commands are unsupported by the current Hyprland adapter
```

## Structural Flow With Viewport

Expected structural flow:

```text
structural event
    -> read display id
    -> resolve config for display
    -> collect target descriptors
    -> get workspace state
    -> synchronize targets and focused id
    -> call solver.solve(...)
    -> update state.last_layout
    -> optionally clamp state.viewport_offset to new workspace extent
    -> convert placements using viewport_offset
    -> call target:place(area)
```

If no target is focused, the adapter should clamp the existing offset against
the new workspace extent before placement.

## Focus/Viewport Flow

Expected focus-only flow:

```text
focus event
    -> collect target descriptors
    -> update state.focused_id from active target
    -> read state.last_layout
    -> find the focused placement
    -> call viewport.reveal(...)
    -> update state.viewport_offset
    -> reapply state.last_layout using viewport_offset
```

This flow must not call `solver.solve(...)`.

Recommended adapter-level state:

```lua
pending_workspace_action = {
    kind = "viewport_only",
    reason = "focus",
}
```

The exact representation may differ, but the adapter must be able to
distinguish structural placement from viewport-only placement.

## Applying Viewport Offset

The solver returns workspace coordinates. Hyprland placement needs visible
coordinates relative to the current viewport.

The adapter applies the viewport offset on the scroll axis before converting
rectangles to Hyprland areas.

Conceptually:

```lua
visible_rect = rect - offset_on_scroll_axis
target:place(to_hyprland_area(visible_rect))
```

The exact sign and axis should come from `traversal.lua` direction metadata.
The adapter should not duplicate direction-specific rules.

## Hidden And Partially Visible Windows

Fit Scroller owns every tiled target in the workspace, including targets
outside the current viewport.

Tests must verify how Hyprland expects off-viewport targets to be placed:

- placing them at their logical offscreen coordinates may be sufficient;
- clamping or hiding them may cause incorrect focus behavior;
- skipping `target:place` for hidden targets is risky and should be avoided
  unless Hyprland requires it.

Until verified, the adapter should apply a placement for every managed target.

## Focus Reveal Source

The adapter should reveal the focused id that Hyprland reports during
synchronization.

It should not reveal a pending focus id from a command unless Hyprland has
already made that target active. This keeps Fit Scroller aligned with the host
window manager when focus requests fail or are redirected.

When focus is changed by an external Hyprland dispatcher and no layout
recalculation is triggered automatically, users can send:

```text
layoutmsg reveal focus
```

The adapter treats this as a viewport synchronization request. It reads the
active target from the current `ctx.targets`, updates `state.focused_id`
through `target_sync.lua`, and reapplies `state.last_layout` with the viewport
offset needed to reveal that focused target.

In normal operation this command should be triggered automatically by
`init.lua` through `hl.on("window.active", ...)` when the active window belongs
to `lua:fit-scroller`.

## Runtime Checks

Tests must verify these integration points on the local Hyprland runtime:

- Does the `window.active` listener dispatch `follow` without recursion or
  noisy errors?
- Does `hl.dispatch(hl.dsp.focus({ window = "address:" .. descriptor.window.address }))`
  focus the target selected by Fit Scroller logical order?
- How does Hyprland behave when targets are placed outside `ctx.area`?

Observed answers should be documented here after testing.

## Guarantees

- `focus previous` and `focus next` use Hyprland's in-process Lua focus
  dispatcher.
- Focus commands follow Fit Scroller logical order.
- Focus changes trigger `follow` through `hl.on("window.active", ...)`.
- Focus-only changes do not call the solver.
- Recalculation reveals the Hyprland-reported focused window.
- All placements are adjusted by `state.viewport_offset`.
- The adapter still hides all Hyprland object details from core modules.

## Hardening

This section defines the integration boundary.

The adapter is responsible for turning core module errors into safe Hyprland
behavior. It should avoid crashes, avoid partial placement, preserve the last
valid layout where possible, and make remaining Hyprland API gaps explicit.

## Recalculation Recovery

Recoverable recalculation failures include:

- invalid display configuration;
- invalid target descriptors;
- solver errors;
- viewport errors;
- rectangle conversion errors;
- missing Hyprland placement capabilities.
- incompatible `last_layout` recovery state.

Recommended recovery flow:

```text
recalculate(ctx)
    -> build inputs
    -> if input validation fails, apply last_layout when possible
    -> decide whether this pass is structural or viewport-only
    -> for structural pass, solve layout
    -> if solve fails, apply last_layout when possible
    -> for viewport-only pass, reuse state.last_layout
    -> compute viewport
    -> if viewport fails, apply last_layout when possible
    -> convert every placement
    -> if conversion fails, apply last_layout when possible
    -> place every target
    -> update state.last_layout only after success
```

If no `last_layout` exists, the adapter should fail softly and log a readable
diagnostic.

## No Partial Placement

Before calling `target:place(area)`, the adapter should prepare every placement
area.

Recommended sequence:

1. compute the core layout;
2. compute viewport offset;
3. build a complete `areas_by_id` table;
4. verify every ordered descriptor has an area;
5. only then call `target:place(area)` for every target.

This avoids moving half the workspace before discovering that one rectangle
cannot be converted.

The same rule applies when reusing `last_layout`: every visible area must be
prepared before any `target:place(area)` call is made.

## Applying `last_layout`

When applying `last_layout`, the adapter must verify that it is compatible
with the current live targets.

Safe use cases:

- same target ids are still present;
- a subset of target ids is present and missing ids can be ignored without
  corrupting placement;
- the display area is still compatible enough to reuse the layout for one
  frame.

Unsafe use cases:

- target ids changed completely;
- target identity fallback is unstable;
- required Hyprland area conversion is unavailable.

If compatibility is uncertain, prefer logging the error and skipping placement
over applying a misleading stale layout.

## Structural vs Viewport-Only Flow

The adapter must preserve this flow separation:

- structural changes call the solver, then update the viewport if needed;
- focus changes and `follow` reuse `state.last_layout` and update only the
  viewport offset;
- opening a window may produce both a structural change and a focus change, so
  the adapter must solve first, then reveal using the new layout;
- no focus-only path may pass focus or viewport data into the solver.

Tests should instrument a mocked solver and verify call counts for structural
and viewport-only paths.

## Insert Mode `view`

For `insert_mode = "view"`, the adapter is responsible for computing
`last_visible_id` from:

- `state.last_layout`;
- `state.viewport_offset`;
- effective `scroll_direction`;
- the normalized viewport size.

If no compatible `last_layout` exists, the adapter passes no visible anchor
and `target_sync.lua` falls back to `last`.

## Command Recovery

`layout_msg(ctx, msg)` should use the same validate-then-commit principle as
core commands.

For state mutations:

- parse and validate the command first;
- create a draft workspace state;
- apply the command mutation to the draft;
- run the same layout validation path used by recalculation when the mutation
  can fail in the solver;
- commit the draft only after success;
- return an error without committing when validation fails.

For commands that require Hyprland integration:

- parse and validate the command first;
- resolve the target id;
- read `descriptor.window.address`;
- build `address:<descriptor.window.address>`;
- request focus with `hl.dispatch(hl.dsp.focus({ window = selector }))`;
- return success only if the request was accepted.

Unsupported integration should return a readable error and should not mutate
state.

## Diagnostics

The adapter should prefix all user-visible errors with `fit-scroller:`.

Useful diagnostics:

- display id;
- workspace key;
- command message;
- target id;
- module that produced the error;
- whether `last_layout` was used.

Examples:

```text
fit-scroller: invalid config for display DP-1: allowed_dimensions[2].w must be > 0 and <= 1
fit-scroller: solver failed for workspace 3: forced dimension 1.0x1.0 does not fit target B
fit-scroller: focus commands are unsupported by the current Hyprland adapter
fit-scroller: recovered with last valid layout after viewport error
```

## Integration Gap Documentation

Before release, unresolved Hyprland behavior must be documented in this
file with one of these statuses:

- `resolved`;
- `unsupported in Hyprland 0.55`;
- `unverified`;
- `requires implementation decision`.

The important gaps are:

- focus control from a custom Lua layout;
- stable window address or selector;
- workspace key source;
- display id source;
- exact `ctx.area` semantics;
- exact `target:place(area)` accepted shape;
- off-viewport target placement behavior;
- whether `layout_msg` success triggers recalculation.

## Test Cases

Adapter tests can use mocked `ctx` and `target` objects.

They should cover:

- invalid config uses `last_layout` when compatible;
- solver error uses `last_layout` when compatible;
- viewport error uses `last_layout` when compatible;
- no `last_layout` produces a readable diagnostic;
- `last_layout` is updated only after all placements have been prepared and
  applied;
- rectangle conversion prepares all areas before placement;
- missing placement for a target prevents partial placement;
- structural recalculation calls the solver;
- focus-only recalculation does not call the solver;
- focus-only recalculation reapplies `last_layout` translated by
  `viewport_offset`;
- opening a new focused window solves first and then reveals it;
- `insert_mode = "view"` passes the last fully visible id to `target_sync.lua`;
- unsupported focus integration returns a readable error;
- command success returns the value Hyprland needs to recalculate;
- target placement is called for every managed target.

Runtime checks on real Hyprland `0.55` should separately verify the API gaps
listed above.

## Guarantees

- Recoverable failures preserve or reuse the last valid layout when safe.
- `last_layout` updates only after complete successful placement.
- Partial placement is avoided.
- Structural and viewport-only flows remain separate.
- `insert_mode = "view"` uses adapter-computed visible-anchor metadata.
- User-visible errors are readable and prefixed with `fit-scroller:`.
- Unsupported Hyprland integration gaps are documented with a status.
- Mocked adapter tests cover recovery and command error paths.
