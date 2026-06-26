# Fit Scroller Specification

## Status

This document is a working product specification.

It defines the expected behavior of Fit Scroller independently from any
particular window manager.

The detailed solver algorithm and validation examples are documented in
[solver/README.md](solver/README.md).

## Version Scope

This document specifies the target behavior for version 1 unless a section is
explicitly marked as a future extension.

Future extensions may be documented in this file while they are still small
and directly related to the V1 model. A separate versioned specification should
only be introduced once multiple released behaviors need to be maintained at
the same time.

## Goals

Fit Scroller must:

- keep windows at dimensions explicitly considered practical by the user;
- fill the visible space as much as possible with configured dimensions;
- preserve a stable window order;
- introduce scrolling when all windows cannot fit at practical dimensions;
- provide discrete, predictable resizing through allowed dimensions;
- behave consistently when windows are added, removed, focused or moved.

## Non-goals

Fit Scroller does not provide:

- arbitrary or pixel-level window resizing;
- automatic reordering based on application, title or recent use;
- overlapping tiled windows;
- dimensions outside the configured allowed set;
- a manually designed layout for every possible window count.

Floating and fullscreen behavior are integrations owned by the host window
manager and are outside this specification.

## Terminology

### Display

The physical or logical output on which a Fit Scroller workspace is shown.

### Viewport

The visible usable rectangle of a display after subtracting reserved areas,
gaps and borders.

### Workspace

An ordered collection of tiled windows. Its layout may extend beyond the
viewport along the configured scroll axis.

### Allowed dimension

A pair `(width, height)` expressed as fractions of the viewport dimensions.
For example, `(0.5, 1.0)` represents half of the viewport width and its full
height.

### Window order

A stable logical sequence containing every tiled window in a workspace.
Layout computation may change dimensions and positions, but must not change
this sequence.

### Auto dimension

The mode in which Fit Scroller chooses a window's dimension from the allowed
set.

### Forced dimension

An allowed dimension explicitly assigned to a window by the user.

### Scroll axis

The axis on which the workspace may exceed the viewport:

- horizontal for `left` and `right`;
- vertical for `up` and `down`.

The direction determines which side receives later workspace content.

### Layout

The dimension and world-space position assigned to every tiled window.

Layout geometry is independent from the current viewport offset.

### Viewport offset

The scroll translation applied when displaying a layout.

Viewport offset is not part of layout solving. It is applied after a layout has
already been computed.

### Tiling mode

The strategy used by the solver to assign dimensions and world-space
positions.

Version 1 supports an order-based tiling model. Spatial tiling, where
placement is chosen from directional adjacency such as left, right, up and
down, is reserved for a future version.

## Configuration

Configuration is defined per display.

The user may define:

- a default display configuration;
- display-specific configurations keyed by display identifier.

When a workspace is laid out on a display, Fit Scroller resolves the effective
configuration for that display. Display-specific values override default
values. If no display-specific configuration exists, the default configuration
is used.

### Required values

- `allowed_dimensions`: a non-empty set of allowed dimensions;
- `scroll_direction`: one of `right`, `left`, `down` or `up`;
- `tiling_mode`: one of `split` or `ajuste`;
- `insert_mode`: one of `last`, `first`, `view`, `after_focused` or
  `before_focused`.

These required values must be present in the effective configuration for every
display used by Fit Scroller.

### Dimension constraints

Each allowed dimension must:

- have a width greater than `0` and less than or equal to `1`;
- have a height greater than `0` and less than or equal to `1`;
- resolve to a usable pixel size after gaps and borders are applied.

Duplicate dimensions are invalid.

The order of `allowed_dimensions` has no semantic meaning. It must not affect
layout selection, dimension sizing or tie-breaking.

### Tiling mode values

`tiling_mode = "split"`:

- prefer incremental splitting of the largest existing slot;
- if the largest slot cannot be split into two configured allowed dimensions,
  fall back to the `ajuste` strategy.

`tiling_mode = "ajuste"`:

- choose dimensions that make window sizes as equivalent as possible;
- when perfect equivalence is impossible, choose the valid layout with the
  smallest size differences while still preserving order, filling visible
  space and minimizing scroll.

### Insert mode values

`insert_mode` controls where newly created tiled windows are inserted in the
logical window order.

It is not a solver option. The solver only consumes the resulting order.

Supported values:

