# Solver Implementation Plan

This document tracks the implementation work required to align the current code
with the official solver documentation.

Normative references:

- [Solver detailed logic](detailed-logic.md)
- [Base solver examples](base-examples.md)
- [Forced solver examples](forced-examples.md)
- [Solver module contract](../layout/solver.md)
- [Configuration module contract](../layout/config.md)

## Current State

The documentation defines one candidate-based solver strategy.

The current code still contains:

- a `tiling_mode` configuration field;
- separate `split` and fallback candidate behavior in `layout/solver.lua`;
- tests that assert `tiling_mode = "split"`;
- tests named after the old split behavior.

The current test suite passes, but it validates the old behavior rather than
the official solver logic.

## Implementation Sequence

Implement these steps in order. Each step should leave the test suite in a
known state.

### Step 1: Remove `tiling_mode` From Configuration

Status: completed.

- Remove `VALID_TILING_MODES` from `layout/config.lua`.
- Remove `tiling_mode` from the default raw configuration.
- Remove `tiling_mode` validation.
- Remove `tiling_mode` from normalized config output.
- Remove `tiling_mode` from display override resolution.
- Update config tests that currently expect `tiling_mode = "split"`.
- Decide and document whether unknown legacy `tiling_mode` fields are ignored
  or rejected.

Decision:

- legacy `tiling_mode` fields are ignored by configuration normalization;
- they are not validated, copied into display overrides or exposed in the
  normalized configuration.

Validation:

- `rg tiling_mode layout/config.lua tests/core_test.lua` should return no
  configuration-test dependency on `tiling_mode`.
- Existing non-solver tests should still pass.

### Step 2: Add Official Solver Example Tests

Status: completed.

Add a dedicated solver example test file, for example:

```text
tests/solver_examples_test.lua
```

The tests should cover every validated example from:

- `docs/solver/base-examples.md`;
- `docs/solver/forced-examples.md`.

Test helpers should:

- build normalized configs from explicit allowed dimensions;
- build target lists from example window ids;
- build `dimension_mode_by_id` from forced window definitions;
- call `solver.solve`;
- assert expected dimensions by id;
- assert forced windows keep their exact dimension;
- assert no assigned dimension is outside `allowed_dimensions`;
- assert no rectangles overlap;
- assert overflow occurs only on the configured scroll axis;
- assert logical order is preserved in canonical coordinates;
- assert `0.99` fills from configured third-based dimensions are treated as
  complete fills.

Expected initial result:

- many new solver example tests may fail before the solver is replaced.

### Step 3: Replace Old Solver Branching With One Strategy

Status: completed.

In `layout/solver.lua`:

- remove the `input.config.tiling_mode` validation;
- remove the `solve_split` branch;
- remove `split_err` fallback behavior;
- remove functions used only by the old split solver:
  - `split_candidates_for_slot`;
  - `append_slot`;
  - `generate_split_slots`;
  - `layout_from_slots`;
  - `solve_split`.

The solver should always:

1. validate input;
2. normalize to canonical direction;
3. resolve dimension modes;
4. generate valid candidate layouts;
5. rank candidates;
6. select the best candidate;
7. transform back to the configured direction.

Validation:

- no solver code should branch on `tiling_mode`;
- old split-specific errors should be gone;
- tests should fail only because candidate generation or ranking is not yet
  complete.

### Step 4: Implement Column-Based Candidate Generation

Status: completed.

Generate candidates using ordered column partitions.

For canonical `right`:

- each column contains a consecutive slice of targets;
- every window in a column shares the same scroll size;
- cross sizes in a column sum to `<= 1 + epsilon`;
- each assigned dimension exists in `allowed_dimensions`;
- forced windows use exactly their forced dimension;
- full-cross forced windows are singleton columns;
- partial forced windows may share a column with adjacent compatible windows.

Candidate generation may be exhaustive or pruned, but it must include every
candidate shape required by the official examples.

Implementation tasks:

- compute canonical dimensions for the current `scroll_direction`;
- compute deterministic dimension priorities independent from config order;
- enumerate ordered partitions or equivalent procedural candidates;
- generate valid column patterns for each partition;
- reject invalid forced column combinations;
- compute canonical rectangles from column patterns;
- compute `workspace_extent`.

Validation:

- base examples should start passing for simple auto cases;
- forced examples should reject invalid forced dimensions instead of changing
  them.

### Step 5: Implement Official Candidate Ranking

Status: completed.

Rank valid candidates by the documented criteria:

1. validity;
2. minimum scroll overflow;
3. no-scroll viewport use;
4. uniform full-cross preference;
5. better cross-axis fill;
6. balanced column counts;
7. larger practical dimensions;
8. smaller auto area range;
9. stable position and dimension tie-breakers.

Important details:

- do not minimize `workspace_extent` blindly for no-scroll candidates;
- a no-scroll layout that fills the viewport well beats a smaller sparse
  layout;
- `0.99` from configured thirds ranks as a complete fill;
- forced dimension violations are invalid candidates, not ranking penalties;
- config order must not affect the result.

Validation:

- auto examples from configurations 2 and 3 should pass;
- candidate ties should be deterministic;
- reordering `allowed_dimensions` should not change solver output.

### Step 6: Complete Forced-Dimension Behavior

Status: completed.

Verify and fix forced-dimension cases:

- forced full-cross windows act as hard singleton anchors;
- auto groups around forced anchors are solved densely;
- partial forced windows can be completed by adjacent auto windows;
- consecutive partial forced windows can share a column when compatible;
- forced fullscreen windows are valid and may create scroll;
- incompatible forced dimensions are rejected.

Validation:

- all examples in `forced-examples.md` pass;
- no candidate changes a forced window to reduce scroll;
- no candidate moves windows across forced anchors.

### Step 7: Clean Up Obsolete Tests

Status: completed.

Update or remove tests that encode old implementation behavior.

In `tests/core_test.lua`:

- remove assertions for `cfg.tiling_mode`;
- remove `tiling_mode` from test configs;
- replace `test_solver_split_and_independence` with a generic solver
  independence test.

In `tests/hyprland_adapter_test.lua`:

- rename assertions that mention split behavior;
- update expected rectangles if the official solver changes them.

Keep tests that still validate stable public behavior:

- focus changes do not alter solver output;
- viewport updates are separate from solver recomputation;
- forced dimensions survive workspace switching;
- failed validation is transactional.

### Step 8: Final Verification

Status: completed.

Run:

```bash
lua tests/run.lua
rg 'tiling_mode|split mode|ajuste|solve_split|generate_split_slots' layout tests docs README.md -g '!docs/solver/implementation-plan.md'
```

Expected:

- all tests pass;
- no `tiling_mode` dependency remains in official code or docs;
- no old split or ajuste solver branch remains;
- the implementation plan itself may still mention old names as completed
  historical tasks.

## Acceptance Criteria

The implementation is complete when:

- `layout/config.lua` exposes no `tiling_mode`;
- `layout/solver.lua` has one candidate-based solver path;
- every example in `base-examples.md` is covered by tests and passes;
- every example in `forced-examples.md` is covered by tests and passes;
- solver output is independent from focus, viewport offset and config order;
- forced dimensions are always preserved or rejected with an error;
- `0.99` third-based fills are treated as complete fills;
- obsolete split/ajuste tests are removed or rewritten.
