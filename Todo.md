
- [x] Fix [[Known issues]]
- [x] Theorize `spacial` mode
- [x] Implement `spacial` mode
- [x] Fix Known issue
- [x] Test Spatial mode
- [x] Document and implement "Forced dimensions options"
- [x] Document and implement "Center windows" option
- [x] Implement separate config file


# Order-mode SUPER+drag implementation tasks

Behavior and verified Hyprland callback sequence: [technical specification](docs/layout/order_drag_drop.md). Spatial mode is out of scope.

## 1. Track the native drag gesture

- [x] Add an adapter-owned drag session with an origin workspace key, stable target IDs, original order and dimension modes. Snapshot before the native drag runs; do not infer the dragged ID from focus or retain Lua target handles.
- [x] Expose press/release callbacks to Hyprland config. Register a non-consuming press observer, the unchanged native drag binding, and a non-consuming release observer for the same chord in that order. Keep press handling inert outside order-mode Fit Scroller.
- [x] In `layout/hyprland_adapter.lua`, identify a single disappearing stable ID from the armed origin workspace before `layout/target_sync.lua` removes its state. Record its original slot and mode, then allow normal layout of the remaining tiles. Handle an empty target list without guessing the workspace.
- [x] Recognize the same ID retiling in the origin workspace before normal insertion. Read `hl.get_cursor_pos()` before placement. Invalidate ambiguous or cross-workspace sessions; clear no-drag, canceled, closed-window, mode-change and reload cases. Ensure stale sessions cannot affect later insertions when modifiers are released first or a release observer is missed.

## 2. Select a logical drop slot

- [x] Retain the last successfully rendered tile rectangles and their workspace/work-area context. Reuse the adapter's viewport, centering and screen-coordinate conversion rather than recomputing a second layout. Clip to the work area and exclude the dragged tile and tiles no longer present.
- [x] Implement a pure drop-to-slot helper: insert before the hovered tile, with a before/after split on the last visible tile; handle gaps, visible strip edges and ties deterministically.
- [x] When the pointer or geometry cannot provide an anchor, recover the original slot using surviving neighbors, then the original index. Cover the one-window case.

## 3. Apply the drop

- [x] Add a one-shot, ID-scoped insertion override to `layout/target_sync.lua`. Pass it only for a validated order-mode return; preserve other windows' relative order, normal `insert_mode` behavior and the spatial path.
- [x] Restore the dragged window's forced dimension if still allowed. Run the existing order solver through the normal adapter transaction and reveal the moved tile without changing Hyprland focus. Consume the session only after successful state/placement commit; handle failures without applying the override to another window.

## 4. Verify and document

- [x] Unit-test slot selection in all four scroll directions, including stacked tiles, gaps and distance ties, centered geometry, and visible edges with off-screen neighbors.
- [x] Add mocked adapter tests for the remove/re-add sequence, a non-focused dragged tile, forced-size preservation, one-window fallback, normal insertion, unrelated target changes, cross-workspace drops, spatial and floating behavior, canceled or expired gestures, and failed placement.
- [x] Run `lua tests/run.lua` and `git diff --check`.
- [x] Document the three-binding setup and drop behavior in `docs/USER_GUIDE_FOR_HYPRLAND_CUSTOM_LAYOUT.md`.
- [x] Confirm order-mode SUPER+drag works on the live Hyprland setup, including dropping into the last position.
- [x] Confirm remaining live edge cases if not already covered: stacked and scrolled layouts, modifier-first release, click without motion, forced dimensions, and ordinary new-window placement.
