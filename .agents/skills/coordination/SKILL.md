---
name: coordination
description: Coordinate independent tasks in isolated copies and integrate reviewed patches on main.
---

Keep work in the current session by default. Use just ai-run and just ai-batch
only when a substantial task can proceed independently and an isolated source
snapshot provides useful protection or parallelism. Give workers compact,
self-contained briefs with the task ID, requirement revision, owned files,
dependencies, relevant decisions, acceptance criteria and exact just commands.
Do not send full conversation history.

The `just ai-run direct` command remains available when its recorded artifact is
useful, but trusted local work does not require it. Trivial documentation and
similarly low-risk edits need no model review. Routine changes need focused tests
or lint. Substantive changes get one consolidated Sol review after implementation,
followed only by targeted review of material fixes. Run `just check` at the commit
boundary and repeat it only when a later edit changes an input it checks.

Worker verification preflights backend and Flutter dependency markers before
running any recipe and rejects shell syntax in focused-test arguments. Install
required dependencies in the snapshot or verify in the main copy when isolation
is unnecessary.
Workers return artifacts and concise findings; only the coordinator integrates.
Reject changed requirements, changed base blobs and unexpected output files.
Refresh overlapping work against integration; never combine patches blindly.
Share download caches only. Isolate build outputs, environments, ports and test
DBs. Hold the heavy Flutter lock for builds/tests and the writer lock for
integration or deployment. Use multiple workers only for substantial independent
tasks; the limit is three, reduced by foreground work and capacity.
Preserve interrupted work. Native session IDs and preview revisions are durable
local state; just ai-status/ai-stop/ai-resume expose recovery.
