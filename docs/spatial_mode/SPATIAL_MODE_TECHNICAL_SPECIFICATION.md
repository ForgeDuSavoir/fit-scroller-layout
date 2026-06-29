# Fit Scroller Spatial Mode Technical Specification

## Status

This document defines the first technical design for
`placement_priority = "spatial"`.

The product behavior is described in
[SPATIAL_MODE_SPECIFICATION.md](SPATIAL_MODE_SPECIFICATION.md). This document
focuses on implementation boundaries, input shapes, event detection, candidate
generation and validation rules.

The implementation sequence is tracked in
[SPATIAL_MODE_IMPLEMENTATION_PLAN.md](SPATIAL_MODE_IMPLEMENTATION_PLAN.md).

Spatial mode is not a variant of the current order solver. It has its own
solver entry point and its own command semantics.

## Version Scope

The first spatial implementation intentionally keeps the model narrow.

Included:

- `placement_priority = "spatial"`;
- spatial structural solving from `last_layout`;
- spatial commands using `left`, `right`, `up` and `down`;
- local handling for window addition, window removal and dimension changes;
- global spatial fallback when local handling fails;
- viewport-aware ranking using `viewport_offset`;
- recoverable failure handling through the existing transaction pattern.

Excluded from the first implementation:

- use of `insert_mode` in spatial mode;
- persistent holes as a supported layout feature;
- user-configurable spatial ranking weights;
- preserving spatial geometry across monitor configuration changes;
- mixed order/spatial command behavior;
- `previous` and `next` commands in spatial mode.

## Configuration Contract

The normalized config must expose:

```lua
Config = {
    placement_priority = "order" | "spatial",
    allowed_dimensions = { ... },
    dimensions_by_key = { ... },
    toggle_cycle = { ... },
    scroll_direction = "right" | "left" | "down" | "up",
    insert_mode = "view" | "last" | "first" | "after_focused" | "before_focused",
}
```

`placement_priority` defaults to `"order"` when omitted.

When `placement_priority = "order"`, existing `insert_mode` behavior applies.

When `placement_priority = "spatial"`, `insert_mode` is validated but ignored.
New windows are placed by the spatial solver according to current geometry,
visible area and the window-addition rules below. Target synchronization must
not insert new spatial windows by order-derived anchors.

This keeps the first spatial implementation simple and avoids mixing two
different placement models.

## Module Boundaries

Recommended implementation modules:

```text
layout/
    spatial_solver.lua
    spatial_geometry.lua
    spatial_focus.lua
```

The existing modules keep their responsibilities:

- `config.lua` validates `placement_priority` and still validates
  `insert_mode`;
- `state.lua` stores workspace state and `last_layout`;
- `target_sync.lua` synchronizes live targets without applying order semantics
  in spatial mode;
- `commands.lua` parses mode-aware commands and returns intent;
- `viewport.lua` reveals focused placements after structural solve;
- `hyprland_adapter.lua` chooses the order or spatial flow.

`spatial_solver.lua` must not:

- read raw Hyprland objects;
- call `target:place`;
- call `viewport.reveal`;
- mutate workspace state directly;
- inspect user keybindings.

## Adapter Flow

The adapter selects the placement strategy after config resolution.

```text
recalculate(ctx)
    -> collect target descriptors
    -> resolve workspace state
    -> resolve config
    -> synchronize targets
    -> if config.placement_priority == "order":
           run existing order structural or viewport flow
       else:
           run spatial structural or viewport flow
```

Spatial structural flow:

```text
structural spatial event
    -> build SpatialSolverInput
    -> spatial_solver.solve(input)
    -> compute or clamp viewport offset
    -> convert rectangles
    -> place all targets
    -> commit workspace state and last_layout
```

Spatial viewport-only flow:

```text
focus-only event or follow command
    -> read state.last_layout
    -> viewport.reveal(...)
    -> reapply last_layout with updated viewport_offset
```

The spatial solver may read `viewport_offset`, but viewport translation is
still applied by the adapter after solving.

## Workspace State

The existing workspace state remains valid:

```lua
WorkspaceState = {
    order = {},
    dimension_mode_by_id = {},
    focused_id = nil,
    viewport_offset = 0,
    last_layout = nil,
}
```

In spatial mode:

- `order` may exist as an internal stable list;
- `order` must not define layout traversal;
- `order` must not define focus navigation;
- new target ids may be appended for deterministic iteration only;
- removing a target removes its dimension mode and any pending event metadata.

