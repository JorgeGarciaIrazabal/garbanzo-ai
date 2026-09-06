---
name: testing
description: Verify development batches, regressions and migrations with appropriate just gates.
---

Use focused just tests while iterating; add regression tests when they verify
a confirmed failure. Run just ai-test and just ai-lint for the controller,
just check before commits, and full just test on the integrated batch before
push/deploy. Record exact source revision and verification evidence.
Substantive behavior changes require independent Sol review (Astra for
architecture/security). Review findings must be resolved before integration.
Use real Docker PostgreSQL migration smoke tests alongside SQLite unit tests.
One heavy Flutter test/build job at a time. Runtime exploratory inspection uses
Dart MCP, Marionette and Playwright; see e2e-testing for established setup.
Do not describe passing health checks as verification of a reported bug.
