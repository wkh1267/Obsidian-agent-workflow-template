---
description: File the current chat as a wiki page (synthesis, concept, comparison, or decision)
argument-hint: "[sub-type] [name]"
---

Run the SAVE operation as documented in `docs/operations.md`.

Arguments (all optional):
- $1: sub-type — `synthesis` (default), `concept`, `comparison`, or `decision`
- $2+: page name; if omitted, ask the user for one before writing

Reminders:
- Skip filing if content fails the savable-content criteria (mechanical Q&A, duplicate, one-off debugging).
- If a page on this topic already exists, offer to update it instead of creating a new one.
- Write the page → log entry → `wiki:` commit → update `knowledge-ingestion.md` and `hot.md` → `spec:` commit.
