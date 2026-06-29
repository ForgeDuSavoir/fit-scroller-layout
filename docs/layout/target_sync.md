# `layout/target_sync.lua`

## Purpose

`target_sync.lua` reconciles the live targets received from Hyprland with Fit
Scroller's persistent per-workspace target list.

In order mode, that list is the logical window order. In spatial mode, that
list is only a deterministic internal iteration list and must not define
placement semantics.

## Responsibilities

`target_sync.lua` must:

- receive normalized target descriptors from `hyprland_adapter.lua`;
- remove ids that are no longer present;
- preserve existing ids;
- insert new ids according to `config.insert_mode` in order mode;
- append new ids for stable iteration in spatial mode;
- clean removed window state through `state.lua`;
- return target descriptors in the internal target list order;
- report inserted or removed ids to the adapter.

It must not:

- inspect raw Hyprland targets;
- compute geometry;
- parse commands;
- decide dimension modes for new windows beyond leaving them as `auto`.

## Inputs

Expected input from the adapter:

```lua
TargetDescriptor = {
    id = "stable-window-id",
    target = <hyprland target>,
    active = true or false,
}
```

`target_sync.lua` should not depend on any other Hyprland fields.

It may also receive host-independent insertion context from the adapter:

```lua
InsertContext = {
    placement_priority = "order" | "spatial",
    insert_mode = "last" | "first" | "view" | "after_focused" | "before_focused",
    focused_id = "B",
    last_visible_id = "D",
}
```

`last_visible_id` is computed outside `target_sync.lua` from
`state.last_layout` and `state.viewport_offset`.

## Order Synchronization Algorithm

Recommended algorithm:

1. Build a `present_by_id` set from live targets.
2. Store the previous `workspace_state.focused_id`.
3. Remove missing ids from `workspace_state.order`.
4. Remove missing ids from `workspace_state.dimension_mode_by_id`.
5. Detect newly present ids in live target order.
6. Insert each new id according to `insert_mode`.
7. Update `workspace_state.focused_id` from the active target, if one exists
   after insertion.
8. Return ordered target descriptors.

This algorithm applies when `placement_priority = "order"` or when no
placement priority is provided.

## Spatial Synchronization Algorithm

Spatial mode does not have a user-visible logical order.

Recommended algorithm:

1. Build a `present_by_id` set from live targets.
2. Store the previous `workspace_state.focused_id`.
3. Remove missing ids from the internal list.
4. Remove missing ids from `workspace_state.dimension_mode_by_id`.
5. Detect newly present ids in live target order.
6. Append each new id to the internal list for deterministic iteration.
7. Update `workspace_state.focused_id` from the active target, if one exists.
8. Return target descriptors in internal list order.

Spatial synchronization must not:

- apply `insert_mode`;
- insert relative to the focused window;
- insert relative to the visible window list;
- interpret the internal list as layout order.

## New Window Insertion

New windows are inserted according to the effective display configuration's
`insert_mode`.

### `insert_mode = "last"`

Append each new window to the end of `workspace_state.order`.

This preserves append-only ordering when explicitly configured.

### `insert_mode = "first"`

Insert each new window at the beginning of `workspace_state.order`.

When several new windows appear in the same synchronization pass, preserve
their relative live order.

### `insert_mode = "after_focused"`

Insert each new window immediately after the focused id known before the
current synchronization pass.

This matters because Hyprland may already report a newly created window as
active when synchronization runs. In that case, the new window must still be
inserted after the previously focused window, not after itself.

If no focused id is known or the focused id is no longer present, fall back to
`last`.

### `insert_mode = "before_focused"`

Insert each new window immediately before the focused id known before the
current synchronization pass.

This uses the same focus snapshot rule as `after_focused`: the anchor is the
focused id known before the current synchronization pass, not a newly created
window that Hyprland may already report as active.

If no focused id is known or the focused id is no longer present, fall back to
`last`.

### `insert_mode = "view"`

Insert each new window immediately after the last currently visible id.

The last visible id is computed by the adapter from:

- `state.last_layout`;
- `state.viewport_offset`;
- the current viewport size and direction.

`target_sync.lua` should not compute visibility itself. If no last visible id
is provided, or if that id is no longer present, fall back to `last`.

This is the default V1 behavior.

When `placement_priority = "spatial"`, `insert_mode` is ignored. It remains
validated by `config.lua`, but it does not affect target synchronization.

Example:

```text
order: A B C
insert_mode: after_focused
focus: B
new: D
result: A B D C
```

If several new windows appear in the same synchronization pass, they should be
inserted in live target order while preserving their relative order.

## Removal

When a window disappears:

- remove it from `order`;
- remove its dimension mode;
- clear `focused_id` if it referenced that id.

