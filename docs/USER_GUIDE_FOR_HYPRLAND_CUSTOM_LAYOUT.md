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

1. Put the project somewhere stable, for example:
```text
~/src/fit-scroller-layout
```

2. Load the layout entry point from your Hyprland Lua configuration:

```lua
dofile("/home/USER/src/fit-scroller-layout/init.lua")
```

Use the absolute path that matches your installation.

If your Hyprland setup uses another import mechanism, the important part is
that Hyprland loads this file:

```text
<fit-scroller>/init.lua
```

3. Select the layout in Hyprland using the registered layout name:

```text
lua:fit-scroller
```

Use this name anywhere Hyprland expects a layout name.

## Configuration

Fit Scroller configuration currently lives in `layout/config.lua`, in
`M.raw_config`.

Default configuration:

```lua
M.raw_config = {
    default = {
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 0.5, 1.0 },
            { 0.5, 0.5 },
        },
        scroll_direction = "right",
        tiling_mode = "split",
        insert_mode = "view",
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

### `scroll_direction`

Valid values:

- `right`;
- `left`;
- `down`;
- `up`.

This controls where the workspace extends when windows no longer fit inside
the visible viewport.

### `tiling_mode`

Valid values:

- `split`;
- `ajuste`.

`split` is the default. It splits the largest existing slot when possible, then
falls back to `ajuste` when no valid split exists.

`ajuste` directly chooses dimensions that keep window sizes as equivalent as
possible, then minimizes scroll.

This is useful especially for larger displays with more allowed dimensions. It has no impact with the default configuration.
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

## Per-Display Configuration

You can override configuration by display name:

```lua
M.raw_config = {
    default = {
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 0.5, 1.0 },
            { 0.5, 0.5 },
        },
        scroll_direction = "right",
        tiling_mode = "split",
        insert_mode = "view",
    },
    displays = {
        ["eDP-1"] = {
            allowed_dimensions = {
                { 1.0, 1.0 },
                { 1.0, 0.5 },
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
            tiling_mode = "split",
            insert_mode = "view",
        },
    },
}
```

Display-specific values override `default` field by field.

## Key Bindings

Fit Scroller exposes layout messages. In a Hyprland Lua config, bind them
through `hl.dsp.layout(...)`.

Recommended logical focus bindings:

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

Recommended dimension toggle binding:

```lua
hl.bind(mainMod .. " + C", hl.dsp.layout("toggle dimension"))
```

## Commands

Supported layout messages:

```text
focus previous
focus next
move previous
move next
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

Use Fit Scroller focus commands for logical navigation:

```lua
hl.dsp.layout("focus previous")
hl.dsp.layout("focus next")
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
- invalid `scroll_direction`;
- invalid `tiling_mode`;
- invalid `insert_mode`;
- unsupported command text;
- missing Hyprland window address for focus commands.

### Force dimension behaves unexpectedly

`toggle dimension` cycles through configured `allowed_dimensions`.

The layout never uses dimensions that are not listed in the effective display
configuration.

## Current Limitations

- Manual scroll commands are not part of V1.
- V1 uses order-based tiling, not spatial left/right/up/down placement logic.
- Configuration is currently edited in `layout/config.lua`.
- Hyprland integration is targeted at Hyprland `0.55`.
