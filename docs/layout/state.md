# `layout/state.lua`

## Purpose

`state.lua` owns mutable Fit Scroller state that must survive between Hyprland
`recalculate(ctx)` calls.

It preserves logical window order, per-window dimension modes, focus state,
viewport offset and the last valid layout.

## Responsibilities

`state.lua` must:

- create workspace state lazily;
- store logical window order;
- store dimension mode per window;
- store the last known focused target id;
- remove all per-window state when a window disappears;
- expose safe mutation helpers for commands;
- avoid leaking state between independent workspaces when a workspace id is
  available.

It must not:

- inspect Hyprland targets directly;
- decide where new windows are inserted;
- parse user commands;
- compute geometry.

## Workspace State Shape

Recommended shape:

```lua
WorkspaceState = {
    order = {},
    dimension_mode_by_id = {},
    focused_id = nil,
    viewport_offset = 0,
    last_layout = nil,
}
```

Core state fields:

- `order`;
- `dimension_mode_by_id`;
- `focused_id`.

`last_layout` is the boundary between the solver and viewport systems: the
solver updates it after structural changes, and viewport changes consume it
without invoking the solver.

## Dimension Modes

A window dimension mode is either:

```lua
{ kind = "auto" }
```

or:

```lua
{ kind = "forced", key = "0.5x1.0" }
```

The stored forced key must come from `config.lua`.

Forced dimension modes persist for as long as the window id remains present.
When a window id disappears during synchronization, its dimension mode must be
removed.

## Public API

Recommended functions:

```lua
state.get_workspace_state(workspace_key)
state.set_focused_id(workspace_state, id)
state.get_focused_id(workspace_state)
state.get_dimension_mode(workspace_state, id)
state.set_dimension_mode(workspace_state, id, mode)
state.remove_window_state(workspace_state, id)
state.swap_order(workspace_state, focused_id, delta)
state.index_of(workspace_state, id)
```

### `swap_order(workspace_state, focused_id, delta)`

Swaps the focused id with its logical neighbor.

Expected behavior:

- `delta = -1` swaps with the predecessor;
- `delta = 1` swaps with the successor;
- if no neighbor exists, it is a no-op;
- returns whether the order changed.

## Workspace Key

State must be keyed by a stable workspace identifier.

Hyprland's Lua custom layout `ctx` does not expose `ctx.workspace`. The adapter
must derive the workspace key from the live target windows:

1. `target.window.workspace.id`;
2. `target.window.workspace.config_name`;
3. `target.window.workspace.name`.

The key should include the field used, for example `workspace:3` or
`workspace-name:special:magic`, so numeric ids and names cannot collide.

Using one global state is not acceptable for normal operation. If no target
window exposes a workspace, the adapter may use an explicit fallback key only
for an empty or unidentifiable context, and must avoid interpreting that
fallback as a real workspace lifecycle event.

This matters for cleanup: a window id missing from the current `ctx.targets`
means "not part of this layout pass". It should be treated as closed only after
the adapter has selected the correct workspace state for the current target
workspace. Otherwise, switching workspaces can delete `dimension_mode_by_id`
entries for windows that still exist on another workspace.

## Invariants

After synchronization:

- every id in `order` corresponds to a present tiled target;
- no id appears more than once in `order`;
- `dimension_mode_by_id` has no entries for missing ids;
- `focused_id` is either present or `nil`.

## Guarantees

- State is created lazily for a workspace.
- Window order survives repeated recalculations.
- Closing a window removes its dimension mode.
- `move previous` and `move next` can mutate order through state helpers.
- `toggle dimension` can mutate only the focused window's dimension mode.

## Hardening

`viewport_offset` stores the current scroll offset for the workspace on the
configured scroll axis. The value is logical, not pixel-based.

State does not decide how the offset changes. It only stores the value
computed by `viewport.lua`.

## Viewport Offset Rules

The offset must be updated only against a valid `last_layout`.

Structural flow:

```text
structural change
    -> solver computes placements and workspace extent
    -> state.last_layout is updated
```

Viewport flow:

```text
focus change or future manual scroll
    -> read state.last_layout
    -> viewport.reveal computes next offset
    -> state.viewport_offset is updated
    -> adapter reapplies last_layout using that offset
```

Focus changes must not update `last_layout`.

If layout computation fails, both `state.viewport_offset` and
`state.last_layout` should keep their previous values.

## Focus State

Hyprland is the source of truth for which window is focused.

`state.focused_id` should be updated from synchronized target descriptors
rather than directly from `focus previous` or `focus next` command execution.

