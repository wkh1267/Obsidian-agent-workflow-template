# Issue Workflow

A GitHub-issue-shaped pipeline for feature work: each idea opens a numbered
directory; bounded subagents step it through `plan -> review -> implement ->
review -> close`; agents communicate only through files in that directory. In
`manual` mode the human triggers each stage transition; in authorized
`auto-plan` and `auto-full` modes the top-level orchestrator may advance while
documented pause gates pass.

Read on demand by the orchestrator and subagents. Entry loaders point here when issue work is requested; the shared runtime rules live in `docs/agent-runtime.md`.

---

## Workspace Structure

`issues/` is a top-level folder, peer of `exp/`. Each issue gets a numbered directory.

```
issues/
├── README.md                       ← Dataview index of in-flight issues
├── _template/                      ← frontmatter skeletons; copy-from for new issues
│   ├── README.md
│   ├── plan.md
│   ├── plan-review.md
│   ├── impl-log.md
│   └── impl-review.md
└── NNNN-feature-slug/
    ├── README.md                   ← issue metadata + status timeline
    ├── plan.md                     ← planner output (revised in place)
    ├── plan-review.md              ← plan reviewer verdict (revised in place)
    ├── impl-log.md                 ← implementer record
    └── impl-review.md              ← implementation reviewer verdict
```

### Numbering

Zero-padded sequential: `0001`, `0002`, … Slug is kebab-case (3–5 words). Numbers never reused, never renumbered. Closed issues stay in place — Dataview filters by `status:` field rather than archiving.

---

## File Contracts

Each artifact has a `status:` frontmatter field — the canonical state for that artifact. Iteration revises the file in place; `revision` increments. Git history preserves diffs across revisions.

### `issues/NNNN-slug/README.md`

Always-current metadata + timeline. Updated by every subagent at the end of its run.

```yaml
---
issue: NNNN
title: <feature description>
status: planning | plan-review | implementing | impl-review | accepted | abandoned
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

Optional issue README frontmatter may include `summary:` plus typed relation
list fields from `docs/wiki-conventions.md`. Use `blocked_by`, `depends_on`,
and `supersedes` for issue dependencies or replacement chains, with values as
wikilinks to issue README pages such as `[[issues/NNNN-slug/README]]`.

Sections: `## Idea` (original prompt verbatim), `## Acceptance Criteria` (user-supplied ideally; planner-drafted marked `[draft — reviewer to confirm]`), `## Timeline`.

### `plan.md`

Planner output. Sections: Goal, Assumptions, Non-goals, Success Criteria,
Context Referenced, Approach, Files to Modify (grouped by scope:
schema/wiki/spec), Commit Boundaries (commit-by-commit with scope + log entry
name + files), Verification Plan, Open Questions for Reviewer. Assumptions,
Non-goals, and Success Criteria are mandatory for every tracked plan; use
explicit `None` or `N/A` content for trivial cases.

Frontmatter: `issue`, `artifact: plan`, `revision: N`, `status: pending | accepted | changes-requested`, `author: issue-planner`, `updated`.

### `plan-review.md`

Plan reviewer verdict. Sections: Verdict, Findings (four categories — CONSISTENCY, CONSTRAINTS, COMPLETENESS, SCOPE), Required Changes (if `changes-requested`), Sign-off (if `accepted`).

Frontmatter: `issue`, `artifact: plan-review`, `revision: N`, `plan-revision-reviewed: N`, `status: accepted | changes-requested`, `reviewer: issue-plan-reviewer`, `updated`.

### `impl-log.md`

Implementer record. Sections: Files Modified (grouped by scope), Commits Made (orchestrator-populated), Deviations from Plan, Verification Run.

Frontmatter: `issue`, `artifact: impl-log`, `revision: N`, `status: pending | accepted | changes-requested`, `implementer: issue-implementer`, `plan-revision-followed: N`, `commits: [SHA-wiki, SHA-spec, SHA-schema]` (orchestrator backfills), `updated`.

### `impl-review.md`

Implementation reviewer verdict. Same shape as `plan-review.md`, scoped to the implementation. Reviewer reads `plan.md` + `impl-log.md` + actual git diff bounded by `commits:` field.

