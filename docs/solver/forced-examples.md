# Forced Solver Examples

This document contains validated solver examples where at least one window has
a forced dimension.

These examples are intended to be used together with
[Solver detailed logic](detailed-logic.md) during
implementation.

The auto solver document defines the base candidate model, column model,
ranking rules and fill policy. The examples below extend that validation corpus
to cases where forced dimensions act as hard constraints.

## Implementation Contract

For every example in this document:

- forced windows must keep their configured forced dimension;
- auto windows must receive one configured allowed dimension;
- logical window order must be preserved;
- overflow may occur only on the scroll axis;
- the solver must minimize scroll before optimizing fill;
- `0.99` must be treated as a full fill when it comes from configured
  third-based dimensions such as `0.33 + 0.66`.

## Configuration A

This configuration covers forced dimensions in the third-based configuration.

```lua
allowed_dimensions = {
    { 0.66, 1.0 },
    { 0.5, 1.0 },
    { 0.33, 1.0 },
    { 0.5, 0.5 },
    { 0.33, 0.5 },
}
scroll_direction = "right"
insert_mode = "view"
```

These examples challenge forced dimensions in a configuration where thirds
exist, but width `0.33` columns can contain only one or two windows.

### Example A.1

#### Windows

```text
A = auto
B = auto
C = forced 0.5 x 1.0
D = auto
E = auto
```

#### Expected Result

```text
A = auto   0.33 x 0.5
B = auto   0.33 x 0.5
C = forced 0.5  x 1.0
D = auto   0.33 x 0.5
E = auto   0.33 x 0.5
```

```text
+----+------+----+
| A  |      | D  |
+----+  C   +----+
| B  |      | E  |
+----+------+----+
```

This case verifies that a forced full-height middle window keeps its dimension,
while the auto groups around it shrink enough to limit scroll.

### Example A.2

#### Windows

```text
A = forced 0.66 x 1.0
B = auto
C = auto
D = auto
E = auto
```

#### Expected Result

```text
A = forced 0.66 x 1.0
B = auto   0.33 x 0.5
C = auto   0.33 x 0.5
D = auto   0.33 x 0.5
E = auto   0.33 x 0.5
```

```text
+--------+----+----+
|        | B  | D  |
|   A    +----+----+
|        | C  | E  |
+--------+----+----+
```

This case verifies that a large forced first window may create scroll, but the
remaining auto windows still use the narrowest layout that limits total extent.

### Example A.3

#### Windows

```text
A = auto
B = forced 0.33 x 1.0
C = auto
D = auto
```

#### Expected Result

```text
A = auto   0.33 x 1.0
B = forced 0.33 x 1.0
C = auto   0.33 x 0.5
D = auto   0.33 x 0.5
```

```text
+----+----+----+
|    |    | C  |
| A  | B  +----+
|    |    | D  |
+----+----+----+
```

This case verifies that a forced full-height `0.33` column can remain in a
no-scroll layout, and neighboring auto windows must not grow if that would
introduce scroll.

### Example A.4

#### Windows

```text
A = auto
B = auto
C = auto
D = forced 0.66 x 1.0
E = auto
F = auto
```

#### Expected Result

```text
A = auto   0.33 x 0.5
B = auto   0.33 x 0.5
C = auto   0.33 x 1.0
D = forced 0.66 x 1.0
E = auto   0.33 x 0.5
F = auto   0.33 x 0.5
```

```text
+----+----+--------+----+
| A  |    |        | E  |
+----+ C  |   D    +----+
| B  |    |        | F  |
+----+----+--------+----+
```

This case verifies that an odd auto group before a large forced window is solved
with one shared column and one full-height column, instead of enlarging every
auto window.

### Example A.5

#### Windows

```text
A = auto
B = forced 0.33 x 0.5
C = forced 0.33 x 0.5
D = auto
E = auto
```

#### Expected Result

```text
A = auto   0.33 x 1.0
B = forced 0.33 x 0.5
C = forced 0.33 x 0.5
D = auto   0.33 x 0.5
E = auto   0.33 x 0.5
```

```text
+----+----+----+
|    | B  | D  |
| A  +----+----+
|    | C  | E  |
+----+----+----+
```

