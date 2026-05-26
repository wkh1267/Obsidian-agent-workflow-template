---
description: Sequentially ingest all pending raw/ files via wiki-ingest subagents with run-state tracking and one final checkpoint
argument-hint: "(no arguments)"
---

Run the structured ingest-inbox workflow. This command processes every raw file
currently pending in `wiki/synthesis/Inbox.md` semantics without loading each
source into the top-level context.

Preflight:
- Read `docs/specs/hot.md`, `docs/agent-runtime.md`,
  `docs/specs/knowledge-ingestion.md`, `docs/operations.md`,
  `docs/wiki-conventions.md`, `docs/git-workflow.md`, and
  `.claude/agents/wiki-ingest.md`.
- Refuse to start with staged paths.
- Refuse uncommitted in-scope ingest drift in `wiki/**`, top-level
  `log/*ingest*.md`, `docs/specs/knowledge-ingestion.md`, `docs/specs/hot.md`,
  or `exp/ingest-inbox-runs/**`.
- Allow unrelated pre-existing dirt only by recording it in the state baseline.
- If a running state exists in `exp/ingest-inbox-runs/`, ask for `resume`,
  `fresh`, or `abort`.

Workflow:
1. From the vault root, run
   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/get-pending-raw.ps1`.
   Treat each output line as one pending `raw/<name>` source; the detector owns
   the Inbox-equivalent frontmatter parsing and normalization rules.
2. If the pending list is empty, print `Inbox is clear; nothing to ingest` and
   exit without creating state.
3. Create `exp/ingest-inbox-runs/<YYYY-MM-DD-HHmmss>-state.md` with
   `status: running`, pending/completed/failed lists, timestamps, and
   `baseline_dirty_paths`.
4. Spawn exactly one `wiki-ingest` worker at a time. Pass the raw source path,
   the other pending sources, and the full Clusters table from
   `docs/specs/knowledge-ingestion.md`.
5. Wait for each worker report before spawning the next. Record `success`,
   `empty`, `malformed`, or `error` in the state file immediately, then
   continue.
6. Present one final checkpoint: `approve closeout`, `retry failures`, or
   `abort`.

Approved closeout:
- Run the top-level cross-reference pass between batch-sibling pages that exist
  on disk.
- Create one collision-safe consolidated ingest log at
  `log/YYYY-MM-DD-HHmmss-ingest-inbox-batch.md`.
- Commit with explicit-path staging in `wiki:` -> `spec:` -> `schema:` order.
- Archive the completed run state with a matching `operation: schema` log entry.

Do not edit `raw/` or `wiki/synthesis/Inbox.md`; workers also must not update
logs, specs, run state, or Git.
