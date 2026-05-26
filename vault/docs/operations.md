# Operations

## INGEST — adding a new source

When the user drops a file in `raw/` or pastes content to ingest:

0. Read `docs/specs/knowledge-ingestion.md` to reconstruct current wiki state and cluster context. Check `wiki/synthesis/Inbox.md` to see which raw files are still pending — this is the canonical list of unprocessed sources.
1. Read the source fully.
2. Identify 3–5 key takeaways and discuss briefly with the user if needed.
3. Determine which existing wiki pages to update (add new information, revise claims).
4. Create new pages for significant entities or concepts not yet in the wiki.
5. Ensure all new pages have correct `type` and `tags` frontmatter — the Dataview index auto-populates.
6. Create `log/YYYY-MM-DD-ingest-name.md` with `date`, `operation`, `source`, and `pages_created` frontmatter.
7. Aim to touch 10–15 wiki pages total per ingest.
8. Commit wiki changes with scope `wiki`.
   Strictly follow the staging discipline in `docs/git-workflow.md` §Pre-commit Staging Rules; stage only the wiki pages and the matching `log/` entry — never `git add -A` or `git add .`.
9. Update `docs/specs/knowledge-ingestion.md` (page count, clusters, open questions, next steps) and `docs/specs/hot.md`; commit both separately with scope `spec`.

### Batch ingest (≥3 raw files)

When the user drops 3+ files in `raw/` at once, or says "ingest all of these" / "batch ingest":

1. **Enumerate** — list every source. Confirm with the user before proceeding.
2. **Per-source pass** (parallelizable via `wiki-ingest` subagent — see `.claude/agents/wiki-ingest.md`): each source goes through the standard ingest pipeline **except cross-references between this batch's pages are deferred**. Each subagent creates only the pages directly derived from its source plus links to *pre-existing* pages.
3. **Cross-reference pass** — once all per-source passes complete, identify connections among the newly created pages. Add bidirectional wikilinks. This is a single sequential step, not subagent-parallelized.
4. **Consolidated closeout** — one log entry covering the whole batch (`operation: ingest`, `source: [list of raw wikilinks]`, `pages_created: [combined list]`); one `wiki:` commit; one `spec:` commit updating `knowledge-ingestion.md` and `hot.md`. Both commits follow the staging discipline in `docs/git-workflow.md` §Pre-commit Staging Rules — stage explicit paths only.

Checkpoint with the user every 10 sources for batches of 30+. Single-writer rule: never run two batch ingests in parallel sessions.

### Structured Inbox ingest

