# Fit Scroller Architecture

## Status

This document describes the first software architecture for Fit Scroller V1.

Fit Scroller is implemented for Hyprland as a custom layout. The V1
implementation targets Hyprland `0.55`.

It is derived from [SPECIFICATION.md](SPECIFICATION.md) and from the local
Hyprland layout examples stored in
`../references/local/hyprland-layout-examples/`.

The architecture assumes the Lua custom layout API demonstrated by the local
examples:

- `hl.layout.register(name, layout)`;
- `layout.recalculate(ctx)`;
- `layout.layout_msg(ctx, msg)`;
- `ctx.targets`;
- `ctx.area`;
- `target:place(area)`.

Any Hyprland-specific behavior not represented in these examples must stay
behind the Hyprland adapter so the core layout algorithm remains testable.

## Architectural Goals

The implementation must:

- keep Fit Scroller's product rules independent from Hyprland API details;
- keep persistent layout state explicit and synchronized with live windows;
- make layout computation deterministic;
- make command handling small and predictable;
- allow the geometry solver to evolve without rewriting the Hyprland adapter;
- support focused tests for state synchronization, command behavior and layout
  selection.

## Proposed File Structure

```text
layout/
    init.lua
    config.lua
    state.lua
    target_sync.lua
    commands.lua
    geometry.lua
    traversal.lua
    solver.lua
    viewport.lua
    hyprland_adapter.lua
```

For V1 this can still be shipped as a small Lua layout. The split above is a
logical architecture; files may be merged temporarily during early
implementation if Hyprland loading constraints require it.

## Runtime Overview

Fit Scroller runs through two entry points exposed to Hyprland.

### Recalculate Flow

```text
Hyprland recalculate(ctx)
    -> adapter extracts live targets and viewport area
    -> config is loaded and validated
    -> workspace state is synchronized with live targets
    -> solver computes desired logical layout
    -> viewport is adjusted to reveal focused window
    -> adapter converts logical rectangles to Hyprland areas
    -> target:place(area) is called for each visible or managed target
```

### Command Flow

```text
Hyprland layout_msg(ctx, msg)
    -> adapter parses raw message
    -> command module validates command
    -> command module produces a mutation plan or focus request
    -> adapter validates recoverable mutations before commit when needed
    -> state is committed only after validation succeeds
    -> recalculation is requested by returning success to Hyprland
```

Commands must not directly place windows. Placement is owned by the
recalculation flow.

Commands that cannot make the layout invalid, such as boundary no-ops, may
return immediately. Commands that may affect solver validity, such as
`toggle dimension`, should be applied through a draft workspace state and
committed only after the adapter confirms that recalculation can produce a
valid layout.

## Modules

### [`init.lua`](layout/init.md)

Registers the layout with Hyprland.

Responsibilities:

- call `hl.layout.register("fit-scroller", layout)`;
- expose `recalculate(ctx)`;
- expose `layout_msg(ctx, msg)`;
- delegate all substantial work to the adapter and core modules.

This file should stay thin.

### [`hyprland_adapter.lua`](layout/hyprland_adapter.md)

Owns all direct interaction with the Hyprland Lua layout API.

Responsibilities:

- read `ctx.targets` and `ctx.area`;
- identify the active target using `target.window.active` when available;
- build stable target ids using `target.window.stable_id` when available;
- call `target:place(area)`;
- translate core rectangles into Hyprland-compatible areas;
- surface command errors as layout message return strings.

The adapter is allowed to know about Hyprland object shapes. Core modules are
not.

Open integration risk:

- the local examples do not show how to programmatically change focus. If the
  API exposes such a method, `focus previous` and `focus next` should use it
  through this adapter. If it does not, those commands will need to return a
  clear unsupported-command error until a valid Hyprland focus mechanism is
  identified.

### [`config.lua`](layout/config.md)

Loads and validates display configuration.

Responsibilities:

- resolve configuration for the current display;
- provide `allowed_dimensions`;
- provide `scroll_direction`;
- support display-specific overrides;
- reject invalid dimensions;
- reject duplicate dimensions;
- normalize dimensions into a canonical representation;
- expose the `toggle dimension` cycle order.

`allowed_dimensions` must behave as a set for layout selection. Its file order
must not influence layout ranking.

The toggle cycle is derived from dimensions sorted by:

1. largest logical area first;
2. widest first when areas are equal;
3. tallest first when width is equal.

### [`state.lua`](layout/state.md)

Stores mutable workspace state.

State per workspace:

- `order`: ordered list of target ids;
- `dimension_mode_by_id`: `auto` or forced dimension key;
- `focused_id`: last known focused target id;
- `viewport_offset`: current scroll offset;
- `last_layout`: last valid computed layout, used for failure recovery.

