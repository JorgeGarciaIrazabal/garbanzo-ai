---
name: guided-development
description: Implement a user request interactively with revision-linked feedback and Beads acceptance criteria.
---

Read root AGENTS.md and the relevant scoped package guidance. In an existing
session run the lightweight `just ai-startup` once, not `just ai` (which launches
another UI). Use `just ai-startup --full` when current production reports and
capacity evidence are relevant to the work.
Record requirements, dependencies and acceptance in Beads via just ai-task;
answer investigative questions without converting them into implementation. For
task selection, run `just ai-task summary` before broader `ready` or `list`
output, then inspect only shortlisted IDs with `show`.
Keep the current agent on a task by default. Use Terra for routine implementation,
Luna for narrow exploration, Sol for substantive review, and Astra for substantial
design or architecture/security review. Delegate only a
substantial independent task, using a compact self-contained brief rather than
full conversation history. Resolve available models and retain the resolved model
in each assignment. Trivial documentation needs no model review; routine work gets
focused tests or lint; substantive work gets one consolidated review with targeted
follow-up for material fixes. Run `just check` at the commit boundary and repeat
it only after an affected input changes.
Keep working while the user tests independent work. Associate feedback with
its exact preview and update affected requirement revisions. User acceptance
is distinct from automated checks; do not claim it on the user's behalf.
See docs/ai-development.md for command schemas and delivery gates.
