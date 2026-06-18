# `layout/traversal.lua`

## Phase

Phase 3: Geometry and Solver.

## Purpose

`traversal.lua` owns the mapping between Fit Scroller's logical window order
and physical placement direction.

The solver should be able to reason in a canonical direction, then use this
module to transform positions for `left`, `down` and `up`.

## Responsibilities

In Phase 3, `traversal.lua` must:

- define direction metadata for `right`, `left`, `down` and `up`;
- identify the scroll axis and cross axis;
- expose canonical ordering rules;
- transform canonical rectangles into configured-direction rectangles;
- expose stable position comparison helpers for candidate tie-breaking.

It must not:

- choose dimensions;
- rank candidates;
- read Hyprland targets;
- mutate workspace state.

## Direction Semantics

V1 rules:

- `right`: left to right, then top to bottom, then overflow to the right;
- `left`: right to left, then top to bottom, then overflow to the left;
- `down`: top to bottom, then left to right, then overflow downward;
- `up`: bottom to top, then left to right, then overflow upward.

## Canonical Direction

The recommended implementation normalizes candidate generation to `right`.

Canonical `right` means:

- main progression inside a viewport region is left to right;
- secondary progression is top to bottom;
- overflow extends to the right.

Other directions are transformations of canonical rectangles.

## Public API

Recommended functions:

```lua
traversal.direction_info(direction)
traversal.scroll_axis(direction)
traversal.cross_axis(direction)
traversal.to_canonical(direction, rect)
traversal.from_canonical(direction, rect)
traversal.compare_positions(direction, rect_a, rect_b)
```

### `direction_info(direction)`

Returns metadata:

```lua
{
    direction = "right",
    scroll_axis = "x",
    cross_axis = "y",
    primary = "x",
    secondary = "y",
    scroll_sign = 1,
}
```

### `from_canonical(direction, rect)`

Transforms a canonical `right` rectangle into the configured direction.

Examples:

- `right`: identity;
- `left`: mirror horizontally;
- `down`: rotate axes so canonical horizontal overflow becomes vertical
  downward overflow;
- `up`: rotate axes and mirror vertically so overflow goes upward.

Exact transformation formulas should be implemented with tests before solver
behavior depends on them.

### `compare_positions(direction, rect_a, rect_b)`

Compares two positions in the configured canonical traversal order.

This is used only as a final deterministic tie-breaker after higher-priority
candidate ranking rules.

## Examples

For `right`, four equal cells are traversed:

```text
+---+---+
| A | B |
+---+---+
| C | D |
+---+---+
```

For `left`, the same logical order is mirrored horizontally:

```text
+---+---+
| B | A |
+---+---+
| D | C |
+---+---+
```

For `down`, the primary direction is vertical:

```text
+---+---+
| A | C |
+---+---+
| B | D |
+---+---+
```

For `up`, vertical progression is mirrored:

```text
+---+---+
| B | D |
+---+---+
| A | C |
+---+---+
```

## Phase 3 Acceptance Criteria

- Each supported direction has explicit metadata.
- Scroll axis and cross axis are correct for each direction.
- Canonical rectangles can be transformed to every direction.
- Position comparison preserves logical order for every direction.
- Direction behavior is testable without Hyprland.

## Phase 5 Additions

Phase 5 hardens direction validation and transformation tests.

Traversal is a small module, but mistakes here affect solver ranking,
viewport reveal and adapter placement. Direction behavior should therefore be
fully covered by tests before implementation is considered complete.

## Direction Validation

Unknown directions must return an error instead of falling back silently.

Valid directions are exactly:

- `right`;
- `left`;
- `down`;
- `up`.

This validation should be consistent with `config.lua`.

## Transformation Invariants

For every supported direction:

- `to_canonical(direction, from_canonical(direction, rect))` returns the
  original canonical rectangle;
- transformed rectangles keep the same logical area;
- scroll axis and cross axis remain consistent with `direction_info`;
- position comparison is deterministic for equivalent rectangles.

## Phase 5 Test Cases

Traversal tests should cover:

- unknown direction rejected;
- metadata for all four directions;
- scroll axis for all four directions;
- cross axis for all four directions;
- round-trip canonical transformation;
- area preservation after transformation;
- comparison order for `right`;
- comparison order for `left`;
- comparison order for `down`;
- comparison order for `up`.

## Phase 5 Acceptance Criteria

- Unknown directions fail explicitly.
- All transformations are round-trip tested.
- Direction metadata is consistent with viewport and solver needs.
- Logical order examples from this document are covered by tests.
