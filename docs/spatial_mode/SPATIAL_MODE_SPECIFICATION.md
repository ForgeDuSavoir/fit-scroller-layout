# Fit Scroller Spatial Mode Specification

## Status

This document specifies the intended behavior for Fit Scroller's future spatial
placement mode.

The detailed technical design is documented in
[SPATIAL_MODE_TECHNICAL_SPECIFICATION.md](SPATIAL_MODE_TECHNICAL_SPECIFICATION.md).

The current implemented solver is order-based. Its normative behavior remains
documented in [SPECIFICATION.md](SPECIFICATION.md) and
[solver/detailed-logic.md](solver/detailed-logic.md).

Spatial mode is a separate placement strategy. It must not be implemented as a
small variation of the order solver, because it optimizes a different user
priority.

## Goal

Spatial mode prioritizes preserving the user's current workspace geometry.

When a structural event happens, Fit Scroller should first try to adapt the
existing layout locally:

- keep existing windows close to their current world-space positions;
- keep existing dimensions when doing so does not conflict with the event;
- preserve the visible viewport as much as possible;
- minimize the number of windows moved or resized;
- extend or reduce scroll only as much as needed;
- rebuild the whole layout only when no acceptable local solution exists.

Spatial mode is intended for workspaces where windows are related by spatial
proximity rather than by an ordered sequence.

## Configuration

Fit Scroller uses `placement_priority` to select the placement strategy.

Supported values:

```lua
placement_priority = "order"
placement_priority = "spatial"
```

`order` is the default and preserves the current behavior.

`spatial` enables the behavior specified in this document.

For the first spatial implementation, `insert_mode` is ignored when
`placement_priority = "spatial"`. New windows are placed from current geometry
and viewport visibility, not from an order insertion rule.

The placement strategy must be selected before invoking solver logic:

```text
if placement_priority == "order":
    use order solver
else if placement_priority == "spatial":
    use spatial solver
```

The two modes may share validation helpers and geometry primitives, but they
must not share one mixed ranking model.

## Shared Invariants

Every spatial layout must still satisfy Fit Scroller's core layout invariants:

1. Every tiled window has exactly one configured allowed dimension.
2. A forced window keeps its forced dimension.
3. Tiled windows do not overlap.
4. Overflow exists only on the configured scroll axis.
5. Every window fits within the viewport on the cross axis.
6. Positions are deterministic for identical input state, event and
   configuration.
7. Invalid or failed layout updates preserve the previous valid layout and
   state.

Spatial mode changes how placements are selected. It does not permit arbitrary
dimensions, overlapping tiled windows or cross-axis overflow.

## Relationship To Order

Spatial mode has no user-visible logical order.

The following order concepts do not apply in spatial mode:

- ordered traversal as a layout constraint;
- `previous` and `next` as user-facing navigation directions;
- placement derived from an ordered window sequence;
- preserving a canonical sequence when rebuilding geometry.

Implementation may still keep an internal stable list of windows for
deterministic iteration, serialization and tie-breaking. That internal list is
arbitrary and must not be exposed as meaningful workspace behavior.

## Commands

Order-mode commands:

```text
move previous
move next
focus previous
focus next
```

Spatial-mode commands:

```text
move left
move right
move up
move down
focus left
focus right
focus up
focus down
```

Commands that belong to the other placement mode should be rejected with a
clear diagnostic. Silent no-ops make binding mistakes hard to detect.

`toggle dimension` remains valid in both modes, but its layout effect is
mode-specific.

`follow` and `reveal focus` remain viewport commands. They should reveal the
focused window without invoking either solver.

## Spatial Solver Input

The order solver must remain independent from focus and viewport state.

