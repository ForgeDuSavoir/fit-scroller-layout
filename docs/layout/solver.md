# `layout/solver.lua`

## Purpose

`solver.lua` computes the best Fit Scroller layout for the current workspace
state and display configuration.

It is the main implementation of the product rules in `SPECIFICATION.md`.

The detailed official solver behavior is documented in
[../solver/detailed-logic.md](../solver/detailed-logic.md).

Validated implementation examples are documented in:

- [../solver/base-examples.md](../solver/base-examples.md);
- [../solver/forced-examples.md](../solver/forced-examples.md).

## Responsibilities

`solver.lua` must:

- consume ordered target descriptors;
- consume normalized display configuration;
- consume per-window dimension modes;
- generate order-preserving layouts using only allowed dimensions;
- preserve logical window order;
- honor forced dimensions;
- reject candidates that overlap on the cross axis;
- allow overflow only on the scroll axis;
- rank candidates according to the official solver logic;
- return placements as host-independent rectangles.

It must not:

- call `target:place`;
- read raw Hyprland objects;
- mutate workspace state directly;
- change focus;
- read focused id;
- read viewport offset;
- decide whether the focused window is visible;
- implement viewport reveal. Focus reveal belongs to `viewport.lua`.

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
}
```

The solver input must not include focus or viewport state. If adapter code has
that information, it must not pass it to the solver.

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
}
```

The solver output is world-space geometry only. `viewport.lua` owns viewport
reveal and offset adjustment.

## Candidate Model

A layout assigns:

- one allowed dimension to each target;
- one logical rectangle to each target;
- a workspace extent along the scroll axis.

Every layout must satisfy:

- every target has exactly one allowed dimension;
- forced dimensions are preserved;
- rectangles do not overlap;
- logical order is preserved through traversal;
- overflow exists only on the scroll axis;
- every rectangle fits on the cross axis.

## Trigger Contract

The solver runs only when structure changes:

- target count changes;
- logical order changes;
- a target's dimension mode changes.

The solver must not run for:

- focus-only changes;
- viewport offset changes;
- future manual scroll input.

When both a structure change and a focus change happen in the same user-visible
operation, the adapter must run the solver first and the viewport second.

## Order Mode

Version 1 uses order-mode tiling only.

For `scroll_direction = "right"`, order is assigned top to bottom inside a
column, then left to right across columns. The same rule is transformed for
the other directions by `traversal.lua`.

Spatial placement, where windows are positioned by directional adjacency, is a
future version concern and must not be mixed into the V1 solver.

## Official Solver Logic

The solver uses one candidate-based strategy for both auto and forced
dimensions.

The solver must:

1. normalize the configured direction to a canonical `right` layout problem;
2. resolve each target's dimension mode;
3. generate valid ordered column candidates;
4. reject candidates that violate forced dimensions;
5. rank candidates by scroll, fill, balance, practical size and stable
   tie-breakers;
6. transform the selected canonical layout back to the configured direction.

The current official solver behavior uses one candidate-based strategy.

The complete candidate model, forced-dimension rules, ranking rules and
examples are documented in
[../solver/detailed-logic.md](../solver/detailed-logic.md).

## Forced Dimensions

Forced dimensions constrain candidate generation.

If a forced dimension fits on the cross axis, the solver must preserve it even
if doing so reduces the number of other visible windows.

If a forced dimension cannot fit on the cross axis, the solver returns an
error. The caller must preserve the previous valid state and layout.

## Workspace Extent

Workspace extent is measured only on the scroll axis.

Smaller extent wins according to the ranking documented in
[../solver/detailed-logic.md](../solver/detailed-logic.md).

### Stable Position Order

If candidates are still equivalent, use `traversal.compare_positions` and
target logical order to choose deterministically.

## Public API

Recommended functions:

```lua
solver.solve(input)
solver.generate_layouts(input)
solver.validate_candidate(candidate, input)
solver.rank_candidate(candidate, input)
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

## Limitations

The current solver intentionally does not implement:

- focus commands;
- focus reveal offset adjustment;
- manual scrolling;
- last-valid-layout recovery beyond returning errors to the caller.

## Guarantees

- Solver output is deterministic for identical input.
- Auto windows receive only configured allowed dimensions.
- Forced windows keep their forced dimensions when valid.
- Invalid forced dimensions return errors.
- Returned placements preserve logical order.
- Overflow occurs only on the configured scroll axis.
- Candidate ranking follows
  [../solver/detailed-logic.md](../solver/detailed-logic.md).

## Hardening

This section defines solver validation, edge-case handling and diagnostics.

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
- no focus id, viewport rectangle or viewport offset is required to compute
  geometry.

Invalid input should produce a structured or readable error and no layout.

## Complete Output Requirement

Successful solver output must include:

- one placement for every target id;
- one dimension for every target id;
- no placements for unknown ids;
- a finite `workspace_extent`;
- diagnostic data useful for explaining solver decisions.

If any placement is missing, the solver must return an error instead of
leaving the adapter to discover the issue during placement.

## Edge Cases

The solver should explicitly handle:

- zero targets;
- one target;
- many targets with all auto dimensions;
- all windows forced to large dimensions;
- mixed forced and auto dimensions;
- equivalent layouts that require deterministic tie-breaking;
- directions `right`, `left`, `down` and `up`.
- focus and viewport values changing outside the solver.

For zero targets, a successful empty layout is acceptable:

```lua
{
    placements_by_id = {},
    dimensions_by_id = {},
    workspace_extent = 0,
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

## Solver and Viewport Independence Tests

Regression tests must prove that solver output depends only on:

- normalized configuration;
- ordered targets;
- forced dimension modes.

Changing any of the following must not change solver output:

- focused id;
- current viewport offset;
- whether a target is currently visible;
- pending viewport reveal state.

The adapter should enforce this by not passing focus or viewport state to
`solver.solve(input)`.

## Solver Logic Tests

Solver logic tests must cover the official validation corpora:

- [../solver/base-examples.md](../solver/base-examples.md);
- [../solver/forced-examples.md](../solver/forced-examples.md).

Tests should also prove:

- no successful candidate violates a forced dimension;
- no successful candidate invents a dimension outside `allowed_dimensions`;
- no successful candidate overlaps on the cross axis;
- `0.99` fills from configured third-based dimensions are treated as complete
  fills;
- output remains deterministic when candidates tie.

## Diagnostics

Solver failures should be diagnosable without exposing Hyprland objects.

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

## Test Cases

Solver tests should cover:

- zero targets;
- one auto target;
- duplicate target ids rejected;
- missing forced dimension key rejected;
- forced dimension too large for cross axis rejected;
- many equivalent candidates produce stable output;
- all examples in [../solver/base-examples.md](../solver/base-examples.md);
- all examples in
  [../solver/forced-examples.md](../solver/forced-examples.md);
- all four directions preserve logical order;
- focus changes do not change solver output;
- viewport offset changes do not change solver output;
- no successful layout has missing placements.

## Guarantees

- Invalid solver input returns an error and no partial layout.
- Successful output contains complete placements and dimensions.
- Candidate ordering is deterministic and independent from table iteration.
- Forced-dimension failures are readable and recoverable by the adapter.
- Solver output is independent from focus and viewport state.
- Edge-case tests cover empty, single-window, forced, mixed and directional
  layouts.
