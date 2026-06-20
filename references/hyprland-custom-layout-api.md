# Hyprland Custom Layout Lua API

## Scope

This document records Hyprland `0.55.4` custom layout API behavior verified
from the official Hyprland source code.

Source tree inspected:

- <https://github.com/hyprwm/Hyprland/tree/v0.55.4>

Relevant source files:

- `src/config/lua/layout/LuaLayoutProvider.cpp`
- `src/config/lua/layout/LuaLayoutContext.cpp`
- `src/config/lua/layout/LuaLayoutTarget.cpp`
- `src/config/lua/objects/LuaWindow.cpp`
- `src/config/lua/LuaEventHandler.cpp`
- `src/config/lua/bindings/LuaBindingsDispatchers.cpp`
- `src/config/lua/bindings/LuaBindingsToplevel.cpp`
- `src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.cpp`

## Custom Layout Registration

Lua layouts are registered with:

```lua
hl.layout.register("name", {
    recalculate = function(ctx)
    end,

    layout_msg = function(ctx, msg)
    end,
})
```

The C++ provider normalizes layout names by prefixing them with `lua:`. A
layout registered as `fit-scroller` is therefore exposed internally as
`lua:fit-scroller`.

`recalculate(ctx)` is mandatory. `layout_msg(ctx, msg)` is optional.

If `recalculate(ctx)` errors, Hyprland logs the error and falls back to a
default grid placement for the live targets.

## Layout Context

The custom layout context passed to `recalculate(ctx)` and
`layout_msg(ctx, msg)` contains:

- `ctx.area`;
- `ctx.targets`;
- `ctx.grid_cell(ctx, index, cols, rows?)`;
- `ctx.column(ctx, index, count)`;
- `ctx.row(ctx, index, count)`;
- `ctx.split(ctx, box, side, ratio)`.

`ctx.area` is a box table:

```lua
{
    x = number,
    y = number,
    w = number,
    h = number,
}
```

The inspected source does not expose workspace identity, monitor identity or
recalculate reason through `ctx`.

## Layout Target Object

Each target exposes these fields:

- `target.index`;
- `target.window`;
- `target.box`;
- `target.place`;
- `target.set_box`.

`target:place(box)` and `target:set_box(box)` both expect:

```lua
{
    x = number,
    y = number,
    w = number,
    h = number,
}
```

The implementation calls `target->setPositionGlobal(box.noNegativeSize())`.

The inspected source does not expose a `target:focus()` method.

## Window Object Fields

`target.window` exposes the normal Lua window object. Relevant fields include:

- `window.address`;
- `window.active`;
- `window.stable_id`;
- `window.focus_history_id`;
- `window.layout`;
- `window.workspace`;
- `window.monitor`.

`window.address` is formatted with a `0x` prefix. To focus it through the Lua
dispatcher, Fit Scroller must build an `address:` selector:

```lua
hl.dsp.focus({ window = "address:" .. window.address })
```

`window.layout.name` reports the current tiled layout name. For Fit Scroller it
should be:

```text
lua:fit-scroller
```

## Layout Messages

`layout_msg(ctx, msg)` is called by Hyprland's layout dispatcher.

Return behavior:

- missing handler: success;
- boolean `false`: rejected layout message error;
- string: rejected layout message error with that string;
- any other value, including `true` or `nil`: success.

After the handler returns, Hyprland calls `recalculate()` on the layout.

Implication for Fit Scroller:

- returning `true` is enough to trigger recalculation;
- returning a string is an error path;
- the adapter should not apply partial placements during command handling.

## Focus Events

The custom layout callbacks do not directly receive focus-change events.

However, the global Hyprland Lua API exposes events through:

```lua
hl.on("window.active", function(window, reason)
end)
```

The event is backed by Hyprland's internal window active event bus and passes:

1. the active window object;
2. a numeric focus reason.

The built-in `scrolling` layout follows focus by subscribing directly in C++ to
the same event family.

## Focus Dispatching

The Lua dispatcher API supports focusing a window selector:

```lua
hl.dispatch(hl.dsp.focus({ window = "address:0x..." }))
```

Since `window.address` already includes the `0x` prefix, Fit Scroller can
build the required selector without shelling out:

```lua
hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
```

This path stays inside Hyprland's Lua API.

Fit Scroller must not call `hyprctl` from `layout_msg` or `recalculate`.
Calling back into Hyprland IPC while Hyprland is already executing a layout
callback can deadlock or time out.

## Directional Focus

`hl.dsp.focus({ direction = "left" })` calls Hyprland's `moveFocus` action.

That action uses compositor geometry to find the next window. It does not
notify custom Lua layouts through `recalculate(ctx)` by itself.

Implication:

- Fit Scroller cannot rely on `recalculate(ctx)` to learn every focus change;
- Fit Scroller should subscribe to `window.active` and request `follow`;
- Fit Scroller's own logical `focus previous` and `focus next` should use
  direct Lua focus dispatch with `window.address`.

## Architectural Decisions For Fit Scroller

1. `init.lua` owns global Hyprland Lua event subscriptions.
2. `hyprland_adapter.lua` owns focus dispatching through `hl.dispatch` and
   `hl.dsp.focus`.
3. Core modules never see raw Hyprland objects.
4. `layout_msg` and `recalculate` must never invoke `hyprctl`, `os.execute` or
   `io.popen`.
5. Focus following should be implemented with `hl.on("window.active", ...)`
   dispatching `hl.dsp.layout("follow")` when the active window belongs to
   `lua:fit-scroller`.
6. Logical focus commands should resolve the Fit Scroller target id to
   `target.window.address`, build `address:<window.address>`, and call
   `hl.dispatch(hl.dsp.focus({ window = selector }))`.
