# `layout/traversal.lua`

## Purpose

`traversal.lua` owns the mapping between Fit Scroller's logical window order
and physical placement direction.

The solver should be able to reason in a canonical direction, then use this
module to transform positions for `left`, `down` and `up`.

## Responsibilities

`traversal.lua` must:

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

- `right`: top to bottom, then left to right, then overflow to the right;
- `left`: top to bottom, then right to left, then overflow to the left;
- `down`: left to right, then top to bottom, then overflow downward;
- `up`: left to right, then bottom to top, then overflow upward.

## Canonical Direction

The recommended implementation normalizes candidate generation to `right`.

Canonical `right` means:

- main progression inside a viewport region is top to bottom;
- secondary progression is left to right;
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

This is used only as a final deterministic tie-breaker after
tiling-mode-specific rules.

## Examples

For `right`, four equal cells are traversed:

```text
+---+---+
| A | C |
+---+---+
| B | D |
+---+---+
```

For `left`, the same logical order is mirrored horizontally:

```text
+---+---+
| C | A |
+---+---+
| D | B |
+---+---+
```

For `down`, the primary direction is vertical:

```text
+---+---+
| A | B |
+---+---+
| C | D |
+---+---+
```

For `up`, vertical progression is mirrored:

```text
+---+---+
| C | D |
+---+---+
| A | B |
+---+---+
```

## Guarantees

- Each supported direction has explicit metadata.
- Scroll axis and cross axis are correct for each direction.
- Canonical rectangles can be transformed to every direction.
- Position comparison preserves logical order for every direction.
- Direction behavior is testable without Hyprland.

## Hardening

This section defines direction validation and transformation tests.

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

## Test Cases

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

## Guarantees

- Unknown directions fail explicitly.
- All transformations are round-trip tested.
- Direction metadata is consistent with viewport and solver needs.
- Logical order examples from this document are covered by tests.
