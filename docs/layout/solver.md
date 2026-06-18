# `layout/solver.lua`

## Phase

Phase 3: Geometry and Solver.

## Purpose

`solver.lua` computes the best Fit Scroller layout for the current workspace
state and display configuration.

It is the main implementation of the product rules in `SPECIFICATION.md`.

## Responsibilities

In Phase 3, `solver.lua` must:

- consume ordered target descriptors;
- consume normalized display configuration;
- consume per-window dimension modes;
- generate candidate layouts using only allowed dimensions;
- preserve logical window order;
- honor forced dimensions;
- reject candidates that overlap on the cross axis;
- allow overflow only on the scroll axis;
- rank candidates deterministically;
- return placements as host-independent rectangles.

It must not:

- call `target:place`;
- read raw Hyprland objects;
- mutate workspace state directly;
- change focus;
- implement viewport reveal. Focus reveal belongs to Phase 4.

## Inputs

Recommended input shape:

```lua
SolverInput = {
    config = Config,
    targets = {
        { id = "A" },
        { id = "B" },
    },
    dimension_mode_by_id = {
        A = { kind = "auto" },
        B = { kind = "forced", key = "0.5x1.0" },
    },
    focused_id = "A",
    viewport = { x = 0, y = 0, w = 1, h = 1 },
    viewport_offset = 0,
}
```

## Output

Recommended output shape:

```lua
Layout = {
    placements_by_id = {
        A = { x = 0, y = 0, w = 0.5, h = 1.0 },
    },
    dimensions_by_id = {
        A = { key = "0.5x1.0", w = 0.5, h = 1.0 },
    },
    workspace_extent = 1.0,
    viewport_offset = 0,
    ranking = {
        visible_count = 2,
        min_visible_area = 0.5,
        workspace_extent = 1.0,
    },
}
```

Phase 3 may keep `viewport_offset` unchanged. Phase 4 owns focus reveal and
offset adjustment.

## Candidate Model

A candidate assigns:

- one allowed dimension to each target;
- one logical rectangle to each target;
- a workspace extent along the scroll axis.

Every candidate must satisfy:

- every target has exactly one allowed dimension;
- forced dimensions are preserved;
- rectangles do not overlap;
- logical order is preserved through traversal;
- overflow exists only on the scroll axis;
- every rectangle fits on the cross axis.

## Candidate Generation

Recommended V1 strategy:

1. Normalize the configured direction to canonical `right`.
2. Generate candidate rows from allowed dimensions.
3. Pack targets in logical order.
4. Start a new scroll-axis region when the next target cannot fit.
5. Preserve forced dimensions before selecting auto dimensions.
6. Transform the selected candidate back to the configured direction.

This keeps candidate generation understandable and lets `traversal.lua`
handle direction-specific placement.

## Forced Dimensions

Forced dimensions constrain candidate generation.

If a forced dimension fits on the cross axis, the solver must preserve it even
if doing so reduces the number of other visible windows.

If a forced dimension cannot fit on the cross axis, the solver returns an
error. The caller must preserve the previous valid state and layout.

## Ranking

Candidates are ranked lexicographically:

1. highest number of fully visible windows in the viewport containing the
   focused window;
2. largest minimum visible window area;
3. smallest workspace extent along the scroll axis;
4. stable canonical position order.

### Visible Count

Only fully visible windows count.

Phase 3 may evaluate visibility with the current `viewport_offset`. Phase 4
will adjust the offset to reveal focus before final placement.

### Minimum Visible Window Area

For candidates with the same visible count, compute the area of every fully
visible window and compare the smallest such area.

The candidate whose smallest fully visible window is largest wins.

### Workspace Extent

Workspace extent is measured only on the scroll axis.

Smaller extent wins after visible count and minimum visible area.

### Stable Position Order

If candidates are still equivalent, use `traversal.compare_positions` and
target logical order to choose deterministically.

## Public API

Recommended functions:

```lua
solver.solve(input)
solver.generate_candidates(input)
solver.validate_candidate(candidate, input)
solver.rank_candidate(candidate, input)
solver.compare_candidates(a, b, input)
```

