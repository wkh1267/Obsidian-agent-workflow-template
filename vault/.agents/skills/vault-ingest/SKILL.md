---
name: vault-ingest
description: Use when the user asks to ingest one or more files from `raw/`, batch ingest sources, process source material into `wiki/` pages, or update ingestion logs/specs. Do not use for general Q&A, standalone git commits, or Obsidian file rename/move/delete operations.
---

# Vault Ingest

Use this skill for the vault's INGEST and batch-ingest workflows.

## Load

Read the current shared instructions before acting:

- `docs/agent-runtime.md`
- `docs/operations.md` (`INGEST` and batch ingest)
- `docs/wiki-conventions.md`
- `docs/git-workflow.md`
- `docs/specs/hot.md`
- `docs/specs/knowledge-ingestion.md`

## Boundaries

- Treat `raw/` as read-only source material.
- Use Obsidian `[[wikilinks]]`, required wiki frontmatter, and bidirectional cross-links where useful.
- For batch ingest, defer links between newly created batch-mate pages until the cross-reference pass.
- Create the required `log/YYYY-MM-DD-ingest-*.md` entry.
- Follow explicit-path staging and separate `wiki:` / `spec:` commit boundaries if the operation reaches commit.
- Use the `obsidian-cli` skill for rename, move, delete, tag rename, heading rename, or block-ID structural operations.

## Closeout

Update `docs/specs/knowledge-ingestion.md` and `docs/specs/hot.md` when persistent wiki state changes. Do not push unless the user explicitly says `sync` or `push`.
