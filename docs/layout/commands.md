# `layout/commands.lua`

## Purpose

`commands.lua` parses Fit Scroller layout messages and applies command-level
state changes.

`commands.lua` supports:

- `move previous`;
- `move next`;
- `toggle dimension`;
- `focus previous`;
- `focus next`;
- `reveal focus`;
- `follow`.

## Responsibilities

`commands.lua` must:

- parse raw `layout_msg` strings;
- reject unknown commands with readable errors;
- implement `move previous`;
- implement `move next`;
- implement `toggle dimension`;
- mutate state only after validation succeeds;
- return whether recalculation is required.

It must not:

- place windows;
- inspect raw Hyprland targets;
- compute layout candidates;
- change Hyprland focus directly.

## Command Parsing

Commands are plain text messages received from Hyprland's `layoutmsg`
dispatcher.

Recommended parsing:

```lua
local command, arg = msg:match("^(%S+)%s*(.*)$")
```

For two-word commands, parse the first token as the command family and the
second token as the action.

Supported messages:

```text
move previous
move next
toggle dimension
```

Focus and reveal messages:

```text
focus previous
focus next
reveal focus
follow
```

## Return Shape

Recommended result shape:

```lua
CommandResult = {
    ok = true,
    changed = true,
    needs_layout_update = true,
    needs_viewport_update = false,
    mutation = {
        kind = "state_update",
    },
}
```

Structural commands use `needs_layout_update`. Focus commands use
`needs_viewport_update`.

For errors:

```lua
CommandResult = {
    ok = false,
    error = "fit-scroller: unsupported command: ..."
}
```

The adapter converts command results into Hyprland `layout_msg` returns.

For mutations that can make the layout invalid, the command result should
describe the intended mutation instead of committing it directly. The adapter
applies that mutation to a draft workspace state, validates recalculation, and
commits the draft only after success.

## `move previous`

Swaps the focused window with its logical predecessor.

Example:

```text
before: A B C
focus:  B
after:  B A C
```

If the focused window has no predecessor, the command is a no-op.

## `move next`

Swaps the focused window with its logical successor.

Example:

```text
before: A B C
focus:  B
after:  A C B
```

If the focused window has no successor, the command is a no-op.

## `toggle dimension`

Cycles the focused window's dimension mode using the config-provided cycle.

Cycle:

```text
auto -> largest forced dimension -> ... -> smallest forced dimension -> auto
```

Expected behavior:

- if the focused window is in `auto`, set the first forced dimension;
- if it has a forced dimension, set the next forced dimension;
- if it has the smallest forced dimension, return to `auto`;
- if there is no focused window, do nothing;
- if the stored forced key is invalid, return an error and do not mutate state.

Command parsing does not validate whether a forced dimension fits on the cross
axis. That validation belongs to the solver.

## Unknown Commands

Unknown commands must return readable errors.

Examples:

```text
fit-scroller: expected command
fit-scroller: unsupported command: resize
fit-scroller: unsupported command: move first
```

Focus commands must either execute successfully or return a clear integration
error if Hyprland focus control is unavailable.

## Guarantees

- `move previous` swaps with the predecessor.
- `move next` swaps with the successor.
- Move commands at order boundaries are no-ops.
- `toggle dimension` cycles through config dimensions and back to `auto`.
- Unknown commands return readable errors.
- Commands do not directly place windows.

## Hardening

Logical focus commands are part of the command set.

Focus commands are different from move commands:

- they do not change `state.order`;
- they do not change dimension modes;
- they select a target id and ask the adapter to focus it through Hyprland;
- they require viewport reveal so the newly focused window is visible.

`commands.lua` still must not call Hyprland directly. It only decides which
logical target should receive focus.

## `focus previous`

Focuses the logical predecessor of the currently focused window.

Example:

```text
order:        A B C
before focus:   B
after focus:  A
```

If the focused window has no predecessor, the command is a no-op.

Recommended result:

```lua
CommandResult = {
    ok = true,
    changed = false,
    needs_layout_update = false,
}
```

The command does not wrap from the first window to the last window in V1.

## `focus next`

Focuses the logical successor of the currently focused window.

Example:

```text
order:        A B C
before focus:   B
after focus:      C
```

If the focused window has no successor, the command is a no-op.

The command does not wrap from the last window to the first window in V1.

## Focus Command Result

Focus commands should return the id to focus, but should not update
`state.focused_id` directly.

Recommended result:

```lua
CommandResult = {
    ok = true,
    changed = true,
    needs_viewport_update = true,
    focus_target_id = "C",
}
```

The adapter consumes `focus_target_id`, resolves the corresponding Hyprland
target or window selector, and performs the actual focus operation.

Hyprland `0.55.4` exposes `target.window.address`, so the adapter should build
an `address:` selector and focus the requested target through:

```lua
hl.dispatch(hl.dsp.focus({ window = "address:" .. descriptor.window.address }))
```

