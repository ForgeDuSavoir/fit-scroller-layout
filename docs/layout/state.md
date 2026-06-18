# `layout/state.lua`

## Phase

Phase 2: State and Commands.

## Purpose

`state.lua` owns mutable Fit Scroller state that must survive between Hyprland
`recalculate(ctx)` calls.

Phase 2 introduces enough state to preserve logical window order and per-window
dimension modes.

## Responsibilities

In Phase 2, `state.lua` must:

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

Phase 2 uses:

- `order`;
- `dimension_mode_by_id`;
- `focused_id`.

`viewport_offset` and `last_layout` are initialized for later phases but do not
need full behavior yet.

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

State should be keyed by a stable workspace identifier when the Hyprland API
exposes one.

Until the runtime integration confirms the available fields, the adapter may
provide a provisional workspace key. The chosen key must be documented here
once verified.

Avoid using a single global workspace state unless Hyprland exposes no usable
workspace identity during early implementation.

## Invariants

After synchronization:

- every id in `order` corresponds to a present tiled target;
- no id appears more than once in `order`;
- `dimension_mode_by_id` has no entries for missing ids;
- `focused_id` is either present or `nil`.

## Phase 2 Acceptance Criteria

- State is created lazily for a workspace.
- Window order survives repeated recalculations.
- Closing a window removes its dimension mode.
- `move previous` and `move next` can mutate order through state helpers.
- `toggle dimension` can mutate only the focused window's dimension mode.

## Phase 4 Additions

Phase 4 starts using `viewport_offset` as active state.

`viewport_offset` stores the current scroll offset for the workspace on the
configured scroll axis. The value is logical, not pixel-based.

State does not decide how the offset changes. It only stores the value
computed by `viewport.lua`.

## Viewport Offset Rules

The offset must be updated only after a valid layout has been computed.

Expected flow:

```text
recalculate(ctx)
    -> solver computes placements and workspace extent
    -> viewport.reveal computes next offset
    -> state.viewport_offset is updated
    -> adapter places windows using that offset
```

If layout computation fails, `state.viewport_offset` should keep its previous
value. Full fallback to `last_layout` is completed in Phase 5.

## Focus State

Hyprland is the source of truth for which window is focused.

`state.focused_id` should be updated from synchronized target descriptors
rather than directly from `focus previous` or `focus next` command execution.

This matters because a focus command may fail at the Hyprland integration
boundary. In that case, state must not pretend a different window is focused.

## Public API Additions

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

Phase 4 may only populate this value. Phase 5 defines the complete recovery
policy for invalid configuration or placement failures.

## Phase 4 Acceptance Criteria

- `viewport_offset` survives repeated recalculations.
- Focus changes update `focused_id` only after Hyprland reports the active
  target.
- Successful reveal updates `viewport_offset`.
- Failed layout or focus integration does not corrupt focus state.
- Offset storage remains per workspace.

## Phase 5 Additions

Phase 5 hardens state mutation and last-valid-layout recovery.

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

Example for `toggle dimension`:

1. resolve the next dimension mode;
2. validate that the key exists in config;
3. optionally ask the solver whether it can fit;
4. only then update `dimension_mode_by_id`.

## State Invariant Checks

Phase 5 should add a debug-only invariant check:

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

## Phase 5 Test Cases

State tests should cover:

- failed command validation does not mutate state;
- failed forced-dimension update preserves the previous mode;
- failed recalculation keeps the previous `viewport_offset`;
- `last_layout` updates only after successful placement;
- invariant validation rejects duplicate order ids;
- invariant validation rejects dimension modes for missing ids.

## Phase 5 Acceptance Criteria

- Recoverable failures do not corrupt workspace state.
- `last_layout` represents only fully successful layouts.
- Command mutations are validate-then-commit.
- Debug invariant checks can identify inconsistent state.
- Tests cover failed mutations and recovery state.
