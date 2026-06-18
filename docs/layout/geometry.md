# `layout/geometry.lua`

## Phase

Phase 3: Geometry and Solver.

## Purpose

`geometry.lua` provides host-independent geometry primitives for Fit Scroller.

It must not depend on Hyprland objects. Its functions operate on plain Lua
tables so they can be tested without a running compositor.

## Responsibilities

In Phase 3, `geometry.lua` must:

- define rectangle and dimension helpers;
- compute areas;
- compare dimensions deterministically;
- convert configured fractions to logical rectangles;
- check containment and overlap;
- compute visibility inside a viewport;
- provide deterministic rounding helpers for adapter use.

It must not:

- read `ctx`, `target` or Hyprland area objects;
- know about window order;
- decide traversal direction;
- rank full layout candidates.

## Core Types

### `Rect`

```lua
Rect = {
    x = number,
    y = number,
    w = number,
    h = number,
}
```

Coordinates are logical coordinates.

### `Dimension`

```lua
Dimension = {
    key = "0.5x1.0",
    w = number,
    h = number,
}
```

`w` and `h` are fractions of the usable viewport.

## Coordinate Model

The core geometry uses a normalized logical viewport:

```lua
viewport = { x = 0, y = 0, w = 1, h = 1 }
```

Candidate layouts may extend beyond this viewport only on the scroll axis.

Actual pixel conversion belongs at the Hyprland adapter boundary.

## Public API

Recommended functions:

```lua
geometry.rect(x, y, w, h)
geometry.area(rect)
geometry.dimension_area(dimension)
geometry.dimension_rect(viewport, dimension, x, y)
geometry.contains(outer, inner)
geometry.overlaps(a, b)
geometry.intersection(a, b)
geometry.visible_area(rect, viewport)
geometry.is_fully_visible(rect, viewport)
geometry.compare_dimension_size(a, b)
geometry.round_rect(rect, pixel_viewport)
```

### `compare_dimension_size(a, b)`

Compares dimensions using the same ordering as `toggle dimension`:

1. larger logical area first;
2. wider first when areas are equal;
3. taller first when width is equal.

This comparison is for deterministic ordering only. Layout selection still uses
the solver ranking rules.

### `is_fully_visible(rect, viewport)`

Returns true when the full rectangle is inside the viewport.

This is used by the solver when ranking candidates by visible window count.

### `round_rect(rect, pixel_viewport)`

Converts a logical rectangle into pixel coordinates.

Rounding must be deterministic. Shared boundaries should be rounded from the
same coordinate values, not by independently rounding widths, to avoid
accidental gaps or overlaps.

## Gaps and Borders

Fit Scroller dimensions describe complete logical layout cells, including the
window frame, borders and the cell's share of inner gaps.

`geometry.lua` should therefore treat a dimension such as `0.5x1.0` as half of
the logical viewport. The adapter may later account for Hyprland-specific
details when converting logical rectangles to placement areas.

## Invariants

Geometry helpers must preserve:

- non-negative width and height;
- deterministic results for identical inputs;
- no hidden dependency on Hyprland state;
- exact logical fractions until explicit rounding is requested.

## Phase 3 Acceptance Criteria

- Area calculation is deterministic.
- Dimension comparison follows area, width, height.
- Containment and overlap checks work for adjacent rectangles.
- Full visibility can be computed against a viewport.
- Logical rectangles can be converted to pixel rectangles consistently.

## Phase 5 Additions

Phase 5 hardens numeric validation and rounding edge cases.

Geometry helpers are used by the solver, viewport and adapter. They should
fail clearly on invalid numbers instead of letting invalid rectangles propagate
into placement.

## Numeric Validation

Geometry functions should reject:

- non-number coordinates;
- `NaN` values;
- infinite values;
- negative widths;
- negative heights;
- zero widths or heights when the caller requires a usable rectangle.

Whether zero-size rectangles are accepted should be explicit per function.
For Fit Scroller placements, zero-size rectangles are invalid.

## Rounding Tests

Pixel rounding should be tested with shared boundaries.

Example:

```text
logical: [0.0, 0.5] [0.5, 1.0]
pixel:   [0, 960]   [960, 1920]
```

The boundary at `0.5` must produce the same pixel coordinate for both adjacent
rectangles.

## Phase 5 Test Cases

Geometry tests should cover:

- invalid rectangles rejected;
- adjacent rectangles do not overlap;
- overlapping rectangles are detected;
- full visibility at exact viewport edges;
- partial visibility before and after viewport;
- dimension comparison with equal area;
- deterministic rounding of shared boundaries;
- no negative pixel widths after rounding.

## Phase 5 Acceptance Criteria

- Invalid numeric input does not propagate silently.
- Rounding is deterministic at shared boundaries.
- Visibility and overlap behavior is tested at edges.
- Geometry remains independent from Hyprland objects.