- `last`: insert new windows at the end of the window order;
- `first`: insert new windows at the beginning of the window order;
- `view`: insert new windows after the last currently visible window;
- `after_focused`: insert new windows immediately after the focused window;
- `before_focused`: insert new windows immediately before the focused window.

If a mode-specific anchor is unavailable, insertion falls back to `last`.

`view` is the default V1 behavior.

### Invalid configuration

Invalid configuration must be rejected with a diagnostic that identifies the
invalid value. Fit Scroller must not silently clamp, remove or reinterpret an
invalid dimension.

An invalid display-specific configuration invalidates that display's effective
configuration. It must not be silently ignored in favor of the default
configuration.

## Window Lifecycle

### Insertion

When a tiled window is created, it is inserted according to `insert_mode`.

The new window starts in auto dimension mode.

`insert_mode = "last"`:

- append the new window to the end of the logical window order.

`insert_mode = "first"`:

- insert the new window at the beginning of the logical window order.

`insert_mode = "view"`:

- insert the new window immediately after the last currently visible window;
- if no visible window is known, append it to the end.

`insert_mode = "after_focused"`:

- insert the new window immediately after the currently focused tiled window;
- if no focused tiled window is known, append it to the end.

`insert_mode = "before_focused"`:

- insert the new window immediately before the currently focused tiled window;
- if no focused tiled window is known, append it to the end.

After insertion, the layout is recomputed and the viewport must reveal the new
window.

### Removal

When a tiled window is removed:

- it is removed from the window order;
- the relative order of remaining windows is preserved;
- the layout is recomputed;
- the viewport offset is reduced when possible so that empty workspace is not
  left beyond the final window.

The focused window after removal is selected by the host window manager.

### Explicit move

A user move operation changes a window's position in the logical window order.
It does not directly assign coordinates.

Version 1 supports logical move commands only:

- `move previous`: swaps the focused window with its logical predecessor;
- `move next`: swaps the focused window with its logical successor.

If the focused window has no predecessor or successor in the requested
direction, the command has no effect.

After the order changes, the layout is recomputed and the moved window remains
visible.

Spatial move commands are outside version 1.

## Layout Requirements

### General invariants

For every computed layout:

1. Every tiled window has exactly one configured allowed dimension.
2. A forced window has its forced dimension.
3. Tiled windows do not overlap.
4. Window order is preserved.
5. The workspace only exceeds the viewport along the scroll axis.
6. Every window fits within the workspace on the cross axis.
7. Positions are deterministic for identical input state and configuration.

Gaps and borders are included in the logical space consumed by each window.
They do not alter the configured dimension fractions.

### Order preservation

The layout must define a canonical traversal direction corresponding to the
logical window order. Reading windows using that traversal must produce the
same sequence as the window order.

The configured direction defines both:

- the direction in which windows are placed before scrolling is required; and
- the direction in which the workspace extends once scrolling is required.

For a `right` direction, windows progress top to bottom first, then left to
right. With four windows, the order is:

```text
+---+---+
| A | C |
+---+---+
| B | D |
+---+---+
```

The opposite directions mirror that traversal:

- `left`: top to bottom first, then right to left;
- `down`: left to right first, then top to bottom;
- `up`: left to right first, then bottom to top.

The canonical traversal must preserve the logical window order for every
configured direction.

### Solver and viewport independence

The solver and viewport are separate systems.

The solver decides:

- window dimensions;
- world-space positions;
- workspace extent.

The solver must not read or depend on:

- the focused window;
- the current viewport offset;
- whether a window is currently visible.

The viewport decides:

- the scroll offset used to reveal a focused window;
- the scroll offset used for manual scrolling in future versions.

The viewport must not change:

- window dimensions;
- world-space positions;
- window order.

The solver has priority when both systems need to run. For example, opening a
window changes the window count and can also change focus. Fit Scroller must
first compute the new layout, then reveal the newly focused window using that
layout.

### Solver triggers

The solver runs only when layout structure changes:

- a tiled window is added;
- a tiled window is removed;
- a window's dimension mode changes between auto and forced, or between forced
  dimensions;
- the logical window order changes.

Focus changes and viewport movement must not trigger the solver.

### Viewport triggers

The viewport runs only when scroll offset should change:

- focus changes;
- manual scroll input occurs in a future version.

Window insertion or removal may be followed by a viewport reveal because focus
changed, but that viewport update is a separate step after solver completion.

### Solver philosophy

The solver follows these priorities:

1. fill the visible space;
2. preserve logical window order;
3. keep scroll as small as possible while respecting the previous priorities.