Use `/ingest-inbox` or `ingest-inbox` when the user wants to process the whole
raw Inbox through a recoverable sequential workflow. It computes pending raw
sources by running the canonical vault-local detector from the vault root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/get-pending-raw.ps1
```

Each output line is one normalized pending `raw/<name>` source. Empty output
means the Inbox is clear and no run state should be created. After preflight,
the workflow keeps mutable run state under `exp/ingest-inbox-runs/`, runs one
`wiki-ingest` worker at a time, and stops for one final checkpoint before
cross-references, the consolidated ingest log, and commits.

Codex invocations use `wiki-ingest` subagents only when the user prompt already
grants subagent/delegation consent or after a preflight consent prompt. Normal
closeout order is `wiki:` for wiki pages plus the batch ingest log, then `spec:`
for ingestion specs, then `schema:` for the completed run-state archive and its
matching schema log. Ad hoc batch ingest remains available for manually scoped
source sets.

## QUERY — answering a question from the wiki

Select a tier before reading. Stop as soon as the tier yields enough.

| Tier | Reads | When to use |
|---|---|---|
| **Quick** | `docs/specs/hot.md` + `index.md` only | one-liners, dates, simple lookups |
| **Standard** (default) | hot.md + index.md + 3–5 most relevant pages | most questions |
| **Deep** | full wiki + optional web fetch | cross-domain synthesis or contradiction reconciliation |

If a Quick read answers the question, respond — do not read further. If Standard is insufficient, ask the user before escalating to Deep.

When the user asks a question:

0. Read `docs/specs/hot.md` to identify recent context and the most relevant clusters. If Quick tier and this answers the question, stop here.
1. Search `index.md` to identify the most relevant pages.
2. Read those pages and synthesize an answer with citations (using `[[wikilinks]]`).
3. If the answer reveals a useful connection or analysis, file it back as a new `synthesis/` page.
4. Create `log/YYYY-MM-DD-query-name.md` with `date`, `operation`, `source` (the question), and `pages_created` frontmatter.
5. Commit wiki changes with scope `wiki`.
   Strictly follow the staging discipline in `docs/git-workflow.md` §Pre-commit Staging Rules; stage only any new synthesis page and the matching `log/` entry — never `git add -A` or `git add .`.
6. Update `docs/specs/knowledge-ingestion.md` if new synthesis pages were created; update `docs/specs/hot.md`; commit both separately with scope `spec`.

## LINT — health-checking the wiki

When the user runs a lint pass:

0. Read `docs/specs/knowledge-ingestion.md` to focus the lint on known problem areas first.
1. **Orphans** — pages with no inbound wikilinks.
2. **Dead links** — wikilinks pointing to non-existent pages.
3. **Stale claims** — assertions on older pages contradicted by newer ingests.
4. **Missing pages** — concepts mentioned ≥3 times across pages with no dedicated page.
5. **Missing cross-refs** — entities named in body text without a wikilink to their page.
6. **Frontmatter gaps** — pages lacking required fields (`title`, `type`, `tags`, `created`, `updated`, `sources`, `status`).
7. **Empty sections** — headings with no substantive content.
8. **Stale index entries** — index/Inbox entries pointing at renamed or deleted pages.
9. Plus: pages exceeding 300 lines (soft cap reminder).
10. Plus: pages with `status: seed` older than 30 days.
11. Report findings; fix the user-approved issues.
12. Create `log/YYYY-MM-DD-lint.md` with `date`, `operation`, and `pages_created` (pages fixed) frontmatter.
13. Commit fixes with scope `wiki`.
    Strictly follow the staging discipline in `docs/git-workflow.md` §Pre-commit Staging Rules; stage only the wiki pages fixed and the lint `log/` entry — never `git add -A` or `git add .`.
14. Update `docs/specs/knowledge-ingestion.md` and `docs/specs/hot.md`; commit separately with scope `spec`.

## SAVE — capturing chat synthesis as a wiki page

When the user invokes `/save` (or asks to save a piece of in-conversation thinking):

0. Read `docs/specs/hot.md` and `docs/specs/knowledge-ingestion.md` for context.
1. **Identify the savable content.** It must meet at least one criterion:
   - non-obvious insight or analysis
   - decision with rationale
   - referenceable comparison or framework
   - research finding worth re-reading

   Skip if it's a mechanical Q&A, documented setup, one-off debugging, or a duplicate. If a QUERY in this conversation already filed a synthesis page on the same topic, do not duplicate it — `/save` is for thinking that QUERY did not file.
2. **Pick a sub-type** (default `synthesis` if ambiguous):
   - `synthesis` → `wiki/synthesis/<name>.md`, `type: synthesis`
   - `concept` → `wiki/concepts/<name>.md`, `type: concept`
   - `comparison` → `wiki/synthesis/<name>.md`, `type: comparison`
   - `decision` → `wiki/synthesis/<name>.md`, `type: synthesis`, `tags` include `decision`, body structured as `## Decision`, `## Rationale`, `## Rejected Alternatives`, `## Do Not Repeat`, `## Consequences`

   Use the full `decision` body only for durable choices likely to be re-opened,
   not routine issue updates. `## Do Not Repeat` uses imperative bullets, each
   paired with a one-line reason.
