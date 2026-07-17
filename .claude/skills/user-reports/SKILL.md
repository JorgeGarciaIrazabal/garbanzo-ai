---
name: user-reports
description: Read user-submitted bug reports and feature requests from the deployed (prod) database, triage them, implement the fix or feature locally, and sync the report's status back to prod. Use when the user asks to check user feedback, triage reports, or act on bugs/features submitted through the app.
argument-hint: "[bug | feature | <report-id> — optional filter]"
---

# User Reports Triage

Users submit bug reports and feature requests in-app; they land in the
`reports` table of the **production** database (migration 026,
`backend/app/models/report.py`). This skill reads them, picks one with the
user, implements the fix/feature on the local dev stack, and keeps the prod
report status in sync.

All prod DB access goes through the bundled script (run from anywhere, it
resolves the repo root itself):

```bash
.claude/skills/user-reports/reports.sh <command>
```

| Command | Purpose |
|---------|---------|
| `list [--type bug\|feature] [--status open\|in_progress\|closed\|all]` | List reports (default: non-closed, bugs first, newest first) |
| `show <report-id>` | One report in full, incl. description |
| `set-status <report-id> open\|in_progress\|closed` | Triage a report (single-row UPDATE by id) |

The script talks to the prod compose stack's postgres via the `deploy/README.md`
psql escape hatch. It requires the prod stack to be running — if it errors,
check `just deploy-status` (WSL2: `sudo service docker start`).

Arguments (if any): **$ARGUMENTS** — `bug`/`feature` →
`list --type $ARGUMENTS`; a report id → `show $ARGUMENTS`; empty → plain `list`.
If there are no open reports, say so and stop.

## Workflow

1. **Read** — `reports.sh list` (+ filter from `$ARGUMENTS`), then
   `reports.sh show <id>` for the one(s) under consideration.
2. **Pick one** — present the open reports as a compact numbered table (type,
   title, reporter, age) and ask the user which to act on. Default suggestion:
   the oldest open **bug** (user pain beats new features). Wait for
   confirmation.
3. **Mark in_progress (ask first)** — only after the user confirms they'll
   work on it now: `reports.sh set-status <id> in_progress`.
4. **Investigate & implement (locally, never against prod)**:
   - **Bug**: reproduce on the dev stack (`just dev`), find the root cause,
     fix following the `vibe-coding` workflow. For cross-stack work, hand off
     to the `team` skill with the report's title + description as the brief.
   - **Feature**: treat the report description as the requirement. Clarify
     ambiguities with the user before building — the reporter isn't available
     for questions, so the user speaks for them.
   - Verify: `just check`, plus `just be-test` / `just fe-test` as applicable.
5. **Close the loop in prod** — a fix isn't delivered until it's deployed.
   Once the work is merged to `main`, ask the user whether to `just deploy`
   now. After a successful deploy (`just deploy-status` healthy):
   `reports.sh set-status <id> closed`. If it won't deploy immediately, leave
   it `in_progress` and tell the user it's still pending a deploy.

## Guardrails

- Prod DB is live user data: **read-only** except `set-status` — always for a
  single report id, always after user confirmation. Never DELETE, never bulk
  updates, never schema changes.
- Never hot-patch the prod backend or edit the deploy worktree — all changes
  ship through the normal `just deploy` flow.
- Don't confuse dev and prod: the script targets `garbanzo_ai_prod` in the
  `garbanzo-prod` compose project; code changes and tests run locally against
  the dev stack.
- Closing triggers **no** notification to the reporter (only admins get
  notified, at submission time) — if a reply is warranted, the reporter's
  email is in `user_id`.
