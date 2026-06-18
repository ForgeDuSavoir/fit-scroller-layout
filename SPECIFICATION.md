# Fit Scroller Specification

## Status

This document is a working product specification.

It defines the expected behavior of Fit Scroller independently from any
particular window manager.

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
- maximize the number of windows visible in the viewport;
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

The dimension and position assigned to every tiled window, together with the
current viewport offset.

## Configuration

Configuration is defined per display.

### Required values

- `allowed_dimensions`: a non-empty set of allowed dimensions;
- `scroll_direction`: one of `right`, `left`, `down` or `up`.

### Dimension constraints

Each allowed dimension must:

- have a width greater than `0` and less than or equal to `1`;
- have a height greater than `0` and less than or equal to `1`;
- resolve to a usable pixel size after gaps and borders are applied.

Duplicate dimensions are invalid.

The order of `allowed_dimensions` has no semantic meaning. It must not affect
layout selection, dimension sizing or tie-breaking.

### Invalid configuration

Invalid configuration must be rejected with a diagnostic that identifies the
invalid value. Fit Scroller must not silently clamp, remove or reinterpret an
invalid dimension.

## Window Lifecycle

### Insertion

When a tiled window is created, it is inserted immediately after the currently
focused tiled window.

If no tiled window is focused, it is appended to the window order.

The new window starts in auto dimension mode unless a matching window rule
assigns a forced dimension.

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

For a `right` direction, windows progress left to right first, then top to
bottom. With four windows, the order is:

```text
+---+---+
| A | B |
+---+---+
| C | D |
+---+---+
```

The opposite directions mirror that traversal:

- `left`: right to left first, then top to bottom;
- `down`: top to bottom first, then left to right;
- `up`: bottom to top first, then left to right.

The canonical traversal must preserve the logical window order for every
configured direction.

### Candidate layouts

A candidate layout assigns an allowed dimension and a position to every
window while satisfying all general invariants.

Forced dimensions constrain candidate generation and cannot be changed by the
layout solver.

### Layout selection

Candidate layouts are ranked lexicographically by:

1. highest number of windows fully visible in the viewport containing the
   focused window;
2. largest minimum visible window area, while keeping the same number of
   windows visible;
3. smallest workspace extent along the scroll axis;
4. stable canonical position order.

The first candidate in this ordering is selected.

This ranking formalizes the layout strategy:

- fit as many windows as possible in the viewport;
- among layouts with the same visible window count, avoid sacrificing one
  visible window to make other visible windows larger;
- use only dimensions from the configured allowed set.

Dimension size is derived from the resulting geometry, not from the position
of a dimension in the configuration.

The size metric for visible windows is the area of each visible window's
logical rectangle. When several candidates show the same number of windows,
Fit Scroller compares the smallest visible window area in each candidate and
keeps the candidate whose smallest visible window is largest.

### Reflow stability

Layout recomputation must not change the viewport offset when:

- all window dimensions and positions remain unchanged; and
- the focused window remains fully visible.

Fit Scroller does not guarantee that an auto window keeps its previous
dimension after a lifecycle or configuration change. Stability may be used as
a final tie-breaker, but it must not reduce visible window count.

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

### Manual scrolling

Manual scrolling is not part of version 1.

In version 1, the viewport offset changes only when focus changes and the
focused window must be revealed.

Manual scrolling is a future extension. If added later, it should change the
viewport offset without changing focus or window order, and the offset should
remain clamped to the workspace bounds.

### Direction semantics

For `right`, logical content starts at the left edge, places windows toward
the right edge, then continues downward before extending right when scrolling
is required.

For `left`, logical content starts at the right edge, places windows toward
the left edge, then continues downward before extending left when scrolling is
required.

For `down`, logical content starts at the top edge, places windows toward the
bottom edge, then continues rightward before extending down when scrolling is
required.

For `up`, logical content starts at the bottom edge, places windows toward the
top edge, then continues rightward before extending up when scrolling is
required.

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

Commands that change focus, order or dimension mode trigger layout
recomputation and must leave the focused window visible.

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
```

### Basic fitting

- One auto window occupies `1.0 x 1.0`.
- Two auto windows are both fully visible.
- Three auto windows are all fully visible.
- Four auto windows are all fully visible.
- Opening a fifth window creates horizontal overflow instead of assigning an
  unconfigured dimension.

The exact positions for two to four windows follow the configured direction
semantics. With `scroll_direction = "right"`, windows progress left to right
first, then top to bottom.

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

Given identical configuration, window order, dimension modes, focus and
viewport size, repeated layout computation produces identical geometry.

## Decisions Required for Version 1

No unresolved decisions currently block the version 1 reference algorithm.
