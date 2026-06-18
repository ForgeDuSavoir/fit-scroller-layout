# Fit Scroller Layout
## Overview
**Fit practical windows before scrolling.**

Fit Scroller is a tiling layout concept built around a simple idea: maximize the number of practical windows visible on screen. When additional windows can no longer fit while preserving practical window dimensions, the layout introduces scrolling rather than shrinking existing windows further.

Instead of allowing arbitrary window dimensions or continuously shrinking windows as new ones are opened, Fit Scroller arranges windows using a predefined set of practical window dimensions and automatically reorganizes the layout to maximize the number of practical windows visible on screen.
When additional windows can no longer fit while respecting those dimension constraints, the layout introduces scrolling. Navigation then behaves similarly to a scrolling tiling manager, allowing the workspace to extend beyond the visible screen area.

This concept is currently implemented as a custom layout for Hyprland, but the underlying ideas are independent of any specific window manager.

The detailed behavioral contract and unresolved design decisions are documented
in [SPECIFICATION.md](SPECIFICATION.md).

---

## Design Principles
Fit Scroller is based on a simple idea:
Not every valid arrangement of windows is practical.

Traditional tiling layouts often allow arbitrary resizing and many intermediate layouts. While flexible, this frequently leads to layouts that provide little practical value and require constant manual adjustments.

Fit Scroller takes the opposite approach: it intentionally restricts the set of possible window dimensions and arrangements.
### Practical Dimensions Only
Windows may only occupy a predefined set of practical dimensions. Layouts are derived automatically from those dimensions rather than explicitly defined.
### Discrete Layout Transitions
Fit Scroller intentionally does not support gradual or pixel-level resizing. Instead, windows can only transition between predefined practical dimensions.

This design choice is philosophical more than technical. Rather than requiring users to repeatedly adjust window borders and fine-tune layouts manually, Fit Scroller encourages transitions between a small set of practical dimensions. The layout then automatically adapts surrounding windows while preserving the existing window order.
### Maximize Practical Density
By default, the layout attempts to display as many windows as possible while keeping every visible window at a practical dimension.
### Scrolling Instead of Shrinking
When additional windows can no longer fit while respecting the allowed dimensions, the layout introduces scrolling rather than continuously shrinking existing windows.


---

## Layout Model
Fit Scroller is driven by a small set of concepts that define how windows are arranged and when scrolling is introduced.
### Allowed Window Dimensions
Each display defines a set of allowed window dimensions.

A window may only occupy one of these predefined dimensions. The layout never performs arbitrary resizing or pixel-level adjustments.
The dimensions are defined as a percentage of the screens width and height.

Example:
```lua
{
    { 1.0, 1.0 },
    { 0.5, 1.0 },
    { 0.5, 0.5 },
}
```

This configuration allows windows to occupy:
- 100% width × 100% height
- 50% width × 100% height
- 50% width × 50% height

The actual arrangements visible on screen are derived from these allowed dimensions rather than explicitly defined.

These predefined dimensions are not arbitrary. They represent practical window dimensions: dimensions that remain comfortable and efficient to use for a given display and workflow.

The exact definition of "practical" depends on the display and user preferences, but the underlying principle remains the same: a window should occupy dimensions that are appropriate for the task being performed. Practical dimensions therefore define both minimum usable sizes and sensible aspect ratios.

Fit Scroller limits windows to a predefined set of practical dimensions and introduces scrolling once no additional windows can fit while preserving those dimensions.
### Automatic Fitting
When windows are opened, closed or moved, the layout automatically adjusts window dimensions and positions to make the best use of the available space.

Fit Scroller preserves the existing window order and never rearranges windows automatically. Instead, it selects the most appropriate practical dimensions for each window in order to keep as many windows visible as possible while respecting the configured dimension constraints.
### Viewport
The visible screen represents a viewport into the workspace.

As long as windows can be displayed while respecting the configured practical dimensions, they remain visible within the viewport.

When no additional windows can fit while preserving those dimensions, the workspace extends beyond the visible viewport.
### Scrolling
Once the viewport is full, newly opened windows are placed outside the visible area.

Navigation then behaves similarly to a scrolling tiling manager: moving focus can automatically bring hidden windows into view while preserving the existing window order.
### Scroll Direction
Each display defines a scroll direction.

This direction determines where the workspace extends once additional windows no longer fit within the visible viewport.

Available directions:
- Right
- Left
- Down
- Up

The scroll direction is a fixed configuration value for each display.
### Forced Dimension
By default, windows use the `auto` dimension mode. In this mode, the layout selects one of the allowed dimensions automatically.

The user may force a specific allowed dimension for a window. When a dimension is forced, Fit Scroller assigns that dimension to the window and adapts the dimensions of surrounding windows to keep the layout valid.

Forced dimensions do not change the window order. They only affect how the available space is distributed around the affected window.

Example modes:
- Auto
- Force 50% × 100%
- Force 100% × 100%

The exact set of available dimension modes is defined in the configuration and can only reference dimensions from the configured set of allowed dimensions.

Forced dimensions are also the primary mechanism for resizing windows, as granular resizing is not permitted (see above).

---

## Layout Structure
Here is an example of behavior for the following allowed dimensions configuration :
```lua
{
    { 1.0, 1.0 },
    { 0.5, 1.0 },
    { 0.5, 0.5 },
}
```

### 1 Window

```text
+-----------+
|           |
|     A     |
|           |
+-----------+
````

### 2 Windows

```text
+-----+-----+
|     |     |
|  A  |  B  |
|     |     |
+-----+-----+
```

### 3 Windows

```text
+-----+-----+
|     |  B  |
|  A  +-----+
|     |  C  |
+-----+-----+
```

or

```text
+-----+-----+
|  A  |     |
|-----+  B  |
|  C  |     |
+-----+-----+
```

### 4 Windows

```text
+-----+-----+
|  A  |  B  |
|-----+-----|
|  D  |  C  |
+-----+-----+
```

### 5+ Windows

Additional windows are placed outside the visible viewport and viewport scrlls to newly focused window.

```text
      +-------------+ 
+-----|+-----+-----+|
|  A  ||  B  |     ||
|-----|+-----|  E  ||
|  D  ||  C  |     ||
+-----|+-----+-----+|
      +-------------+
```
(A and D not visible, B, C and E visible)

Then

```text
      +-------------+
+-----|+-----+-----+|
|  A  ||  B  |  E  ||
|-----|+-----|-----||
|  D  ||  C  |  F  ||
+-----|+-----+-----+|
      +-------------+
```
(A and D not visible, B, C, E and F visible)

The viewport scrolls through the workspace similarly to a scrolling tiling manager.
