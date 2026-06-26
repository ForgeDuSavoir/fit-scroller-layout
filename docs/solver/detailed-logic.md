# Solver Detailed Logic

This document defines the intended solver behavior for both:

- windows in `auto` dimension mode;
- windows with a forced dimension.

Auto mode is the default case. Forced dimensions are hard constraints applied
on top of the same candidate model, column model and ranking rules.

The validated examples are extracted into:

- [Base solver examples](base-examples.md);
- [Forced solver examples](forced-examples.md).

The goal is to remove ambiguity from the solver behavior:

- every window receives one configured allowed dimension;
- forced windows keep their forced dimension exactly;
- logical window order is preserved;
- scrolling is avoided whenever possible;
- when scrolling is unavoidable, scroll extent is minimized;
- visible space is filled with practical dimensions instead of arbitrary sizes;
- the result is deterministic.

## Definitions

### Viewport

The viewport is the visible screen area. In normalized solver coordinates, the
viewport has size:

```text
+-------------------+
| width = 1         |
| height = 1        |
+-------------------+
```

Allowed dimensions are expressed as fractions of this viewport.

### Scroll Axis

The scroll axis is derived from `scroll_direction`.

```text
right or left -> horizontal scroll axis
down or up    -> vertical scroll axis
```

The solver may first normalize every direction to a canonical `right` direction.
In canonical form:

- the scroll axis is horizontal;
- columns progress from left to right;
- windows progress from top to bottom inside each column.

After solving, the layout can be transformed back to the configured direction.

### Cross Axis

The cross axis is the axis perpendicular to the scroll axis.

In canonical `right` mode:

- scroll axis = width / x;
- cross axis = height / y.

Overflow is allowed only on the scroll axis. A window must never exceed the
viewport on the cross axis.

### Dimension Components

In canonical `right` mode, an allowed dimension has:

```text
scroll_size = width
cross_size  = height
area        = width * height
```

For vertical scrolling, the implementation may swap width and height during
canonical solving, then transform the final rectangles back.

### Logical Order

Window order is fixed by the input target list.

For canonical `right` mode, the traversal order is:

```text
top to bottom inside a column,
then left to right across columns.
```

Therefore, each column contains a consecutive slice of the window order.

Example:

```text
Column 1: A B
Column 2: C D
Column 3: E
```

represents the order:

```text
A, B, C, D, E
```

### Dimension Mode

Each window has exactly one dimension mode.

```text
auto
forced <dimension>
```

`auto` means the solver may choose any allowed dimension for the window.

`forced <dimension>` means the solver must assign that exact allowed dimension
to the window.

Forced dimensions do not change the window order. They only constrain the
candidate layouts that may be selected.

### Forced Dimension

A forced dimension is valid only if:

- it exists in `allowed_dimensions`;
- it fits on the cross axis after canonical normalization;
- it can be placed without overlap while preserving logical order.

If a forced dimension is not allowed by the current display configuration, the
solver must reject the input.

If a forced dimension cannot fit on the cross axis, the solver must reject the
input.

The solver must never silently downgrade a forced dimension to `auto`, replace
it with a nearby allowed dimension, or shrink it to make a candidate easier to
place.

## Candidate Model

The solver should reason in terms of layout candidates.

A candidate is a complete layout proposal containing:

- a partition of the ordered windows into columns;
- one allowed dimension per window;
- one rectangle per window;
- a workspace extent on the scroll axis.

For canonical `right`, a candidate is valid only if:

- every window appears exactly once;
- every assigned dimension exists in `allowed_dimensions`;
- every forced window receives its exact forced dimension;
- windows keep their logical order;
- windows do not overlap;
- every window satisfies `0 <= y` and `y + height <= 1`;
- overflow, if any, exists only on the x axis;
- each column contains a consecutive sequence of windows;
- the workspace extent is the maximum `x + width` of all rectangles.

### Column Model

In auto mode, a column should be modeled as a stack of one or more consecutive
windows.

All windows in the same column share the same `scroll_size`.

For canonical `right`, that means all windows in the same column have the same
width. Their heights may differ, as long as their sum does not exceed `1`.

Example valid column:

```text
width = 0.33

A = 0.33 x 0.33
B = 0.33 x 0.33
C = 0.33 x 0.33

height sum = 0.99 <= 1
```

Example valid column:

```text
width = 0.33

A = 0.33 x 0.5
B = 0.33 x 0.5

height sum = 1.0
```

A candidate should not rely on arbitrary empty holes inside a column when a
configured dimension can fill that space without increasing scroll extent.

### Column Model With Forced Dimensions

Forced windows use the same column model as auto windows.

In canonical `right` mode, every window in a column must still share the same
width.

Therefore, a forced window can share a column with another window only when the
other window can use the same `scroll_size`.

Example valid forced column:

```text
width = 0.33

B = forced 0.33 x 0.5
C = forced 0.33 x 0.5

height sum = 1.0
```

Example valid mixed column:

```text
width = 0.66

C = forced 0.66 x 0.5
D = auto   0.66 x 0.5

height sum = 1.0
```

Example valid near-full forced column:

```text
width = 0.33

C = forced 0.33 x 0.66
D = forced 0.33 x 0.33

height sum = 0.99
```

Because approximate thirds are treated as full fills, the last example fills
the column.

Example invalid forced column:

```text
width = mixed

C = forced 0.66 x 0.5
D = auto   0.33 x 0.5
```

This is invalid because the two windows do not share the same `scroll_size`.

### Full-Cross Forced Windows

A forced window whose `cross_size` fills the cross axis occupies a complete
column by itself.

In canonical `right`, a forced `0.5 x 1.0` window cannot share its column with
another window, because its height already fills the column.

Such a window acts as a hard anchor in the ordered column sequence.

Example:

```text
A = auto
B = auto
C = forced 0.5 x 1.0
D = auto
E = auto
```

The candidate column sequence must keep `C` between the preceding and following
windows:

```text
Column 1: A B
Column 2: C
Column 3: D E
```

The solver may still choose dimensions for `A`, `B`, `D` and `E`, but it may
not move any of them across `C`.

### Partial Forced Windows

A forced window whose `cross_size` does not fill the cross axis may share a
column with adjacent windows in logical order.

The solver may choose column boundaries before or after the forced window as
long as:

- every window in the column has the same `scroll_size`;
- the sum of cross sizes does not exceed the cross-axis size;
- logical order is preserved.

Example:

```text
A = auto
B = auto
C = forced 0.66 x 0.5
D = auto
E = auto
```

A valid candidate may use:

```text
Column 1: A B
Column 2: C D
Column 3: E
```

where `D` is auto-selected as `0.66 x 0.5` to complete the column containing
the forced window.

### Forced Windows And Scroll

Forced dimensions may make scroll unavoidable.

When this happens, the solver must preserve the forced dimensions and minimize
the additional scroll using the remaining auto windows.

A candidate that reduces scroll by changing a forced dimension is invalid.

Example:

```text
A = forced 1.0 x 1.0
B = auto
C = auto
D = auto
E = auto
F = auto
```

`A` consumes a full viewport-width column. The following auto windows must be
packed after `A`; `A` must not be reduced.

## Precomputed Configuration Values

The following values can be computed when the configuration is loaded.

These values are optimizations and helper concepts. They must not override the
candidate validity and ranking rules.

### `axis`

```text
right or left -> horizontal
down or up    -> vertical
```

### `canonical_dimensions`

The list of allowed dimensions converted to canonical coordinates.

For horizontal scrolling, dimensions are unchanged.

For vertical scrolling, width and height are swapped for solving purposes.

Each canonical dimension should keep a reference to its original configured
dimension key.

### `maximized_dimension`

The largest allowed dimension by area.

Tie-breaking:

1. larger area first;
2. larger cross size first;
3. larger scroll size first;
4. stable key order.

This value is useful for simple one-window or fully maximized cases.

### `smallest_dimension`

The smallest allowed dimension by area.

Tie-breaking:

1. smaller area first;
2. smaller scroll size first;
3. smaller cross size first;
4. stable key order.

This value is useful as a fallback for scroll-heavy cases, but it must not be
the only source of `max_grid_size`.

### `max_grid_size`

`max_grid_size` is the maximum number of windows that can fit inside the
viewport without scrolling using a single repeated dimension.

It should be computed across all allowed dimensions:

```text
max_grid_size =
  max(
    floor(1 / dimension.scroll_size)
    *
    floor(1 / dimension.cross_size)
  )
```

Do not compute it only from `smallest_dimension`, because the smallest area
dimension is not guaranteed to produce the largest grid capacity.

