# Git Commit Workflow

Commits happen **during** work, not in a single lump at the end.

## Rules

- Commit after each logical unit of work (e.g. finishing an ingest pass, creating a set of related pages).
- Write descriptive commit messages that say **what changed and why** — not a file count.
- **Never auto-push.** Push only when the user explicitly says `sync` or `push`.
- The Stop hook is a closeout warning only. It reports uncommitted work and never stages or commits.

## Commit message format

```
<scope>: <what changed and why>

<optional bullet list of specifics if helpful>
```

**Scopes:** `wiki`, `raw`, `meta`, `schema`, `spec`, `init`

| Scope | What it covers |
|---|---|
| `wiki` | Pages in `wiki/` — ingest, query, lint edits |
| `schema` | Agent loaders (`CLAUDE.md`, `AGENTS.md`), `docs/`, `issues/` artifacts (plan, reviews, impl-log, issue README), `.claude/`, `.codex/`, `.agents/skills/`, and `exp/` files |
| `spec` | `docs/specs/` — spec updates are always committed separately, never bundled with `wiki` commits |
| `meta` | `index.md`, `log.md`, root-level structure |
| `raw` | Files added to `raw/` |
| `init` | One-time vault initialization |

**Strict separation rule:** a `spec` commit never includes `wiki/` files, and a `wiki` commit never includes `docs/specs/` files. After each operation, commit wiki changes first, then commit spec updates as a separate `spec` commit.

### Pre-commit Staging Rules

Stage only the files that belong in the commit you are about to make. **Never `git add -A`, `git add --all`, or `git add .`** during regular operations — these sweep in unrelated files (Obsidian autosaves, untracked drafts, log output, vault config churn) and produce commits like `5237c34` (2026-05-12, where a `wiki:`-scoped ingest commit silently bundled the Obsidian workspace file, `Clippings/*.md`, three `raw/*.md` files, `server.log`, `tips.md`, and a `note/` rename).

**Required staging pattern:**

1. List candidate files: `git status --porcelain` (shows staged + unstaged + untracked in one view).
2. Identify which files belong in the scope of the current operation (see scope table above). For example:
   - INGEST → `wiki/*.md` + the corresponding `log/YYYY-MM-DD-ingest-*.md` (scope `wiki:`).
   - SAVE → the new wiki page + log entry (scope `wiki:`).
   - LINT → fixed wiki pages + the lint log entry (scope `wiki:`).
   - QUERY → any new synthesis page + the query log entry (scope `wiki:`).
   - Spec updates (`docs/specs/*.md` + `hot.md`) always commit separately as `spec:`.
3. Stage each file by explicit path: `git add wiki/foo.md log/2026-05-12-ingest-foo.md` — **never** with `-A`, `--all`, or `.`.
4. Run `git diff --cached --name-only` to confirm only the intended paths are staged.
5. Commit with the matching scope.

**Also forbidden during regular operations:** `git commit -a` and `git commit --all`, which auto-stage all modified tracked files (the same failure mode as `git add -A` via a different command shape).

**Enforcement:** the `Bash(git add ...)` PreToolUse hook (`.claude/scripts/git-add-guard.ps1`) blocks the forbidden argument shapes automatically — see `.claude/settings.json`. If the hook fires, switch to the explicit-path form above.

**Exceptions:** the rule applies to regular operation commits and has no Stop-hook carve-out. It does **not** apply to:
- One-time vault initialization (`scope: init`).
- Issue-stage implementation commits — those follow the stricter procedure in `docs/issue-workflow.md` §Pre-commit staging discipline (which already forbids `-A`/`.` for its own reasons).

Prefer file-level paths (`git add wiki/foo.md`) over directory-level (`git add wiki/`) unless you have verified every file in the directory belongs in the scope of the current operation.

### Pre-commit Content Validation

A git pre-commit hook at `.githooks/pre-commit` runs automated checks on every `git commit`:

1. **Frontmatter auto-bump** — for each staged `wiki/**/*.md` and `docs/specs/**/*.md` file, sets `updated:` (wiki) or `last_updated:` (specs) to today's ISO date and re-stages the file. The agent is not responsible for remembering to bump timestamps on edit. Any trailing text on the same line (parenthetical context, em-dash prose, or both) is preserved verbatim — only the date portion is rewritten.

