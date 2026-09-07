---
name: testing
description: Verify development batches, regressions and migrations with appropriate just gates.
---

Match verification cost to the change. Trivial documentation and similarly
low-risk edits need no model review. Routine changes get relevant focused just
tests or lint; add regression tests when they verify a confirmed failure.
Substantive changes receive one consolidated independent Sol review after the
implementation is coherent. Resolve its findings, then request targeted follow-up
only for material fixes.

Run `just check` once at the commit boundary and repeat it only when a later edit
changes an input it checks. Run full `just test` on the integrated batch before a
push or deployment; use `just ai-test` and `just ai-lint` when controller changes
require them. Record the exact source revision and verification evidence.
Use real Docker PostgreSQL migration smoke tests alongside SQLite unit tests.
One heavy Flutter test/build job at a time. Runtime exploratory inspection uses
Dart MCP, Marionette and Playwright; see e2e-testing for established setup.
Do not describe passing health checks as verification of a reported bug.
