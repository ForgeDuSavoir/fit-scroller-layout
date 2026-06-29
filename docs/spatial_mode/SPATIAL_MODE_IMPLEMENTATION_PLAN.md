# Spatial Mode Implementation Plan

This document tracks the implementation work required to add
`placement_priority = "spatial"` to Fit Scroller.

Normative references:

- [Spatial mode product specification](SPATIAL_MODE_SPECIFICATION.md)
- [Spatial mode technical specification](SPATIAL_MODE_TECHNICAL_SPECIFICATION.md)
- [Fit Scroller specification](SPECIFICATION.md)
- [Architecture](ARCHITECTURE.md)
- [Configuration module contract](layout/config.md)
- [Command module contract](layout/commands.md)
- [State module contract](layout/state.md)
- [Target synchronization contract](layout/target_sync.md)
- [Viewport module contract](layout/viewport.md)
- [Hyprland adapter contract](layout/hyprland_adapter.md)

## Current State

Fit Scroller currently implements an order-based solver.

The current behavior:

- uses logical window order as a layout constraint;
- supports `move previous` and `move next`;
- supports `focus previous` and `focus next`;
- uses `insert_mode` to decide where newly discovered windows enter the
  logical order;
- keeps solver input independent from focus and viewport state;
- stores `last_layout` for viewport reveal and recovery.

Spatial mode is documented but not implemented.

The first spatial implementation must:

- add `placement_priority = "spatial"`;
- keep `placement_priority = "order"` behavior unchanged;
- ignore `insert_mode` in spatial mode while still validating it;
- avoid exposing `previous` and `next` semantics in spatial mode;
- use `viewport_offset` only for spatial solving and viewport reveal;
- preserve recoverable failure behavior.

## Implementation Principles

Each step should leave the project in a known state.

Order mode must remain the default until spatial mode is complete enough to be
usable.

Prefer adding spatial-specific modules over adding conditional branches deep
inside the existing order solver.

Tests should be added before or alongside each behavior change. When a step
adds a new public contract, add tests for both accepted behavior and rejected
mode-mismatch behavior.

## Implementation Sequence

### Step 1: Add `placement_priority` To Configuration

Status: completed.

Implementation tasks:

- Add `placement_priority` to the default raw configuration with value
  `"order"`.
- Add validation for:
  - `"order"`;
  - `"spatial"`;
  - invalid values.
- Expose `placement_priority` in normalized config output.
- Support display-specific overrides.
- Keep `insert_mode` validation unchanged.
- Document in `layout/config.md` that `insert_mode` is ignored by spatial mode
  but still validated.

Tests:

- default config returns `placement_priority = "order"`;
- explicit `"order"` is accepted;
- explicit `"spatial"` is accepted;
- invalid values return a readable error;
- display override can change `placement_priority`;
- spatial configs still reject invalid `insert_mode`.

Validation:

- Existing order-mode tests continue to pass without config changes.

### Step 2: Make Command Parsing Mode-Aware

Status: completed.

Implementation tasks:

- Pass normalized config or `placement_priority` into command execution.
- Keep existing order commands valid only in order mode:
  - `move previous`;
  - `move next`;
  - `focus previous`;
  - `focus next`.
- Add spatial commands valid only in spatial mode:
  - `move left`;
  - `move right`;
  - `move up`;
  - `move down`;
  - `focus left`;
  - `focus right`;
  - `focus up`;
  - `focus down`.
- Keep shared commands valid in both modes:
  - `toggle dimension`;
  - `reveal focus`;
  - `follow`.
- Return clear mode-mismatch errors.
- For spatial move commands, return a `spatial_event` mutation intent instead
  of mutating order.
- For spatial focus commands, return a `focus_direction` or resolved
  `focus_target_id` intent without requesting solver execution.

Tests:

- order commands work in order mode;
- order commands are rejected in spatial mode;
- spatial commands work in spatial mode;
- spatial commands are rejected in order mode;
- shared commands work in both modes;
- malformed spatial commands return readable errors;
- spatial move reports `needs_layout_update = true`;
- spatial focus reports `needs_viewport_update = true` and does not request
  layout solving.

