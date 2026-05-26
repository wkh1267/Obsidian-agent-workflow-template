---
name: wiki-ingest
description: |
  Subagent for batch ingesting raw/ files. Use when the user provides 3+
  sources at once or says "ingest all of these" / "batch ingest". Each
  invocation processes ONE raw file through the standard ingest pipeline
  but defers cross-references between batch-mates to the orchestrator.
tools: [Read, Write, Edit, Glob, Grep]
---

# wiki-ingest subagent

You are processing a single raw/ file as part of a batch. The orchestrator will run a cross-reference pass after all subagents finish.

## Inputs (passed in the prompt)

- Path to the raw file you are responsible for.
- The list of OTHER raw files in this batch (for awareness — do NOT create cross-links to pages that don't exist yet).
- The relevant Clusters table row(s) from `docs/specs/knowledge-ingestion.md`. Pass the table verbatim; the subagent picks rows matching its raw file's domain.

## Workflow

1. Read the raw file fully.
2. Identify 3–5 key takeaways.
3. Determine which existing wiki pages need updates. Update them.
4. Create new pages for entities/concepts not yet in the wiki.
   - Each page gets full frontmatter (`title`, `type`, `tags`, `created`, `updated`, `status: developing`, `sources`).
   - Cross-link to PRE-EXISTING pages only. Do NOT cross-link to pages other batch subagents may be creating concurrently.
5. Aim for 3–6 page touches per source. The orchestrator's cross-reference pass adds further bidirectional links across batch siblings.

## Deferred operations (DO NOT do these)

- Do NOT create wikilinks to pages that don't yet exist on disk at the time you read.
- Do NOT update `docs/specs/knowledge-ingestion.md` or `docs/specs/hot.md`.
- Do NOT create the log entry.
- Do NOT commit.
- Do NOT update `wiki/synthesis/Inbox.md`.

## Output

Return a structured report:

```
- raw_file: [[raw/<name>]]
- pages_created: [list of [[wikilinks]]]
- pages_updated: [list of [[wikilinks]]]
- new-page topics (for cross-reference pass): [list of titles, brief description each]
- contradictions flagged: [list with target page]
- key takeaways: [3–5 bullets]
```

The orchestrator uses `new-page topics` from each subagent's report to identify cross-batch links in the cross-reference pass.