---

## Agent Roles

Four bounded subagents. Each reads its designated inputs, writes one output artifact, and returns a short summary. The main agent is the sole orchestrator.

| Agent | Reads | Writes | Tools |
|---|---|---|---|
| `issue-planner` | README, system docs, plan-review (if revising) | `plan.md`, issue README timeline | Read, Write, Edit, Glob, Grep |
| `issue-plan-reviewer` | README, plan, system docs | `plan-review.md`, issue README timeline | Read, Write, Edit, Glob, Grep |
| `issue-implementer` | README, accepted plan + review, impl-review (if revising) | files across repo + `impl-log.md`, issue README timeline | Read, Write, Edit, Glob, Grep |
| `issue-impl-reviewer` | README, plan, impl-log (`commits:` bounds diff), git diff | `impl-review.md`, issue README timeline | Read, Write, Edit, Glob, Grep, Bash |

**Tool-grant notes:**

- The **implementer has no Bash**. Read/Glob/Grep cover state inspection; the orchestrator owns commits and any Bash-driven verification.
- The **impl-reviewer's Bash is read-only git only**: `git diff <range>`, `git log <range>`, `git show <sha>`, `git status`. Never `git commit`, `git push`, `git reset`, `git checkout`, or non-git Bash.

**Hard prompt-enforced boundaries:**

- Reviewer agents write only to their review file + the issue README timeline. They cannot rewrite plans or fix implementations.
- Planner writes are confined to `issues/NNNN-slug/`.
- No agent edits `issues/README.md` (the Dataview folder index).
- No agent updates `docs/specs/` files — orchestrator handles all spec edits.
- No agent commits or pushes. The orchestrator owns explicit Git commits under the staging rules documented here.

---

## Communication Protocol

All inter-agent communication is file-based. Orchestrator prompts pass only: issue number + slug, and optional human notes.

### Orchestration modes

Issue work has three modes:

- `manual` - current staged behavior. The user explicitly triggers planning,
  plan review, implementation, implementation review, close, and abandon.
- `auto-plan` - one orchestrator session opens the issue, runs the planner,
  runs plan review, and loops planner revision plus review until the plan is
  accepted or a pause gate stops the run. It stops after an accepted plan and
  does not implement.
- `auto-full` - one orchestrator session runs planning, plan review,
  implementation, implementation review, issue closeout, and required closeout
  `spec:` follow-up when every gate passes. It never pushes; `sync`/`push`
  remains a separate explicit user action.

Automation is orchestrator-level only. The same bounded subagents run each
stage, read the issue files themselves, and keep their existing write
boundaries. The orchestrator passes only bounded stage inputs: issue number,
slug, mode, original idea for first planning, revising flag, optional short
human note, and the artifact status needed for the current stage. Do not paste
prior subagent transcripts into later subagents.

Codex auto-mode prompts must contain both an auto-mode token and explicit
subagent/delegation consent before custom agents are spawned. Good trigger
shapes include "use subagents to auto-plan an issue for ...", "delegate an
auto-full issue workflow for ...", and "run the issue workflow with agents in
auto-full mode for ...". If a Codex prompt mentions `auto-plan` or `auto-full`
without explicit subagent/delegation consent, pause before the first subagent
call and ask for that authorization.

Claude Code uses slash-command mode tokens: `/issue manual <idea>`,
`/issue auto-plan <idea>`, and `/issue auto-full <idea>`.

### Status as source of truth

The orchestrator decides what's possible next based on the latest artifact's `status:`:

- `pending` — agent finished; awaiting human decision.
- `accepted` — reviewer signed off; next stage may proceed.
- `changes-requested` — needs revision; bounce back to the corresponding role.

### Round-limit soft rule

If `plan-review` or `impl-review` returns `changes-requested` three times on the same artifact, escalate to the user before spawning again. Prevents infinite loops.

Auto modes allow at most two automatic revision attempts per artifact in one
orchestrated run. The existing three-`changes-requested` hard escalation still
applies across the issue lifecycle. After the automatic retry limit is reached,
summarize the blocker and return control to the user.

### Pause gates

Stop automatic progression and return control to the user when any gate fires:

- A plan or implementation review exceeds the automatic retry limit or the
  three-`changes-requested` hard escalation rule.
- An accepted plan has unresolved Open Questions requiring a human choice.
- The plan or implementation touches high-risk areas such as `.obsidian/`,
  `raw/`, destructive filesystem operations, pushes, or history rewrites.
- The implementer modifies files outside the accepted plan's file list without
  documenting a justified deviation.
- Verification fails, `impl-log.md` has an empty `commits:` field before
  implementation review, or staged paths do not match the implementer's scope
  allowlist.
- A command requires escalation or approval under the runtime permission rules.
- Unrelated pre-existing worktree drift would make scoped staging ambiguous.

---

## Lifecycle

```
[user idea]
    ↓ user: "add a feature: X" / "/issue X"
[main agent → issue-planner]
    issues/NNNN-slug/ created; plan.md v1 (status: pending); README timeline updated
    orchestrator commits schema: — log entry, operation: implement
    ↓ user: "review the plan" or auto-mode continues if gates pass
[main agent → issue-plan-reviewer]
    plan-review.md v1
    orchestrator commits schema:
    ├─ status: changes-requested → user: "fix the plan per review" → loop to planner
    └─ status: accepted ↓
            ↓ user: "implement" or auto-full continues
[main agent → issue-implementer]
    actual file changes + impl-log.md v1 (commits: empty initially)
    orchestrator commits in scope order:
      1. wiki:   (wiki/ files, if any) → SHA-wiki
      2. spec:   (docs/specs/ + hot.md refresh) → SHA-spec
                 Required whenever step 1 fired; skipped for pure-schema implementations.
      3. schema: (impl-log.md with commits: backfilled, issue README, other schema files) → SHA-schema
                 Log entry filed here, operation: implement.
    ↓ user: "review the implementation" or auto-full continues after commit/SHA backfill
[main agent → issue-impl-reviewer]
    impl-review.md v1 — uses commits: field to bound git diff/log
    orchestrator commits schema:
    ├─ status: changes-requested → user: "fix the impl per review" → loop to implementer
    └─ status: accepted ↓
[main agent: per-issue README.md → status: accepted]
    ↓ user: "close issue NNNN" or auto-full closes when gates pass
[orchestrator commits schema: (status flip)]
    if new capability, settled Open Question, or added Active Decision:
      → orchestrator updates docs/specs/system-development.md + docs/specs/hot.md → spec:
```

In `manual` mode, the user controls every stage transition. In `auto-plan` and
`auto-full`, the user grants the top-level orchestrator permission to advance
while gates pass. Subagents never advance themselves, commit, push, or widen
their write boundaries.

### Closeout discipline check

The shared git pre-commit hook runs a closeout-discipline phase when a staged
`issues/NNNN-slug/README.md` frontmatter change flips `status:` to `accepted`.
The gate is limited to accepted-status closes: `abandoned` flips, timeline-only
README edits, and non-README issue artifact edits are not gated.

Before the close-status `schema:` commit can land, the checker validates the
commit snapshot from Git's index. Unchanged tracked files are already present in
the index, staged deletions count as missing evidence, and unstaged working-tree
edits do not count as closeout evidence. It enforces four conditions:

1. `impl-log.md` frontmatter `commits:` is non-empty, every listed SHA resolves,
   and every listed commit subject starts with one allowed scope token:
   `wiki:`, `raw:`, `meta:`, `schema:`, `spec:`, or `init:`.
2. `plan.md` frontmatter `required-activations:` is satisfied using only
   allowlisted declarative checks. The initial supported entry is
   `type: git-config` with `key:` and `equals:`.
3. `required-spec-followup: true` is the default. When true, an issue-specific
   `spec:` commit whose subject names the issue number must already be in
   `HEAD` after the last implementation SHA listed in `impl-log.md`; this means
   the closeout `spec:` commit lands before the accepted-status `schema:`
   commit.
4. Every numbered step under `plan.md` `### Orchestrator-run runtime tests`
   has a matching `impl-log.md` `## Verification Run` table row with the same
   step number, status `PASS`, `FAIL`, or `DEFERRED`, and a non-empty `Actual`
   cell. The runtime heading must exist even when there are zero numbered
   runtime steps.