No user-visible spatial behavior may depend on `order`.

## Target Synchronization In Spatial Mode

`target_sync.lua` must support a spatial synchronization path.

Spatial synchronization responsibilities:

1. keep existing ids in a deterministic internal list;
2. append newly discovered ids to that list for stable iteration;
3. remove ids that are no longer present;
4. preserve existing dimension modes;
5. initialize new windows with `{ kind = "auto" }`;
6. detect target additions and removals for event construction.

Spatial synchronization must not:

- apply `insert_mode`;
- insert relative to the focused window;
- insert relative to the visible window list;
- interpret the internal list as layout order.

Recommended sync result:

```lua
TargetSyncResult = {
    changed = true,
    added_ids = { "C" },
    removed_ids = { "B" },
    present_ids = { "A", "C" },
}
```

The adapter converts this result into a spatial event.

## Spatial Events

The spatial solver must receive an explicit event.

```lua
SpatialEvent =
    { kind = "initial" }
  | { kind = "window_added", target_id = "C" }
  | { kind = "window_removed", target_id = "B", previous_rect = Rect }
  | { kind = "dimension_forced", target_id = "A", key = "0.5x1.0" }
  | { kind = "dimension_auto", target_id = "A", previous_key = "1.0x1.0" }
  | { kind = "move", target_id = "A", direction = "left" | "right" | "up" | "down" }
  | { kind = "config_changed" }
```

Event construction rules:

- no `last_layout` or empty previous state produces `initial`;
- exactly one added id produces `window_added`;
- exactly one removed id produces `window_removed`;
- multiple added or removed ids produce `config_changed` or another global
  rebuild event;
- `toggle dimension` from auto to forced produces `dimension_forced`;
- `toggle dimension` from forced to auto produces `dimension_auto`;
- spatial move commands produce `move`.

If more than one structural cause is present, the adapter should choose a
global spatial rebuild event rather than pretending it is a simple local event.

## Spatial Solver Input

Recommended input shape:

```lua
SpatialSolverInput = {
    config = Config,
    targets = {
        { id = "A" },
        { id = "B" },
    },
    dimension_mode_by_id = {
        A = { kind = "auto" },
        B = { kind = "forced", key = "0.5x1.0" },
    },
    last_layout = {
        placements_by_id = {
            A = { x = 0, y = 0, w = 0.5, h = 1.0 },
        },
        dimensions_by_id = {
            A = { key = "0.5x1.0", w = 0.5, h = 1.0 },
        },
        workspace_extent = 1.0,
    },
    viewport_offset = 0,
    event = { kind = "window_added", target_id = "C" },
}
```

The solver must validate:

- `config.placement_priority == "spatial"`;
- supported `scroll_direction`;
- non-empty `allowed_dimensions`;
- unique target ids;
- every target has a dimension mode or defaults to auto;
- forced dimension keys exist in `dimensions_by_key`;
- `viewport_offset` is finite and non-negative;
- `last_layout` is present for local events;
- every previous placement is a valid finite rectangle.

For `initial` and `config_changed`, `last_layout` may be missing. The solver
must use global spatial rebuild.

## Spatial Solver Output

Recommended output shape:

```lua
SpatialSolverResult = {
    ok = true,
    layout = {
        placements_by_id = {
            A = { x = 0, y = 0, w = 0.5, h = 1.0 },
        },
        dimensions_by_id = {
            A = { key = "0.5x1.0", w = 0.5, h = 1.0 },
        },
        workspace_extent = 1.0,
    },
    diagnostics = {
        strategy = "initial_global_rebuild" | "global_rebuild" |
                   "global_preserve" | "global_preserve_compact" |
                   "local_split" | "local_append" |
                   "local_preserve" | "local_expand" |
                   "local_compact_full_cross_hole" |
                   "local_push_compact_full_cross_hole" |
                   "local_cross_fill" | "local_push_cross_fill" |
                   "local_resize" | "local_push" |
                   "local_auto_resize" | "local_auto_compact" |
                   "local_swap" | "local_split_move" |
                   "local_scroll_extend" | "noop",
        changed_ids = { "A", "C" },
    },
}
```

On failure:

```lua
{
    ok = false,
    error = "fit-scroller: spatial: no valid candidate for window_added C"
}
```

The solver must never return partial placements.

