---
name: ingest-inbox
description: Use when the user explicitly asks to run the ingest-inbox workflow, process the whole raw Inbox, or sequentially run wiki-ingest subagents over pending raw/ files with run-state tracking and one final checkpoint. Do not use for ordinary single-source ingest, general QUERY, or standalone git commits.
---

# Ingest Inbox

Use this skill for the structured workflow that clears every currently pending
`raw/*.md` source shown by `wiki/synthesis/Inbox.md` while keeping raw-source
contents out of the top-level agent context.

This workflow uses one `wiki-ingest` subagent at a time. If the user prompt
already mentions subagents, agents, delegation, or sequential `wiki-ingest`
workers, that is sufficient consent to spawn the workers. If the prompt only
names `ingest-inbox`, `/ingest-inbox`, or "process the whole raw Inbox", pause
before the first spawn and ask: "May I run one wiki-ingest subagent at a time for
this ingest-inbox workflow?" If the user declines, stop without creating a state
file.

## Load

Before any state file or subagent spawn, read:

1. `docs/specs/hot.md`
2. `docs/agent-runtime.md`
3. `docs/specs/knowledge-ingestion.md`
4. `docs/operations.md`
5. `docs/wiki-conventions.md`
6. `docs/git-workflow.md`
7. `.codex/agents/wiki-ingest.toml`

Use the full Clusters table from `docs/specs/knowledge-ingestion.md` in each
worker prompt.

## Preflight

1. Inspect `git status --porcelain` and `git diff --cached --name-only`.
2. Refuse to start if any path is staged.
3. If a running state file exists under `exp/ingest-inbox-runs/`, ask the user
   to choose `resume`, `fresh`, or `abort`.
4. `resume` continues from that state file. Allow in-scope drift only when it is
   consistent with the completed and failed reports already recorded there.
5. `fresh` is allowed only when there is no in-scope wiki, log, spec, or run
   state drift beyond the old state file. Mark the old state `superseded`, then
   create a new state file.
6. `abort` marks the running state `aborted` and stops.
7. If no running state exists, refuse to start when uncommitted in-scope ingest
   drift exists in `wiki/**`, top-level `log/*ingest*.md`,
   `docs/specs/knowledge-ingestion.md`, `docs/specs/hot.md`, or
   `exp/ingest-inbox-runs/**`.
8. Allow unrelated pre-existing dirty paths, record them in
   `baseline_dirty_paths`, and never stage them.

The only prompts before the final review are the Codex worker-consent gate and
the recovery prompt for an existing running state.

## Pending List

From the vault root, run the canonical detector before creating any state file:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/get-pending-raw.ps1
```

Treat each output line as one normalized pending `raw/<name>` source, without a
trailing `.md`. The detector owns the `wiki/synthesis/Inbox.md`-equivalent
frontmatter parsing and normalization rules. If the output is empty, print
`Inbox is clear; nothing to ingest` and exit without creating a state file.

## State File

Create mutable state lazily at:

`exp/ingest-inbox-runs/<YYYY-MM-DD-HHmmss>-state.md`

Use this frontmatter shape:

```yaml
---
type: ingest-inbox-run
status: running
started: YYYY-MM-DD HH:mm:ss
updated: YYYY-MM-DD HH:mm:ss
pending:
  - "[[raw/foo]]"
completed: []
failed: []
baseline_dirty_paths: []
---
```

Body sections:

- `## Pending` - unchecked checklist of remaining raw sources.
- `## Completed` - one subsection per successful source with the full worker
  report.
- `## Failed` - one subsection per failed source with classification and reason.
- `## Closeout` - final user choice and commit SHAs once available.

Valid state statuses are `running`, `complete`, `aborted`, and `superseded`.
Update the file immediately after every worker success or failure.

## Source Loop

For each pending source `R`:

1. Re-read the state file at the top of the loop.
2. Compute `others` as pending raw sources other than `R`.
3. Spawn exactly one `wiki-ingest` subagent for `R`.
4. Pass the raw source path, `others`, and the full Clusters table.
5. Wait for the report before spawning any later worker.
6. Classify the result:
   - `success` when the report matches the worker contract and has at least one
     `pages_created` or `pages_updated` entry.
   - `empty` when the report matches the worker contract but both page lists are
     empty.
   - `malformed` when the report does not match the worker contract.
   - `error` when the subagent returns an error or does not complete.
7. Move `R` from `pending` to `completed` with the full structured report on
   success, or to `failed` with classification and reason otherwise.
8. Continue to the next source without asking the user.

Workers must not update logs, specs, `wiki/synthesis/Inbox.md`, run state, or
Git. The top-level agent owns those steps.

## Final Review

After the loop, show one summary:

```text
Inbox ingest complete.
- Total processed: N
- Succeeded: M sources, created K pages, updated U pages
- Failed: F sources
  - [[raw/foo]]: malformed - missing pages_created field
What next? approve closeout / retry failures / abort
```

If the user chooses `retry failures`, move selected failed entries back to
`pending`, rerun the source loop for those sources only, then return to this
checkpoint.

If the user chooses `abort`, mark the state `aborted`, stop before creating the
consolidated ingest log, and report all in-scope uncommitted paths. Do not
delete generated wiki pages automatically.

## Approved Closeout

On approval:

1. Run the cross-reference pass over pages from successful reports. Add useful
   bidirectional wikilinks between batch siblings, but only to pages that exist
   on disk.
2. Create one consolidated ingest log at
   `log/YYYY-MM-DD-HHmmss-ingest-inbox-batch.md`. If the path exists, append
   `-2`, `-3`, and so on. Never overwrite an existing log entry.
3. The log frontmatter uses `operation: ingest`, `source` as a YAML list of
   raw wikilinks without `.md`, and `pages_created` as the combined list of new
   wiki pages.
4. Commit the content closeout first with explicit-path staging:
   - `wiki:` for created and updated `wiki/**/*.md` files from the reports plus
     the consolidated ingest log.
   - `spec:` for `docs/specs/knowledge-ingestion.md` and `docs/specs/hot.md`.
5. After the `wiki:` and `spec:` commits land, mark the state file `complete`
   and record the final user choice plus the available closeout commit SHAs in
   `## Closeout`.
6. Create the matching schema log entry
   `log/YYYY-MM-DD-schema-ingest-inbox-run-state-HHmmss.md`.
7. Commit only the completed state file and matching schema log entry as the
   `schema:` run-state archive.

Do not edit `raw/` or `wiki/synthesis/Inbox.md`. Processed raw files disappear
from the Inbox through the consolidated ingest log after Dataview reindexes.