Emergency bypass remains Git's standard pre-commit bypass:
`git commit --no-verify`. Use it only when the missing closeout evidence is
understood and will be repaired deliberately.

### Quick-start (skip plan review)

User says: `"add feature X — implement directly"`. Planner still writes a minimal `plan.md`, but plan-review is skipped and `plan.md` lands at `status: accepted` immediately. Implementation review is **not** skippable.

### Abandonment

User: `"abandon issue NNNN"` → main agent sets `README.md status: abandoned`, commits. Issue dir stays in place as a record.

---

## Human Triggers

| User says | Main agent does |
|---|---|
| `"add a feature: X"` / `/issue X` | spawn `issue-planner` (new issue) |
| `/issue manual X` | same staged workflow as `/issue X` |
| `/issue auto-plan X` | run planner/reviewer loop until accepted plan or pause gate |
| `/issue auto-full X` | run the full issue lifecycle through closeout when gates pass; never push |
| Codex prompt with `auto-plan` or `auto-full` plus explicit subagent/delegation consent | run the corresponding auto mode |
| Codex prompt with `auto-plan` or `auto-full` but no explicit subagent/delegation consent | ask for consent before spawning subagents |
| `"review the plan for issue NNNN"` | spawn `issue-plan-reviewer` |
| `"fix the plan per review"` | spawn `issue-planner` (revising) |
| `"implement issue NNNN"` | spawn `issue-implementer` |
| `"review the implementation"` | spawn `issue-impl-reviewer` |
| `"fix the impl per review"` | spawn `issue-implementer` (revising) |
| `"close issue NNNN"` | update README status → accepted, commit |
| `"abandon issue NNNN"` | update README status → abandoned, commit |
| `"what's the status of issue NNNN"` | read README.md, summarize |

---

## Commit & Log Strategy

Issue artifacts are workflow scaffolding (`schema:` scope by default). Implementation is the exception — implementer-modified files commit under their natural scope.

### `implement` — the 6th operation

Issue-stage commits use `operation: implement` in `log/` frontmatter. Registered under both `wiki` and `schema` keys in `log-triggers.json`. (`spec:` commits remain silent — no log entry.)

### Commit ordering during implementation

`auto-full` does not change commit ownership. The top-level orchestrator still
runs staging inspection, explicit-path staging, commits, `impl-log.md` SHA
backfill, close status updates, and closeout `spec:` follow-up. Subagents never
commit or push in any mode.

To keep `impl-log.md`'s `commits:` field accurate and `hot-check.ps1` quiet:

1. `wiki:` (if any) — captures SHA-wiki.
2. `spec:` — refreshes `hot.md` (Current Focus: "issue NNNN implementation"), plus any other `docs/specs/` edits. **Required whenever step 1 fired** — `hot-check.ps1` fires post-`wiki:` commit. Skipped only for pure-schema implementations. Captures SHA-spec.
3. `schema:` — `impl-log.md` (with `commits: [SHA-wiki, SHA-spec]` backfilled), issue README, any non-wiki/non-spec files. Log entry filed here. Captures SHA-schema.

### Pre-commit staging discipline

Before **every** issue-stage `git commit` during implementation (i.e. each of the wiki / spec / schema commits in §Commit ordering, not only the first), the orchestrator runs a three-step staging inspection:

1. **Enumerate currently-staged paths** — `git diff --cached --name-only` lists everything currently staged for the next commit. (Use `git status --porcelain` if you want unstaged + staged in one view, but `--cached --name-only` is the strict-staged-only view this check requires.)

2. **Cross-reference against the scope's allowlist** — the implementer's required output report (see §Implementer output report) lists files grouped by scope. Treat the list for the scope you are about to commit (wiki / spec / schema) as the allowlist. Any staged path not on that list is **out-of-scope drift** and must be unstaged before commit.

3. **Unstage out-of-scope paths** — `git restore --staged <path>` for each drift path. Then re-confirm with `git diff --cached --name-only` that only allowlisted paths remain. Stage any missing in-scope paths with explicit-path `git add <path>` — **never `git add .` or `git add -A`** during issue-stage commits, because both sweep in pre-staged drift the procedure just removed.