The solver must use only configured allowed dimensions.

### `split` tiling mode

`split` is an incremental order-preserving strategy.

The solver maintains ordered slots. Each slot has a dimension and a world-space
position. Windows are assigned to slots in logical order.

Algorithm:

1. Start with one full viewport slot.
2. If more slots are needed, find the largest existing slot.
3. Check whether that slot can be replaced by two slots whose dimensions are
   both configured allowed dimensions and whose union exactly fills the
   original slot.
4. If the split is possible, replace the original slot with the two new slots
   and preserve traversal order.
5. If the split is not possible, use the `ajuste` strategy for the required
   window count.
6. If all existing visible slots are minimum practical size and more windows
   are needed, append new slots along the scroll axis. The appended slot uses
   the smallest allowed scroll-axis size that minimizes additional scroll and
   the largest allowed cross-axis size that fills visible space.

For horizontal scrolling, this means a new overflow column should be as narrow
as allowed and as tall as allowed.

### `ajuste` tiling mode

`ajuste` computes a valid order-preserving layout directly for the current
window count.

The solver should:

1. generate valid order-preserving layouts using only allowed dimensions;
2. prefer layouts where all windows have the same dimension;
3. when equal dimensions are impossible, prefer the layout with the smallest
   difference between window areas;
4. then prefer the smallest workspace extent along the scroll axis;
5. use stable canonical position order only as a final tie-breaker.

`ajuste` does not first attempt the incremental largest-slot split.

### Reflow stability

Fit Scroller separates layout geometry from viewport translation:

- layout geometry assigns each window a stable world-space rectangle;
- viewport movement only translates those rectangles before placement.

Changing focus or scrolling the viewport must not change selected dimensions
or world-space positions.

Layout recomputation must not change the viewport offset when:

- all window dimensions and positions remain unchanged; and
- the focused window remains fully visible.

Fit Scroller does not guarantee that an auto window keeps its previous
dimension after a lifecycle or configuration change. Stability may be used as
a final tie-breaker, but it must not override filling visible space, preserving
order or minimizing scroll.

## Forced Dimensions

The user may set a window to:

- auto mode; or
- any configured allowed dimension.

Changing this mode triggers layout recomputation.

Version 1 exposes this through `toggle dimension`, which cycles the focused
window between auto mode and forced modes for the configured allowed
dimensions.

The cycle order is:

1. auto mode;
2. forced dimensions from largest to smallest;
3. back to auto mode.

Dimension size is compared by logical area. If two dimensions have the same
area, the wider dimension comes first. If width is also equal, the taller
dimension comes first. The order of `allowed_dimensions` in configuration does
not affect the toggle cycle.

Forced dimensions are honored before auto dimensions are selected. If a forced
dimension can fit by itself on the cross axis, Fit Scroller must keep that
forced dimension and place surrounding windows in adjacent scroll-axis regions
when required.

Forced dimensions may reduce the number of other windows visible in the
viewport. They must not cause other windows to use dimensions outside the
configured allowed set.

If a forced dimension cannot fit on the cross axis, the operation must fail
and preserve the previous layout and dimension mode.

## Scrolling and Focus

### Viewport offset

The viewport offset is zero when the start of the workspace is visible. It is
clamped between zero and the maximum workspace overflow.

Positive offset moves toward the configured scroll direction.

### Focus reveal

When focus changes to a window that is not fully visible, Fit Scroller changes
the viewport offset by the smallest amount necessary to reveal the complete
window.

If the focused window is larger than the effective viewport because of
rounding, gaps or borders, its leading edge is aligned with the viewport's
leading edge.

Focusing an already fully visible window does not scroll the viewport.

### Focus commands

Version 1 supports logical focus commands only:

- `focus previous`: moves focus to the logical predecessor of the focused
  window;
- `focus next`: moves focus to the logical successor of the focused window.

If the focused window has no predecessor or successor in the requested
direction, the command has no effect.

After focus changes, the viewport reveals the focused window according to the
normal focus reveal rules.

Focus changes do not trigger layout solving.

### Manual scrolling

Manual scrolling is not part of version 1.

In version 1, the viewport offset changes only when focus changes and the
focused window must be revealed.

Manual scrolling is a future extension. If added later, it should change the
viewport offset without changing focus or window order, and the offset should
remain clamped to the workspace bounds.

### Direction semantics

For `right`, logical content starts at the left edge, places windows toward
the bottom edge within the current column, then continues rightward before
extending right when scrolling is required.