## Coordinate Model

The spatial solver works in normalized world-space coordinates.

The viewport always has normalized size:

```text
width = 1
height = 1
```

For horizontal scroll directions:

- scroll axis is `x`;
- cross axis is `y`;
- viewport interval is `[viewport_offset, viewport_offset + 1]`.

For vertical scroll directions:

- scroll axis is `y`;
- cross axis is `x`;
- viewport interval is `[viewport_offset, viewport_offset + 1]`.

For negative scroll directions, world-space coordinates are negative but scroll
coordinates remain non-negative:

- `left`: a world rect `x = -1, w = 1` maps to scroll interval `[0, 1]`;
- `left`: a world rect `x = -2, w = 1` maps to scroll interval `[1, 2]`;
- `up`: a world rect `y = -1, h = 1` maps to scroll interval `[0, 1]`;
- `up`: a world rect `y = -2, h = 1` maps to scroll interval `[1, 2]`.

Viewport conversion must mirror that model. For `left`, the visible screen x is
`world_x + viewport_offset + 1`; for `up`, the visible screen y is
`world_y + viewport_offset + 1`.

The solver may normalize every problem to canonical `right` coordinates, but
returned placements must use the configured direction's world-space coordinate
system.

## Rect Validity

A rect is valid when:

```lua
Rect = {
    x = finite_number,
    y = finite_number,
    w = finite_number > 0,
    h = finite_number > 0,
}
```

For every output rect:

- `w` and `h` must match one configured allowed dimension;
- `x` and `y` must be finite;
- the cross-axis start must be `>= 0`;
- the cross-axis end must be `<= 1`;
- rects must not overlap, with epsilon tolerance;
- scroll-axis positions may extend beyond the viewport only along the
  configured scroll axis.

## Dimension Resolution

For each target:

```text
if mode == forced:
    allowed candidate dimensions = { forced dimension }
else:
    allowed candidate dimensions = all configured dimensions
```

Forced dimensions are hard constraints.

Auto dimensions should prefer the current dimension when comparing otherwise
equivalent candidates, except for `dimension_auto` events. In a
`dimension_auto` event, preserving the previous forced geometry must not be a
special preference; the event means the user returned control to the solver.

## Visibility

The solver computes visibility from `last_layout`, `viewport_offset` and
`scroll_direction`.

Recommended helpers:

```lua
is_visible(rect, viewport_offset, direction)
is_fully_visible(rect, viewport_offset, direction)
visible_overlap(rect, viewport_offset, direction)
```

A window is visible if its interval on the scroll axis intersects the viewport
interval and its cross-axis interval intersects `[0, 1]`.

Visible windows receive stronger preservation priority than non-visible
windows.

## Candidate Pipeline

`spatial_solver.solve(input)` should use this pipeline:

```text
1. Validate input.
2. Normalize geometry helpers for scroll direction.
3. Build current layout snapshot from last_layout.
4. Build candidate list for the event.
5. Validate every candidate against shared invariants.
6. Rank valid candidates with spatial cost.
7. If no local candidate is valid, generate global rebuild candidates.
8. Rank global candidates with spatial cost.
9. Return the best complete layout or an error.
```

Candidate generation should be local first. Global rebuild is fallback, not the
default behavior.

## Spatial Cost

Each candidate receives a lexicographic cost tuple. Lower is better.

Recommended tuple:

```lua
cost = {
    invalid,                     -- 0 for valid, invalid candidates discarded
    forced_violation,            -- always 0 for ranked candidates
    visible_moved_count,
    visible_movement_distance,
    visible_resized_count,
    total_moved_count,
    total_movement_distance,
    total_resized_count,
    scroll_overflow,
    workspace_extent,
    visible_hole_area,
    total_hole_area,
    negative_fill_quality,
    stable_tie_breaker,
}
```

Movement distance compares rectangle centers in world-space coordinates:

```text
distance = abs(old_center_x - new_center_x)
         + abs(old_center_y - new_center_y)
```

Resize distance compares dimensions:

```text
resize = abs(old_w - new_w) + abs(old_h - new_h)
```

A target counts as moved when its center changes by more than epsilon.

A target counts as resized when its dimension key changes.

`visible_hole_area` is the area inside the visible viewport that is not covered
by any window but could have been filled by a local candidate without
increasing scroll. The first implementation may approximate this value, but it
must not prefer obvious visible holes over equivalent hole-free candidates.