### `dimension_priority`

Dimensions should have a deterministic priority order for candidate generation.

Recommended order:

1. larger area first;
2. larger cross size first;
3. smaller scroll size first when the cross size is equal;
4. stable key order.

This order is only a generation priority. Final selection must be made by the
candidate ranking.

## Solver Overview

The solver should follow this conceptual flow:

```text
1. Normalize to canonical direction.
2. Resolve each window dimension mode.
3. Generate valid candidate layouts.
4. Reject candidates that violate forced dimensions.
5. Rank candidates.
6. Select the best candidate.
7. Transform back to the configured scroll direction.
```

The selected candidate is the first candidate according to the ranking rules.

No configurable solver mode is needed.

Forced dimensions must not trigger a separate solver mode. They are constraints
inside the same candidate search.

## Candidate Generation

The implementation may generate candidates procedurally instead of literally
enumerating every possible layout. However, the generated set must include every
candidate shape required by the examples below.

When forced dimensions are present, candidate generation must be constrained,
not replaced.

For every candidate:

- forced windows contribute only their forced dimension;
- auto windows contribute one selected allowed dimension;
- a column containing forced windows has a constrained `scroll_size`;
- a full-cross forced window is a singleton column;
- partial forced windows may be completed by neighboring auto windows or other
  forced windows when dimensions are compatible.

### Candidate Generation With Dimension Modes

The solver should generate candidates from the ordered window list, not from an
unordered set of dimensions.

For each window:

```text
if mode = forced:
    candidate dimension set = { forced_dimension }

if mode = auto:
    candidate dimension set = allowed_dimensions
```

This can be pruned by column constraints.

For example, once a column has `scroll_size = 0.33`, auto windows in that column
only need to consider dimensions whose canonical `scroll_size` is also `0.33`.

### Candidate Generation By Ordered Partitions

A robust implementation strategy is to enumerate or procedurally produce
ordered column partitions.

For `N` windows, a partition describes where column breaks occur.

Example:

```text
A B C D E
```

Possible partitions include:

```text
[A] [B] [C] [D] [E]
[A B] [C] [D E]
[A B] [C D] [E]
```

Each bracketed group is a candidate column.

For each column, the solver checks whether there is at least one valid column
pattern compatible with:

- the windows in that column;
- their dimension modes;
- the shared column `scroll_size`;
- the cross-axis fill limit.

This partition-based model is important for forced dimensions because a forced
partial window may need to be grouped with neighboring windows to fill the
column.

### Forced Column Pattern Generation

For a candidate column, generate valid column patterns as follows.

1. Determine possible `scroll_size` values.
2. For every window in the column:
   - forced windows require their forced `scroll_size`;
   - auto windows may use any allowed dimension matching the column
     `scroll_size`.
3. If two forced windows in the same column have different `scroll_size`
   values, the pattern is invalid.
4. If a forced window fills the cross axis and the column contains more than
   one window, the pattern is invalid.
5. Sum the cross sizes.
6. If the sum exceeds `1 + epsilon`, the pattern is invalid.
7. Rank valid patterns using the column pattern ranking.

Example:

```text
Column: C D

C = forced 0.66 x 0.5
D = auto
```

The forced window fixes the column `scroll_size` to `0.66`.

The solver may select:

```text
D = auto 0.66 x 0.5
```

because:

```text
0.5 + 0.5 = 1.0
```

Example:

```text
Column: C D

C = forced 0.33 x 0.66
D = forced 0.33 x 0.33
```

This is valid because:

```text
same scroll_size = 0.33
0.66 + 0.33 = 0.99
```

and `0.99` is treated as a full fill.

Example:

```text
Column: C D

C = forced 0.66 x 0.5
D = forced 0.33 x 0.5
```

This is invalid because the forced scroll sizes differ.

### Forced Skeleton As Pruning

A forced skeleton may be used as an implementation optimization.

The skeleton is not a separate semantic mode. It is a way to prune candidate
generation.

Full-cross forced windows are safe skeleton anchors because they must be
singleton columns.

Example:

```text
A B C D E
C = forced 0.5 x 1.0
```

The partition must contain:

```text
[...] [C] [...]
```

The windows before and after `C` still need to be solved with the same ranking
rules.

