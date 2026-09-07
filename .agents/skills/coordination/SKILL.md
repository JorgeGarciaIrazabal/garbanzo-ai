---
name: coordination
description: Coordinate independent tasks in isolated copies and integrate reviewed patches on main.
---

Use just ai-run and just ai-batch for isolated source snapshots and manifests.
Give workers bounded briefs, task IDs, requirement revisions, owned files,
dependencies, relevant decisions, acceptance and exact just verification commands.
For small controller/dev-tooling fixes, integrate directly after checks and
independent review; do not start an isolated worker handoff unless isolation
genuinely adds value. Worker snapshots do not include backend development
dependencies, so run `ai-lint` and `check` in the real repository or make those
dependencies available before allowing a recipe in worker verification.
Workers return artifacts and concise findings; only the coordinator integrates.
Reject changed requirements, changed base blobs and unexpected output files.
Refresh overlapping work against integration; never combine patches blindly.
Share download caches only. Isolate build outputs, environments, ports and test
DBs. Hold the heavy Flutter lock for builds/tests and the writer lock for
integration or deployment. Up to three workers; foreground and capacity reduce it.
Preserve interrupted work. Native session IDs and preview revisions are durable
local state; just ai-status/ai-stop/ai-resume expose recovery.
