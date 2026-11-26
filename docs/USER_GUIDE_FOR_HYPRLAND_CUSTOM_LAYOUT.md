# User Guide For Hyprland Custom Layout

This guide explains how to install, load and configure Fit Scroller as a
Hyprland custom Lua layout.

Fit Scroller currently targets Hyprland `0.55`.

## Files

Fit Scroller's runtime files are in:

```text
layout/
  init.lua
  hyprland_adapter.lua
  config.lua
  config_resolver.lua
  state.lua
  target_sync.lua
  commands.lua
  geometry.lua
  traversal.lua
  solver.lua
  viewport.lua
```

Keep these files together in the same directory.

`layout/init.lua` loads the other files relative to itself. This means the
layout directory does not need to be inside `~/.config/hypr/`; it can live
wherever you want, as long as Hyprland loads `layout/init.lua`.
The folder can also be renamed to your liking.

## Installation

### From An Official Release

Download the latest `fit-scroller-layout-vX.Y.Z.tar.gz` archive from the
GitHub release page:

```text
https://github.com/ForgeDuSavoir/fit-scroller-layout/releases
```

Then extract it into a stable Hyprland layouts directory:

```sh
mkdir -p ~/.config/hypr/layouts
tar -C ~/.config/hypr/layouts -xzf fit-scroller-layout-vX.Y.Z.tar.gz
```

This creates:

```text
~/.config/hypr/layouts/fit-scroller/
```

Load the layout entry point from your Hyprland Lua configuration:

```lua
dofile(os.getenv("HOME") .. "/.config/hypr/layouts/fit-scroller/init.lua")
```

Then select the registered layout name:

```text
lua:fit-scroller
```

### From A Git Checkout

Use this method only if you want to develop Fit Scroller or inspect the full
repository.

1. Put the project somewhere stable, for example:
```text
~/src/fit-scroller-layout
```

2. Load the layout entry point from your Hyprland Lua configuration:

```lua
dofile("/home/USER/src/fit-scroller-layout/layout/init.lua")
```

Use the absolute path that matches your installation.

If your Hyprland setup uses another import mechanism, the important part is
that Hyprland loads this file:

```text
<fit-scroller>/layout/init.lua
```

3. Select the layout in Hyprland using the registered layout name:

```text
lua:fit-scroller
```

Use this name anywhere Hyprland expects a layout name.

## Configuration

Fit Scroller user configuration lives in `layout/config.lua`.

`layout/config.lua` is intentionally limited to the raw configuration table.
The runtime code that validates, resolves and normalizes configuration lives in
`layout/config_resolver.lua`.

Default configuration:

```lua
return {
    default = {
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 0.5, 1.0 },
            { 0.5, 0.5 },
        },
        force_dimensions = {},
        scroll_direction = "right",
        insert_mode = "view",
        placement_priority = "order",
        center_windows = true,
    },
    displays = {},
}
```

### `allowed_dimensions`

Allowed dimensions are `{ width, height }` fractions of the usable viewport.

Example:

```lua
allowed_dimensions = {
    { 1.0, 1.0 },
    { 0.5, 1.0 },
    { 0.5, 0.5 },
}
```

This allows:

- full width, full height;
- half width, full height;
- half width, half height.

Fit Scroller never invents arbitrary dimensions outside this list.

### `force_dimensions`

`force_dimensions` controls the dimensions visited by `toggle dimension`.

Example:

```lua
allowed_dimensions = {
    { 1.0, 1.0 },
    { 0.5, 1.0 },
    { 0.5, 0.5 },
}

force_dimensions = {
    { 1.0, 1.0 },
    { 0.5, 1.0 },
}
```

With this configuration, automatic layout may still use any
`allowed_dimensions` entry, but `toggle dimension` only cycles through
`1.0x1.0` and `0.5x1.0`.

If `force_dimensions` is omitted or empty, `toggle dimension` cycles through
`allowed_dimensions`, which is the current default behavior.

Every `force_dimensions` entry must also exist in `allowed_dimensions`. If one
entry is not allowed, Fit Scroller ignores `force_dimensions` for that display
configuration and falls back to the `allowed_dimensions` cycle.

### `scroll_direction`

Valid values:

- `right`;
- `left`;
- `down`;
- `up`.

This controls where the workspace extends when windows no longer fit inside
the visible viewport.