The host window manager chooses the next focused window after removal. The next
sync pass should update `focused_id` from the active target.

## Output

The module should return an ordered list:

```lua
{
    { id = "A", target = targetA, active = false },
    { id = "B", target = targetB, active = true },
}
```

The solver consumes this ordered list.

In the current implementation, synchronization may also return metadata about the sync
pass:

```lua
{
    inserted_ids = { "C" },
    added_ids = { "C" },
    removed_ids = {},
    structural_changed = true,
}
```

`inserted_ids` is retained for order-mode compatibility. `added_ids` is the
mode-neutral name used by spatial mode.

The adapter uses the last inserted or added id as a reveal target during the
same recalculation. This matters because Hyprland may focus a newly opened
window after the custom layout has already read `target.window.active`, so
waiting for the active flag alone can leave the viewport on the previous focus.

## Invariants

After synchronization:

- `workspace_state.order` contains only present ids;
- every present id appears exactly once in `workspace_state.order`;
- ordered output follows `workspace_state.order`;
- removed ids have no dimension mode left in state.

## Guarantees

- Existing order is preserved across recalculations.
- New windows respect `insert_mode = "last"`.
- New windows respect `insert_mode = "first"`.
- New windows respect `insert_mode = "after_focused"`.
- New windows respect `insert_mode = "before_focused"`.
- New windows respect `insert_mode = "view"` when a visible anchor exists.
- New windows fall back to `last` when their mode-specific anchor is missing.
- Spatial synchronization ignores `insert_mode`.
- Spatial synchronization appends new ids only for deterministic iteration.
- Closed windows are removed from order and dimension state.
- The returned target list follows the mode's internal target list order.

## Hardening

This section defines synchronization against inconsistent or incomplete target
descriptors.

`target_sync.lua` is the first core module that receives live target identity.
It must therefore protect the rest of the layout from duplicate ids, missing
ids and stale state.

## Input Validation

Synchronization should reject:

- a descriptor without an id;
- duplicate descriptor ids;
- descriptor lists that are not arrays;
- active target ambiguity when more than one descriptor is marked active.

Recommended error:

```text
fit-scroller: duplicate target id during synchronization: <id>
```

These errors are recoverable at the adapter level. The previous valid layout
should remain visible when possible.

## State Cleanup

Cleanup should happen only after target input has been validated.

This avoids deleting state because of a malformed descriptor list.

Recommended flow:

1. validate descriptors;
2. compute `present_by_id`;
3. compute removed ids;
4. compute inserted ids;
5. apply state cleanup and insertion;
6. return ordered descriptors.

The function should return enough metadata for the adapter to distinguish:

- structural changes caused by insertion or removal;
- focus changes reported by Hyprland;
- pure no-op synchronization.

This metadata is required so focus-only recalculations can reveal the viewport
without invoking the solver.

## Active Target Rules

If exactly one descriptor is active, update `focused_id` to that id.

If no descriptor is active:

- keep `focused_id` only if it is still present;
- otherwise clear it.

If multiple descriptors are active, return an error. Fit Scroller should not
guess which active window Hyprland intended.

## Insert Mode Hardening

Insertion mode must be treated as an explicit input, not as hidden target sync
policy.

Rules to verify:

- `last` appends new ids at the end;
- `first` inserts new ids at the beginning;
- `view` inserts after the adapter-provided `last_visible_id`;
- `after_focused` inserts after the focus snapshot from before the sync pass;
- `before_focused` inserts before the focus snapshot from before the sync pass;
- missing anchors for `view`, `after_focused` and `before_focused` fall back
  to `last`;
- several new ids in one sync pass keep their relative live order for every
  mode.

`target_sync.lua` must not compute visibility itself. For `view`, it trusts the
adapter-provided `last_visible_id`.

## Test Cases

Target sync tests should cover:

- missing target id rejected;
- duplicate live target ids rejected;
- multiple active targets rejected;
- cleanup does not happen when input validation fails;
- removed ids clear dimension modes;
- removed focused id is cleared when no active target replaces it;
- no active target preserves existing focused id when still present;
- several new windows preserve relative order for every insert mode;
- `last` appends new windows;
- `first` prepends new windows;
- `after_focused` insertion uses previous focus, not newly active focus;
- `before_focused` insertion uses previous focus, not newly active focus;
- `view` insertion uses adapter-provided last visible id;
- missing focused or `view` anchor falls back to `last`.

## Guarantees

- Invalid target descriptor input returns errors before mutating state.
- Duplicate ids cannot enter `state.order`.
- Removed ids clean order and dimension modes.
- Focus state follows active target rules deterministically.
- Insert mode behavior matches all documented modes and fallbacks.
- Tests cover malformed descriptors, removals and multi-window insertion.
