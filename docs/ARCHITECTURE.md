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

The source-level Hyprland Lua API review is recorded in
`../references/hyprland-custom-layout-api.md`. It confirms additional
integration points used by Fit Scroller:

- `hl.on("window.active", callback)` for focus-change observation;
- `window.address` for building `address:<window.address>` focus selectors;
- `hl.dispatch(hl.dsp.focus({ window = selector }))` for focusing a specific
  window;
- automatic recalculation after successful `layout_msg(ctx, msg)`.

Any Hyprland-specific behavior must stay behind the Hyprland boundary so the
core layout algorithm remains testable.

## Architectural Goals

The implementation must:

- keep Fit Scroller's product rules independent from Hyprland API details;
- keep persistent layout state explicit and synchronized with live windows;
- make layout computation deterministic;
- make command handling small and predictable;
- allow the geometry solver to evolve without rewriting the Hyprland adapter;
- support focused tests for state synchronization, command behavior and layout
  selection.

## File Structure

```text
layout/
    init.lua
    config.lua
    state.lua
    target_sync.lua
    commands.lua
    geometry.lua
    spatial_geometry.lua
    spatial_focus.lua
    traversal.lua
    solver.lua
    spatial_solver.lua
    viewport.lua
    hyprland_adapter.lua
```

The implementation should load sibling modules relative to `layout/init.lua`,
not relative to Hyprland's configuration directory or Lua `package.path`.
Hyprland's import resolution may otherwise force users to install all modules
under a specific configuration path. The loader resolves the current
`init.lua` path and loads sibling modules from the same directory.

## Runtime Overview

Fit Scroller runs through two entry points exposed to Hyprland.

It also installs one global Hyprland Lua event listener during initialization.
This listener is integration glue, not core layout behavior.

### Focus Event Flow

```text
Hyprland window.active event
    -> init.lua checks that the active window uses lua:fit-scroller
    -> init.lua dispatches hl.dsp.layout("follow")
    -> Hyprland calls layout_msg(ctx, "follow")
    -> adapter synchronizes active target from ctx.targets
    -> viewport is adjusted during the following recalculation
```

This flow is required because Hyprland focus dispatchers can change active
focus without calling a custom layout's `recalculate(ctx)` immediately.

The event listener must not perform layout computation directly. It only asks
the current layout to run its normal `follow` command.

### Structural Layout Flow

```text
Hyprland structural event or structural command
    -> adapter extracts live targets and viewport area
    -> config is loaded and validated
    -> workspace state is synchronized with live targets
    -> solver computes desired logical layout
    -> state.last_layout is updated after successful computation
    -> adapter converts logical rectangles to Hyprland areas
    -> target:place(area) is called for each visible or managed target
```

Structural layout is triggered only by:

- target count changes;
- logical window order changes;
- dimension mode changes.

### Viewport Flow

```text
Hyprland focus event or future manual scroll command
    -> adapter reads state.last_layout
    -> viewport computes or updates viewport_offset
    -> adapter reapplies the existing logical layout with the new offset
```

Viewport changes must not invoke the solver.

When one user-visible action causes both a structural change and a focus
change, the structural layout flow runs first and the viewport flow runs after
it using the freshly computed `last_layout`.

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
structural layout and viewport flows.

Commands that cannot make the layout invalid, such as boundary no-ops, may
return immediately. Commands that may affect solver validity, such as
`toggle dimension`, should be applied through a draft workspace state and
committed only after the adapter confirms that recalculation can produce a
valid layout.

Focus commands are not structural commands. They request a Hyprland focus
change, then the viewport flow reveals the focused target using
`state.last_layout`.

## Modules

### [`init.lua`](layout/init.md)

Registers the layout with Hyprland.

Responsibilities:

- load sibling modules relative to `init.lua`;
- call `hl.layout.register("fit-scroller", layout)`;
- expose `recalculate(ctx)`;
- expose `layout_msg(ctx, msg)`;
- subscribe to Hyprland's `window.active` event and dispatch `follow` when the
  active window belongs to `lua:fit-scroller`;
- delegate all substantial work to the adapter and core modules.

This file should stay thin.