2. **Dead-link linter** — for each staged `wiki/**/*.md` file, scans `[[wikilinks]]` and `![[embeds]]` in body text (frontmatter is excluded — `sources: ["[[raw/...]]"]` entries are structured, not body prose) and aborts the commit if any link resolves to no file in the vault. The *scan* scope (files read) is `wiki/**/*.md` only; the *resolve* scope (valid link targets) is broader — root-level Markdown files such as `index.md`, `log.md`, `CLAUDE.md`, and `AGENTS.md`, plus the `wiki/**/*.md` tree plus `docs/**/*.md` (excluding `docs/specs/**`). Wiki pages may therefore link to `[[index]]`, `[[log]]`, `[[CLAUDE]]`, `[[AGENTS]]`, or `[[docs/operations]]` and resolve cleanly. Excluded from the resolve index: `issues/`, `log/`, `raw/`, `exp/`, `.claude/`, `.codex/`, `.agents/`, `docs/specs/`. Resolves shortlinks (`[[Claude Code]]`), full-path links (`[[wiki/entities/Nous Research]]`), and alias forms (`[[wiki/entities/X|X]]`). Fenced code blocks are excluded from the scan; `docs/`, `issues/`, and `log/` files are exempt from being scanned (different wikilink conventions).

3. **Closeout discipline check** - for staged `issues/NNNN-slug/README.md`
   flips to `status: accepted`, verifies issue closeout evidence before the
   close-status `schema:` commit lands. The rule details live in
   `docs/issue-workflow.md` "Closeout discipline check".

All phases share the orchestration script `.claude/hooks/pre-commit.ps1` and
run in order: bump, lint, then closeout discipline.

**Activation:** the hook is committed to the repo at `.githooks/pre-commit`. To activate on this clone, run once:

    git config core.hooksPath .githooks

Or run the setup script: `pwsh -File .githooks/install.ps1` (or `powershell -File .githooks/install.ps1` on bare Windows without PowerShell Core).

**Bypass:** for emergencies (e.g., committing a known-dead link with a follow-up fix), use:

    git commit --no-verify

This skips the pre-commit hook entirely. Use sparingly — the LINT operation (`docs/operations.md` §LINT) is the broader fallback for catching content issues.

**Interaction with closeout checks:** Claude and Codex closeout hooks do not call `git commit`, so they do not invoke pre-commit validation. Pre-commit validation runs only on explicit commits.

**Good examples:**
```
wiki: ingest scaffolding post — agent scaffolding, rigor relocation, first-pass acceptance rate
spec: update knowledge-ingestion after scaffolding ingest — 22 pages, AI/agents cluster added
schema: move shared agent rules into docs/agent-runtime
meta: initialize second brain folder structure and index/log
```

**Bad examples:**
```
vault: update 11 files        ← meaningless
vault: update settings        ← no context
adding files                  ← no scope, no meaning
```

## exp/ and issues/ filename conventions

Exploration files in `exp/` use `<topic-slug>-<artifact-type>.md`. Types: `comparison`, `plan`, `review`, `fixups`, `notes`, `proposal`. Commit scope: `schema:`.

Issue directories in `issues/` use `NNNN-feature-slug/` (zero-padded sequential number + kebab-case slug). Issue artifacts (`plan.md`, `plan-review.md`, `impl-log.md`, `impl-review.md`, per-issue `README.md`) commit under `schema:`. Implementation work — the actual repo file changes an issue drives — commits under the natural scope of the files touched (`wiki:`, `spec:`, or `schema:`).

**Issue implementation commit order** (preserves `impl-log.md` SHA accuracy and satisfies `hot-check.ps1`):
1. `wiki:` first (if any wiki/ files changed)
2. `spec:` second (hot.md refresh + any docs/specs/ edits; required whenever step 1 fired)
3. `schema:` last (impl-log.md with `commits:` backfilled + issue README + other schema files; log entry filed here, `operation: implement`)

`auto-full` issue runs use the same orchestrator-owned commit order. Subagents
do not stage, commit, push, or backfill SHAs in any mode.

See `docs/issue-workflow.md` §Pre-commit staging discipline for the per-commit staging inspection orchestrators must run before each of these three commits.

## Push workflow

User types `sync` or `push` → `git-push.ps1` runs → pushes all committed work to GitHub.
This is the only way commits reach the remote.