Validation:

- Existing command tests remain valid when run with `placement_priority =
  "order"`.

### Step 3: Add Spatial Target Synchronization Metadata

Status: completed.

Implementation tasks:

- Extend `target_sync.lua` with a spatial synchronization path.
- Preserve the current order synchronization path for order mode.
- In spatial mode:
  - keep existing ids in a stable internal list;
  - append new ids only for deterministic iteration;
  - remove missing ids;
  - initialize new windows as auto;
  - report `added_ids` and `removed_ids`;
  - do not apply `insert_mode`;
  - do not derive placement from the internal list.
- Preserve dimension mode cleanup for removed windows.

Tests:

- spatial sync appends new ids independently from `insert_mode`;
- changing `insert_mode` does not change spatial sync output;
- spatial sync reports one added id;
- spatial sync reports one removed id;
- spatial sync reports multiple changes for global rebuild handling;
- spatial sync removes dimension modes for missing ids;
- spatial sync preserves existing ids for deterministic iteration.

Validation:

- Existing `insert_mode` behavior remains unchanged in order mode.

### Step 4: Add Spatial Geometry Helpers

Status: completed.

Implementation tasks:

- Add `layout/spatial_geometry.lua`.
- Implement host-independent helpers:
  - rectangle validation;
  - overlap detection;
  - adjacency detection;
  - center and distance calculation;
  - scroll-axis interval extraction;
  - cross-axis interval extraction;
  - visibility from `viewport_offset`;
  - candidate movement and resize metrics.
- Support all scroll directions through direction-aware helpers or canonical
  normalization.

Tests:

- visibility for horizontal directions;
- visibility for vertical directions;
- full visibility vs partial visibility;
- overlap with epsilon tolerance;
- adjacency on each side;
- movement distance;
- resize distance;
- cross-axis bounds validation.

Validation:

- The helper module has no dependency on Hyprland objects.

### Step 5: Add Spatial Focus Resolution

Status: completed.

Implementation tasks:

- Add `layout/spatial_focus.lua`.
- Resolve directional focus from `state.last_layout`.
- Rank candidates by:
  - requested half-plane;
  - perpendicular overlap;
  - directional distance;
  - center distance;
  - stable id.
- Return target id for the adapter to focus.
- Do not mutate state directly.
- Do not invoke the spatial solver.

Tests:

- focus left selects the best left candidate;
- focus right selects the best right candidate;
- focus up selects the best upper candidate;
- focus down selects the best lower candidate;
- perpendicular overlap beats pure center distance;
- no candidate is a no-op;
- missing `last_layout` returns a readable integration error or no-op result;
- focus resolution is deterministic for ties.

Validation:

- `focus left/right/up/down` does not change layout geometry.

### Step 6: Add Spatial Solver Skeleton And Input Validation

Status: completed.

Implementation tasks:

- Add `layout/spatial_solver.lua`.
- Implement `spatial_solver.solve(input)`.
- Validate:
  - `config.placement_priority == "spatial"`;
  - supported scroll direction;
  - non-empty allowed dimensions;
  - unique target ids;
  - valid dimension modes;
  - forced dimension keys;
  - finite non-negative `viewport_offset`;
  - required `last_layout` for local events;
  - complete previous placements when `last_layout` is present.
- Return complete error objects or readable errors.
- Implement a simple deterministic global rebuild for `initial` only.

Tests:

- invalid placement priority is rejected;
- duplicate target ids are rejected;
- invalid forced key is rejected;
- local event without `last_layout` is rejected or routed to global fallback;
- `initial` returns a complete valid layout;
- solver output includes placements and dimensions for every target;
- solver output has no unknown ids.

Validation:

- The module can be tested without Hyprland.

### Step 7: Wire Adapter Strategy Selection

Status: completed.

Implementation tasks:

- Update `hyprland_adapter.lua` to branch early on `placement_priority`.
- Keep order flow unchanged.
- Add spatial structural flow that builds `SpatialSolverInput`.
- Pass `viewport_offset` to spatial solver only.
- Do not pass `viewport_offset` to order solver.
- Preserve viewport-only flow for `follow` and `reveal focus`.
- Commit `last_layout` only after complete successful placement.

