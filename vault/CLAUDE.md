# CLAUDE.md - Claude Loader

This file is intentionally thin. Shared vault rules live in
`docs/agent-runtime.md`; keep common instructions there so Claude and Codex do
not drift.

## Load Order

1. Load and follow the file listed in the Imports stanza
   (`docs/agent-runtime.md` — the shared runtime SSOT).
2. Use `docs/operations.md`, `docs/wiki-conventions.md`, `docs/git-workflow.md`,
   and `docs/issue-workflow.md` as task-specific references — read each only
   when the request calls for it, following the read-on-demand quick map in
   `docs/agent-runtime.md` §Startup Context.
3. Read `docs/specs/hot.md` and the relevant spec exactly as
   `docs/agent-runtime.md` directs.

## Claude-Specific Notes

- Honor the strict preservation rule defined in docs/agent-runtime.md §Core Safety Rules.
- Claude slash commands live in `.claude/commands/`; `/save` and `/issue`
  delegate to the procedures in `docs/operations.md`.
- Claude subagents live in `.claude/agents/` and are used only through the
  issue and ingest workflows documented in `docs/issue-workflow.md` and
  `docs/operations.md`.
- Claude hooks are configured in `.claude/settings.json`. Treat hook behavior as
  an implementation detail of the Claude layer unless the user asks for hook or
  workflow changes.
- Claude Obsidian skills live under `.claude/obsidian-skills/`; use them when
  the shared runtime rules call for Obsidian-aware Markdown, CLI, Base, Canvas,
  or extraction behavior.

## See Also

- [[docs/agent-runtime]]
- [[docs/operations]]
- [[docs/wiki-conventions]]
- [[docs/git-workflow]]
- [[docs/issue-workflow]]

## Imports

@docs/agent-runtime.md