3. **Check for duplicates.** If a page on the same topic exists, offer to update it rather than create a new one.
4. **Write the page** with full frontmatter (`title`, `type`, `tags`, `created`, `updated`, `status: developing`, `sources: [chat session]`).
5. **Cross-link** — add wikilinks both directions to related pages; add `## See Also`.
6. Create `log/YYYY-MM-DD-save-<slug>.md` with `date`, `operation: save`, `source: chat`, `pages_created`.
7. Commit `wiki:`.
   Strictly follow the staging discipline in `docs/git-workflow.md` §Pre-commit Staging Rules; stage only the new wiki page and the `log/` entry — never `git add -A` or `git add .`.
8. Update `docs/specs/knowledge-ingestion.md` and `docs/specs/hot.md`; commit `spec:` separately.

## SCHEMA — vault tooling and workflow changes

When changing skills, hooks, `CLAUDE.md`, `AGENTS.md`, `docs/agent-runtime.md`, other `docs/` files, `settings.json`, `local settings file`, or agent runtime scripts:

0. Read `docs/specs/system-development.md` to reconstruct current tooling state.
1. Make the change.
2. Create `log/YYYY-MM-DD-schema-name.md` with `date`, `operation: schema`, `source`, and `pages_created: []` frontmatter.
3. Commit changes with scope `schema`.
   Strictly follow the staging discipline in `docs/git-workflow.md` §Pre-commit Staging Rules; stage only the changed schema files and the matching `log/` entry — never `git add -A` or `git add .`.
4. Update `docs/specs/system-development.md` and `docs/specs/hot.md`; commit separately with scope `spec`.

## ISSUE — feature work via bounded subagents

Open an issue: `/issue <description>` or say "open an issue for X". Full lifecycle and agent contracts: `docs/issue-workflow.md`.

Modes:
- `manual` - current staged flow; the human triggers each stage.
- `auto-plan` - planner/reviewer loop through accepted plan, then stop.
- `auto-full` - full lifecycle through accepted implementation review, closeout,
  and required `spec:` follow-up when gates pass; never push automatically.

Codex auto-mode prompts must include explicit subagent/delegation consent before
custom agents are spawned. Claude uses `/issue manual`, `/issue auto-plan`, and
`/issue auto-full`.

Stages (manual, or advanced by the orchestrator in an authorized auto mode):
1. `issue-planner` → `plan.md` (status: pending)
2. `issue-plan-reviewer` → `plan-review.md` (accepted or changes-requested)
3. `issue-implementer` → actual repo changes + `impl-log.md`
4. `issue-impl-reviewer` → `impl-review.md` (accepted or changes-requested)
5. Close: orchestrator sets `status: accepted`; follow-up `spec:` commit if new capability landed.

Pause auto modes for review retry limits, unresolved human choices, unexpected
high-risk paths, undocumented out-of-plan edits, failed verification, empty
`impl-log.md` commits before review, staging drift, or any approval/escalation
requirement. Automatic issue orchestration may make at most two revision
attempts per artifact in one run, while the existing three-`changes-requested`
hard escalation still applies across the issue lifecycle.

Issue artifacts commit under `schema:`; implementation work commits under its natural scope (`wiki:`, `spec:`, `schema:`). Log `operation: implement` on all issue-stage commits.

**ISSUE vs SAVE**: SAVE = "capture a thought already formed in chat"; ISSUE = "track a change not yet made to the vault or its tooling."

## Index and Log rules

**index.md**
- Dataview-powered — do not manually edit the lists.
- To add a page to the index: give it correct `type` and `tags` frontmatter. It appears automatically.
- To add a new concept category: add a new `LIST` query block filtered by the relevant tag.

**log.md**
- Dataview dashboard — do not manually edit.
- All log content lives as individual files in `log/`.

**log/ entries**
- One file per operation: `log/YYYY-MM-DD-operation-name.md`.
- Required frontmatter: `date`, `operation`, `source`, `pages_created` (list of wikilinks).
- `source` for ingest operations must be a wikilink to the raw file **without** the `.md` extension: `"[[raw/filename]]"` not `"[[raw/filename.md]]"`. The `Inbox.md` Dataview query depends on this to mark files as processed.
- Body: short prose summary of what was done.
- Never edit or delete past log entries.
