# SUPER+drag reordering in order mode

## Scope

In `placement_priority = "order"`, dropping a tiled Fit Scroller window on its original workspace selects a new logical insertion slot. The order solver still owns final positions and allowed sizes; a drop does not set arbitrary coordinates. Other windows retain their relative order. Spatial mode, floating-window drags, and cross-workspace drops keep their existing behavior. No drag preview or edge autoscroll is required.

## Hyprland verification (0.56.2)

- Live Lua queries on the target machine returned numeric `hl.get_cursor_pos().x/.y`, a numeric `window.stable_id` and boolean `window.floating`.
- In the matching Hyprland source, `DragController.cpp` temporarily floats a tiled target once the move threshold is crossed and retiles it on drag end. `Algorithm.cpp` moves the same target between algorithms. `LuaLayoutProvider.cpp` recalculates immediately after removing the target and again when adding it back. The Lua callback has no drop event or focal point; the native `movedTarget` path calls `newTarget` without forwarding that parameter. Sample the global cursor in the first recalculation that sees the target return, before any placement.
- Native drag start hit-tests the pointer, not the active window. Do not use focus as the dragged identity. The Lua drag dispatcher participates in the keybind manager's release handling; retain that dispatcher and do not emulate window motion.
- Verified in the live compositor with synthetic mouse/keyboard input on a two-tile workspace. A temporary test chord used a non-consuming press observer, the unwrapped native drag binding, then a non-consuming release observer. The press observer ran first; target `402653465` disappeared, then returned with the same ID. The first re-add callback read `(461, 572)`, matching the pointer sampled immediately before release. The release observer ran after re-add. A standalone Lua wrapper around the drag dispatcher did not initiate a drag in this probe; use the separate observers instead. The probe was removed after the test.

## Adapter and synchronization contract

1. Register three bindings for the same chord in order: a `non_consuming` press observer that arms one short-lived session, the existing `hl.dsp.window.drag()` binding unchanged, and a `release` + `non_consuming` observer that clears the session. Do not wrap or replace the native dispatcher. Normal recalculations must not arm a session. Record the origin workspace and an order-mode snapshot (IDs and modes). Do not persist Lua target handles across callbacks.
2. Identify the dragged target by the single stable ID disappearing from that workspace's tiled list during the armed gesture. If the origin or identity is ambiguous, leave the native behavior unchanged. Capture its prior order slot (neighbor IDs, with original index as fallback) and dimension mode before normal synchronization removes it. Let the remaining tiles lay out normally while dragging. If the origin's only target disappears, no drop hit-testing is needed; restoring its slot is sufficient.
3. On that same ID's first return to the same order-mode workspace, sample the cursor and select the slot before `target_sync.sync` applies its ordinary insertion policy. Supply a one-shot insertion override for this ID only. Restore its previous dimension mode if the dimension is still allowed. Require a stable ID; do not use an index fallback for drag identity.
4. Run the existing order solver once and use the usual viewport reveal path for the moved tile. Consume the override only on a successful layout/state commit. If there is no usable drop point or no surviving anchor, restore the previous slot rather than append. A no-threshold click, closed window, canceled or completed gesture, workspace change, mode change, or config reload must not leave an armed session that can affect a later insertion. The release observer runs after synchronous re-add with modifiers held; do not rely on it as the sole cleanup path. Replace any previous session on the next press and expire stale sessions, including when modifiers are released first.

The `layout/init.lua` entry point returns a `bind_order_drag(chord)` helper that installs these three bindings. To opt in, save the result of `dofile` and call the helper in place of the existing drag binding for that chord (not in addition to it).

## Drop-to-slot rule

Use the last rendered rectangles of surviving tiles in the destination workspace immediately before re-add. Use the adapter's existing conversion to global screen coordinates, including viewport offset and centering; clip hit-test regions to the workspace work area so hidden tiles cannot claim the pointer. Ignore the dragged target.

- Over a visible tile, insert immediately before it in logical order, except for the last visible tile. For that tile, its leading half inserts before and its trailing half (including the midpoint) inserts after. Split a standalone tile along the scroll axis in the configured direction; split a stacked tile top-to-bottom for horizontal scrolling or left-to-right for vertical scrolling.
- In a gap inside the work area, insert before the nearest visible rectangle by point-to-rectangle distance; break ties by logical order. Before the first or beyond the last visible strip edge along the scroll direction, insert immediately before the first or after the last visible tile. These are visible edges, not workspace ends.
- Outside the work area, or without any usable geometry, restore the original slot when the target retiles on its origin workspace.

## Acceptance tests

- Mock the remove/re-add lifecycle: reorder by stable ID, preserve a forced dimension, and leave ordinary insertions and spatial mode unchanged. Test a click without drag, cancellation, unrelated add/remove callbacks, and a cross-workspace drop. Include the only-window case.
- Unit-test slot selection for all four scroll directions, stacked tiles, gaps, centered layouts, and a scrolled layout with off-screen windows on both sides.
- Live smoke test: with three tiled windows, start a drag over a non-focused window, drop it on either half of a non-last tile and then on both halves of the last visible tile. Repeat on a scrolled viewport. Temporarily trace the binding invocation, target IDs before/remove/re-add, and the cursor in the re-add callback. Confirm the button releases normally, a forced size survives, and new windows still follow `insert_mode`.
