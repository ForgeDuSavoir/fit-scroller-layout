# `layout/config.lua`

## Purpose

`config.lua` owns the normalized Fit Scroller configuration used by command
handling and layout computation.

Its main responsibility is to expose the allowed dimensions and the
deterministic cycle used by `toggle dimension` for the display currently being
laid out.

## Responsibilities

`config.lua` must:

- provide a default V1 configuration;
- support display-specific configuration overrides;
- resolve the effective configuration for a display;
- normalize allowed dimensions into stable keys;
- validate configured dimensions;
- reject duplicate dimensions;
- expose dimensions as a set for layout semantics;
- expose the sorted cycle used by `toggle dimension`;
- expose `scroll_direction`;
- expose `insert_mode`.

It must not:

- rank layout candidates;
- assign dimensions to auto windows;
- read Hyprland targets directly;
- store per-window dimension modes.

## Raw Configuration Shape

The user-facing configuration should support a default display configuration
and optional display-specific overrides:

```lua
RawConfig = {
    default = {
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 0.5, 1.0 },
            { 0.5, 0.5 },
        },
        scroll_direction = "right",
        insert_mode = "view",
    },
    displays = {
        ["eDP-1"] = {
            allowed_dimensions = {
                { 1.0, 1.0 },
                { 0.5, 1.0 },
            },
            scroll_direction = "down",
            insert_mode = "after_focused",
        },
        ["DP-1"] = {
            allowed_dimensions = {
                { 1.0, 1.0 },
                { 0.5, 1.0 },
                { 0.333, 1.0 },
                { 0.5, 0.5 },
            },
            scroll_direction = "right",
            insert_mode = "view",
        },
    },
}
```

Display keys should match the display identifier exposed by the Hyprland
adapter. The exact identifier field must be documented in
`hyprland_adapter.md` once verified at runtime.

If a display does not have an entry in `displays`, Fit Scroller uses
`default`.

## Normalized Configuration Shape

The normalized effective configuration for one display should expose:

```lua
Config = {
    display_id = "DP-1",
    allowed_dimensions = {
        { key = "1.0x1.0", w = 1.0, h = 1.0 },
        { key = "0.5x1.0", w = 0.5, h = 1.0 },
        { key = "0.5x0.5", w = 0.5, h = 0.5 },
    },
    dimensions_by_key = {
        ["1.0x1.0"] = { key = "1.0x1.0", w = 1.0, h = 1.0 },
    },
    toggle_cycle = {
        "1.0x1.0",
        "0.5x1.0",
        "0.5x0.5",
    },
    scroll_direction = "right",
    insert_mode = "view",
}
```

The exact Lua table representation may change, but callers must be able to:

- list all allowed dimensions;
- check whether a forced dimension key is allowed;
- get the next dimension mode for `toggle dimension`;
- read the configured `insert_mode`.

## Dimension Keys

A dimension key must uniquely identify a normalized dimension.

Recommended format:

```text
<width>x<height>
```

Examples:

- `1.0x1.0`;
- `0.5x1.0`;
- `0.5x0.5`.

The key format should be stable enough to store in `state.dimension_mode_by_id`.

## Validation Rules

Each allowed dimension must:

- have `w > 0` and `w <= 1`;
- have `h > 0` and `h <= 1`;
- be unique after normalization.

`insert_mode` must be one of:

- `last`;
- `first`;
- `view`;
- `after_focused`;
- `before_focused`.

Unknown insert modes are invalid configuration.

Invalid configuration must return a readable error. It must not silently clamp
or remove dimensions.

Validation is performed on effective display configurations.

An invalid display-specific override must fail for that display. It must not be
silently ignored in favor of `default`, because that would hide configuration
mistakes and make display behavior unpredictable.

The default configuration must also be valid, because it is used as fallback
for displays without explicit overrides.

## Toggle Cycle

`toggle dimension` cycles:

```text
auto -> largest forced dimension -> ... -> smallest forced dimension -> auto
```

The cycle is derived from allowed dimensions sorted by:

1. largest logical area first;
2. widest first when areas are equal;
3. tallest first when width is equal.

The order in which `allowed_dimensions` appears in configuration must not
affect layout selection or the toggle cycle.

## Insert Mode

`insert_mode` controls where new windows are inserted in the logical window
order during target synchronization.

Supported values:

- `last`: append to the end of the order;
- `first`: prepend to the beginning of the order;
- `view`: insert after the last currently visible window;
- `after_focused`: insert after the currently focused window;
- `before_focused`: insert before the currently focused window.

The default value is `view`.

`insert_mode` is consumed by `target_sync.lua`, not by `solver.lua`.

## Public API

Recommended functions:

```lua
config.get_for_display(display_id)
config.validate(raw_config)
config.resolve_display(raw_config, display_id)
config.dimension_key(dimension)
config.is_allowed_dimension_key(config, key)
config.next_dimension_mode(config, current_mode)
```

