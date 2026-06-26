# Base Solver Examples

This document contains the validated base solver examples for the official
solver behavior.

Use this document together with
[Solver detailed logic](detailed-logic.md) during
implementation.

The examples in this document cover:

- the simple forced-dimension baseline from `Exemple 1`;
- the auto-only third-based configuration from `Exemple 2`;
- the auto-only richer configuration from `Exemple 3`.

More advanced forced-dimension examples are documented separately in
[Forced solver examples](forced-examples.md).

## Implementation Contract

For every example in this document:

- each window must receive the exact expected allowed dimension;
- logical order must be preserved;
- overflow may occur only on the configured scroll axis;
- no dimensions may be invented outside `allowed_dimensions`;
- `0.99` must be treated as a complete fill when it comes from configured
  third-based dimensions such as `0.33 + 0.66`.

## Configuration 1

This configuration covers the baseline forced-dimension examples.

```lua
allowed_dimensions = {
    { 1.0, 1.0 },
    { 0.5, 1.0 },
    { 0.5, 0.5 },
}
scroll_direction = "right"
insert_mode = "view"
```

### Example 1.1

#### Windows

```text
A = forced 0.5 x 1.0
B = auto
C = auto
D = auto
E = auto
```

#### Expected Result

```text
A = forced 0.5 x 1.0
B = auto   0.5 x 0.5
C = auto   0.5 x 0.5
D = auto   0.5 x 0.5
E = auto   0.5 x 0.5
```

```text
+-----+-----+-----+
|     |  B  |  D  |
|  A  +-----+-----+
|     |  C  |  E  |
+-----+-----+-----+
```

### Example 1.2

#### Windows

```text
A = auto
B = forced 0.5 x 1.0
C = auto
D = auto
E = auto
```

#### Expected Result

```text
A = auto   0.5 x 1.0
B = forced 0.5 x 1.0
C = auto   0.5 x 0.5
D = auto   0.5 x 0.5
E = auto   0.5 x 1.0
```

```text
+-----+-----+-----+-----+
|     |     |  C  |     |
|  A  |  B  +-----+  E  |
|     |     |  D  |     |
+-----+-----+-----+-----+
```

