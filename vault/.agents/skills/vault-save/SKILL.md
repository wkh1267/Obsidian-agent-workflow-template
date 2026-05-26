---
name: vault-save
description: Use when the user asks to save durable in-conversation thinking as a `wiki/` page, including synthesis, concept, comparison, or decision pages. Do not use for one-off debugging notes, duplicate QUERY outputs, standalone git commits, or Obsidian file rename/move/delete operations.
---

# Vault Save

Use this skill for SAVE operations that preserve durable chat synthesis in the wiki.

## Load

Read the current shared instructions before acting:

- `docs/agent-runtime.md`
- `docs/operations.md` (`SAVE`)
- `docs/wiki-conventions.md`
- `docs/git-workflow.md`
- `docs/specs/hot.md`
- `docs/specs/knowledge-ingestion.md`

## Boundaries

- Save only reusable analysis, decisions, comparisons, frameworks, or research findings.
- Skip mechanical Q&A, one-off debugging notes, and duplicates of a QUERY synthesis already filed in the same session.
- Check for existing pages on the topic before creating a new one.
- Use the correct page type and frontmatter for `synthesis`, `concept`, `comparison`, or decision-style synthesis pages.
- Create the required `log/YYYY-MM-DD-save-*.md` entry.
- Follow explicit-path staging and separate `wiki:` / `spec:` commit boundaries if the operation reaches commit.

## Closeout

Update `docs/specs/knowledge-ingestion.md` and `docs/specs/hot.md` when persistent wiki state changes. Do not push unless the user explicitly says `sync` or `push`.