Responsibilities:

- create workspace state lazily;
- remove state for closed windows;
- preserve forced dimensions while a window exists;
- discard forced dimensions when a window disappears;
- provide safe accessors for commands and solver input.

State must be keyed by workspace if the Hyprland API exposes a stable workspace
identifier. If not, V1 should use the best available context identifier and
document the limitation in the implementation.

### [`target_sync.lua`](layout/target_sync.md)

Synchronizes live Hyprland targets with `state.order`.

Responsibilities:

- collect currently present target ids;
- remove ids that no longer exist;
- insert new ids immediately after the focused id;
- append new ids when no focused id exists;
- preserve the relative order of existing ids;
- return an ordered target list for the solver.

This module follows the pattern demonstrated by `manual.lua`, but must also
clean `dimension_mode_by_id` when windows disappear.

### [`commands.lua`](layout/commands.md)

Parses and executes V1 commands.

Supported commands:

- `move previous`;
- `move next`;
- `focus previous`;
- `focus next`;
- `toggle dimension`.

Responsibilities:

- parse raw command strings;
- reject unknown commands with a readable error;
- swap the focused id with its predecessor or successor for move commands;
- request focus changes through the adapter for focus commands;
- cycle dimension mode for `toggle dimension`;
- return whether recalculation is required.

Command behavior:

- missing predecessor or successor is a no-op;
- commands that mutate order or dimension mode require recalculation;
- focus commands require viewport reveal after focus changes.

### [`geometry.lua`](layout/geometry.md)

Provides host-independent geometry primitives.

Core types:

```lua
Rect = {
    x = number,
    y = number,
    w = number,
    h = number,
}

Dimension = {
    w = number,
    h = number,
}
```

Responsibilities:

- compute logical areas;
- compare dimensions by area, width and height;
- check overlap;
- check containment;
- convert viewport fractions to logical rectangles;
- perform deterministic rounding at adapter boundaries.

Geometry uses logical coordinates first. Pixel conversion should happen as late
as possible, ideally in the adapter.

### [`traversal.lua`](layout/traversal.md)

Implements direction-dependent ordering.

Responsibilities:

- define traversal for `right`, `left`, `down` and `up`;
- map logical positions to physical rectangles;
- mirror or rotate placement based on `scroll_direction`;
- expose comparison helpers for canonical position order.

V1 traversal rules:

- `right`: left to right, then top to bottom, then overflow to the right;
- `left`: right to left, then top to bottom, then overflow to the left;
- `down`: top to bottom, then left to right, then overflow downward;
- `up`: bottom to top, then left to right, then overflow upward.

### [`solver.lua`](layout/solver.md)

Computes the best layout candidate.

Inputs:

- validated configuration;
- ordered targets;
- dimension modes;
- focused id;
- viewport rectangle;
- current viewport offset.

Output:

```lua
Layout = {
    placements_by_id = {
        [id] = Rect,
    },
    dimensions_by_id = {
        [id] = Dimension,
    },
    workspace_extent = number,
    viewport_offset = number,
}
```

Responsibilities:

- honor forced dimensions before assigning auto dimensions;
- generate candidate placements using only allowed dimensions;
- preserve logical window order using traversal rules;
- ensure windows do not overlap;
- allow overflow only on the scroll axis;
- rank candidates according to the spec;
- return a deterministic best candidate.

Candidate ranking:

1. highest number of fully visible windows in the viewport containing the
   focused window;
2. largest minimum visible window area;
3. smallest workspace extent along the scroll axis;
4. stable canonical position order.

Recommended V1 strategy:

- normalize all directions to a canonical `right` layout problem;
- generate candidate rows or columns using allowed dimensions;
- pack windows in logical order;
- evaluate visibility and extent;
- transform the selected canonical layout back to the configured direction.

This keeps direction handling separate from packing complexity.

### [`viewport.lua`](layout/viewport.md)

Computes and clamps viewport offset.

Responsibilities:

- reveal the focused window by the smallest required offset change;
- keep the offset unchanged when the focused window is already fully visible;
- clamp offset between `0` and maximum workspace overflow;
- reduce offset after removals when trailing empty workspace would be visible.

Manual scrolling is intentionally absent from V1.

## Data Flow Details

### Target Identity

Target identity should prefer `target.window.stable_id`, following the local
`manual.lua` example. If unavailable, the adapter may fall back to
`target.index`, but this fallback is weaker and should be treated as an
integration limitation.

### Window Insertion

New targets are inserted after the currently focused target. The insertion
logic belongs to `target_sync.lua`, not to the solver.

