---
name: vault-issue-workflow
description: Use when the user asks to open, plan, review, implement, close, abandon, or check the status of a tracked issue under `issues/NNNN-slug/`. Do not use for untracked quick edits, standalone git commits, or general project planning outside the vault issue lifecycle.
---

# Vault Issue Workflow

Use this skill for the vault's ISSUE lifecycle.

## Load

Read the current shared instructions before acting:

- `docs/agent-runtime.md`
- `docs/operations.md` (`ISSUE`)
- `docs/issue-workflow.md`
- `docs/git-workflow.md`
- `docs/specs/hot.md`
- `docs/specs/system-development.md`

## Boundaries

- Use numbered `issues/NNNN-slug/` directories and keep issue artifacts inside their issue directory.
- Treat the issue README and artifact frontmatter `status:` fields as the source of truth.
- Default to `manual` mode: the user triggers open, plan review,
  implementation, implementation review, close, or abandon.
- Run `auto-plan` or `auto-full` only when the prompt includes the auto-mode
  token and explicit subagent/delegation consent. If the user mentions an auto
  mode without consent, pause before the first subagent call and ask for it.
- Reviewer stages write only review artifacts and the issue README timeline.
- The orchestrator owns commits, spec closeout, and any push request.
- Follow explicit-path staging and the issue commit-order rules in `docs/issue-workflow.md` when committing issue work.

## Auto Modes

- `manual` - current staged workflow.
- `auto-plan` - planner/reviewer loop until accepted plan or pause gate, then
  stop before implementation.
- `auto-full` - planner/reviewer, implementation, implementation review, close,
  and required closeout `spec:` follow-up when every gate passes. Never push.

Pass only bounded stage inputs to subagents: issue number, slug, mode, original
idea on first planning, revising flag, optional short human note, and artifact
status. Do not paste prior subagent transcripts into later subagents.

Pause auto modes for review retry limits, unresolved human choices, high-risk
paths such as `.obsidian/` or `raw/`, destructive filesystem or history
operations, pushes, undocumented out-of-plan edits, failed verification, empty
`impl-log.md` commits before review, staging drift, or any escalation/approval
requirement. Allow at most two automatic revision attempts per artifact in one
auto run while still respecting the three-`changes-requested` hard escalation
rule across the issue lifecycle.

## Closeout

For tooling or workflow changes introduced by an issue, update `docs/specs/system-development.md` and `docs/specs/hot.md` according to the spec follow-up criteria. Do not push unless the user explicitly says `sync` or `push`.