The spatial solver needs additional context because its ranking depends on the
current geometry and visible area.

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
    last_layout = LastLayout,
    viewport_offset = 0,
    event = {
        kind = "window_added" | "window_removed" | "dimension_changed" | "move",
        target_id = "C",
        direction = "left" | "right" | "up" | "down",
    },
}
```

`last_layout` is the previous fully successful world-space layout.

`viewport_offset` is required to determine which windows and empty spaces are
currently visible.

The event describes the user-visible cause of the solve. Spatial mode should
not treat every structural recalculation identically.

## Visible Area

In spatial mode, the visible viewport has semantic weight.

When several valid local solutions exist, prefer solutions that:

1. preserve the currently visible windows;
2. place newly created windows in visible space when possible;
3. avoid moving windows that are fully visible;
4. avoid changing `viewport_offset` unless the focused or newly created window
   must be revealed;
5. avoid creating visible holes.

The solver may still modify off-screen windows if that produces a better local
solution with less visible disruption.

## Fallback Model

Spatial mode should use a staged solving model:

```text
1. Try a local spatial update.
2. If that fails, try a global spatial rebuild.
3. If that fails, reject the update and preserve the previous valid layout.
```

The global fallback is not the order solver.

A global spatial rebuild may reposition every window, but it must still rank
candidates according to spatial priorities:

1. preserve forced dimensions;
2. preserve visible windows when possible;
3. minimize total movement from `last_layout`;
4. minimize the number of moved windows;
5. minimize the number of resized windows;
6. minimize scroll overflow;
7. maximize practical viewport fill;
8. use stable tie-breakers.

## Window Addition

When a window is added, it starts in auto dimension mode.

Spatial mode ignores `insert_mode` for window addition in the first
implementation.

The new window should be placed by trying, in order:

1. split the largest splittable visible auto window;
2. split the best splittable non-visible auto window;
3. place the window in an existing free space, if free spaces are supported;
4. append the window by extending the workspace on the scroll axis with the
   smallest possible extent increase;
5. run a global spatial rebuild.

A splittable window is an auto window whose current rectangle can be replaced
by two non-overlapping allowed-dimension rectangles: one for the existing
window and one for the new window.

Candidate split ranking:

1. visible target before non-visible target;
2. larger target area first;
3. fewer changed windows;
4. better fill of the original rectangle;
5. smaller scroll extent increase;
6. stable target id tie-breaker.

The newly added window should be revealed after the structural update succeeds.

## Window Removal

When a window is removed, spatial mode should preserve other windows whenever
possible.

The solver should try, in order:

1. remove the window and keep every other rectangle unchanged;
2. expand one adjacent auto window into the freed space;
3. reduce trailing scroll extent without changing remaining dimensions;
4. compact locally around the freed space;
5. run a global spatial rebuild.

Visible holes should be avoided. If holes are allowed internally, they should
be treated as temporary low-quality states and ranked below equivalent
hole-free solutions.

Open question:

- whether spatial mode should allow persistent off-screen holes to avoid
  moving windows. The initial implementation should avoid persistent holes
  unless a later design explicitly introduces them.

## Forcing A Dimension

When a window changes from auto mode to a forced dimension, the forced
dimension becomes a hard constraint.

The solver should try, in order:

1. resize the target in place if no overlap is introduced;
2. resize or move adjacent auto windows locally;
3. extend or reduce scroll to make room;
4. compact local affected windows;
5. run a global spatial rebuild.

The solver must reject the operation if the forced dimension is not configured
or cannot fit on the cross axis.

The solver must not silently replace the forced dimension with a nearby auto
dimension.

## Returning To Auto Dimension

Returning a window from forced dimension mode to auto dimension mode is a
manual user action and should produce an optimization attempt.

Spatial mode should not simply keep the current dimension because it is still
allowed. The user is explicitly returning control to the solver.

The solver should try to compact and improve the local layout:

1. remove the forced constraint from the target window;
2. recompute an auto dimension for the target based on local fit;
3. reduce scroll if possible;
4. fill adjacent free space when doing so does not increase scroll;
5. resize other auto windows only when this improves local density or avoids a
   visible hole;
6. run a global spatial rebuild if local compaction cannot produce a valid
   layout.

This handles both cases:

- the forced dimension was larger than the auto solver would choose;
- the forced dimension was smaller than the auto solver would choose.

## Spatial Move

Spatial move commands operate on geometry, not on logical order.

For:

```text
move left
move right
move up
move down
```

the solver should attempt to move the focused window in the requested
direction.

Candidate behavior:

1. move into an adjacent free space if one exists;
2. split an adjacent auto window if the moved window is auto and the split is
   valid;
3. swap geometry with the best directional neighbor if dimensions are
   compatible;
4. move the window to a new position by extending scroll when the direction
   matches the scroll axis;
5. run a global spatial rebuild.

If the focused window has a forced dimension, candidates must preserve that
dimension.

The moved window should remain visible after the operation succeeds.

## Spatial Focus

Spatial focus commands select the best window in the requested direction from
the currently focused window.

For:

```text
focus left
focus right
focus up
focus down
```

selection should be based on current world-space rectangles from
`last_layout`.

Recommended ranking for directional focus:

1. candidate lies in the requested half-plane;
2. strongest overlap on the perpendicular axis;
3. shortest distance on the requested axis;
4. shortest center-to-center distance;
5. stable target id tie-breaker.

Focus commands do not invoke the solver. After Hyprland reports the new focus,
`follow` or `reveal focus` should update only the viewport offset.

## Locality And Cost

Spatial mode needs a cost model for comparing valid candidates.

Recommended cost components, in priority order:

1. invalid candidates are discarded;
2. forced dimension violations are invalid;
3. visible-window movement count;
4. visible-window total movement distance;
5. visible-window resize count;
6. total movement count;
7. total movement distance;
8. total resize count;
9. scroll extent increase;
10. visible holes;
11. total holes;
12. practical fill quality;
13. stable tie-breakers.

Movement distance should compare world-space rectangles before viewport
translation. Viewport offset changes are handled separately by `viewport.lua`.

## State Requirements

Spatial mode requires the existing persistent state plus enough information to
identify the structural event.

`last_layout` is mandatory for local spatial solving. If no previous layout is
available, spatial mode should use the global spatial rebuild path.

The adapter must preserve the existing transaction pattern:

1. build a draft state;
2. compute the spatial layout;
3. compute or clamp viewport offset;
4. verify every target can be placed;
5. apply every placement;
6. commit state and `last_layout`.

Failed spatial solves must not partially update dimension modes, viewport
offset or last layout.

## Interaction With Viewport

Spatial solving may read `viewport_offset`.

Viewport reveal remains a separate step:

```text
structural spatial solve
    -> produces world-space placements
    -> updates last_layout after successful placement
    -> viewport reveal may adjust viewport_offset
