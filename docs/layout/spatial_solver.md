# `layout/spatial_solver.lua`

## Purpose

`spatial_solver.lua` computes spatial-mode world-space layouts.

This module is separate from the order solver. It is selected only when
`placement_priority = "spatial"`.

The first implementation contains:

- input validation;
- initial global rebuild;
- config-change global rebuild;
- local `window_added` handling;
- local `window_removed` handling;
- local `dimension_forced` handling;
- local `dimension_auto` handling;
- local `move` handling;
- complete layout output for every target;
- forced-dimension validation and preservation.

## Responsibilities

`spatial_solver.lua` must:

- validate spatial solver input;
- require `config.placement_priority = "spatial"`;
- validate target ids and dimension modes;
- validate forced dimension keys;
- validate `viewport_offset`;
- validate `last_layout` for local events;
- return complete placements and dimensions;
- avoid partial layouts.

It must not:

- read raw Hyprland objects;
- call `target:place`;
- invoke viewport reveal;
- mutate workspace state;
- use order traversal as user-visible behavior.

## Input

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
        kind = "initial" | "config_changed" | "window_added" |
               "window_removed" | "dimension_forced" |
               "dimension_auto" | "move",
    },
}
```

`last_layout` may be absent for `initial` and `config_changed`.

`last_layout` is required for local events.

## Output

Successful output:

```lua
{
    ok = true,
    layout = {
        placements_by_id = {
            A = { x = 0, y = 0, w = 1, h = 1 },
        },
        dimensions_by_id = {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        },
        workspace_extent = 1,
        diagnostics = {
            strategy = "initial_global_rebuild",
        },
    },
    diagnostics = {
        strategy = "initial_global_rebuild",
    },
}
```

Failure output:

```lua
{
    ok = false,
    error = "fit-scroller: spatial: ..."
}
```

## Initial Global Rebuild

When no previous spatial geometry exists, the solver has no positions to
preserve.

The initial rebuild uses deterministic internal target order and places each
window in its own scroll-axis slot:

- `right`: increasing positive `x`;
- `left`: increasing negative `x`;
- `down`: increasing positive `y`;
- `up`: increasing negative `y`.

Auto windows use the first normalized allowed dimension. Since `config.lua`
sorts dimensions by practical size, this is currently the largest configured
dimension.

Forced windows use their forced dimension exactly.

This initial rebuild is intentionally simple. Later steps replace or augment it
with local spatial candidate generation and spatial global ranking.

## Global Rebuild

Global rebuild is used for initial layout, config changes, multi-window
structural changes, and local fallback paths.

When no previous layout exists, the solver uses the deterministic dense rebuild
described above.

When a previous layout exists, the solver generates and ranks these candidates:

- dense rebuild from the current target list;
- preserve existing valid placements and append missing targets;
- preserve existing valid placements, append missing targets, then compact
  auto windows toward the scroll origin.

Removed windows are omitted from preserved candidates.

Preserved placements must still match current dimension constraints:

- forced windows must match their forced dimension exactly;
- auto windows must match an allowed configured dimension.

Global candidates are ranked by:

1. count of visible windows preserved without movement or resize;
2. total movement distance from previous geometry;
3. resize count;
4. workspace extent;
5. fill quality;
6. stable candidate rank.

Global rebuild does not call or reuse the order solver.

## Window Addition

For `event.kind = "window_added"`, the solver first tries local split
candidates.

A split candidate:

- selects one existing auto window from `last_layout`;
- replaces only that source window's rectangle;
- gives the source and new window allowed dimensions;
- keeps every other placement unchanged;
- rejects overlap and cross-axis overflow.

Split candidates are ranked by:

1. visible source window before non-visible source window;
2. larger source area;
3. smaller uncovered source area;
4. smaller workspace extent;
5. stable source id.

If no split is valid, the solver appends the new window on the scroll axis
using the dimension that increases scroll extent the least.

Current strategies:

- `local_split`;
- `local_append`.

## Window Removal

For `event.kind = "window_removed"`, the solver uses the removed window's
previous rectangle from `event.previous_rect` or from `last_layout`.

If the previous rectangle is unavailable, the solver routes the event to a
global rebuild because it cannot identify the freed spatial area.

When the removed rectangle is known, the solver:

1. removes the deleted window from previous placements and dimensions;
2. when the freed rectangle spans the full cross axis, tries to close the hole
   by shifting every later window toward the scroll origin;
3. when the freed rectangle is only partial on the cross axis, tries to fill it
   by resizing an adjacent auto window in the same column or row;
4. tries to expand an adjacent auto window into the freed rectangle when the
   union matches an allowed dimension;
5. preserves all remaining rectangles when no valid local repair exists;
6. recomputes `workspace_extent` from the resulting placements.

Partial cross-axis repair ranks dimensions by scroll-axis size:

1. keep the current column or row scroll size;
2. shrink the column or row scroll size and compact later windows;
3. grow the column or row scroll size and push later windows away.

Forced adjacent windows are not resized by removal handling.

Current strategies:

- `local_compact_full_cross_hole`;
- `local_cross_fill`;
- `local_expand`;
- `local_preserve`;
- `global_rebuild`.

## Forced Dimension

For `event.kind = "dimension_forced"`, the solver validates that:

- the target is present;
- the target's draft dimension mode is `forced`;
- the event key matches the draft forced key;
- the key exists in `config.dimensions_by_key`.

The local algorithm tries:

1. resize around the target's current top-left corner;
2. resize around the target's current center;
3. the same candidates while pushing overlapping auto neighbors along the
   configured scroll direction.

Auto neighbors may be moved but keep their dimensions. Forced neighbors are not
pushed by local candidates. If no local candidate succeeds, the solver falls
back to global rebuild.

When a forced resize frees a rectangle that spans the full cross axis, the
solver tries to close that hole by shifting every later window toward the scroll
origin. In horizontal scrolling, this means shifting later windows left for
`right` and right for `left`; in vertical scrolling, this means shifting later
windows up for `down` and down for `up`.

When the freed rectangle is only partial on the cross axis, the solver tries to
fill it by resizing an adjacent auto window in the same column or row. The same
dimension ranking is used as for removal: keep the scroll-axis size first,
shrink it second, grow it last.

Current strategies:

- `local_resize`;
- `local_push`;
- `local_compact_full_cross_hole`;
- `local_push_compact_full_cross_hole`;
- `local_cross_fill`;
- `local_push_cross_fill`;
- `global_rebuild`.

## Return To Auto

For `event.kind = "dimension_auto"`, the solver validates that the target is
present and that its draft dimension mode is already `auto`.

The local algorithm generates candidates for every allowed dimension of the
target:

- resize around the target's current top-left corner;
- resize around the target's current center;
- compact auto windows toward the scroll origin when that removes scroll-axis
  gaps.

Candidate ranking prefers layouts that reduce workspace extent. When no
candidate reduces extent, it prefers larger target area instead of preserving
the previous forced dimension.

Forced neighbors are not moved during auto compaction.

Current strategies:

- `local_auto_resize`;
- `local_auto_compact`;
- `global_rebuild`.

## Spatial Move

For `event.kind = "move"`, the solver validates the target id and requested
direction.

The local algorithm generates candidates that move the target's center in the
requested direction:

- swap with a directional neighbor when both windows can use each other's
  rectangle dimensions;
- split a directional auto neighbor when direct swap is incompatible;
- extend on the configured scroll axis when the requested direction matches
  `config.scroll_direction`.

Forced dimensions are hard constraints. A forced target can move only into a
rectangle matching its forced key, and forced neighbors are not resized by split
move candidates.

If no candidate produces directional progress, the solver returns the previous
layout with strategy `noop`.

Current strategies:

- `local_swap`;
- `local_split_move`;
- `local_scroll_extend`;
- `noop`.

## Guarantees

- The solver can be tested without Hyprland.
- Invalid input returns readable errors.
- Duplicate target ids are rejected.
- Invalid forced dimensions are rejected.
- Initial rebuild returns complete placements for every target.
- `window_added` can split an existing visible auto window.
- `window_added` appends when no split is valid.
- `window_removed` can expand an adjacent auto window into the freed area.
- `window_removed` can compact later windows into a full-cross freed area.
- `window_removed` can fill a partial cross-axis hole by resizing an auto
  window in the same column or row.
- `window_removed` preserves remaining placements when expansion is invalid.
- `window_removed` reduces trailing scroll extent through extent recomputation.
- `dimension_forced` applies the requested dimension exactly.
- `dimension_forced` can push overlapping auto neighbors along the scroll axis.
- `dimension_forced` can compact later windows into a full-cross hole created
  by a forced shrink.
- `dimension_forced` can fill a partial cross-axis hole created by a forced
  shrink.
- `dimension_auto` can shrink a forced-large window when compaction reduces
  extent.
- `dimension_auto` can grow a forced-small window when there is no compaction
  gain.
- `move` requires visible directional progress unless it returns `noop`.
- `move` preserves forced dimensions.
- Global rebuild preserves valid previous spatial geometry when it wins the
  spatial cost ranking.
- Global rebuild can append multiple additions and omit multiple removals.
- Local events without `last_layout` are rejected.
- Unsupported local events are not silently treated as order-mode solves.
