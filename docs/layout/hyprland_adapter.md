# `layout/hyprland_adapter.lua`

## Phase

Phase 1: Integration Skeleton.

## Purpose

`hyprland_adapter.lua` owns the boundary between Fit Scroller and the Hyprland
Lua custom layout API.

In Phase 1, it provides the smallest useful implementation:

- read the live targets from `ctx.targets`;
- read the available area from `ctx.area`;
- place all windows using a trivial deterministic layout;
- return readable errors for unsupported layout messages.

The adapter is the only Phase 1 module that should know the shape of Hyprland
objects such as `ctx`, `target`, `target.window`, and Hyprland area objects.

## Responsibilities

In Phase 1, the adapter must:

- expose `recalculate(ctx)`;
- expose `layout_msg(ctx, msg)`;
- safely handle `nil` or empty `ctx.targets`;
- safely handle missing `ctx.area`;
- place each target using `target:place(area)`;
- use Hyprland-provided area helpers where possible;
- report unsupported messages as strings.

It must not yet:

- preserve window order across recalculations;
- compute target ids;
- store workspace state;
- implement Fit Scroller commands;
- implement forced dimensions;
- implement scrolling or viewport offset;
- implement the final solver.

## Public API

### `recalculate(ctx)`

Recomputes and applies the temporary Phase 1 layout.

Expected behavior:

1. Read `ctx.targets`.
2. If there are no targets, return without error.
3. Read `ctx.area`.
4. Place each target in a deterministic temporary layout.

Phase 1 may use a simple columns layout:

```lua
for i, target in ipairs(ctx.targets) do
    target:place(ctx:column(i, #ctx.targets))
end
```

This mirrors the local `columns.lua` example and avoids custom rectangle
conversion before the `target:place(area)` shape is verified.

### `layout_msg(ctx, msg)`

Handles layout messages sent through Hyprland's `layoutmsg` dispatcher.

In Phase 1, no messages are supported. The function should return a readable
string such as:

```text
fit-scroller: unsupported command: <command>
```

If `msg` is empty or missing, the error should still be readable:

```text
fit-scroller: expected command
```

## Temporary Layout

The Phase 1 layout is intentionally not Fit Scroller's final layout.

Its purpose is only to verify that:

- the custom layout is registered correctly;
- `ctx.targets` is readable;
- `ctx.area` is available;
- `target:place(area)` works;
- layout messages reach `layout_msg(ctx, msg)`.

The recommended temporary placement is equal columns because Hyprland's local
examples show `ctx:column(i, n)` being passed directly to `target:place(area)`.

## Runtime Checks To Perform In Phase 1

Phase 1 should answer or narrow these integration questions:

- Does returning `true` from `layout_msg` trigger `recalculate(ctx)`?
- What exact value is present in `ctx.area`?
- Can `target:place(area)` accept only Hyprland helper areas, or also plain Lua
  rectangle tables?
- Which fields are available on each `target` and `target.window`?
- Is workspace identity available from `ctx`?

These checks should be documented here once observed on Hyprland `0.55`.

## Unknown Command Behavior

Unknown command handling should be implemented before real commands.

This gives keybindings a predictable failure mode and confirms that the
`layoutmsg` dispatch path reaches the custom layout.

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

The final last-valid-layout recovery described in the architecture belongs to
later phases. Phase 1 only needs to avoid crashing during basic Hyprland use.

## Phase 1 Acceptance Criteria

- With zero tiled windows, `recalculate(ctx)` returns without error.
- With one tiled window, the target is placed in the full available area.
- With multiple tiled windows, targets are placed in deterministic equal
  columns.
- Sending any layout message returns a readable unsupported-command error.
- The implementation records enough observed API behavior to update this file
  before Phase 2 starts.

## Phase 2 Additions

Phase 2 keeps the adapter as the only module that reads raw Hyprland objects,
but it starts producing normalized target descriptors for state and command
modules.

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
2. a verified Hyprland window address field, if exposed;
3. `target.index` as a temporary fallback.

`target.index` is not stable enough for final behavior. If it is used during
early implementation, the limitation must be documented and treated as a
runtime integration gap.

### Active Target

The adapter should set `active = true` when `target.window.active` is truthy.

If no active target is visible in `ctx.targets`, `target_sync.lua` will preserve
or clear focus according to its state rules.

### Workspace Key

The adapter should provide a workspace key to `state.lua`.

Resolution order:

1. a verified workspace id from `ctx`, if available;
2. a verified workspace name from `ctx`, if available;
3. a temporary global key during early implementation.

The chosen key must be documented once Hyprland `0.55` runtime behavior is
observed.

### Command Dispatch

In Phase 2, `layout_msg(ctx, msg)` delegates supported command parsing to
`commands.lua`.

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

### Temporary Placement With Logical Order

The final solver is not implemented in Phase 2.

However, once `target_sync.lua` returns targets in logical order, the temporary
columns layout should use that order instead of raw `ctx.targets` order. This
allows `move previous` and `move next` to be visibly tested before the solver
exists.

### Phase 2 Acceptance Criteria

- Each live target is converted to a descriptor with an id.
- Workspace state is retrieved through a workspace key.
- Recalculation synchronizes target order before placement.
- Temporary placement follows Fit Scroller logical order.
- `move previous` and `move next` visibly change temporary placement order.
- `toggle dimension` updates state even though geometry does not yet reflect
  forced dimensions.

## Phase 3 Additions

Phase 3 replaces the temporary columns placement with solver-produced
placements.

The adapter still owns all Hyprland object interaction. The solver must return
plain logical rectangles, and the adapter must convert those rectangles into
the shape accepted by `target:place(area)`.