The solver must only consume the resulting order.

### Forced Dimensions

Forced dimensions are stored in `state.dimension_mode_by_id`.

`toggle dimension` cycles:

```text
auto -> largest forced dimension -> ... -> smallest forced dimension -> auto
```

When a forced dimension fits on the cross axis, the solver must preserve it and
push other windows into scroll-axis regions when needed.

If a forced dimension cannot fit on the cross axis, the command must fail and
the previous valid state must be preserved.

### Focus

The active target should be read from Hyprland during synchronization. The
current active id updates `state.focused_id`.

For `focus previous` and `focus next`, the command module determines the target
id. The adapter is responsible for performing the actual focus change if
Hyprland exposes an API for it.

After focus changes, recalculation must reveal the focused window.

## Error Handling

Recoverable failures should preserve `state.last_layout`.

Examples:

- invalid configuration;
- forced dimension cannot fit on the cross axis;
- incomplete target geometry from Hyprland;
- unsupported integration command.

Unknown user commands should return a readable error string from `layout_msg`.

Invalid state transitions should not partially mutate state. Commands should
validate first, then commit. When command validity depends on layout
computation, the adapter should evaluate the command against a draft workspace
state and commit only after the solver and viewport succeed.

## Testing Strategy

The core modules should be testable without Hyprland.

Recommended test layers:

- `config` tests for validation and toggle cycle ordering;
- `target_sync` tests for insertion, removal and order preservation;
- `commands` tests for move and toggle behavior;
- `traversal` tests for each direction;
- `viewport` tests for reveal and clamping;
- `solver` tests for candidate ranking and forced dimensions;
- adapter smoke tests using mocked `ctx` and `target:place`.

The Hyprland adapter should be kept thin enough that most behavior can be
verified with plain Lua tests.

## Implementation Phases

### Phase 1: Integration Skeleton

- register the `fit-scroller` layout
  ([`init.lua`](layout/init.md));
- read targets and area
  ([`hyprland_adapter.lua`](layout/hyprland_adapter.md));
- place all windows using a trivial deterministic layout
  ([`hyprland_adapter.lua`](layout/hyprland_adapter.md));
- support unknown command errors
  ([`hyprland_adapter.lua`](layout/hyprland_adapter.md)).

### Phase 2: State and Commands

- implement target identity
  ([`hyprland_adapter.lua`](layout/hyprland_adapter.md),
  [`state.lua`](layout/state.md));
- synchronize order
  ([`target_sync.lua`](layout/target_sync.md));
- implement `move previous` and `move next`
  ([`commands.lua`](layout/commands.md));
- implement `toggle dimension`
  ([`commands.lua`](layout/commands.md),
  [`config.lua`](layout/config.md));
- store forced dimensions for window lifetime
  ([`state.lua`](layout/state.md)).

### Phase 3: Geometry and Solver

- implement dimensions and rectangles
  ([`geometry.lua`](layout/geometry.md));
- implement direction traversal
  ([`traversal.lua`](layout/traversal.md));
- implement candidate generation
  ([`solver.lua`](layout/solver.md));
- implement candidate ranking
  ([`solver.lua`](layout/solver.md));
- apply selected placements
  ([`solver.lua`](layout/solver.md),
  [`hyprland_adapter.lua`](layout/hyprland_adapter.md)).

### Phase 4: Focus and Viewport

- implement `focus previous` and `focus next` if Hyprland focus control is
  available
  ([`commands.lua`](layout/commands.md),
  [`hyprland_adapter.lua`](layout/hyprland_adapter.md));
- implement focus reveal
  ([`viewport.lua`](layout/viewport.md));
- implement viewport offset clamping after removals
  ([`viewport.lua`](layout/viewport.md)).

### Phase 5: Hardening

- validate configuration errors
  ([`config.lua`](layout/config.md),
  [`hyprland_adapter.lua`](layout/hyprland_adapter.md));
- preserve last valid layout on recoverable failures
  ([`state.lua`](layout/state.md),
  [`hyprland_adapter.lua`](layout/hyprland_adapter.md));
- harden solver and viewport invalid-input behavior
  ([`solver.lua`](layout/solver.md),
  [`viewport.lua`](layout/viewport.md));
- add tests around edge cases
  ([`config.lua`](layout/config.md),
  [`target_sync.lua`](layout/target_sync.md),
  [`commands.lua`](layout/commands.md),
  [`geometry.lua`](layout/geometry.md),
  [`traversal.lua`](layout/traversal.md),
  [`solver.lua`](layout/solver.md),
  [`viewport.lua`](layout/viewport.md));