Partial forced windows should not be treated as mandatory singleton anchors.
They must remain eligible to share a column with adjacent compatible windows.

### Forced Dimensions And Auto Groups

When full-cross forced windows split the order into auto groups, each group
should be solved with the same candidate families and ranking rules used for
auto mode.

However, group-local optimization must not hide global scroll effects.

The final selected layout is still ranked globally by total workspace extent
and fill.

Example:

```text
A B C D E F
D = forced 0.66 x 1.0
```

A valid high-quality layout is:

```text
Column 1: A B
Column 2: C
Column 3: D
Column 4: E F
```

with:

```text
A, B = 0.33 x 0.5
C    = 0.33 x 1.0
D    = forced 0.66 x 1.0
E, F = 0.33 x 0.5
```

This preserves order, respects the forced dimension, and keeps the auto groups
dense.

### Candidate Family 1: Uniform Full-Cross Layouts

A uniform full-cross layout assigns the same dimension to every window, and
that dimension fills the cross axis.

In canonical `right`, this means:

```text
all windows use width W and height 1.0
```

This candidate is valid without scrolling when:

```text
window_count * W <= 1
```

If multiple full-cross uniform candidates are valid, prefer the one that fills
the scroll axis most closely without exceeding the viewport.

Example:

With:

```text
allowed_dimensions = {
  0.66 x 1.0,
  0.5 x 1.0,
  0.33 x 1.0,
  0.5 x 0.5,
  0.33 x 0.5,
}
```

and `3` windows, the solver should choose:

```text
0.33 x 1.0 for every window
```

because:

```text
3 * 0.33 = 0.99 <= 1
```

and all windows are full height.

### Candidate Family 2: Base Grid With Splits

If no suitable uniform full-cross layout exists, the solver should consider
layouts derived from a repeated base dimension.

For each base dimension in `dimension_priority` order:

1. compute the base grid capacity:

```text
base_columns = floor(1 / base.scroll_size)
base_rows    = floor(1 / base.cross_size)
base_capacity = base_columns * base_rows
```

2. if `window_count <= base_capacity`, create a uniform base-grid candidate;
3. if `window_count > base_capacity`, compute:

```text
buffer = window_count - base_capacity
```

4. if `buffer <= base_capacity`, check whether the base dimension can be split
   into two allowed dimensions that exactly cover the base slot;
5. if it can, split `buffer` base slots in traversal order.

For canonical `right`, splitting in traversal order means:

```text
split earlier columns before later columns;
inside a column, split earlier slots before later slots.
```

When a base slot is split, the two child slots replace the original slot in
logical order.

Example:

With:

```text
base = 0.5 x 1.0
split = two slots of 0.5 x 0.5
window_count = 3
```

the result is:

```text
Column 1: A B
Column 2: C
```

```text
+-----+-----+
|  A  |     |
+-----+  C  |
|  B  |     |
+-----+-----+
```

### Candidate Family 3: Balanced Column Layouts

Balanced column layouts are required when:

- a full-cross uniform layout is not available;
- a larger base-grid split is not valid;
- all windows can still fit without scrolling by using smaller dimensions.

The solver should create columns with a shared `scroll_size`, then distribute
the ordered windows across those columns.

For a given `scroll_size`, define valid column patterns.

A column pattern for `k` windows is a list of `k` allowed dimensions where:

- every dimension has the same `scroll_size`;
- the sum of cross sizes is `<= 1`;
- the pattern preserves top-to-bottom order.

For each `scroll_size`, compute the best pattern for each possible `k`.

Pattern ranking:

1. larger total cross fill first;
2. exact cross fill of `1` beats partial fill;
3. smaller cross-size range first;
4. larger individual dimensions first;
5. stable dimension key order.

Examples for `scroll_size = 0.33`:

If available:

```text
1 window  -> 0.33 x 0.66, if 0.33 x 1.0 is unavailable
2 windows -> 0.33 x 0.5 + 0.33 x 0.5
3 windows -> 0.33 x 0.33 + 0.33 x 0.33 + 0.33 x 0.33
```

For a chosen `scroll_size`, compute:

```text
max_rows = maximum k for which a valid column pattern exists
column_count = ceil(window_count / max_rows)
```

The column count must then be distributed as evenly as possible while preserving
order.

Distribution rule:

- earlier columns receive the extra windows;
- the difference between any two column counts should be at most `1`;
- no column may exceed `max_rows`.