### `solve(input)`

Returns either:

```lua
{ ok = true, layout = Layout }
```

or:

```lua
{ ok = false, error = "fit-scroller: ..." }
```

## Phase 3 Limitations

Phase 3 does not implement:

- focus commands;
- focus reveal offset adjustment;
- manual scrolling;
- last-valid-layout recovery beyond returning errors to the caller.

## Phase 3 Acceptance Criteria

- Solver output is deterministic for identical input.
- Auto windows receive only configured allowed dimensions.
- Forced windows keep their forced dimensions when valid.
- Invalid forced dimensions return errors.
- Candidate ranking follows visible count, minimum visible area, extent and
  stable order.
- Returned placements preserve logical order.
- Overflow occurs only on the configured scroll axis.

## Phase 5 Additions

Phase 5 hardens solver validation, edge-case handling and diagnostics.

The solver should never return a partial layout. It returns either a complete
valid layout for every target, or an error that the adapter can recover from.

## Input Validation

`solver.solve(input)` should validate:

- `config` is present and already normalized;
- `config.allowed_dimensions` is non-empty;
- `config.scroll_direction` is supported;
- `targets` is a list;
- every target has a stable id;
- target ids are unique;
- every forced dimension key exists in `config.dimensions_by_key`;
- `viewport` has positive width and height;
- `viewport_offset` is a finite number greater than or equal to `0`.

Invalid input should produce a structured or readable error and no layout.

## Complete Output Requirement

Successful solver output must include:

- one placement for every target id;
- one dimension for every target id;
- no placements for unknown ids;
- a finite `workspace_extent`;
- a finite `viewport_offset`;
- ranking data useful for diagnostics.

If any placement is missing, the solver must return an error instead of
leaving the adapter to discover the issue during placement.

## Edge Cases

The solver should explicitly handle:

- zero targets;
- one target;
- many targets with all auto dimensions;
- all windows forced to large dimensions;
- mixed forced and auto dimensions;
- focused id missing from targets;
- viewport offset beyond workspace extent;
- equivalent candidates that require deterministic tie-breaking;
- directions `right`, `left`, `down` and `up`.

For zero targets, a successful empty layout is acceptable:

```lua
{
    placements_by_id = {},
    dimensions_by_id = {},
    workspace_extent = 0,
    viewport_offset = 0,
}
```

## Forced Dimension Failure

When a forced dimension cannot fit on the cross axis, the solver returns an
error and no layout.

Recommended error:

```text
fit-scroller: forced dimension 1.0x1.0 does not fit on the cross axis
```

The solver should include the target id and dimension key when practical.

The caller is responsible for preserving the previous dimension mode and
layout.

## Determinism Checks

Candidate generation and ranking must not depend on Lua table iteration order.

Implementation should avoid `pairs()` when order matters. Prefer ordered lists
derived from:

- `workspace_state.order`;
- normalized `config.allowed_dimensions`;
- explicit sorted candidate keys.

Tie-breaking must be stable for identical input.

## Diagnostics

Phase 5 should make solver failures diagnosable without exposing Hyprland
objects.

Useful diagnostic fields:

```lua
{
    code = "forced_dimension_does_not_fit",
    target_id = "B",
    dimension_key = "1.0x1.0",
    direction = "right",
}
```

The adapter may flatten these into strings for Hyprland logs.

## Phase 5 Test Cases

Solver tests should cover:

- zero targets;
- one auto target;
- duplicate target ids rejected;
- missing forced dimension key rejected;
- forced dimension too large for cross axis rejected;
- many equivalent candidates produce stable output;
- candidate ranking prioritizes visible count;
- candidate ranking prioritizes minimum visible area after visible count;
- candidate ranking prioritizes smaller extent after area;
- all four directions preserve logical order;
- no successful layout has missing placements.

## Phase 5 Acceptance Criteria

- Invalid solver input returns an error and no partial layout.
- Successful output contains complete placements and dimensions.
- Candidate ordering is deterministic and independent from table iteration.
- Forced-dimension failures are readable and recoverable by the adapter.
- Edge-case tests cover empty, single-window, forced, mixed and directional
  layouts.