### [`hyprland_adapter.lua`](layout/hyprland_adapter.md)

Owns all direct interaction with the Hyprland Lua layout API.

Responsibilities:

- read `ctx.targets` and `ctx.area`;
- identify the active target using `target.window.active` when available;
- build stable target ids using `target.window.stable_id` when available;
- call `target:place(area)`;
- focus logical targets by building `address:<descriptor.window.address>` and
  calling `hl.dispatch(hl.dsp.focus({ window = selector }))`;
- translate core rectangles into Hyprland-compatible areas;
- surface command errors as layout message return strings.

The adapter is allowed to know about Hyprland object shapes. Core modules are
not.

The adapter must not invoke `hyprctl`, `os.execute` or `io.popen` from
`recalculate(ctx)` or `layout_msg(ctx, msg)`. All focus integration must use
Hyprland's in-process Lua API.

### [`config.lua`](layout/config.md)

Loads and validates display configuration.

Responsibilities:

- resolve configuration for the current display;
- provide `allowed_dimensions`;
- provide `scroll_direction`;
- provide `insert_mode`;
- provide `placement_priority`;
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

State must be keyed by workspace. Hyprland's Lua layout `ctx` does not expose
workspace identity directly, but `target.window.workspace` exposes a workspace
object with stable fields. The adapter should derive the state key from
`workspace.id`, then `workspace.config_name`, then `workspace.name`.

### [`target_sync.lua`](layout/target_sync.md)

Synchronizes live Hyprland targets with the workspace target list.

In order mode, that list is the user-visible logical order. In spatial mode,
the list is only a deterministic internal iteration list and does not define
placement semantics.

Responsibilities:

- collect currently present target ids;
- remove ids that no longer exist;
- insert new ids according to `config.insert_mode` in order mode;
- append new ids for deterministic iteration in spatial mode;
- preserve the relative order of existing ids;
- return an ordered target list for the solver.

This module follows the pattern demonstrated by `manual.lua`, but must also
clean `dimension_mode_by_id` when windows disappear.

### [`commands.lua`](layout/commands.md)

Parses and executes commands.

Supported commands:

- order mode: `move previous`, `move next`, `focus previous`,
  `focus next`;
- spatial mode: `move left`, `move right`, `move up`, `move down`,
  `focus left`, `focus right`, `focus up`, `focus down`;
- both modes: `toggle dimension`, `reveal focus`, `follow`.

Responsibilities:

- parse raw command strings;
- reject unknown commands with a readable error;
- swap the focused id with its predecessor or successor for order move
  commands;
- emit spatial events for spatial move commands;
- request focus changes through the adapter for focus commands;
- cycle dimension mode for `toggle dimension`;
- return whether recalculation is required.

Command behavior:

- missing predecessor or successor is a no-op;
- missing spatial target or candidate is a no-op when no progress is possible;
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

### [`spatial_geometry.lua`](layout/spatial_geometry.md)

Provides host-independent geometry helpers for spatial placement mode.

Responsibilities:

- validate normalized rectangles;
- compute scroll-axis and cross-axis intervals;
- compute visibility from `viewport_offset`;
- detect overlap and adjacency;
- compute movement and resize distances;
- detect directional progress.

This module does not place windows, read Hyprland objects or choose layout
candidates.

### [`spatial_focus.lua`](layout/spatial_focus.md)

Resolves spatial focus directions to target ids.

Responsibilities:

- read focused and candidate rectangles from `state.last_layout`;
- select candidates in the requested half-plane;
- rank candidates by perpendicular overlap, directional distance, center
  distance and stable id;
- return focus target ids without invoking the solver or Hyprland directly.

This module is used by spatial focus commands. It does not mutate workspace
state or layout geometry.

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

The official detailed solver behavior and validation examples are documented in
[`docs/solver/`](solver/README.md).

Inputs:

- validated configuration;
- ordered targets;
- dimension modes.

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

The solver must not use focus or viewport offset to choose dimensions or
world-space positions. Focus reveal is a viewport translation step owned by
`viewport.lua` and the adapter.

V1 supports order-mode tiling only. Spatial tiling is reserved for a future
version.

Recommended V1 strategy:

- normalize all directions to a canonical `right` layout problem;
- generate ordered column candidates using the official solver logic;
- preserve forced dimensions as hard constraints;
- rank candidates by scroll, fill, balance, practical size and stable
  tie-breakers;
- transform the selected canonical layout back to the configured direction.

This keeps direction handling separate from packing complexity.

### [`spatial_solver.lua`](layout/spatial_solver.md)

Computes spatial-mode world-space layouts.

Inputs:

- validated spatial configuration;
- target descriptors;
- dimension modes;
- `last_layout` for local events;
- `viewport_offset`;
- an explicit spatial event.

Responsibilities:

- validate spatial solver input;
- preserve forced dimensions;
- return complete world-space placements;
- provide initial global rebuild behavior when no previous geometry exists;
- reject local events that cannot be solved yet without mutating state.

The spatial solver is selected only when `placement_priority = "spatial"`.
It is not a branch inside the order solver.

### [`viewport.lua`](layout/viewport.md)

Computes and clamps viewport offset.

Responsibilities:

- reveal the focused window by the smallest required offset change;
- keep the offset unchanged when the focused window is already fully visible;
- clamp offset between `0` and maximum workspace overflow;
- reduce offset after removals when trailing empty workspace would be visible.

Manual scrolling is intentionally absent from V1.

`viewport.lua` consumes solver output from `state.last_layout`; it does not
trigger or influence the solver.

## Data Flow Details

### Target Identity

Target identity should prefer `target.window.stable_id`, following the local
`manual.lua` example. If unavailable, the adapter should fall back to
`target.window.address` before using `target.index`. The index fallback is
weaker and should be treated as an integration limitation.

### Window Insertion

In order mode, new targets are inserted according to the effective
`config.insert_mode`.

The insertion logic belongs to `target_sync.lua`, not to the solver. For
`insert_mode = "view"`, the adapter provides the last visible id from
`state.last_layout` and `state.viewport_offset`.

In spatial mode, `insert_mode` is ignored. `target_sync.lua` appends new ids
only for deterministic iteration, and `spatial_solver.lua` places new windows
from geometry.

The order solver consumes the resulting logical order. The spatial solver must
not treat that internal list as user-visible placement order.

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

Focus changes must not trigger the solver. They update `focused_id`, compute a
viewport offset from `state.last_layout`, and reapply the previous layout with
that offset.

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
- `solver` tests for the official examples in
  [`docs/solver/`](solver/README.md), order preservation, forced dimensions and
  independence from focus/viewport state;
- adapter smoke tests using mocked `ctx` and `target:place`.

The Hyprland adapter should be kept thin enough that most behavior can be
verified with plain Lua tests.

The canonical local test command is:

```bash
lua tests/run.lua
```

Current test suites are grouped by subsystem:

- `tests/core_test.lua` covers host-independent core behavior;
- `tests/hyprland_adapter_test.lua` covers mocked Hyprland integration;
- `tests/support.lua` contains shared test helpers;
- `tests/run.lua` runs every suite.

## Implementation Guarantees

Fit Scroller's implementation is expected to provide these guarantees:

- the layout is registered as `fit-scroller` and exposed by Hyprland as
  `lua:fit-scroller`;
- all Hyprland object access is isolated in `init.lua` and
  `hyprland_adapter.lua`;
- target identity prefers `target.window.stable_id`, then `target.window.address`
  before any index-based fallback;
- workspace state is keyed from `target.window.workspace`, not from a global
  state bucket;
- target synchronization preserves logical order, inserts new targets according
  to `insert_mode`, and removes per-window state only for windows absent from the
  resolved workspace;
- commands validate their intent and mutate state transactionally;
- structural changes invoke the solver, while focus-only changes update viewport
  offset without changing world-space placements or selected dimensions;
- `state.last_layout` is updated only after solving, viewport computation,
  rectangle conversion and target placement all succeed;
- recoverable failures preserve the previous coherent workspace state and last
  valid layout;
- core modules remain testable without Hyprland.

## Integration Questions

This section tracks Hyprland integration details that affect the adapter.

### Focus changes

Status: resolved from Hyprland `0.55.4` source.

