# `layout/target_sync.lua`

## Phase

Phase 2: State and Commands.

## Purpose

`target_sync.lua` reconciles the live targets received from Hyprland with Fit
Scroller's logical window order.

It is responsible for preserving existing order, removing closed windows and
inserting new windows after the currently focused window.

## Responsibilities

In Phase 2, `target_sync.lua` must:

- receive normalized target descriptors from `hyprland_adapter.lua`;
- remove ids that are no longer present;
- preserve the relative order of existing ids;
- insert new ids immediately after the focused id;
- append new ids when no focused id is known;
- clean removed window state through `state.lua`;
- return targets in logical order.

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

## Synchronization Algorithm

Recommended algorithm:

1. Build a `present_by_id` set from live targets.
2. Store the previous `workspace_state.focused_id` as the insertion anchor.
3. Remove missing ids from `workspace_state.order`.
4. Remove missing ids from `workspace_state.dimension_mode_by_id`.
5. Iterate live targets in Hyprland order.
6. For each target not already in `order`, insert it after the insertion
   anchor when that anchor is still present.
7. If the insertion anchor is missing or unknown, append the new target.
8. Update `workspace_state.focused_id` from the active target, if one exists
   after insertion.
9. Return ordered target descriptors.

This follows the insertion behavior in the specification and the pattern shown
by the local `manual.lua` example.

## New Window Insertion

New windows are inserted immediately after the focused window.

The focused window used for insertion is the focus known before the current
synchronization pass. This matters because Hyprland may already report a newly
created window as active when `recalculate(ctx)` runs. In that case, the new
window must still be inserted after the previously focused window, not after
itself.

Example:

```text
order: A B C
focus: B
new:   D
result: A B D C
```

If several new windows appear in the same synchronization pass, they should be
inserted in the live target order after the focused window, preserving their
relative order.

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

The solver later consumes this ordered list. In Phase 2, the adapter may still
use it only for deterministic temporary placement.

## Invariants

After synchronization:

- `workspace_state.order` contains only present ids;
- every present id appears exactly once in `workspace_state.order`;
- ordered output follows `workspace_state.order`;
- removed ids have no dimension mode left in state.

## Phase 2 Acceptance Criteria

- Existing order is preserved across recalculations.
- New windows are inserted after the focused id.
- New windows are appended when no focused id exists.
- Closed windows are removed from order and dimension state.
- The returned target list is ordered by Fit Scroller's logical order.

## Phase 5 Additions

Phase 5 hardens synchronization against inconsistent or incomplete target
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

## Active Target Rules

If exactly one descriptor is active, update `focused_id` to that id.

If no descriptor is active:

- keep `focused_id` only if it is still present;
- otherwise clear it.

If multiple descriptors are active, return an error. Fit Scroller should not
guess which active window Hyprland intended.

## Phase 5 Test Cases

Target sync tests should cover:

- missing target id rejected;
- duplicate live target ids rejected;
- multiple active targets rejected;
- cleanup does not happen when input validation fails;
- removed ids clear dimension modes;
- removed focused id is cleared when no active target replaces it;
- no active target preserves existing focused id when still present;
- several new windows inserted after the previous focused id;
- insertion anchor uses previous focus, not newly active focus.

## Phase 5 Acceptance Criteria

- Invalid target descriptor input returns errors before mutating state.
- Duplicate ids cannot enter `state.order`.
- Removed ids clean order and dimension modes.
- Focus state follows active target rules deterministically.
- Tests cover malformed descriptors, removals and multi-window insertion.
