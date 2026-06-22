# Tests

Run all Fit Scroller tests from the project root:

```bash
lua tests/run.lua
```

## Structure

- `run.lua`: loads every test suite and reports the total count.
- `support.lua`: shared assertions and layout-module loading helpers.
- `core_test.lua`: host-independent tests for configuration, state
  synchronization, commands, solver and viewport behavior.
- `hyprland_adapter_test.lua`: mocked Hyprland adapter tests using fake
  `ctx`, `target`, `target.window` and `target:place` objects.

Test filenames describe the subsystem under test. They should not use
implementation-history names.