Tests:

- adapter calls order solver for `placement_priority = "order"`;
- adapter calls spatial solver for `placement_priority = "spatial"`;
- order solver input does not include `viewport_offset`;
- spatial solver input includes `viewport_offset`;
- spatial solver input includes an event;
- failed spatial solve preserves previous `last_layout`;
- failed spatial solve preserves previous `viewport_offset`.

Validation:

- Existing order-mode integration tests continue to pass.

### Step 8: Implement Spatial Window Addition

Status: completed.

Implementation tasks:

- Detect `window_added` events from spatial target sync.
- Generate local split candidates from existing auto windows.
- Prefer visible split targets using `viewport_offset`.
- Ignore `insert_mode`.
- Generate append candidates on the configured scroll axis when no split is
  valid.
- Fall back to global spatial rebuild when local candidates fail.
- Reveal the newly added window after successful structural solve.

Tests:

- adding a window splits a visible splittable auto window;
- adding a window prefers visible split over non-visible split;
- adding a window chooses the largest valid visible split target;
- adding a window appends when no split exists;
- changing `insert_mode` does not change addition result;
- forced windows are not split;
- new window starts in auto mode;
- new window is present in `last_layout` after success.

Validation:

- Window addition does not mutate order semantics in spatial mode.

### Step 9: Implement Spatial Window Removal

Status: completed.

Implementation tasks:

- Detect `window_removed` events and capture the removed window's previous
  rectangle when available.
- Generate keep-unchanged candidates.
- Generate adjacent auto expansion candidates.
- Generate trailing scroll reduction candidates.
- Generate local compaction candidates around the freed space.
- Avoid persistent visible holes when a valid hole-free candidate exists.
- Fall back to global spatial rebuild when needed.

Tests:

- removing a window can preserve all remaining rects;
- removing a trailing scroll-axis window reduces workspace extent;
- removing a window expands an adjacent auto window when valid;
- forced adjacent windows are not resized;
- visible holes rank below equivalent hole-free candidates;
- missing previous rect routes to global rebuild;
- removed window dimension mode is cleaned up.

Validation:

- Removal does not move unrelated visible windows when a valid local solution
  exists.

### Step 10: Implement Spatial Forced Dimension Changes

Status: completed.

Implementation tasks:

- Build `dimension_forced` events from `toggle dimension`.
- Validate forced dimension before committing state mutation.
- Generate candidates:
  - resize around top-left;
  - resize around center;
  - push overlapping auto neighbors;
  - extend scroll for pushed windows.
- Preserve all forced windows.
- Fall back to global spatial rebuild if local candidates fail.
- Reject impossible forced dimensions without committing the mode change.

Tests:

- forced dimension is preserved exactly;
- invalid forced key is rejected without mutation;
- cross-axis impossible forced dimension is rejected;
- local resize succeeds when no overlap is introduced;
- overlapping auto neighbor can be moved;
- forced neighbor is not moved or resized;
- failed forced change preserves previous dimension mode.

Validation:

- Forced dimension behavior remains hard-constraint based.

### Step 11: Implement Return To Auto Compaction

Status: completed.

Implementation tasks:

- Build `dimension_auto` events from `toggle dimension`.
- Remove the forced constraint only in a draft state.
- Generate local candidates for every allowed dimension of the target.
- Prefer candidates that reduce visible holes or workspace extent.
- Allow target shrink or growth.
- Allow adjacent auto windows to resize when density improves.
- Do not give special preference to the previous forced dimension.
- Fall back to global spatial rebuild if local compaction fails.

Tests:

- returning to auto can shrink a previously forced-large window;
- returning to auto can grow a previously forced-small window;
- returning to auto reduces scroll when possible;
- returning to auto fills adjacent visible space when possible;
- failed auto return preserves previous forced mode;
- previous forced dimension is not preferred when a better auto layout exists.

Validation:

- The command produces an optimization attempt instead of preserving geometry
  unchanged.

### Step 12: Implement Spatial Move

Status: completed.

Implementation tasks:

- Build `move` events from spatial move commands.
- Resolve directional neighbors from current geometry.
- Generate swap candidates.
- Generate split-neighbor insertion candidates.
- Generate free-space candidates if helper support exists.
- Generate scroll-extension candidates when the direction matches the scroll
  axis.
- Require visible progress in the requested direction.
- Return no-op when no candidate makes progress.

Tests:

- move left moves the focused window left when possible;
- move right moves the focused window right when possible;
- move up moves the focused window up when possible;
- move down moves the focused window down when possible;
- compatible neighbor swap works;
- auto neighbor split works;
- forced dimensions are preserved;
- no-progress move is a no-op;
- moved window remains revealable after success.

Validation:

- Spatial move never mutates order as a user-visible operation.

### Step 13: Complete Global Spatial Rebuild

Status: completed.

Implementation tasks:

- Generate global rebuild candidates for:
  - initial layout;
  - multiple additions or removals;
  - config changes;
  - local candidate failure.
- Reuse order solver output as a candidate source only if re-ranked through
  spatial cost.
- Rank rebuild candidates by:
  - forced dimension validity;
  - visible window preservation;
  - movement distance;
  - resize count;
  - scroll overflow;
  - fill quality;
  - stable tie-breakers.
- Ensure global rebuild does not expose `previous` or `next` semantics.

Tests:

- initial rebuild is deterministic;
- global rebuild preserves forced dimensions;
- global rebuild prefers less visible movement;
- global rebuild handles multiple added windows;
- global rebuild handles multiple removed windows;
- global rebuild handles missing `last_layout`;
- failed global rebuild preserves previous valid state.

Validation:

- Global rebuild is a fallback path for spatial mode, not a call back into
  order behavior at the adapter boundary.

### Step 14: Harden Transactions And Recovery

Status: completed.

Implementation tasks:

- Ensure every spatial structural operation uses draft state.
- Commit dimension modes only after spatial solve and placement validation.
- Commit target sync state only after placement validation when possible.
- Preserve previous `last_layout` on solver failure.
- Preserve previous `viewport_offset` on solver or viewport failure.
- Avoid partial target placement when output is incomplete.
- Add debug invariant checks for spatial state.

Tests:

- failed spatial move preserves state;
- failed forced dimension preserves state;
- failed return-to-auto preserves state;
- failed target sync validation preserves state;
- failed rectangle conversion preserves `last_layout`;
- incomplete solver output is rejected;
- successful operation commits state exactly once.

Validation:

- Recovery behavior matches existing order-mode hardening expectations.

### Step 15: Update Documentation And User Guide

Status: completed.

Implementation tasks:

- Update `layout/config.md` for `placement_priority`.
- Update `layout/commands.md` for mode-aware commands.
- Update `layout/target_sync.md` for spatial synchronization.
- Update `layout/hyprland_adapter.md` for strategy selection.
- Add module docs for:
  - `layout/spatial_solver.lua`;
  - `layout/spatial_geometry.lua`;
  - `layout/spatial_focus.lua`.
- Update user guide with example bindings for spatial mode.
- Document that `insert_mode` is ignored in spatial mode.

Tests:

- documentation examples use valid command names;
- no docs imply that `previous` or `next` are meaningful in spatial mode;
- no docs imply that `insert_mode` affects spatial addition.

Validation:

- `rg "insert_mode" docs` should show the spatial-mode exception wherever
  relevant.

### Step 16: Final Regression Pass

Status: completed.

Implementation tasks:

- Run the full test suite.
- Run focused order-mode tests.
- Run focused spatial-mode tests.
- Review command errors for clarity.
- Review config errors for clarity.
- Review docs for consistency.

Validation:

- Order mode remains default.
- Order mode behavior is unchanged.
- Spatial mode can be enabled explicitly.
- Spatial mode ignores `insert_mode`.
- Spatial mode has no user-visible previous/next behavior.
- Spatial structural failures preserve the previous valid layout.