This matters because a focus command may fail at the Hyprland integration
boundary. In that case, state must not pretend a different window is focused.

Changing `focused_id` may trigger viewport reveal. It must not trigger the
solver by itself.

## Public API

Recommended additions:

```lua
state.get_viewport_offset(workspace_state)
state.set_viewport_offset(workspace_state, offset)
state.update_last_layout(workspace_state, layout)
```

### `set_viewport_offset(workspace_state, offset)`

Stores the new clamped viewport offset.

The caller is responsible for passing a valid offset returned by
`viewport.lua`.

### `update_last_layout(workspace_state, layout)`

Stores the most recent valid layout for later recovery.

The adapter may only populate this value after a complete successful placement.
Recovery from invalid configuration or placement failures must keep the previous
valid value.

## Guarantees

- `viewport_offset` survives repeated structural recalculations.
- Focus changes update `focused_id` only after Hyprland reports the active
  target.
- Successful reveal updates `viewport_offset`.
- Failed layout or focus integration does not corrupt focus state.
- Offset storage remains per workspace.

## Hardening

This section defines state mutation and last-valid-layout recovery.

The core rule is that recoverable failures must not leave state halfway
mutated. Commands and recalculation should either commit a coherent new state
or keep the previous state.

## Last Valid Layout

`last_layout` stores the most recent layout that was fully computed and
successfully applied.

Recommended shape:

```lua
LastLayout = {
    placements_by_id = {},
    dimensions_by_id = {},
    workspace_extent = 1.0,
    viewport_offset = 0,
    display_id = "DP-1",
    target_ids = { "A", "B" },
}
```

The adapter may use this layout when a later recalculation fails for a
recoverable reason.

`last_layout` should not be updated until after every target placement has
been accepted by the adapter.

Updating `last_layout` immediately after solver success is not sufficient.
The adapter must first:

1. compute the layout;
2. compute or clamp viewport offset;
3. convert every target rectangle;
4. verify every target can be placed;
5. apply every placement;
6. commit `last_layout` and state mutations.

## Recoverable Failures

State should preserve the previous valid values for:

- invalid configuration;
- solver errors;
- viewport errors;
- failed rectangle conversion;
- incomplete Hyprland target geometry;
- unsupported focus integration.

For these failures:

- do not update `viewport_offset`;
- do not update `last_layout`;
- do not partially apply dimension mode changes;
- do not partially apply target order changes;
- do not claim a pending focus change succeeded.

## Transaction Pattern

Mutating operations should follow a validate-then-commit pattern.

Recommended helper shape:

```lua
state.clone_workspace_state(workspace_state)
state.commit_workspace_state(workspace_state, draft_state)
```

This does not require a deep copy for every recalculation if implementation
cost is too high, but command mutations should still be structured so a failed
validation cannot leave partial state behind.

Operations that should use this pattern:

- target synchronization when descriptor validation can fail;
- `toggle dimension`, because the next forced dimension can be solver-invalid;
- `move previous` and `move next`, because order changes affect solver input;
- recalculation paths that update `viewport_offset`;
- updates to `last_layout`.

Example for `toggle dimension`:

1. resolve the next dimension mode;
2. validate that the key exists in config;
3. optionally ask the solver whether it can fit;
4. only then update `dimension_mode_by_id`.

## State Invariant Checks

State exposes a debug-oriented invariant check:

```lua
state.validate_workspace_state(workspace_state, present_ids)
```

It should verify:

- `order` has no duplicates;
- every id in `order` is present;
- `dimension_mode_by_id` has no missing ids;
- `focused_id` is either present or `nil`;
- `viewport_offset` is a finite number greater than or equal to `0`;
- `last_layout`, when present, has placements only for known ids.

The adapter may call this during development or tests. Runtime behavior should
not depend on expensive validation unless needed for diagnostics.

## Test Cases

State tests should cover:

- failed command validation does not mutate state;
- failed forced-dimension update preserves the previous mode;
- failed move command preserves previous order;
- failed target synchronization preserves previous order and dimension modes;
- failed recalculation keeps the previous `viewport_offset`;
- failed recalculation keeps the previous `last_layout`;
- `last_layout` updates only after successful placement;
- focus-only reveal does not alter `last_layout` geometry;
- invariant validation rejects duplicate order ids;
- invariant validation rejects dimension modes for missing ids.

## Guarantees

- Recoverable failures do not corrupt workspace state.
- `last_layout` represents only fully successful layouts.
- State mutations are validate-then-commit for commands and recalculation.
- Command mutations are validate-then-commit.
- Debug invariant checks can identify inconsistent state.
- Tests cover failed mutations and recovery state.