### `get_for_display(display_id)`

Returns the normalized effective configuration for a display.

Expected behavior:

- use `raw_config.displays[display_id]` when present;
- otherwise use `raw_config.default`;
- validate the effective configuration;
- return either a normalized config or a readable error.

### `resolve_display(raw_config, display_id)`

Builds the raw effective configuration for a display before normalization.

Display-specific values override default values field by field.

Example:

```lua
default = {
    allowed_dimensions = { { 1.0, 1.0 }, { 0.5, 1.0 } },
    scroll_direction = "right",
}

displays["eDP-1"] = {
    scroll_direction = "down",
}
```

Effective config for `eDP-1`:

```lua
{
    allowed_dimensions = { { 1.0, 1.0 }, { 0.5, 1.0 } },
    scroll_direction = "down",
}
```

### `next_dimension_mode(config, current_mode)`

Returns the next mode for `toggle dimension`.

Expected behavior:

- `auto` returns the first key in `toggle_cycle`;
- a forced dimension key returns the next key in `toggle_cycle`;
- the last forced dimension key returns `auto`;
- an unknown key should be treated as invalid and return an error.

## Guarantees

- Invalid dimensions are rejected.
- Duplicate dimensions are rejected.
- Display-specific overrides are resolved over defaults.
- Displays without overrides use the default configuration.
- Invalid display-specific effective configuration returns a readable error.
- Invalid `insert_mode` returns a readable error.
- The toggle cycle is independent from config order.
- `auto` cycles to the largest dimension.
- The smallest forced dimension cycles back to `auto`.

## Hardening

This section defines configuration validation and error reporting.

The goal is that invalid user configuration fails predictably before it can
mutate state or produce partial placements.

## Error Shape

Configuration errors should include:

- the display id being resolved;
- the field path;
- the invalid value when it is useful and safe to print;
- the expected constraint.

Recommended shape:

```lua
ConfigError = {
    code = "invalid_dimension",
    display_id = "DP-1",
    path = "displays.DP-1.allowed_dimensions[2].w",
    message = "fit-scroller: dimension width must be > 0 and <= 1",
}
```

The adapter may convert this to a string for Hyprland logs or `layout_msg`
responses, but core modules should keep structured errors where practical.

## Validation Order

Recommended validation order:

1. validate that `raw_config` is a table;
2. validate `default`;
3. resolve the effective display configuration;
4. validate required fields on the effective configuration;
5. normalize dimensions;
6. reject duplicates after normalization;
7. build derived maps and toggle cycle.

Invalid display-specific configuration must fail for that display. It must not
fall back to `default` silently.

## Required Field Errors

Missing required fields should produce explicit errors:

- missing `allowed_dimensions`;
- empty `allowed_dimensions`;
- missing `scroll_direction`;
- unknown `scroll_direction`;
- unknown `insert_mode`.

Example:

```text
fit-scroller: displays.DP-1.scroll_direction must be one of right, left, down, up
```

## Dimension Normalization

Dimension normalization must be deterministic.

If the implementation accepts both array and keyed forms during development,
they must normalize to the same internal structure:

```lua
{ 0.5, 1.0 }
{ w = 0.5, h = 1.0 }
```

Both represent:

```lua
{ key = "0.5x1.0", w = 0.5, h = 1.0 }
```

If accepting multiple shapes adds ambiguity, V1 should keep only one public
shape and reject the other with a clear error.

## Recovery Behavior

`config.lua` does not decide how to recover from invalid configuration.

It returns an error. The adapter decides whether to keep the last valid layout
visible for the affected workspace.

The important constraint is that an invalid configuration must not produce a
partially normalized config.

## Default Values

Tests must verify defaulting explicitly:

- `insert_mode` defaults to `view` only when the field is omitted from the
  effective configuration;
- display overrides inherit unspecified values from `default`;
- invalid display-specific values fail for that display instead of falling
  back silently.

The normalized configuration returned to callers must always contain concrete
`insert_mode` values.

## Test Cases

Configuration tests should cover:

- missing `default`;
- missing `allowed_dimensions`;
- empty `allowed_dimensions`;
- width equal to `0`;
- width greater than `1`;
- height equal to `0`;
- height greater than `1`;
- duplicate dimensions after normalization;
- invalid `scroll_direction`;
- invalid `insert_mode`;
- omitted `insert_mode` defaults to `view`;
- display override that changes only `scroll_direction`;
- display override that changes only `insert_mode`;
- invalid display override that must not fall back silently;
- toggle cycle independent from input order.

## Guarantees

- Every invalid config path returns a readable diagnostic.
- No invalid config produces a partial normalized config.
- Normalized config always exposes `insert_mode`.
- The documented defaults are tested.
- Display-specific errors identify the affected display.
- Duplicate dimensions are detected after normalization.
- Tests cover required fields, invalid values, duplicates and display
  overrides.
