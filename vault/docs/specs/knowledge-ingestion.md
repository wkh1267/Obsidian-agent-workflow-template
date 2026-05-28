---
title: Knowledge Ingestion Spec
track: knowledge-ingestion
last_updated: 2026-05-28 (public template seed)
---

# Knowledge Ingestion

## Goal

Turn raw sources into a structured, cross-linked Obsidian wiki with durable
operation logs and updated local specs.

## Current State

This public vault is blank. It has zero ingested knowledge pages, no raw backlog,
no topic clusters, and generated empty folders for `raw/`, `wiki/`, and `log/`.

## Active Decisions

- Raw sources go in `raw/` and are treated as immutable.
- Curated pages live under `wiki/concepts/`, `wiki/entities/`, and
  `wiki/synthesis/`.
- Each durable operation writes one dated log entry under `log/`.
- Wiki pages follow `docs/wiki-conventions.md`.

## Open Questions

N/A until sources are added.

## Next Steps

1. Add source files to `raw/`.
2. Run INGEST from the vault root.
3. Update this spec and `docs/specs/hot.md` during closeout.

## Update Protocol

After ingestion or wiki maintenance, update page counts, active clusters, open
questions, and next steps for the local vault.