The procedure applies to **every** issue-stage commit, not only the first — pre-staged drift can accumulate between commits in a multi-step implementation (e.g., a `Write` to `hot.md` between the wiki and spec commits, an the Obsidian workspace file mtime bump from Obsidian autosave). One inspection per commit is the rule.

**Example (taken from Issue 0001's contaminated `meta:` commit `ecba6e7` — counterfactual):**

Plan v4 specified three files for the `meta:` commit: `.obsidian/community-plugins.json`, `.obsidian/plugins/tag-wrangler/manifest.json`, an Obsidian plugin bundle file. The implementer's output report listed these three under "meta files."

Procedure:
```bash
git diff --cached --name-only
# (suppose this prints 14 lines including the 3 allowlisted + 11 drift paths)
git restore --staged Clippings/<file>.md paper/binding/TCRmodel2.pdf server.log tips.md .obsidian/app.json the Obsidian workspace file the local Claude settings file docs/specs/hot.md issues/0001-safe-structural-mutations/README.md issues/0001-safe-structural-mutations/plan.md issues/0001-safe-structural-mutations/plan-review.md
git diff --cached --name-only
# (now prints only the 3 allowlisted paths)
git commit -m "meta: install Tag Wrangler plugin (issue 0001 precondition)"
```

The unstaged drift remains in the working tree, available for staging in its rightful scope during a future user or agent turn. Closeout hooks only warn about that drift. The procedure does not throw work away; it just routes each file to the correct commit.

**Why explicit-path `git add` matters:** `git add .` and `git add -A` both restage everything `git restore --staged` just removed. If the procedure unstages drift and then `git add .` is run, the drift is back. Use `git add <path1> <path2> ...` with the exact allowlist paths from the implementer's output report.

### Commit table

| Stage | What's committed | Scope | Log entry |
|---|---|---|---|
| Open issue + plan v1 | `issues/NNNN-slug/{README,plan}.md` | `schema:` | yes — `operation: implement` |
| Plan revision | `plan.md`, issue README | `schema:` | yes — `operation: implement` |
| Plan review | `plan-review.md`, issue README | `schema:` | yes — `operation: implement` |
| Implementation — wiki phase | `wiki/` files | `wiki:` | none (logged at schema phase) |
| Implementation — spec phase | `docs/specs/` + `hot.md` | `spec:` | no |
| Implementation — schema phase | `impl-log.md` (commits: backfilled), issue README, other schema files | `schema:` | yes — `operation: implement` |
| Impl review | `impl-review.md`, issue README | `schema:` | yes — `operation: implement` |
| Close (status flip) | issue README | `schema:` | optional |
| Close → spec follow-up | `docs/specs/system-development.md` + `hot.md` | `spec:` | no |

A pure-schema implementation collapses the three implementation rows into a single `schema:` commit; `commits:` lists only `[SHA-schema]`.

### Log entry frontmatter

```yaml
---
date: YYYY-MM-DD
operation: implement
source: "[[issues/NNNN-slug/README]]"
pages_created: []    # wiki pages created; empty for schema-only stages
---
```

### Implementer output report

The implementer MUST list files grouped by scope so the orchestrator stages cleanly:

```
## Files modified
- schema files: [...]
- wiki files: [...]
- spec files: [...]
```

---

## Spec follow-up criteria (on close)

A `spec:` follow-up updating `docs/specs/system-development.md` + `docs/specs/hot.md` is required when the issue introduced any of:

- A new agent or operation
- A new convention, hook, or permission entry
- A settled Open Question → Active Decision

Default **no** for routine wiki refactors. Default **yes** for any tooling change.

---

## See Also

- [[docs/agent-runtime]]
- [[CLAUDE.md]]
- [[AGENTS]]
- [[docs/operations]]
- [[docs/git-workflow]]
- [[exp/issue-workflow-plan]]
- [[.claude/agents/issue-planner]]
- [[.claude/agents/issue-plan-reviewer]]
- [[.claude/agents/issue-implementer]]
- [[.claude/agents/issue-impl-reviewer]]