Examples:

```text
5 windows, max_rows = 2 -> [2, 2, 1]
6 windows, max_rows = 2 -> [2, 2, 2]
7 windows, max_rows = 3 -> [3, 2, 2]
8 windows, max_rows = 3 -> [3, 3, 2]
```

Then apply the best pattern for each column count.

This explains:

```text
7 windows -> [3, 2, 2]

Column 1: 3 x 0.33 height
Column 2: 2 x 0.5 height
Column 3: 2 x 0.5 height
```

and:

```text
8 windows -> [3, 3, 2]

Column 1: 3 x 0.33 height
Column 2: 3 x 0.33 height
Column 3: 2 x 0.5 height
```

### Candidate Family 4: Scroll Layouts

If no candidate can fit all windows within scroll extent `<= 1`, scrolling is
required.

In that case, the solver should:

1. minimize workspace extent on the scroll axis;
2. use the smallest practical scroll size that can pack dense columns;
3. fill each complete column with the densest valid pattern;
4. fill the final partial column with the best pattern for its remaining count.

The final partial column should be expanded on the cross axis when this does
not increase scroll extent.

Example principle:

```text
If the final column contains one window and 0.33 x 1.0 is allowed,
use 0.33 x 1.0 instead of 0.33 x 0.5.
```

## Candidate Ranking

Candidate ranking is the core behavior contract.

The ranking must be deterministic and must not depend on the order in which
`allowed_dimensions` appears in the user configuration.

Rank candidates by the following criteria, in order.

### 1. Validity

Invalid candidates are discarded before ranking.

Forced dimension violations are validity errors, not ranking penalties.

A candidate is invalid if:

- a forced window receives any dimension other than its forced dimension;
- a forced dimension is not in `allowed_dimensions`;
- a forced dimension does not fit on the cross axis;
- a forced full-cross window shares a column with another window;
- a column contains forced windows with incompatible `scroll_size` values;
- preserving a forced dimension would require reordering windows.

### 2. Minimum Scroll Overflow

Compute:

```text
overflow = max(0, workspace_extent - 1)
```

Smaller overflow is always better.

A candidate with no scroll always beats a candidate that scrolls.

This rule applies after forced dimensions have been preserved. A candidate that
reduces scroll by changing a forced dimension is invalid and must never be
ranked.

### 3. No-Scroll Viewport Use

When comparing candidates with `overflow = 0`, do not minimize
`workspace_extent` blindly.

The solver should prefer candidates that use the viewport effectively.

Viewport use has two components:

- scroll-axis fill;
- cross-axis fill inside each used column.

In canonical `right`:

```text
scroll_fill = min(workspace_extent, 1)
```

Column cross fill is the sum of the heights in that column.

A candidate that fills both axes well should beat a candidate that uses tiny
windows merely because it has a smaller extent.

### 4. Uniform Full-Cross Preference

If a candidate assigns the same full-cross dimension to every window and fits
without scrolling, it should be strongly preferred over a split layout when it
also fills the scroll axis well.

This rule explains:

```text
3 windows with 0.33 x 1.0 available
-> use three 0.33 x 1.0 windows
```

instead of:

```text
0.5 x 0.5
0.5 x 0.5
0.5 x 1.0
```

However, the uniform preference applies only when the uniform layout fills the
cross axis.

A uniform layout that leaves large cross-axis holes should not beat a better
filled split layout.

This rule explains:

```text
3 windows without 0.33 x 1.0
-> use 0.5 x 0.5, 0.5 x 0.5, 0.5 x 1.0
```

instead of using three smaller equal windows that leave much of the viewport
empty.

### 5. Better Cross-Axis Fill

After scroll and full-cross uniform preference, candidates with better
cross-axis fill are preferred.

For each column:

```text
column_fill = sum(cross_size of windows in column)
```

Prefer:

1. more columns with `column_fill` close to `1`;
2. larger total filled area;
3. fewer avoidable holes.

An empty region is avoidable if a larger allowed dimension could fill it without
increasing scroll extent or breaking order.

For columns containing forced dimensions, the same fill rule applies.

If a forced partial window leaves cross-axis space and an adjacent auto window
can fill that space with the same `scroll_size`, the filled candidate should
beat a candidate that leaves the space empty, provided scroll extent does not
increase.

Example:

