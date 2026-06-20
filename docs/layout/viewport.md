# `layout/viewport.lua`

## Phase

Phase 4: Focus and Viewport.

## Purpose

`viewport.lua` computes the scroll offset used to reveal the focused window.

It is host-independent: it receives logical rectangles from the solver and
returns a logical offset. It does not know about Hyprland targets, pixel
areas, dispatchers or layout messages.

`viewport.lua` does not invoke the solver. It consumes the latest valid layout
computed by the solver.

## Responsibilities

In Phase 4, `viewport.lua` must:

- reveal the focused window with the smallest required offset change;
- keep the current offset unchanged when the focused window is already fully
  visible;
- clamp the offset to the workspace bounds;
- reduce the offset after removals when the workspace becomes shorter;
- support all configured scroll directions through traversal metadata;
- keep manual scrolling out of V1 behavior.

It must not:

- choose window dimensions;
- choose window positions;
- trigger layout solving;
- rank layout candidates;
- mutate window order;
- change Hyprland focus;
- convert logical coordinates to pixels.

## Concepts

The viewport offset is measured on the configured scroll axis.

Positive offset always moves toward the configured scroll direction:

- `right`: positive offset reveals content farther to the right;
- `left`: positive offset reveals content farther to the left;
- `down`: positive offset reveals content farther downward;
- `up`: positive offset reveals content farther upward.

The viewport module should use `traversal.lua` metadata so the implementation
does not duplicate direction rules.

## Inputs

Recommended input shape:

```lua
ViewportInput = {
    direction = "right",
    viewport = { x = 0, y = 0, w = 1, h = 1 },
    workspace_extent = 2.0,
    current_offset = 0.5,
    focused_rect = { x = 1.0, y = 0, w = 0.5, h = 1.0 },
}
```

`focused_rect` must already be expressed in the configured direction's logical
coordinate system.

## Output

Recommended output shape:

```lua
ViewportResult = {
    ok = true,
    offset = 1.0,
    changed = true,
}
```

For invalid inputs:

```lua
ViewportResult = {
    ok = false,
    error = "fit-scroller: focused window has no placement"
}
```

## Public API

Recommended functions:

```lua
viewport.clamp_offset(current_offset, viewport_size, workspace_extent)
viewport.reveal(input)
viewport.max_offset(viewport_size, workspace_extent)
```

### `max_offset(viewport_size, workspace_extent)`

Returns the maximum allowed offset on the scroll axis.

```lua
max_offset = math.max(0, workspace_extent - viewport_size)
```

If the workspace fits inside the viewport, the maximum offset is `0`.

### `clamp_offset(current_offset, viewport_size, workspace_extent)`

Clamps an offset between `0` and `max_offset`.

This function is used after:

- removals;
- configuration changes;
- display changes;
- solver output that produces a shorter workspace than the previous layout.

### `reveal(input)`

Returns the offset that reveals the focused rectangle.

Expected behavior:

1. Clamp `current_offset`.
2. Compute the visible interval on the scroll axis.
3. Compute the focused window interval on the scroll axis.
4. If the focused interval is fully visible, keep the clamped offset.
5. If the focused interval starts before the visible interval, align its start.
6. If the focused interval ends after the visible interval, align its end.
7. Clamp the result before returning it.

## Reveal Algorithm

For a normalized scroll axis:

```lua
local viewport_start = current_offset
local viewport_end = current_offset + viewport_size
local window_start = focused_start
local window_end = focused_start + focused_size
```

Then:

```lua
if window_start >= viewport_start and window_end <= viewport_end then
    return current_offset
end

if focused_size > viewport_size then
    return clamp(window_start)
end

if window_start < viewport_start then
    return clamp(window_start)
end

if window_end > viewport_end then
    return clamp(window_end - viewport_size)
end
```

The `focused_size > viewport_size` branch exists for defensive robustness.
Allowed dimensions should normally fit inside the viewport on their own, but
pixel rounding, borders or integration differences may still produce a
slightly oversized final rectangle.

## Direction Handling

The reveal algorithm should operate on a normalized positive scroll axis.

`traversal.lua` owns the mapping from configured direction to logical axis and
sign. `viewport.lua` should ask traversal for:

- the scroll axis;
- the viewport size on that axis;
- the focused rectangle start on that axis;
- the workspace extent on that axis.

This keeps viewport behavior identical for `right`, `left`, `down` and `up`.

## Integration With Solver

