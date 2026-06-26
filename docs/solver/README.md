# Solver Documentation

This folder contains the official detailed documentation for the Fit Scroller
solver behavior.

Use these documents when implementing or validating `layout/solver.lua`:

- [Solver detailed logic](detailed-logic.md): normative solver behavior,
  candidate model, ranking rules, auto dimensions and forced dimensions;
- [Base solver examples](base-examples.md): validated baseline and auto-only
  examples;
- [Forced solver examples](forced-examples.md): validated examples with at
  least one forced dimension;
- [Implementation plan](implementation-plan.md): step-by-step work plan for
  aligning the current code with the official solver behavior.

The module-level implementation contract remains documented in
[layout/solver.md](../layout/solver.md).
