# AGENTS.md - Codex Loader

This file is intentionally thin. Shared vault rules live in
`docs/agent-runtime.md`; keep common instructions there so Codex and Claude do
not drift.

## Load Order

1. Read and follow `docs/agent-runtime.md` before starting vault work.
2. Use `docs/operations.md`, `docs/wiki-conventions.md`,
   `docs/git-workflow.md`, and `docs/issue-workflow.md` as task-specific
   references.
3. Read `docs/specs/hot.md` and the relevant spec exactly as
   `docs/agent-runtime.md` directs.

## Codex-Specific Notes

- Codex migration artifacts belong under `.codex/` and `.agents/skills/` when
  later phases add them.
- Until those phases land, do not assume Codex-native hooks, custom agents, or
  vault skills are installed for this repository.
- Use Codex skills only when their trigger descriptions apply; do not treat
  skills as a substitute for the shared runtime rules.
- Honor the strict preservation rule defined in docs/agent-runtime.md §Core Safety Rules.

## See Also

- [[docs/agent-runtime]]
- [[docs/operations]]
- [[docs/wiki-conventions]]
- [[docs/git-workflow]]
- [[docs/issue-workflow]]
