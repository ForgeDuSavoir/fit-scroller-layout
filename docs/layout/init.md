# `layout/init.lua`

## Phase

Phase 1: Integration Skeleton.

## Purpose

`init.lua` is the entry point loaded by Hyprland.

Its job is to register the Fit Scroller layout and delegate all runtime work to
the Hyprland adapter. It must stay intentionally thin so Hyprland-specific
loading concerns do not spread into the core layout modules.

## Responsibilities

In Phase 1, `init.lua` must:

- require or load the Hyprland adapter module;
- register the layout as `fit-scroller`;
- expose a `recalculate(ctx)` callback;
- expose a `layout_msg(ctx, msg)` callback;
- return adapter results without adding extra behavior.

It must not:

- compute window geometry directly;
- maintain workspace state;
- parse Fit Scroller commands itself;
- know about target identity, dimensions, traversal or solver details.

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

## Phase 1 Behavior

### `recalculate(ctx)`

`recalculate(ctx)` delegates to:

```lua
adapter.recalculate(ctx)
```

The adapter is responsible for reading `ctx.targets`, reading `ctx.area`, and
placing windows with the temporary Phase 1 layout.

### `layout_msg(ctx, msg)`

`layout_msg(ctx, msg)` delegates to:

```lua
adapter.layout_msg(ctx, msg)
```

In Phase 1, no Fit Scroller command is implemented yet. Any message should
return a readable unknown-command error through the adapter.

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

## Phase 1 Acceptance Criteria

- Hyprland lists or accepts the `fit-scroller` layout.
- Switching to the layout does not crash with zero windows.
- Opening tiled windows causes `recalculate(ctx)` to delegate to the adapter.
- Sending an unsupported layout message returns a readable error.