## Window Addition Algorithm

Input event:

```lua
{ kind = "window_added", target_id = "C" }
```

First implementation ignores `insert_mode`.

Algorithm:

1. Build the set of existing auto windows from `last_layout`.
2. Partition them into visible and non-visible candidates.
3. For each candidate window, try every valid two-rect split:
   - existing window keeps one allowed auto dimension;
   - new window gets one allowed auto dimension;
   - both rects fit within the original candidate rect;
   - both rects do not overlap;
   - the original candidate's previous rect is the only replaced rect.
4. Rank split candidates.
5. If no split candidate is valid, generate append candidates on the scroll
   axis.
6. If append candidates fail, run global rebuild.

Split candidate ranking:

```text
1. visible source window before non-visible source window
2. larger source area first
3. smaller uncovered area inside source rect
4. fewer changed windows
5. smaller workspace extent increase
6. spatial cost tuple
```

Append candidate rules:

- append after the current maximum scroll-axis end for `right` or `down`;
- append before the current minimum scroll-axis start for `left` or `up`;
- choose the largest allowed dimension that does not exceed the cross axis and
  minimizes additional workspace extent;
- place on the cross axis at `0` unless another valid cross-axis placement
  produces better viewport fill without increasing disruption;
- reveal of the new window happens after solver success through viewport flow.

## Window Removal Algorithm

Input event:

```lua
{ kind = "window_removed", target_id = "B", previous_rect = Rect }
```

Algorithm:

1. Remove the deleted target from `last_layout`.
2. If the deleted rect spans the full cross axis, generate a full-cross
   compaction candidate.
3. If the deleted rect is partial on the cross axis, generate partial-cross
   fill candidates.
4. Candidate preservation: keep every remaining rect unchanged when no better
   local repair exists.
5. Candidate expansion: for partial holes only, expand one adjacent auto window
   into the deleted rect when the expanded rect matches an allowed dimension.
6. Reduce trailing scroll extent through workspace extent recomputation.
7. If no candidate is valid or quality is unacceptable, run global rebuild.

Adjacency:

- two rects are adjacent when their edges touch within epsilon and their
  perpendicular intervals overlap;
- adjacency should be checked in all four directions;
- expansion is allowed only for partial-cross holes and only when the expanded
  rect matches an allowed dimension for the adjacent auto window.

Full-cross compaction:

- a full-cross hole covers `y = 0..1` for `right` and `left` scroll;
- a full-cross hole covers `x = 0..1` for `down` and `up` scroll;
- windows after the hole on the scroll axis are translated by the hole's
  scroll-axis size;
- for `right`, later windows shift left;
- for `left`, later windows shift right;
- for `down`, later windows shift up;
- for `up`, later windows shift down;
- dimensions are preserved during this compaction;
- the resulting candidate must still validate as non-overlapping and within
  the cross axis.

Partial-cross fill:

- a partial-cross hole does not cover the full cross axis;
- the solver searches for an adjacent auto window in the same column or row;
- the selected window expands on the cross axis to cover the hole;
- the selected window may keep, shrink or grow its scroll-axis size if the
  resulting rectangle matches an allowed dimension;
- if the column or row scroll-axis size changes, later windows on the scroll
  axis are shifted to keep the layout non-overlapping;
- forced windows must not be resized by partial-cross fill.

Partial-cross dimension ranking:

1. keep the selected column or row scroll-axis size;
2. shrink the selected column or row scroll-axis size;
3. grow the selected column or row scroll-axis size.

Within the shrink group, prefer the largest shrink result that is valid. Within
the grow group, prefer the smallest grow result that is valid. After this
priority, rank by workspace extent and stable ids.

Persistent holes are not supported in the first implementation. A keep-unchanged
candidate with a visible hole may be valid only if no local hole-free candidate
exists.

## Forced Dimension Algorithm

Input event:

```lua
{ kind = "dimension_forced", target_id = "A", key = "0.5x1.0" }
```

Algorithm:

1. Validate the forced dimension key.
2. Try resizing the target around its current top-left position.
3. Try resizing around its current center.
4. Try resizing while pushing overlapping auto neighbors away locally.
5. Detect scroll-axis holes freed by the forced resize.
6. For full-cross freed holes, generate compaction candidates using the same
   direction-aware translation rules as window removal.