### Example 1.3

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
A = auto   0.5 x 0.5
B = auto   0.5 x 0.5
C = forced 0.5 x 1.0
D = auto   0.5 x 0.5
E = auto   0.5 x 0.5
```

```text
+-----+-----+-----+
|  A  |     |  D  |
+-----+  C  +-----+
|  B  |     |  E  |
+-----+-----+-----+
```

### Example 1.4

#### Windows

```text
A = auto
B = auto
C = auto
D = forced 0.5 x 1.0
E = auto
```

#### Expected Result

```text
A = auto   0.5 x 0.5
B = auto   0.5 x 0.5
C = auto   0.5 x 1.0
D = forced 0.5 x 1.0
E = auto   0.5 x 1.0
```

```text
+-----+-----+-----+-----+
|  A  |     |     |     |
+-----+  C  |  D  |  E  |
|  B  |     |     |     |
+-----+-----+-----+-----+
```

### Example 1.5

#### Windows

```text
A = auto
B = auto
C = auto
D = auto
E = forced 0.5 x 1.0
```

#### Expected Result

```text
A = auto   0.5 x 0.5
B = auto   0.5 x 0.5
C = auto   0.5 x 0.5
D = auto   0.5 x 0.5
E = forced 0.5 x 1.0
```

```text
+-----+-----+-----+
|  A  |  C  |     |
+-----+-----+  E  |
|  B  |  D  |     |
+-----+-----+-----+
```

## Configuration 2

This configuration covers the third-based auto examples.

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

### Example 2.1

#### Windows

```text
A = auto
B = auto
C = auto
```

#### Expected Result

```text
A = auto 0.33 x 1.0
B = auto 0.33 x 1.0
C = auto 0.33 x 1.0
```

```text
+-----+-----+-----+
|     |     |     |
|  A  |  B  |  C  |
|     |     |     |
+-----+-----+-----+
```

### Example 2.2

#### Windows

```text
A = auto
B = auto
C = auto
D = auto
```

#### Expected Result

```text
A = auto 0.5 x 0.5
B = auto 0.5 x 0.5
C = auto 0.5 x 0.5
D = auto 0.5 x 0.5
```

```text
+-----+-----+
|  A  |  C  |
+-----+-----+
|  B  |  D  |
+-----+-----+
```

### Example 2.3

#### Windows

```text
A = auto
B = auto
C = auto
D = auto
E = auto
```

#### Expected Result

```text
A = auto 0.33 x 0.5
B = auto 0.33 x 0.5
C = auto 0.33 x 0.5
D = auto 0.33 x 0.5
E = auto 0.33 x 1.0
```

```text
+-----+-----+-----+
|  A  |  C  |     |
+-----+-----+  E  |
|  B  |  D  |     |
+-----+-----+-----+
```

## Configuration 3

This configuration covers the richer auto examples.

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

### Example 3.1

#### Windows

```text
A = auto
B = auto
```

#### Expected Result

```text
A = auto 0.5 x 1.0
B = auto 0.5 x 1.0
```

```text
+-----+-----+
|     |     |
|  A  |  B  |
|     |     |
+-----+-----+
```

### Example 3.2

#### Windows

```text
A = auto
B = auto
C = auto
```

#### Expected Result

```text
A = auto 0.5 x 0.5
B = auto 0.5 x 0.5
C = auto 0.5 x 1.0
```

```text
+-----+-----+
|  A  |     |
+-----+  C  |
|  B  |     |
+-----+-----+
```

### Example 3.3

#### Windows

```text
A = auto
B = auto
C = auto
D = auto
```

#### Expected Result

```text
A = auto 0.5 x 0.5
B = auto 0.5 x 0.5
C = auto 0.5 x 0.5
D = auto 0.5 x 0.5
```

```text
+-----+-----+
|  A  |  C  |
+-----+-----+
|  B  |  D  |
+-----+-----+
```

### Example 3.4

#### Windows

```text
A = auto
B = auto
C = auto
D = auto
E = auto
```

#### Expected Result

```text
A = auto 0.33 x 0.5
B = auto 0.33 x 0.5
C = auto 0.33 x 0.5
D = auto 0.33 x 0.5
E = auto 0.33 x 0.66
```

```text
+-----+-----+-----+
|  A  |  C  |  E  |
+-----+-----+     |
|  B  |  D  |-----+
+-----+-----+
```

### Example 3.5

#### Windows

```text
A = auto
B = auto
C = auto
D = auto
E = auto
F = auto
```

#### Expected Result

```text
A = auto 0.33 x 0.5
B = auto 0.33 x 0.5
C = auto 0.33 x 0.5
D = auto 0.33 x 0.5
E = auto 0.33 x 0.5
F = auto 0.33 x 0.5
```

```text
+-----+-----+-----+
|  A  |  C  |  E  |
+-----+-----+-----+
|  B  |  D  |  F  |
+-----+-----+-----+
```

### Example 3.6

#### Windows

```text
A = auto
B = auto
C = auto
D = auto
E = auto
F = auto
G = auto
```

#### Expected Result

```text
A = auto 0.33 x 0.33
B = auto 0.33 x 0.33
C = auto 0.33 x 0.33
D = auto 0.33 x 0.5
E = auto 0.33 x 0.5
F = auto 0.33 x 0.5
G = auto 0.33 x 0.5
```

```text
+-----+-----+-----+
|  A  |  D  |  F  |
+-----+     |     |
|  B  |-----+-----+
+-----+  E  |  G  |
|  C  |     |     |
+-----+-----+-----+
```

### Example 3.7

#### Windows

```text
A = auto
B = auto
C = auto
D = auto
E = auto
F = auto
G = auto
H = auto
```

#### Expected Result

```text
A = auto 0.33 x 0.33
B = auto 0.33 x 0.33
C = auto 0.33 x 0.33
D = auto 0.33 x 0.33
E = auto 0.33 x 0.33
F = auto 0.33 x 0.33
G = auto 0.33 x 0.5
H = auto 0.33 x 0.5
```

```text
+-----+-----+-----+
|  A  |  D  |  G  |
+-----+-----+     |
|  B  |  E  |-----+
+-----+-----+  H  |
|  C  |  F  |     |
+-----+-----+-----+
```
