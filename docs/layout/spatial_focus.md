# `layout/spatial_focus.lua`

## Purpose

`spatial_focus.lua` resolves spatial focus directions to target ids.

It is used by spatial mode commands such as:

```text
focus left
focus right
focus up
focus down
```

The module is host-independent. It reads world-space rectangles from
`last_layout` and returns the id of the best directional candidate. It does
not call Hyprland and does not mutate workspace state.

## Responsibilities

`spatial_focus.lua` must:

- validate spatial focus input;
- read the focused target's rectangle from `last_layout`;
- find candidates in the requested half-plane;
- rank candidates deterministically;
- return a target id for the adapter to focus;
- return no-op results when no focused id or no candidate exists.

It must not:

- place windows;
- invoke the solver;
- update `state.focused_id`;
- call Hyprland dispatchers;
- mutate `last_layout`.

## Input

Recommended input shape:

```lua
SpatialFocusInput = {
    focused_id = "A",
    direction = "left" | "right" | "up" | "down",
    last_layout = {
        placements_by_id = {
            A = { x = 1, y = 1, w = 0.5, h = 0.5 },
            B = { x = 0, y = 1, w = 0.5, h = 0.5 },
        },
    },
}
```

## Output

When a candidate is found:

```lua
{
    ok = true,
    changed = true,
    focus_target_id = "B",
    target_id = "B",
    direction = "left",
}
```

When no focus can be applied:

```lua
{
    ok = true,
    changed = false,
}
```

For invalid input:

```lua
{
    ok = false,
    error = "fit-scroller: spatial focus: ..."
}
```

## Ranking

Candidates are considered only when their center lies in the requested
half-plane from the focused window's center.

Valid candidates are ranked by:

1. strongest overlap on the perpendicular axis;
2. shortest distance on the requested axis;
3. shortest center-to-center Manhattan distance;
4. stable target id.

This matches user expectation for directional focus: prefer a window that is
clearly aligned in the requested direction, then choose the nearest aligned
candidate.

## Guarantees

- Spatial focus does not invoke the solver.
- Spatial focus does not change layout geometry.
- Missing focused id is a no-op.
- Missing `last_layout` is an error when a focused id exists.
- Ties are deterministic.