7. For partial-cross freed holes, generate partial-cross fill candidates using
   the same column or row resize ranking as window removal.
8. Try extending scroll to fit pushed windows.
9. Run global rebuild if local candidates fail.

Neighbor pushes:

- may only move auto windows;
- must not change forced windows;
- should prefer movement on the scroll axis;
- must preserve cross-axis bounds;
- must produce non-overlapping allowed-dimension rects.

If the forced dimension cannot fit on the cross axis, return an error and keep
the previous forced or auto mode unchanged through the adapter transaction.

Full-cross and partial-cross repair never changes the forced target's requested
dimension. It may move or resize only eligible auto windows, and every resized
auto window must end on one configured allowed dimension.

## Return To Auto Algorithm

Input event:

```lua
{ kind = "dimension_auto", target_id = "A", previous_key = "1.0x1.0" }
```

The target is no longer constrained to `previous_key`.

Algorithm:

1. Generate local candidates for every allowed dimension of the target.
2. Prefer candidates that reduce workspace extent or visible holes.
3. Allow the target to shrink or grow according to local fit.
4. Allow adjacent auto windows to resize when this improves density.
5. Do not give special preference to preserving the previous forced dimension.
6. Run global rebuild if no local compaction candidate is valid.

The event should produce a visible optimization attempt whenever a better local
layout exists.

## Spatial Move Algorithm

Input event:

```lua
{ kind = "move", target_id = "A", direction = "left" }
```

Algorithm:

1. Identify directional neighbors from `last_layout`.
2. Generate swap candidates with compatible neighbors.
3. Generate insertion candidates by splitting an auto neighbor in the requested
   direction.
4. Generate free-space move candidates if free-space detection is available.
5. Generate scroll-extension candidates when the requested direction is on the
   scroll axis.
6. Rank candidates by whether they make visible progress in the requested
   direction, then by spatial cost.

A move candidate makes progress when the moved window's center moves in the
requested direction by more than epsilon.

If no candidate makes progress, the command is a no-op with no layout update.

## Spatial Focus Algorithm

Spatial focus is not a solver event.

Input command:

```text
focus left
focus right
focus up
focus down
```

Algorithm:

1. Read `state.focused_id`.
2. Read focused rect from `state.last_layout`.
3. Build candidates whose center lies in the requested half-plane.
4. Rank candidates:
   - strongest perpendicular interval overlap;
   - shortest directional distance;
   - shortest center distance;
   - stable target id.
5. Ask the adapter to focus the selected target.
6. Let `follow` or `reveal focus` update the viewport offset.

Focus commands must not call `spatial_solver.solve`.

## Global Spatial Rebuild

Global rebuild is used for:

- initial layout when no `last_layout` exists;
- multiple simultaneous additions or removals;
- display or config changes;
- local candidate failure.

The first implementation may reuse the order solver as a candidate generator
only if the result is re-ranked as a spatial global candidate and the spatial
mode contract remains visible at the adapter boundary.

For initial layout with no previous geometry, a deterministic dense layout is
acceptable. In that one case, there is no geometry to preserve.

For rebuilds with previous geometry, ranking must prioritize:

1. valid forced dimensions;
2. preserving visible windows;
3. minimizing movement from previous geometry;
4. minimizing resizes;
5. minimizing scroll overflow;
6. maximizing fill.

The global rebuild must not restore user-visible `previous` or `next`
semantics.

## Command Parsing

`commands.lua` must become mode-aware.

Recommended command support:

```text
order mode:
    move previous
    move next
    focus previous
    focus next

spatial mode:
    move left
    move right
    move up
    move down
    focus left
    focus right
    focus up
    focus down

both modes:
    toggle dimension
    reveal focus
    follow
```

Mode mismatch errors:

```text
fit-scroller: command requires order placement: move previous
fit-scroller: command requires spatial placement: move left
```

Spatial move command result:

```lua
{
    ok = true,
    changed = true,
    needs_layout_update = true,
    spatial_event = {
        kind = "move",
        target_id = "A",
        direction = "left",
    },
}
```

Spatial focus command result:

```lua
{
    ok = true,
    changed = true,
    needs_viewport_update = true,
    focus_target_id = "B",
}
```

## Transaction Requirements

Every structural spatial operation must be validate-then-commit.

Required sequence:

```text
1. clone or draft workspace state
2. apply sync or command mutation to draft
3. build spatial event
4. run spatial solver against draft
5. validate complete output
6. convert and verify target placements
7. apply placements
8. commit draft state, viewport offset and last_layout
```

If any step fails:

- do not commit dimension mode changes;
- do not commit internal target list changes unless target disappearance is
  unavoidable and already reflected by Hyprland;
- do not update `viewport_offset`;
- do not update `last_layout`;
- do not partially place targets.

## Diagnostics

Spatial diagnostics should include:

- placement mode;
- event kind;
- target id when available;
- candidate phase that failed;
- forced dimension key when relevant.

Examples:

```text
fit-scroller: spatial: insert_mode is ignored in spatial placement
fit-scroller: spatial: no valid local split for window_added C
fit-scroller: spatial: forced dimension 0.66x1.0 cannot fit on cross axis
fit-scroller: spatial: command requires spatial placement: move left
```

The `insert_mode` diagnostic should be development-facing only. Ignoring
`insert_mode` in spatial mode is expected behavior, not a runtime error.

## Test Plan

Configuration tests:

- default `placement_priority` is `"order"`;
- `"order"` and `"spatial"` are accepted;
- invalid `placement_priority` is rejected;
- `insert_mode` remains validated in spatial configs;
- `insert_mode` does not affect spatial window addition.

Command tests:

- `move previous` is rejected in spatial mode;
- `focus previous` is rejected in spatial mode;
- `move left/right/up/down` is rejected in order mode;
- `focus left/right/up/down` is rejected in order mode;
- spatial move returns a spatial move event;
- spatial focus does not request layout solving.

Target sync tests:

- spatial sync appends new ids only for stable iteration;
- spatial sync ignores `insert_mode`;
- spatial sync reports added and removed ids;
- spatial sync removes dimension modes for missing ids;
- spatial sync does not reorder existing ids for layout meaning.

Solver tests:

- initial spatial solve returns a complete valid layout;
- adding one window splits a visible auto window when possible;
- changing `insert_mode` does not change the addition result;
- adding one window appends on the scroll axis when no split exists;
- removing one window preserves remaining rects when no visible hole results;
- removing one trailing full-cross window reduces scroll extent without
  expanding the remaining window;
- removing one full-cross middle window compacts later windows toward the
  scroll origin;
- full-cross compaction shifts later windows left for `right` scroll;
- full-cross compaction shifts later windows right for `left` scroll;
- full-cross compaction shifts later windows up for `down` scroll;
- full-cross compaction shifts later windows down for `up` scroll;
- removing one partial-cross window can resize an auto window in the same
  column or row;
- partial-cross repair keeps scroll-axis size when possible, shrinks it when
  keeping is not possible, and grows it only as a last local option;
- partial-cross repair uses width as scroll-axis size in horizontal scroll and
  height as scroll-axis size in vertical scroll;
- forcing a dimension preserves that dimension exactly;
- forcing a smaller dimension can compact a full-cross freed hole;
- forcing a smaller dimension can repair a partial-cross freed hole;
- returning to auto can shrink a previously forced-large window;
- returning to auto can grow a previously forced-small window;
- moving left/right/up/down changes the focused window geometry in that
  direction when possible;
- failed local solving falls back to global spatial rebuild;
- failed global rebuild preserves previous last layout.

Viewport tests:

- spatial solver receives `viewport_offset`;
- visible-window ranking changes when `viewport_offset` changes;
- focus left/right/up/down does not invoke the solver;
- reveal after spatial structural solve uses `viewport.lua`.

Integration tests:

- adapter chooses order solver for `placement_priority = "order"`;
- adapter chooses spatial solver for `placement_priority = "spatial"`;
- order solver input never includes `viewport_offset`;
- spatial solver input includes `viewport_offset` and event;
- failed spatial structural command preserves previous dimension mode.

## Implementation Sequence

Recommended implementation order:

1. Add `placement_priority` config validation.
2. Make command parsing mode-aware.
3. Add spatial target synchronization metadata.
4. Add spatial focus helpers.
5. Add spatial solver input validation and initial global rebuild.
6. Implement `window_added` local split and append.
7. Implement `window_removed` local preservation and expansion.
8. Implement `dimension_forced`.
9. Implement `dimension_auto`.
10. Implement spatial move.
11. Add global rebuild fallback ranking.
12. Wire adapter transaction flow.
13. Add integration tests for `insert_mode` being ignored in spatial mode.