If the adapter cannot focus the requested target because the expected Hyprland
Lua API is unavailable, it should return:

```lua
{
    ok = false,
    error = "fit-scroller: focus commands are unsupported by the current Hyprland adapter"
}
```

In that case, `commands.lua` must not mutate state.

Focus commands must not use `hyprctl`, `os.execute` or `io.popen` from inside
the layout callback.

## Focus Source Of Truth

Hyprland remains the source of truth for active focus.

After a focus command:

1. `commands.lua` selects the logical target id.
2. `hyprland_adapter.lua` asks Hyprland to focus that target.
3. the next focus synchronization reads the active target from `ctx.targets`;
4. `target_sync.lua` updates `state.focused_id`;
5. `viewport.lua` reveals the focused placement from `state.last_layout`.

This avoids state claiming that a target is focused when Hyprland rejected or
ignored the focus request.

## `reveal focus`

Requests a viewport update that reveals the focus currently reported by
Hyprland.

This command does not change focus, reorder windows or update dimension modes.
It exists for integration with Hyprland focus bindings that change focus
without changing layout structure.

Expected usage:

```text
Hyprland window.active event
hl.dispatch(hl.dsp.layout("follow"))
```

During `layout_msg(ctx, "reveal focus")`, the adapter synchronizes live targets
from `ctx.targets`, so `target.window.active` updates `state.focused_id`.
The adapter then uses `viewport.lua` and `state.last_layout` to reveal the
newly focused window without calling the solver.

`follow` is an alias for `reveal focus`. It exists because some Hyprland Lua
configuration wrappers and event handlers are easier to use with single-token
layout messages, for example:

```lua
hl.dispatch(hl.dsp.layout("follow"))
```

## Guarantees

- `focus previous` selects the logical predecessor.
- `focus next` selects the logical successor.
- `reveal focus` requests reveal of the Hyprland-reported active target.
- Focus commands at order boundaries are no-ops.
- Focus commands do not reorder windows.
- Focus commands do not change dimension modes.
- Successful focus commands use Hyprland's in-process Lua focus dispatcher.
- External focus changes trigger `follow` through `hl.on("window.active", ...)`.
- Focus commands and `follow` do not trigger the solver.
- Unsupported Hyprland focus integration returns a readable error without
  mutating state.

## Hardening

This section defines command validation and state mutation.

Commands should be predictable even when the user sends malformed messages,
when no window is focused, or when the current state is temporarily incomplete.

## Parsing Validation

Command parsing should reject:

- `nil` messages;
- empty messages;
- unknown command families;
- known command families with missing actions;
- known command families with unknown actions;
- extra unsupported arguments.

Examples:

```text
fit-scroller: expected command
fit-scroller: unsupported command: move
fit-scroller: unsupported command: move first
fit-scroller: unsupported command: toggle size
```

## Mutation Safety

Commands that mutate state must validate all required data before committing.

Examples:

- `toggle dimension` must validate the current mode and next mode before
  changing `dimension_mode_by_id`;
- `move previous` and `move next` must find both ids before swapping;
- focus commands must find the target id before returning `focus_target_id`.

No command should partially mutate state and then return an error.

When final validity depends on the solver, commands should return a mutation
plan and let the adapter commit it through a draft workspace state.

This is required for `toggle dimension`: a forced dimension key may be valid
in configuration but still fail because it cannot fit on the cross axis. In
that case, the previous dimension mode must remain active.

Focus commands are viewport-only commands. They may request a Hyprland focus
change and a viewport reveal, but they must not request layout solving.

Structural commands are:

- `move previous`;
- `move next`;
- `toggle dimension`.

Viewport-only commands are:

- `focus previous`;
- `focus next`;
- `reveal focus`;
- `follow`.

Tests must verify that each command reports the correct intent to the
adapter so the adapter can choose between structural layout flow and
viewport-only flow.

## No-Focus Behavior

If no focused id exists:

- `move previous` is a no-op;
- `move next` is a no-op;
- `focus previous` is a no-op;
- `focus next` is a no-op;
- `toggle dimension` is a no-op.

These are not errors because no user intent can be applied to a missing focus.

## Test Cases

Command tests should cover:

- empty command;
- unknown command;
- malformed two-word command;
- extra arguments;
- every command with no focused id;
- move at both order boundaries;
- focus at both order boundaries;
- toggle from `auto`;
- toggle from each forced dimension;
- toggle with an invalid stored forced key;
- `move previous` and `move next` report structural layout intent;
- `toggle dimension` reports structural layout intent;
- `focus previous` and `focus next` report viewport-only intent;
- `reveal focus` and `follow` report viewport-only intent;
- failed validation leaves state unchanged.

## Guarantees

- Malformed commands return readable errors.
- No-focus commands are no-ops.
- Boundary commands are no-ops.
- Command results distinguish structural layout updates from viewport-only
  updates.
- Failed command validation does not mutate workspace state.
- Failed command validation never mutates state.
- Tests cover parsing, no-op behavior and mutation safety.