### Recalculate Flow

Expected Phase 3 flow:

```text
recalculate(ctx)
    -> read display id
    -> resolve config for display
    -> collect target descriptors
    -> get workspace state
    -> synchronize targets
    -> call solver.solve(...)
    -> convert placements to Hyprland areas
    -> call target:place(area)
```

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

The exact Hyprland placement area shape is still an integration detail. Phase 3
must verify whether `target:place` accepts plain Lua tables or requires objects
created by Hyprland helpers.

Until verified, implementation should prefer the safest Hyprland-supported
path:

- use helper-produced areas when possible;
- keep all direct area construction in this adapter;
- do not expose Hyprland area objects to `geometry.lua` or `solver.lua`.

### Solver Errors

If the solver returns an error, the adapter should avoid applying partial
placements.

Phase 3 may return a readable error or keep the previous visible placement if
available. Full last-valid-layout recovery is hardened later, but partial
application of invalid solver output should be avoided from the start.

### Phase 3 Acceptance Criteria

- Recalculation calls the solver with normalized config, ordered targets and
  dimension modes.
- Temporary columns placement is no longer the primary placement path.
- Solver rectangles are applied to the matching Hyprland targets.
- Adapter-specific rectangle conversion is isolated in this file.
- Solver errors do not produce partial placement updates.

## Phase 4 Additions

Phase 4 connects logical focus commands and viewport offsets to Hyprland.

The adapter remains the only module allowed to:

- inspect Hyprland target objects;
- resolve a Fit Scroller target id to a Hyprland window selector;
- call a Hyprland focus mechanism;
- convert viewport-adjusted logical rectangles into Hyprland placement areas.

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

If Hyprland focus control is unavailable from the custom layout environment,
the adapter must return a readable unsupported error and leave state unchanged.

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

1. a direct focus method exposed by the target or window object;
2. a Hyprland dispatcher callable from Lua with a stable window address;
3. no implementation, with a readable unsupported-command error.

Using Hyprland's default `cyclenext` is not sufficient because Fit Scroller
focus commands follow Fit Scroller's logical order, not Hyprland's internal
focus order.

## Recalculate Flow With Viewport

Expected Phase 4 recalculation:

```text
recalculate(ctx)
    -> read display id
    -> resolve config for display
    -> collect target descriptors
    -> get workspace state
    -> synchronize targets and focused id
    -> call solver.solve(...)
    -> find the focused placement
    -> call viewport.reveal(...)
    -> update state.viewport_offset
    -> convert placements using viewport_offset
    -> call target:place(area)
```

If no target is focused, the adapter should still clamp the existing offset
against the new workspace extent before placement.

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

Phase 4 must verify how Hyprland expects off-viewport targets to be placed:

- placing them at their logical offscreen coordinates may be sufficient;
- clamping or hiding them may cause incorrect focus behavior;
- skipping `target:place` for hidden targets is risky and should be avoided
  unless Hyprland requires it.

Until verified, the adapter should apply a placement for every managed target.

## Focus Reveal Source

The adapter should reveal the focused id that Hyprland reports during
`recalculate(ctx)`.

It should not reveal a pending focus id from a command unless Hyprland has
already made that target active. This keeps Fit Scroller aligned with the host
window manager when focus requests fail or are redirected.

## Phase 4 Runtime Checks

Phase 4 should answer these integration questions on Hyprland `0.55`:

- Is there a direct focus method on `target` or `target.window`?
- Is a stable window address available on `target.window`?
- Can the custom layout call a Hyprland dispatcher from Lua?
- Does returning `true` from `layout_msg` after a focus command trigger a
  recalculation?
- How does Hyprland behave when targets are placed outside `ctx.area`?

Observed answers should be documented here after testing.

## Phase 4 Acceptance Criteria

- `focus previous` and `focus next` either work through Hyprland or fail with
  a clear unsupported error.
- Focus commands follow Fit Scroller logical order.
- Successful focus changes trigger recalculation.
- Recalculation reveals the Hyprland-reported focused window.
- All placements are adjusted by `state.viewport_offset`.
- The adapter still hides all Hyprland object details from core modules.

## Phase 5 Additions

Phase 5 hardens the integration boundary.

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

Recommended recovery flow:

```text
recalculate(ctx)
    -> build inputs
    -> if input validation fails, apply last_layout when possible
    -> solve layout
    -> if solve fails, apply last_layout when possible
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
- verify the Hyprland focus mechanism exists;
- request focus;
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

By the end of Phase 5, unresolved Hyprland behavior must be documented in this
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

## Phase 5 Test Cases

Adapter tests can use mocked `ctx` and `target` objects.

They should cover:

- invalid config uses `last_layout` when compatible;
- solver error uses `last_layout` when compatible;
- viewport error uses `last_layout` when compatible;
- no `last_layout` produces a readable diagnostic;
- rectangle conversion prepares all areas before placement;
- missing placement for a target prevents partial placement;
- unsupported focus integration returns a readable error;
- command success returns the value Hyprland needs to recalculate;
- target placement is called for every managed target.

Runtime checks on real Hyprland `0.55` should separately verify the API gaps
listed above.

## Phase 5 Acceptance Criteria

- Recoverable failures preserve or reuse the last valid layout when safe.
- `last_layout` updates only after complete successful placement.
- Partial placement is avoided.
- User-visible errors are readable and prefixed with `fit-scroller:`.
- Unsupported Hyprland integration gaps are documented with a status.
- Mocked adapter tests cover recovery and command error paths.
