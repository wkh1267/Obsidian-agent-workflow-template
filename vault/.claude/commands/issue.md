---
description: Open or orchestrate a tracked issue workflow
argument-hint: "[manual|auto-plan|auto-full] <description of the feature or change>"
---

Open a tracked issue workflow for: $ARGUMENTS

Modes:
- `manual` - open the issue and stop after planner output. This is also the
  default when no mode token is supplied.
- `auto-plan` - open the issue, run planner, run plan review, and loop planner
  revision plus review until the plan is accepted or a pause gate fires.
- `auto-full` - run planning, plan review, implementation, implementation
  review, any required closeout `spec:` follow-up, and the accepted-status close
  when all gates pass. Never push automatically.

Manual steps:
1. Compute the next issue number: glob `issues/[0-9][0-9][0-9][0-9]-*/`
   (excludes `_template/`), take the max numeric prefix, add 1, zero-pad to 4
   digits. If no issues exist yet, start at `0001`.
2. Pick a kebab-case slug from the description (3-6 words, lowercase, hyphens
   only).
3. Spawn the `issue-planner` subagent with: issue number, slug, mode `manual`,
   and the original description verbatim as the idea.
4. After planner returns, commit: `schema: issue NNNN: open <slug> - plan v1`
   with log entry `operation: implement`.

`auto-plan` steps:
1. Run the manual planner setup with mode `auto-plan`, including the planner
   output commit from manual step 4.
2. Spawn `issue-plan-reviewer`.
3. Commit `plan-review.md` plus the issue README timeline under `schema:` with
   an `operation: implement` log entry before deciding the next stage.
4. If review is `accepted`, stop with the accepted plan ready for
   implementation.
5. If review is `changes-requested`, spawn `issue-planner` with revising flag,
   commit the revised `plan.md` plus README timeline under `schema:`, then
   review again. Allow at most two automatic revision attempts in this run, and
   stop earlier if the three-`changes-requested` hard escalation rule for the
   artifact is reached.

`auto-full` steps:
1. Run the `auto-plan` loop.
2. If the plan is accepted and no pause gate fired, spawn `issue-implementer`.
3. Orchestrator performs explicit-path staging, commits in the required issue
   order, and backfills `impl-log.md` commits before review.
4. Spawn `issue-impl-reviewer`.
5. Commit `impl-review.md` plus the issue README timeline under `schema:`
   before deciding the next stage.
6. If review is `changes-requested`, spawn `issue-implementer` with revising
   flag, commit the revised implementation in the required issue order,
   backfill `impl-log.md`, then review again. Allow at most two automatic
   implementation revision attempts in this run, and stop earlier if the
   three-`changes-requested` hard escalation rule is reached.
7. If implementation review is `accepted`, determine whether closeout discipline
   requires an issue-specific `spec:` follow-up. When required, commit the
   `docs/specs/system-development.md` and `docs/specs/hot.md` `spec:` update
   first, so the spec commit is already in `HEAD` before the accepted-status
   close.
8. Set the issue README status to `accepted` and commit the close under
   `schema:`. This accepted-status close is the final schema step before any
   optional user-requested push.

For every auto-mode subagent stage or revision, follow the commit table in
`docs/issue-workflow.md`: commit the artifact and README timeline update before
spawning the next stage. Reviewers and implementers still never commit; the
orchestrator owns staging, log entries, commits, SHA backfill, closeout, and any
user-requested push.

Pause gates:
- unresolved Open Questions that require a human choice
- high-risk paths such as `.obsidian/` or `raw/`
- destructive filesystem operations, pushes, or history rewrites
- undocumented edits outside the accepted plan's file list
- failed verification, empty `impl-log.md` commits before review, or staged
  paths outside the implementer's allowlist
- any command that needs approval or escalation
- unrelated pre-existing worktree drift that makes scoped staging ambiguous

The planner creates `issues/NNNN-slug/` and writes `plan.md` (status: pending).
In manual mode, next step: say "review the plan for issue NNNN" to trigger plan
review.