```text
C = forced 0.66 x 0.5
D = auto
```

should prefer:

```text
D = auto 0.66 x 0.5
```

over placing `D` in a separate column, when both preserve order and the shared
column does not increase scroll.

### 6. Balanced Column Counts

For balanced column layouts, prefer distributions where column counts differ as
little as possible.

When there is an unavoidable remainder, earlier columns receive the extra
windows.

This preserves stable order and matches:

```text
5 windows -> [2, 2, 1]
7 windows -> [3, 2, 2]
8 windows -> [3, 3, 2]
```

Forced full-cross anchors may intentionally break this balance.

Balance is evaluated only after hard forced constraints are respected. The
solver must not move windows across a forced anchor to make column counts more
balanced.

Partial forced windows may participate in balanced columns when compatible.

### 7. Larger Practical Dimensions

When scroll, viewport fill and balance are equivalent, prefer larger individual
window areas.

This prevents unnecessary shrinking.

For auto windows near forced windows, this criterion applies only after scroll
and fill.

Example:

```text
A = auto
B = forced 0.33 x 1.0
C = auto
D = auto
```

The expected result keeps `C` and `D` at `0.33 x 0.5` because widening them
would introduce scroll. Larger dimensions do not beat smaller scroll extent.

### 8. Smaller Area Range

When larger practical dimensions do not decide, prefer smaller differences
between auto window areas.

This keeps auto layouts visually coherent.

This criterion is intentionally lower than viewport fill. Equal tiny windows
should not beat a layout that fills the viewport much better.

### 9. Stable Position Order

If candidates are still equivalent, use a stable canonical tie-breaker:

1. smaller x first;
2. smaller y first;
3. target logical order;
4. stable dimension key order.

Forced dimensions do not alter the tie-breaker order. They only remove invalid
candidates before ranking.

## Expected Auto Behavior

### Configuration A

```lua
allowed_dimensions = {
    { 0.66, 1.0 },
    { 0.5, 1.0 },
    { 0.33, 1.0 },
    { 0.5, 0.5 },
    { 0.33, 0.5 },
}
scroll_direction = "right"
```

#### 3 Windows

Expected:

```text
A = 0.33 x 1.0
B = 0.33 x 1.0
C = 0.33 x 1.0
```

Reason:

- full-cross uniform candidate exists;
- it fits without scrolling;
- it fills the scroll axis closely.

#### 4 Windows

Expected:

```text
A = 0.5 x 0.5
B = 0.5 x 0.5
C = 0.5 x 0.5
D = 0.5 x 0.5
```

Reason:

- no full-cross uniform candidate fits without scrolling;
- `0.5 x 1.0` can be split into two `0.5 x 0.5` windows;
- the resulting layout fills the viewport.

#### 5 Windows

Expected:

```text
A = 0.33 x 0.5
B = 0.33 x 0.5
C = 0.33 x 0.5
D = 0.33 x 0.5
E = 0.33 x 1.0
```

Reason:

- `0.33 x 1.0` provides three full-height columns;
- two of those columns can be split into `0.33 x 0.5`;
- the final column remains full height;
- all windows fit without scrolling.

### Configuration B

```lua
allowed_dimensions = {
    { 1.0, 1.0 },
    { 0.66, 1.0 },
    { 0.5, 1.0 },
    { 1.0, 0.66 },
    { 0.66, 0.66 },
    { 0.5, 0.66 },
    { 0.66, 0.5 },
    { 0.5, 0.5 },
    { 0.33, 0.66 },
    { 0.33, 0.5 },
    { 0.66, 0.33 },
    { 0.5, 0.33 },
    { 0.33, 0.33 },
}
scroll_direction = "right"
```

#### 2 Windows

Expected:

```text
A = 0.5 x 1.0
B = 0.5 x 1.0
```

Reason:

- full-cross uniform candidate exists;
- it fills the viewport exactly.

#### 3 Windows

Expected:

```text
A = 0.5 x 0.5
B = 0.5 x 0.5
C = 0.5 x 1.0
```

Reason:

- no full-cross uniform candidate fits three windows without scrolling;
- tiny equal windows would leave too much of the viewport unused;
- splitting one `0.5 x 1.0` slot fills the viewport.

#### 4 Windows

Expected:

```text
A = 0.5 x 0.5
B = 0.5 x 0.5
C = 0.5 x 0.5
D = 0.5 x 0.5
```