The solver and viewport are independent systems that run sequentially.

Structural changes run the solver first:

```text
solver.solve(...)
    -> layout.placements_by_id
    -> state.last_layout is updated
```

Focus or scroll changes run the viewport after a layout already exists:

```text
state.last_layout
    -> viewport.reveal(...)
    -> state.viewport_offset is updated
    -> adapter reapplies state.last_layout relative to viewport_offset
```

The viewport may only change the translation offset. It must not cause the
solver to choose different dimensions or world-space positions for the same
order, config and dimension modes.

If a user-visible action creates a new window and focuses it, those are two
separate effects:

1. the new target count triggers the solver;
2. the focus change triggers viewport reveal using the new layout.

## Removal Clamping

When windows are removed, the workspace extent may shrink.

If the previous offset is now beyond the maximum offset, `viewport.lua` must
reduce it:

```text
before removal: offset = 2.0, max = 2.0
after removal:  offset = 2.0, max = 1.0
result:         offset = 1.0
```

This prevents trailing empty workspace from remaining visible after the final
window is removed.

## Manual Scrolling

Manual scrolling is intentionally absent from V1.

`viewport.lua` may keep the API small enough to add manual scrolling later,
but Phase 4 must not introduce commands or state transitions that move the
viewport independently from focus reveal and clamping.

## Errors

`viewport.reveal` should return an error when:

- `focused_rect` is missing while a focused id exists;
- `workspace_extent` is missing or invalid;
- the viewport size on the scroll axis is zero or negative.

The adapter decides whether to preserve `state.last_layout` or surface the
error. Full recovery behavior is hardened in Phase 5.

## Phase 4 Acceptance Criteria

- The focused window is fully visible after successful focus changes.
- Focusing an already visible window does not change the offset.
- The offset changes by the smallest amount needed to reveal focus.
- Offset is clamped between `0` and maximum workspace overflow.
- Removing trailing windows reduces the offset when needed.
- Direction-specific behavior works for `right`, `left`, `down` and `up`.
- Manual scrolling is not exposed.

## Phase 5 Additions

Phase 5 hardens invalid-input handling and boundary behavior.

`viewport.lua` should remain a small pure module. Its main hardening goal is
to make offset behavior predictable for every boundary case.

## Numeric Validation

Viewport functions should reject:

- `nil` offsets;
- non-number offsets;
- `NaN` offsets;
- negative viewport sizes;
- zero viewport sizes;
- negative workspace extents.

Invalid numeric input should return an error, not a silently clamped value,
except for ordinary out-of-range offsets. Out-of-range offsets are valid input
and should be clamped.

## Boundary Rules

Boundary behavior must be explicit:

- if `workspace_extent <= viewport_size`, the only valid offset is `0`;
- if `current_offset < 0`, clamp to `0`;
- if `current_offset > max_offset`, clamp to `max_offset`;
- if the focused window is exactly aligned with a viewport edge, do not scroll;
- if the focused window is larger than the viewport, align its leading edge.

These rules should be identical for all directions after normalization.

## Geometry Independence

Viewport updates may only change the scroll offset.

Phase 5 tests must prove that changing focus or viewport offset:

- does not invoke the solver;
- does not change world-space placements in `state.last_layout`;
- does not change selected dimensions;
- only changes the visible placement after adapter translation.

This is a cross-module invariant between `viewport.lua`, `state.lua` and
`hyprland_adapter.lua`.

## No-Focus Behavior

When no focused id exists, `viewport.lua` should not reveal anything.

The adapter may call `clamp_offset` directly to keep the offset inside the new
workspace extent after removals or configuration changes.

## Phase 5 Test Cases

Viewport tests should cover:

- workspace smaller than viewport;
- workspace exactly equal to viewport;
- negative offset clamps to zero;
- offset beyond max clamps to max;
- focused window already fully visible;
- focused window before visible interval;
- focused window after visible interval;
- focused window larger than viewport;
- removal that shrinks max offset;
- all four directions through traversal metadata;
- focus reveal does not change `last_layout` placements;
- focus reveal does not change selected dimensions;
- invalid numeric inputs return errors.

## Phase 5 Acceptance Criteria

- Boundary behavior is deterministic and tested.
- Invalid numeric inputs return errors.
- Ordinary out-of-range offsets are clamped.
- No-focus recalculation clamps offset without reveal.
- Viewport changes are translation-only and never alter layout geometry.
- Direction-specific reveal behavior is covered by tests.