### `insert_mode`

Valid values:

- `view`;
- `last`;
- `first`;
- `after_focused`;
- `before_focused`.

Default value:

```lua
insert_mode = "view"
```

Behavior:

- `view`: insert a new window after the last currently visible window;
- `last`: append a new window at the end of the logical order;
- `first`: insert a new window at the beginning of the logical order;
- `after_focused`: insert a new window just after the focused window;
- `before_focused`: insert a new window just before the focused window.

If the required anchor is unavailable, Fit Scroller falls back to `last`.

When `placement_priority = "spatial"`, `insert_mode` is still validated but is
ignored. New windows are placed from current geometry and viewport visibility,
not from order insertion anchors.

### `placement_priority`

Valid values:

- `order`;
- `spatial`.

Default value:

```lua
placement_priority = "order"
```

`order` keeps the original Fit Scroller behavior: window order is the primary
layout constraint, and `move previous` / `move next` mutate that order.

`spatial` makes current geometry the primary layout constraint. Spatial mode
uses directional commands such as `move left`, `move right`, `focus up` and
`focus down`. In this mode, `previous` and `next` commands are rejected.

### `center_windows`

Valid values:

- `true`;
- `false`.

Default value:

```lua
center_windows = true
```

`false` keeps the current placement behavior.

`true` centers windows when the resolved visible window group does not fill the
available viewport. If the group already fills the viewport on an axis, that
axis is left unchanged.

Centering is a final presentation step. It is applied after layout solving and
viewport reveal, and it does not affect solver decisions, saved layout state or
focus reveal. When a structural layout change causes the solver to run again,
the centering offset is discarded and recomputed from the new layout.

## Per-Display Configuration

You can override configuration by display name:

```lua
return {
    default = {
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 0.5, 1.0 },
            { 0.5, 0.5 },
        },
        force_dimensions = {
            { 1.0, 1.0 },
            { 0.5, 1.0 },
        },
        scroll_direction = "right",
        insert_mode = "view",
        placement_priority = "order",
        center_windows = true,
    },
    displays = {
        ["eDP-1"] = {
            allowed_dimensions = {
                { 1.0, 1.0 },
                { 1.0, 0.5 },
            },
            force_dimensions = {
                { 1.0, 1.0 },
            },
            scroll_direction = "down",
        },
        ["DP-1"] = {
            allowed_dimensions = {
                { 1.0, 1.0 },
                { 0.5, 1.0 },
                { 0.5, 0.5 },
            },
            scroll_direction = "right",
            insert_mode = "view",
            placement_priority = "spatial",
            center_windows = false,
        },
    },
}
```

Display-specific values override `default` field by field.

## Key Bindings

Fit Scroller exposes layout messages. In a Hyprland Lua config, bind them
through `hl.dsp.layout(...)`.

Recommended order-mode logical focus bindings:

```lua
hl.bind(mainMod .. " + Z", hl.dsp.layout("focus previous"))
hl.bind(mainMod .. " + X", hl.dsp.layout("focus next"))
```

These follow Fit Scroller's logical window order, not Hyprland's spatial
`movefocus` behavior.

Recommended order movement bindings:

```lua
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.layout("move previous"))
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.layout("move next"))
```

### Reorder tiles with SUPER+drag (order mode)

Save the result of loading Fit Scroller and replace your existing drag binding
for that chord with `bind_order_drag`. Load the layout only once:

```lua
local fit_scroller = dofile(os.getenv("HOME") .. "/.config/hypr/layouts/fit-scroller/init.lua")
fit_scroller.bind_order_drag("SUPER + mouse:272")
```

Use your checkout path instead if you load Fit Scroller from Git. Remove the
standalone `hl.bind` for that same chord: the helper installs a non-consuming
press observer, the unchanged native drag binding, and a non-consuming release
observer, in that order.

On release, the window takes the logical slot of the tile under the pointer,
pushing that tile one position later. The last visible tile is the exception:
drop on its leading half to insert before it or on its trailing half to insert
after it. For a stacked tile, that means top/bottom with horizontal scrolling
or left/right with vertical scrolling. Dropping in a gap uses the nearest
visible tile; dropping beyond the trailing edge of the visible tiles inserts
after the last visible tile. If no valid slot is available, the window returns
to its original slot. Forced dimensions
are kept if still allowed. Floating windows, cross-workspace drops, and spatial
mode keep their normal Hyprland behavior.

