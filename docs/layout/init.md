# `layout/init.lua`

## Purpose

`init.lua` is the entry point loaded by Hyprland.

Its job is to register the Fit Scroller layout and delegate all runtime work to
the Hyprland adapter. It must stay intentionally thin so Hyprland-specific
loading concerns do not spread into the core layout modules.

## Responsibilities

`init.lua` must:

- load the Hyprland adapter module relative to `init.lua`;
- register the layout as `fit-scroller`;
- expose a `recalculate(ctx)` callback;
- expose a `layout_msg(ctx, msg)` callback;
- return adapter results without adding extra behavior.

It must not:

- compute window geometry directly;
- maintain workspace state;
- parse Fit Scroller commands itself;
- know about target identity, dimensions, traversal or solver details.

`init.lua` also owns global Hyprland Lua event subscription setup. This remains
a thin integration role: event callbacks must only dispatch Fit Scroller layout
messages and must not compute state or geometry themselves.

## Hyprland Contract

The expected registration shape follows the local layout examples:

```lua
hl.layout.register("fit-scroller", {
    recalculate = function(ctx)
        -- delegate to adapter
    end,

    layout_msg = function(ctx, msg)
        -- delegate to adapter
    end,
})
```

Hyprland `0.55.4` also exposes focus events through:

```lua
hl.on("window.active", function(window, reason)
end)
```

Fit Scroller should subscribe to this event once during initialization and ask
the active Fit Scroller layout to run `follow`:

```lua
hl.on("window.active", function(window)
    if window and window.layout and window.layout.name == "lua:fit-scroller" then
        hl.dispatch(hl.dsp.layout("follow"))
    end
end)
```

The callback must be defensive. If `window.layout` is missing or does not name
Fit Scroller, it should do nothing.

## Module Loading

`init.lua` must not depend on Hyprland's current working directory or on a
user-specific `package.path`.

Hyprland appears to resolve Lua imports relative to the Hyprland configuration
environment rather than relative to the loaded layout file. A plain
`require("hyprland_adapter")` would therefore force users to place Fit
Scroller modules in a specific configuration directory such as
`~/.config/hypr/layout`, making installation fragile.

Instead, `init.lua` should resolve its own source path and load sibling modules
relative to that path:

```text
layout/init.lua
layout/hyprland_adapter.lua
```

The current implementation uses Lua's `debug.getinfo` to find the current
file and `loadfile` to load `hyprland_adapter.lua` from the same directory.
This keeps the layout directory relocatable as long as the files stay together.

Runtime assumption:

- Hyprland's Lua environment exposes `debug.getinfo`;
- Hyprland's Lua environment exposes `loadfile`;
- `debug.getinfo(1, "S").source` returns a file path prefixed with `@`.

If any of these assumptions fail in Hyprland `0.55`, the fallback strategy
should be explicit, such as shipping a bundled single-file layout or
documenting an installation path constraint. Do not silently reintroduce a
`require`-based dependency on the Hyprland configuration directory.

## Runtime Behavior

### `recalculate(ctx)`

`recalculate(ctx)` delegates to:

```lua
adapter.recalculate(ctx)
```

The adapter is responsible for reading `ctx.targets`, reading `ctx.area`, and
placing windows with the current layout.

### `layout_msg(ctx, msg)`

`layout_msg(ctx, msg)` delegates to:

```lua
adapter.layout_msg(ctx, msg)
```

Unsupported Fit Scroller commands should return a readable unknown-command error
through the adapter.

## Error Handling

`init.lua` should avoid swallowing adapter errors silently.

If the adapter returns a string error from `layout_msg`, `init.lua` must return
that string unchanged.

If the adapter returns `true`, `init.lua` must return `true` unchanged.

## Implementation Notes

Keep this file small enough that future changes rarely touch it. Most new
behavior should be added to:

- `hyprland_adapter.lua` for Hyprland API interaction;
- `commands.lua` for command parsing;
- `state.lua` and `target_sync.lua` for workspace state;
- `solver.lua` for final layout computation.

The exception is global Hyprland event registration. Event registration belongs
in `init.lua` because it installs the layout into Hyprland's Lua runtime.

## Guarantees

- Hyprland lists or accepts the `fit-scroller` layout.
- Switching to the layout does not crash with zero windows.
- Opening tiled windows causes `recalculate(ctx)` to delegate to the adapter.
- Sending an unsupported layout message returns a readable error.
