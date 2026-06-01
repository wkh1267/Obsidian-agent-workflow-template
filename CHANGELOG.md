# Changelog

All notable public-template changes are recorded here.

## v0.1.0 - Initial Public Template Release

Released: 2026-05-28

This first public release provides an Obsidian-based agent workflow template for
Claude Code and Codex. It ships a nested `vault/` layout, with the repository
root reserved for Git hooks and release-maintenance scripts while users open
`vault/` in Obsidian, Claude Code, or Codex.

Included in this release:

- Shared agent runtime loaders through `CLAUDE.md` and `AGENTS.md`.
- Human trigger vocabulary for ingest, query, save, lint, issue, release, sync,
  and push workflows.
- Structured issue workflow with plan, review, implementation, implementation
  review, and closeout artifacts.
- Public export and release-maintenance helpers, including tree and repository
  security scan scripts.
- Root MIT `LICENSE`.
- Optional Git hooks for local safety checks. Review the hook scripts before
  installing or adapting them.

