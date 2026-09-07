---
name: coordination
description: Coordinate independent tasks in isolated copies and integrate reviewed patches on main.
---

Use just ai-run and just ai-batch for isolated source snapshots and manifests.
Give workers bounded briefs, task IDs, requirement revisions, owned files,
dependencies, relevant decisions, acceptance and exact just verification commands.
For small controller/dev-tooling fixes, integrate directly after checks and
independent review with `just ai-run direct`; do not start an isolated worker
handoff unless isolation genuinely adds value. Changes to the direct command,
its dependencies, repository agent instructions, skills, or check definitions
remain on the isolated path because the direct path cannot review its own trust
boundary. Declare every modified `scripts/ai_dev/` path in a direct run so the
review sees all controller inputs. Accept direct review only when it approves
with no findings, and obtain it before modified controller tests execute. Worker
verification preflights backend and
Flutter dependency markers before running any recipe and rejects shell syntax
in focused-test arguments. Install the required dependencies in the worker
snapshot, or use the direct path so `ai-lint` and `check` run in the real
repository.
Workers return artifacts and concise findings; only the coordinator integrates.
Reject changed requirements, changed base blobs and unexpected output files.
Refresh overlapping work against integration; never combine patches blindly.
Share download caches only. Isolate build outputs, environments, ports and test
DBs. Hold the heavy Flutter lock for builds/tests and the writer lock for
integration or deployment. Up to three workers; foreground and capacity reduce it.
Preserve interrupted work. Native session IDs and preview revisions are durable
local state; just ai-status/ai-stop/ai-resume expose recovery.