For `left`, logical content starts at the right edge, places windows toward
the bottom edge within the current column, then continues leftward before
extending left when scrolling is required.

For `down`, logical content starts at the top edge, places windows toward the
right edge within the current row, then continues downward before extending
down when scrolling is required.

For `up`, logical content starts at the bottom edge, places windows toward the
right edge within the current row, then continues upward before extending up
when scrolling is required.

Changing the configured direction recomputes positions while preserving window
order and the focused window.

## Geometry

### Fraction to pixel conversion

Logical dimensions are computed from the usable viewport rectangle.

Pixel conversion must use a deterministic rounding rule. Shared boundaries
must be derived from the same rounded coordinate so adjacent windows do not
produce unintended gaps or overlaps.

### Gaps and borders

Configured fractions describe the complete layout cell consumed by a window,
including the window frame, its borders and its share of inner gaps.

For example, two windows using `0.5 x 1.0` side by side each consume half of
the viewport width. Their frames, borders and the gap between them must be
accounted for within those two equal halves so the visible result remains
symmetrical.

Outer gaps are subtracted from the usable viewport before dimensions are
computed.

Inner gaps and borders are allocated inside the logical rectangle assigned to
a window. They must not cause the resulting frame to exceed that rectangle.

## State

The following state exists per workspace:

- logical window order;
- dimension mode for each window;
- focused window reference;
- viewport offset.

Display configuration is read when the workspace is laid out. Moving a
workspace to another display recomputes its layout using the destination
display's configuration.

Forced dimensions persist for as long as the window exists. They survive
workspace moves and display moves, but are discarded when the window is
closed.

Persistent per-application dimension rules are outside version 1. They may be
added later as explicit configuration rules that assign an initial forced
dimension to matching windows.

## User Commands

Version 1 exposes the following user commands:

- `move previous`: swaps the focused window with its logical predecessor;
- `move next`: swaps the focused window with its logical successor;
- `focus previous`: focuses the logical predecessor of the focused window;
- `focus next`: focuses the logical successor of the focused window;
- `toggle dimension`: cycles the focused window between auto mode and forced
  modes for the configured allowed dimensions, from largest to smallest.

Commands that target a missing predecessor or successor have no effect.

Commands that change order or dimension mode trigger layout recomputation.

Commands that change focus trigger viewport reveal only. They must not trigger
layout recomputation.

## Error Handling

Fit Scroller must preserve the last valid layout when:

- configuration reload fails;
- a forced-dimension request cannot fit on the cross axis;
- the host window manager provides incomplete geometry.

Errors must be observable through the host window manager's logging mechanism.

## Acceptance Scenarios

The scenarios below assume:

```lua
allowed_dimensions = {
    { 1.0, 1.0 },
    { 0.5, 1.0 },
    { 0.5, 0.5 },
}
scroll_direction = "right"
tiling_mode = "split"
```

### Basic fitting

- One auto window occupies `1.0 x 1.0`.
- Two auto windows are both fully visible.
- Three auto windows are all fully visible.
- Four auto windows are all fully visible.
- Opening a fifth window creates horizontal overflow instead of assigning an
  unconfigured dimension.

The exact positions for two to four windows follow order-mode direction
semantics. With `scroll_direction = "right"`, windows progress top to bottom
inside a column, then left to right.

Expected order-preserving sequence:

```text
1 window:  A uses 1.0 x 1.0
2 windows: A and B use 0.5 x 1.0
3 windows: A and B split the first column; C uses the second column
4 windows: A/B and C/D form two half-width columns
5 windows: E is appended as the next narrow full-height column
6 windows: E/F split that appended column
```

### Focus reveal

Given at least one hidden window:

- focusing it makes it fully visible;
- logical window order does not change;
- window dimensions do not change solely because focus changed;
- returning focus to a visible window scrolls only when needed to reveal it.

### Forced fullscreen-sized window

Given several windows, forcing one window to `1.0 x 1.0`:

- preserves window order;
- keeps that window at `1.0 x 1.0`;
- moves other windows into adjacent scroll-axis regions as required;
- reveals the forced window when it is focused.

### Removal after scrolling

Given a viewport scrolled to the final workspace region, removing the final
window clamps the viewport offset and does not leave blank space after the
remaining content.

### Determinism

Given identical configuration, window order and dimension modes, repeated
layout computation produces identical geometry regardless of focus or viewport
offset.

## Decisions Required for Version 1

No unresolved decisions currently block the version 1 reference algorithm.