### Spatial-mode bindings

Recommended spatial-mode focus bindings:

```lua
hl.bind(mainMod .. " + H", hl.dsp.layout("focus left"))
hl.bind(mainMod .. " + L", hl.dsp.layout("focus right"))
hl.bind(mainMod .. " + K", hl.dsp.layout("focus up"))
hl.bind(mainMod .. " + J", hl.dsp.layout("focus down"))
```

Recommended spatial-mode movement bindings:

```lua
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.layout("move left"))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.layout("move right"))
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.layout("move up"))
hl.bind(mainMod .. " + SHIFT + J", hl.dsp.layout("move down"))
```

Recommended dimension toggle binding:

```lua
hl.bind(mainMod .. " + C", hl.dsp.layout("toggle dimension"))
```

## Commands

Supported layout messages:

```text
order mode:
focus previous
focus next
move previous
move next

spatial mode:
focus left
focus right
focus up
focus down
move left
move right
move up
move down

both modes:
toggle dimension
reveal focus
follow
debug targets
```

Command behavior:

- `focus previous`: focus the previous window in Fit Scroller order;
- `focus next`: focus the next window in Fit Scroller order;
- `move previous`: move the focused window one slot earlier;
- `move next`: move the focused window one slot later;
- `focus left/right/up/down`: focus the best spatial candidate in that
  direction;
- `move left/right/up/down`: move the focused window spatially in that
  direction;
- `toggle dimension`: cycle the focused window through allowed dimensions;
- `reveal focus`: reveal Hyprland's current focused window;
- `follow`: alias for `reveal focus`;
- `debug targets`: return debug information about the targets seen by the
  layout.

## Checking That It Works

After loading the layout and selecting `lua:fit-scroller`:

1. Open one tiled window.
2. Open a second tiled window.
3. Open a third and fourth tiled window.
4. Open a fifth tiled window.

With the default config, the fifth window should be placed beyond the initial
viewport and the viewport should reveal it when it receives focus.

You can ask the layout what targets it sees:

```sh
hyprctl eval 'hl.dispatch(hl.dsp.layout("debug targets"))'
```

Hyprland reports layout message strings as errors when the layout intentionally
returns debug text. For `debug targets`, that is expected.

## Troubleshooting

### Layout does not load

Check that your Hyprland config loads:

```text
<fit-scroller>/layout/init.lua
```

Do not load `hyprland_adapter.lua` directly.

### Module import fails

Keep every file in `layout/` together. `init.lua` loads sibling files relative
to its own path.

### Focus changes but viewport does not follow

In order mode, use Fit Scroller focus commands for logical navigation:

```lua
hl.dsp.layout("focus previous")
hl.dsp.layout("focus next")
```

In spatial mode, use directional focus commands:

```lua
hl.dsp.layout("focus left")
hl.dsp.layout("focus right")
hl.dsp.layout("focus up")
hl.dsp.layout("focus down")
```

If you use Hyprland's native focus dispatchers, Fit Scroller should still
receive `window.active` and run `follow`, but this depends on Hyprland's Lua
event behavior.

You can bind `follow` manually as a fallback:

```lua
hl.bind(mainMod .. " + F", hl.dsp.layout("follow"))
```

### A command returns an error

Errors are prefixed with:

```text
fit-scroller:
```

Common causes:

- invalid `allowed_dimensions`;
- invalid `force_dimensions`;
- invalid `scroll_direction`;
- invalid `insert_mode`;
- invalid `center_windows`;
- using an order-only command such as `move previous` while
  `placement_priority = "spatial"`;
- using a spatial-only command such as `move left` while
  `placement_priority = "order"`;
- unsupported command text;
- missing Hyprland window address for focus commands.

### Force dimension behaves unexpectedly

`toggle dimension` cycles through configured `force_dimensions` when present
and valid.

If `force_dimensions` is omitted, empty or references a dimension that is not in
`allowed_dimensions`, `toggle dimension` cycles through `allowed_dimensions`.

The layout never uses dimensions that are not listed in the effective display
configuration.

## Current Limitations

- Manual scroll commands are not part of V1.
- User configuration is edited in `layout/config.lua`; validation and
  normalization are handled by `layout/config_resolver.lua`.
- Hyprland integration is targeted at Hyprland `0.55`.
