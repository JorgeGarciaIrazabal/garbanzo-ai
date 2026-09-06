---
name: releases
description: Prepare and execute explicitly requested releases and report-specific delivery verification.
---

Read deploy/AGENTS.md and deploy/README.md. Deploy only when requested; preserve
signing keys, versioning, annotated tags, explicit just deploy and desktop assets.
Run the complete integrated tests before deployment. Use one writer lock with
integration; never package uncommitted source accidentally. Release evidence
must distinguish the built source revision from the later version-bump commit.
Changelog generation uses Codex from sanitized commit/task information with a
deterministic fallback. Associate Report-ID trailers; never match report titles
or send raw report diagnostics to the changelog model.
A healthy /health alone does not close reports. Verify linked behavior on the
actual deployed fix revision, then synchronize exact report IDs with CAS. Failed
deployment/verification leaves reports open/in_progress. Do not notify reporters.
