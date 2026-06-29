# `layout/spatial_geometry.lua`

## Purpose

`spatial_geometry.lua` provides host-independent geometry helpers for spatial
placement mode.

It exists so the spatial solver, spatial focus resolver and adapter tests can
share one deterministic rectangle model without depending on Hyprland objects.

## Responsibilities

`spatial_geometry.lua` must:

- validate normalized rectangles;
- expose scroll-axis and cross-axis intervals for every scroll direction;
- compute visibility from `viewport_offset`;
- detect overlap and adjacency;
- compute center movement and resize distances;
- detect directional progress for spatial move commands;
- keep all helpers independent from Hyprland.

It must not:

- place windows;
- read workspace state;
- read raw Hyprland targets;
- choose window dimensions;
- rank complete layout candidates by itself.

## Coordinate Model

The module works on normalized world-space rectangles:

```lua
Rect = {
    x = number,
    y = number,
    w = number,
    h = number,
}
```

For `right` and `down`, scroll coordinates grow positively.

For `left` and `up`, existing Fit Scroller layout geometry uses negative
world-space coordinates. Visibility therefore compares the absolute position
on the scroll axis with `viewport_offset`, matching `viewport.lua` and the
adapter's viewport translation behavior.

## Public Helpers

Recommended helper groups:

```lua
spatial_geometry.validate_rect(rect)
spatial_geometry.validate_direction(direction)
spatial_geometry.scroll_interval(rect, direction)
spatial_geometry.cross_interval(rect, direction)
spatial_geometry.is_visible(rect, viewport_offset, direction)
spatial_geometry.is_fully_visible(rect, viewport_offset, direction)
spatial_geometry.visible_overlap(rect, viewport_offset, direction)
spatial_geometry.overlaps(a, b)
spatial_geometry.adjacent_side(a, b)
spatial_geometry.is_adjacent(a, b, side?)
spatial_geometry.movement_distance(previous_rect, next_rect)
spatial_geometry.resize_distance(previous_rect, next_rect)
spatial_geometry.directional_progress(previous_rect, next_rect, direction)
```

## Guarantees

- Invalid rectangles return readable validation errors.
- Touching edges are adjacency, not overlap.
- Corner-only contact is not adjacency.
- Visibility is derived from world-space geometry and `viewport_offset`.
- Movement and resize metrics are deterministic.
- The module can be tested without loading Hyprland or the adapter.