Reason:

- two `0.5 x 1.0` columns can both be split;
- the result fills the viewport exactly.

#### 5 Windows

Expected:

```text
A = 0.33 x 0.5
B = 0.33 x 0.5
C = 0.33 x 0.5
D = 0.33 x 0.5
E = 0.33 x 0.66
```

Reason:

- use three `0.33` width columns;
- distribute counts as `[2, 2, 1]`;
- use `0.33 x 0.5` for two-window columns;
- use `0.33 x 0.66` for the single-window final column because it
  improves cross-axis fill without increasing scroll extent.

#### 6 Windows

Expected:

```text
A = 0.33 x 0.5
B = 0.33 x 0.5
C = 0.33 x 0.5
D = 0.33 x 0.5
E = 0.33 x 0.5
F = 0.33 x 0.5
```

Reason:

- use three `0.33` width columns;
- distribute counts as `[2, 2, 2]`;
- each two-window column uses two `0.33 x 0.5` windows;
- all columns fill the cross axis.

#### 7 Windows

Expected:

```text
A = 0.33 x 0.33
B = 0.33 x 0.33
C = 0.33 x 0.33
D = 0.33 x 0.5
E = 0.33 x 0.5
F = 0.33 x 0.5
G = 0.33 x 0.5
```

Reason:

- use three `0.33` width columns;
- distribute counts as `[3, 2, 2]`;
- the three-window column uses three `0.33 x 0.33` windows;
- each two-window column uses two `0.33 x 0.5` windows.

#### 8 Windows

Expected:

```text
A = 0.33 x 0.33
B = 0.33 x 0.33
C = 0.33 x 0.33
D = 0.33 x 0.33
E = 0.33 x 0.33
F = 0.33 x 0.33
G = 0.33 x 0.5
H = 0.33 x 0.5
```

Reason:

- use three `0.33` width columns;
- distribute counts as `[3, 3, 2]`;
- three-window columns use three `0.33 x 0.33` windows;
- the two-window column uses two `0.33 x 0.5` windows.

## Expected Forced Behavior

The complete forced-dimension validation corpus is documented in
[Forced solver examples](forced-examples.md).

This section describes the behavior patterns those examples require.

### Forced Full-Cross Middle Anchor

When a forced window fills the cross axis and appears in the middle of the
order, it becomes a singleton column. The auto windows before and after it are
packed around it.

Example:

```text
A = auto
B = auto
C = forced 0.5 x 1.0
D = auto
E = auto
```

Expected column structure:

```text
Column 1: A B
Column 2: C
Column 3: D E
```

Expected dimensions:

```text
A = 0.33 x 0.5
B = 0.33 x 0.5
C = forced 0.5 x 1.0
D = 0.33 x 0.5
E = 0.33 x 0.5
```

This may create scroll. The solver must not reduce `C` to avoid it.

### Forced Wide First Window

When the first window is forced to a wide full-cross dimension, all following
windows must be packed after it.

Example:

```text
A = forced 0.66 x 1.0
B = auto
C = auto
D = auto
E = auto
```

Expected dimensions:

```text
A = forced 0.66 x 1.0
B = 0.33 x 0.5
C = 0.33 x 0.5
D = 0.33 x 0.5
E = 0.33 x 0.5
```

The forced window makes the workspace wider. Auto windows still use the dense
layout that minimizes additional extent.

### Forced Narrow Full-Cross Window

A forced narrow full-cross window can be part of a no-scroll layout when the
remaining windows can fit around it.

Example:

```text
A = auto
B = forced 0.33 x 1.0
C = auto
D = auto
```

Expected dimensions:

```text
A = 0.33 x 1.0
B = forced 0.33 x 1.0
C = 0.33 x 0.5
D = 0.33 x 0.5
```

The solver should not widen `C` and `D` if that introduces scroll.

### Consecutive Partial Forced Windows

Consecutive forced windows may share a column when:

- they have the same `scroll_size`;
- their cross sizes fill or nearly fill the cross axis;
- their order is consecutive in the column.

Example:

```text
B = forced 0.33 x 0.5
C = forced 0.33 x 0.5
```

Expected shared column:

```text
B
C
```

because:

```text
0.5 + 0.5 = 1.0
```

Example:

```text
C = forced 0.33 x 0.66
D = forced 0.33 x 0.33
```

Expected shared column:

```text
C
D
```

because:

```text
0.66 + 0.33 = 0.99
```

and `0.99` is treated as a complete fill.

### Partial Forced Window Completed By Auto Window

A partial forced window can be completed by an adjacent auto window with the
same `scroll_size`.

Example:

```text
A = auto
B = auto
C = forced 0.66 x 0.5
D = auto
E = auto
```

Expected middle column:

```text
C = forced 0.66 x 0.5
D = auto   0.66 x 0.5
```

This candidate should beat placing `D` in a separate column when it preserves
order and does not increase scroll.

### Forced Fullscreen Window

A forced `1.0 x 1.0` window occupies a complete viewport-sized column.

Example:

```text
A = forced 1.0 x 1.0
B = auto
C = auto
D = auto
E = auto
F = auto
```

Expected behavior:

- `A` remains `1.0 x 1.0`;
- all other windows are packed after `A`;
- the auto group after `A` uses the same dense layout it would use if solved as
  an ordered suffix.

The solver must not treat fullscreen forced windows as a special failure case.
They are valid hard anchors that may require scroll.

### Auto Groups Around Forced Anchors

When forced full-cross windows split the order into groups, each auto group
should be packed densely, but the final ranking remains global.

Example:

```text
A B C D E F
D = forced 0.66 x 1.0
```

Expected dimensions:

```text
A = 0.33 x 0.5
B = 0.33 x 0.5
C = 0.33 x 1.0
D = forced 0.66 x 1.0
E = 0.33 x 0.5
F = 0.33 x 0.5
```

The odd auto group before `D` uses one shared column and one full-cross column.
The group after `D` uses one shared column.

### Forced Dimensions And Candidate Rejection

If no candidate can preserve all forced dimensions while satisfying geometry
constraints, the solver should return an error.

This should be rare when the forced dimensions are allowed and fit on the cross
axis, because scroll is available on the scroll axis. However, invalid
combinations can still exist, for example:

- a forced dimension not present in `allowed_dimensions`;
- a forced dimension whose canonical cross size is greater than `1`;
- a candidate column that tries to stack incompatible forced widths;
- a candidate column whose forced cross sizes exceed `1`.

The solver must reject the invalid candidate or input rather than silently
altering a forced window.

## Implementation Notes

### Do Not Use Config Order as Semantics

The order of `allowed_dimensions` in the user configuration must not influence
the selected layout.

All ordering must come from explicit computed priorities and ranking rules.

### Use Epsilon for Fractional Dimensions

Values like `0.33` and `0.66` are approximations.

The solver should use a small epsilon when checking whether dimensions fill the
viewport.

Examples:

```text
0.33 + 0.33 + 0.33 = 0.99
0.33 + 0.66 = 0.99
```

These should be treated as intentional near-fills, not as layout failures.

Recommended checks:

```text
value <= 1 + epsilon
abs(value - 1) <= epsilon_for_fill
```

The exact epsilon should be chosen consistently across geometry validation and
candidate ranking.

For layout-fill purposes, approximate thirds should be treated as full fills.

That means:

```text
0.33 + 0.33 + 0.33 = 0.99
0.33 + 0.66 = 0.99
```

must rank as equivalent to:

```text
1.0
```

This rule applies when deciding whether a row, column, or viewport axis is
filled. A candidate that fills an axis to `0.99` because it uses configured
third-based dimensions should not be penalized against a candidate that fills
the same axis to exactly `1.0`.

### Avoid Arbitrary Pixel Resizing

The solver must never invent dimensions.

Every assigned window dimension must come from `allowed_dimensions`.

If a visually obvious fill would require a missing dimension, the solver must
not synthesize it. It should choose the best available valid candidate or return
a diagnostic if no valid candidate exists.

### Candidate Generation Can Be Pruned

The implementation does not need to brute-force every possible combination.

It may generate the candidate families described above and rely on ranking.

However, pruning must not remove candidates required by the documented
examples.

## Related Validation Examples

Use this document together with the following example corpora during
implementation:

- [Base solver examples](base-examples.md), which extracts the
  validated baseline and auto examples into a dedicated implementation
  reference;
- [Forced solver examples](forced-examples.md), which extracts the
  validated forced-dimension examples into a dedicated
  implementation reference.