This case verifies that consecutive partial forced windows can share one column
when their dimensions fill the cross axis.

## Configuration B

This configuration covers forced dimensions in the richer configuration.

```lua
allowed_dimensions = {
    { 1.0, 1.0 },
    { 0.66, 1.0 },
    { 0.5, 1.0 },
    { 1.0, 0.66 },
    { 0.66, 0.66 },
    { 0.5, 0.66 },
    { 0.33, 0.66 },
    { 0.66, 0.5 },
    { 0.5, 0.5 },
    { 0.33, 0.5 },
    { 0.5, 0.33 },
    { 0.33, 0.33 },
}
scroll_direction = "right"
insert_mode = "view"
```

These examples challenge forced dimensions in a richer configuration where
multiple partial fills are possible for the same width.

### Example B.1

#### Windows

```text
A = auto
B = forced 0.66 x 1.0
C = auto
```

#### Expected Result

```text
A = auto   0.33 x 0.66
B = forced 0.66 x 1.0
C = auto   0.33 x 0.66
```

```text
+----+--------+----+
| A  |        | C  |
|    |   B    |    |
|----|        |----|
+----+--------+----+
```

This case verifies that a wide forced middle window preserves logical order,
forcing the auto windows around it to use partial `0.33` columns.

### Example B.2

#### Windows

```text
A = auto
B = auto
C = forced 0.66 x 0.5
D = auto
E = auto
```

#### Expected Result

```text
A = auto   0.33 x 0.5
B = auto   0.33 x 0.5
C = forced 0.66 x 0.5
D = auto   0.66 x 0.5
E = auto   0.33 x 0.66
```

```text
+----+--------+----+
| A  |   C    | E  |
+----+--------+    |
| B  |   D    |----|
+----+--------+----+
```

This case verifies that a wide partial forced dimension can be completed by an
auto window with the same width in the same column.

### Example B.3

#### Windows

```text
A = forced 1.0 x 1.0
B = auto
C = auto
D = auto
E = auto
F = auto
```

#### Expected Result

```text
A = forced 1.0  x 1.0
B = auto   0.33 x 0.5
C = auto   0.33 x 0.5
D = auto   0.33 x 0.5
E = auto   0.33 x 0.5
F = auto   0.33 x 0.66
```

```text
+----------+----+----+----+
|          | B  | D  | F  |
|    A     +----+----+    |
|          | C  | E  |----|
+----------+----+----+----+
```

This case verifies that a forced fullscreen window can coexist with a dense auto
layout after it, without the solver shrinking the forced window.

### Example B.4

#### Windows

```text
A = auto
B = auto
C = auto
D = auto
E = forced 0.5 x 1.0
F = auto
G = auto
H = auto
```

#### Expected Result

```text
A = auto   0.33 x 0.5
B = auto   0.33 x 0.5
C = auto   0.33 x 0.5
D = auto   0.33 x 0.5
E = forced 0.5  x 1.0
F = auto   0.33 x 0.33
G = auto   0.33 x 0.33
H = auto   0.33 x 0.33
```

```text
+----+----+------+----+
| A  | C  |      | F  |
+----+----+  E   +----+
| B  | D  |      | G  |
+----+----+      +----+
|    |    |      | H  |
+----+----+------+----+
```

This case verifies that auto groups around a full-height forced window may need
to shrink to minimize total extent.

### Example B.5

#### Windows

```text
A = auto
B = auto
C = forced 0.33 x 0.66
D = forced 0.33 x 0.33
E = auto
F = auto
G = auto
```

#### Expected Result

```text
A = auto   0.33 x 0.5
B = auto   0.33 x 0.5
C = forced 0.33 x 0.66
D = forced 0.33 x 0.33
E = auto   0.33 x 0.33
F = auto   0.33 x 0.33
G = auto   0.33 x 0.33
```

```text
+-----+-----+-----+
|  A  |  C  |  E  |
|     |     +-----+
+-----+     |  F  |
|  B  +-----+-----+
|     |  D  |  G  |
+-----+-----+-----+
```

This case verifies that multiple partial forced dimensions can form a near-full
third-based column, and `0.66 + 0.33 = 0.99` is treated as a complete fill.