- document unsupported Hyprland API gaps if any remain
  ([`hyprland_adapter.lua`](layout/hyprland_adapter.md)).

## Integration Questions

This section tracks Hyprland integration details that affect the adapter.

### Focus changes

Status: partially resolved.

The Hyprland dispatcher list documents several focus-related dispatchers:

- `focuswindow`, which focuses the first window matching a window selector;
- `cyclenext`, which focuses the next or previous window on a workspace;
- `movefocus`, which moves focus in a spatial direction.

Fit Scroller needs logical focus by its own window order, not Hyprland's
default spatial or historical order. The preferred implementation is therefore:

1. resolve the target id selected by `focus previous` or `focus next`;
2. obtain a Hyprland window selector for that target, ideally an address;
3. call Hyprland focus through the adapter.

The local Lua examples show `target.window.stable_id` and `target.window.active`
but do not show a focus method or a window address field. The adapter must
verify whether a target exposes a usable address or direct focus method.

If no focus API is available to Lua custom layouts, `focus previous` and
`focus next` must remain unsupported in the adapter until a valid Hyprland
mechanism is identified.

Sources:

- <https://wiki.hypr.land/Configuring/Dispatchers/>

### `layout_msg` recalculation behavior

Status: unresolved, requires runtime verification.

The Hyprland wiki documents layout-specific messages through the `layoutmsg`
dispatcher on built-in layouts such as `scrolling`.

The local Lua examples implement `layout_msg(ctx, msg)` and return `true` after
state changes. They do not prove whether returning `true` automatically causes
Hyprland to call `recalculate(ctx)`.

Implementation requirement:

- add a smoke test or manual runtime check that sends a layout message and
  verifies whether `recalculate(ctx)` is called automatically;
- if not, the adapter must explicitly request or force recomputation using the
  mechanism provided by Hyprland 0.55.

Sources:

- <https://wiki.hypr.land/Configuring/Scrolling-Layout/>
- `../references/local/hyprland-layout-examples/manual.lua`
- `../references/local/hyprland-layout-examples/spiral.lua`

### `ctx.area` semantics

Status: unresolved, requires runtime verification.

Hyprland documents global gap and border settings such as `general:gaps_in`,
`general:gaps_out` and `general:border_size`. The local Lua examples use
`ctx.area` directly, but neither the wiki nor the examples state whether
`ctx.area` already excludes:

- monitor reserved areas;
- outer gaps;
- workspace gaps;
- border space.

Implementation requirement:

- treat `ctx.area` as the adapter's input viewport;
- measure it at runtime against monitor dimensions and configured gaps;
- document the observed Hyprland 0.55 behavior in `docs/layout/hyprland_adapter.md`;
- keep gap and border accounting isolated in the adapter and geometry modules.

Sources:

- <https://wiki.hypr.land/Configuring/Variables/>
- <https://wiki.hypr.land/Configuring/Monitors/>

### `target:place(area)` shape

Status: partially resolved from local examples, not officially documented in
the wiki sources found.

The local examples pass areas returned by Hyprland helpers directly to
`target:place(area)`:

- `ctx:column(i, n)`;
- `ctx:grid_cell(i, cols)`;
- `ctx:split(area, side, ratio)`;
- `ctx.area`.

This implies that `target:place` expects a Hyprland area object compatible with
those helpers. It does not prove whether a plain Lua rectangle table can be
passed directly.

Implementation requirement:

- keep core geometry in host-independent `Rect` values;
- convert `Rect` values to the exact Hyprland area shape in
  `hyprland_adapter.lua`;
- verify during Phase 1 whether direct tables are accepted or whether all areas
  must be produced through Hyprland helper methods.

Sources:

- `../references/local/hyprland-layout-examples/columns.lua`
- `../references/local/hyprland-layout-examples/grid.lua`
- `../references/local/hyprland-layout-examples/manual.lua`
- `../references/local/hyprland-layout-examples/spiral.lua`

### Workspace identity in `ctx`

Status: unresolved, requires runtime verification.

Hyprland exposes workspace information through `hyprctl workspaces`,
`hyprctl activeworkspace` and IPC workspace events. The wiki does not show
whether the Lua custom layout `ctx` exposes a stable workspace id.

Implementation requirement:

- first look for a stable workspace identifier on `ctx`;
- if unavailable, key state by the best available combination of monitor and
  workspace name/id exposed to the layout;
- document the chosen key in `docs/layout/state.md`;
- avoid using global state that mixes independent workspaces.

Sources:

- <https://wiki.hypr.land/Configuring/Using-hyprctl/>
- <https://wiki.hypr.land/IPC/>