The Hyprland dispatcher list documents several focus-related dispatchers:

- `focuswindow`, which focuses the first window matching a window selector;
- `cyclenext`, which focuses the next or previous window on a workspace;
- `movefocus`, which moves focus in a spatial direction.

Fit Scroller needs logical focus by its own window order, not Hyprland's
default spatial or historical order. The preferred implementation is therefore:

1. resolve the target id selected by `focus previous` or `focus next`;
2. obtain a Hyprland window selector for that target, ideally an address;
3. call Hyprland focus through the adapter.

Hyprland's Lua window object exposes `window.address` as `0x...`. The adapter
must build an `address:` selector for the Lua dispatcher:

```lua
hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
```

Fit Scroller's adapter must use this path for logical focus commands.

Hyprland also exposes `hl.on("window.active", callback)`, which Fit Scroller
uses to dispatch `follow` when focus changes through normal Hyprland bindings.

`hyprctl` must not be called from `layout_msg(ctx, msg)` or
`recalculate(ctx)`.

Sources:

- <https://wiki.hypr.land/Configuring/Dispatchers/>
- `../references/hyprland-custom-layout-api.md`

### `layout_msg` recalculation behavior

Status: resolved from Hyprland `0.55.4` source.

The Hyprland wiki documents layout-specific messages through the `layoutmsg`
dispatcher on built-in layouts such as `scrolling`.

The Lua layout provider calls `recalculate()` after a handled
`layout_msg(ctx, msg)`.

Implementation requirement:

- return a string for command errors;
- return success (`true` or `nil`) only after command handling is complete;
- rely on Hyprland's automatic recalculation after successful layout messages.

Sources:

- <https://wiki.hypr.land/Configuring/Scrolling-Layout/>
- `../references/local/hyprland-layout-examples/manual.lua`
- `../references/local/hyprland-layout-examples/spiral.lua`
- `../references/hyprland-custom-layout-api.md`

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

Status: resolved from Hyprland `0.55.4` source.

The local examples pass areas returned by Hyprland helpers directly to
`target:place(area)`:

- `ctx:column(i, n)`;
- `ctx:grid_cell(i, cols)`;
- `ctx:split(area, side, ratio)`;
- `ctx.area`.

Hyprland's Lua layout target binding reads a plain table with numeric
`x`, `y`, `w` and `h` fields, then calls `setPositionGlobal`.

Implementation requirement:

- keep core geometry in host-independent `Rect` values;
- convert `Rect` values to `{ x, y, w, h }` tables in
  `hyprland_adapter.lua`.

Sources:

- `../references/local/hyprland-layout-examples/columns.lua`
- `../references/local/hyprland-layout-examples/grid.lua`
- `../references/local/hyprland-layout-examples/manual.lua`
- `../references/local/hyprland-layout-examples/spiral.lua`
- `../references/hyprland-custom-layout-api.md`

### Workspace Identity

Status: resolved from Hyprland source inspection.

Hyprland's custom Lua layout context is built with `area`, `targets` and helper
functions. It does not expose `ctx.workspace`, `ctx.monitor` or the recalculation
reason.

Workspace identity is exposed through `target.window.workspace`. The workspace
object exposes `id`, `name` and `config_name`. The global Lua API also exposes
`hl.get_workspaces()`, `hl.get_active_workspace(monitor?)`,
`hl.get_active_special_workspace(monitor?)` and
`hl.get_workspace_windows(workspace)`.

Implementation requirement:

- derive the workspace key from target windows, preferring
  `target.window.workspace.id`;
- fall back to `workspace.config_name`, then `workspace.name`;
- use global query helpers only for validation or recovery, not as the primary
  identity path inside a layout pass;
- avoid using global state that mixes independent workspaces.

Sources:

- <https://github.com/hyprwm/Hyprland/tree/5a7078d20a14bb199ef9bb81faa4faeaf5e92117>
- `src/config/lua/layout/LuaLayoutContext.cpp`
- `src/config/lua/objects/LuaWindow.cpp`
- `src/config/lua/objects/LuaWorkspace.cpp`
- `src/config/lua/bindings/LuaBindingsQuery.cpp`