```

The spatial solver should not directly apply display translations.

The order solver must not receive `viewport_offset`.

## Diagnostics

Spatial mode should return readable errors for:

- invalid `placement_priority`;
- spatial command used in order mode;
- order command used in spatial mode;
- missing `last_layout` when a local solve is required and global rebuild is
  unavailable;
- invalid forced dimension;
- forced dimension that cannot fit on the cross axis;
- no valid spatial candidate.

Diagnostics should identify the event and target id when available.

## Test Cases

Spatial mode tests should cover:

- configuration accepts `placement_priority = "order"`;
- configuration accepts `placement_priority = "spatial"`;
- configuration rejects invalid placement priorities;
- order commands are rejected in spatial mode;
- spatial commands are rejected in order mode;
- adding a window splits a visible splittable auto window;
- adding a window extends scroll when no visible split is possible;
- removing a window preserves unchanged windows when possible;
- removing a window reduces trailing scroll when possible;
- forcing a dimension preserves the forced dimension exactly;
- returning to auto triggers compaction rather than preserving the forced
  geometry unchanged;
- moving left/right/up/down uses geometry rather than order;
- focusing left/right/up/down does not invoke the solver;
- failed spatial solve preserves previous state and last layout;
- spatial solver uses `viewport_offset` to identify visible windows;
- order solver input remains independent from `viewport_offset`.
- changing `insert_mode` does not change spatial window-addition behavior.

## Open Design Questions

The following details are intentionally left open until implementation work
starts:

- whether persistent off-screen holes are allowed;
- how aggressive global spatial rebuild should be;
- whether movement and resize distances should use rectangle edges or centers;
- whether visible windows should be absolutely protected or only heavily
  weighted;
- how spatial mode should behave when the display configuration changes while
  a workspace already has a spatial layout;
- whether different displays should preserve spatial geometry when a workspace
  moves between monitors with different allowed dimensions.
