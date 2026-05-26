---
name: vault-lint
description: Use when the user asks to lint, audit, health-check, or repair the wiki for contradictions, orphaned pages, stale claims, missing cross-links, frontmatter issues, or tag problems. Do not use for build/test linting of software code, standalone git commits, or Obsidian file rename/move/delete operations.
---

# Vault Lint

Use this skill for the vault's LINT health-check workflow.

## Load

Read the current shared instructions before acting:

- `docs/agent-runtime.md`
- `docs/operations.md` (`LINT`)
- `docs/wiki-conventions.md`
- `docs/git-workflow.md`
- `docs/specs/hot.md`
- `docs/specs/knowledge-ingestion.md`

## Boundaries

- Inspect the wiki for the categories defined in `docs/operations.md`: orphans, dead links, stale claims, missing pages, missing cross-references, frontmatter gaps, empty sections, stale index entries, page length, and old `seed` pages.
- Report findings before broad repairs unless the user already approved fixes.
- Use `obsidian-cli` for structural rename, move, delete, tag rename, heading rename, or block-ID work.
- Create the required `log/YYYY-MM-DD-lint*.md` entry for fixes.
- Follow explicit-path staging and separate `wiki:` / `spec:` commit boundaries if the operation reaches commit.

## Closeout

Update `docs/specs/knowledge-ingestion.md` and `docs/specs/hot.md` when persistent wiki state changes. Do not push unless the user explicitly says `sync` or `push`.
