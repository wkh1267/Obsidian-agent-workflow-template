# Obsidian Agent Workflow Template

Public template for agent-assisted knowledge work in Obsidian. It combines a
starter vault layout, Claude Code and Codex runtime loaders, issue-tracked
workflow changes, Dataview dashboards, and Git hooks for disciplined commits.

The repository root contains release and Git support files. The Obsidian vault
you open and work in is `vault/`.

## Quickstart

Clone the template repository:

```powershell
git clone <repository-url>
Set-Location <repository-folder>
```

Open `vault/` in Obsidian.

Install and enable these Obsidian community plugins:

- Dataview
- PDF Plus
- Tag Wrangler

Optionally activate the Git hooks. Before activating hooks, review `.githooks/`,
`vault/.claude/hooks/`, `vault/.claude/scripts/`, and `vault/.codex/hooks/`:
`install.ps1` enables PowerShell Git hooks that run on this machine during later
Git and agent workflows.

```powershell
pwsh -File .githooks/install.ps1
git config --get core.hooksPath
```

Start using the vault:

- Put source material in `vault/raw/`.
- Build curated knowledge pages in `vault/wiki/`.
- Track workflow changes in `vault/issues/`.
- Read operation history in `vault/log/`.

For agent workflows, start Claude Code or Codex from `vault/` and use natural
language such as:

```text
ingest raw/my-source.md
What do I know about spaced repetition?
lint
implement issue 0001-your-feature
sync
```

## Repository Shape

| Area | Purpose |
|---|---|
| `vault/raw/` | Immutable source inbox for INGEST work |
| `vault/wiki/` | Curated concept, entity, synthesis, and comparison pages |
| `vault/docs/` | Shared runtime rules, operation procedures, and specs |
| `vault/issues/` | Numbered issue workflow artifacts |
| `vault/log/` | One operation log file per durable change |
| `vault/exp/` | Exploration notes, plans, reviews, and test records |
| `vault/.claude/` | Claude commands, agents, hooks, scripts, and skills |
| `vault/.codex/`, `vault/.agents/skills/` | Codex hooks, agents, scripts, and skills |
| `vault/index.md`, `vault/log.md` | Dataview-backed dashboards |
| `.githooks/` | Repository Git hooks that call into the vault workflow scripts |
| `scripts/` | Release and maintenance scripts |

## Agent Runtime

`vault/CLAUDE.md` and `vault/AGENTS.md` are thin loaders. Shared behavior lives
in `vault/docs/agent-runtime.md`, with task-specific procedures in:

- `vault/docs/operations.md`
- `vault/docs/wiki-conventions.md`
- `vault/docs/git-workflow.md`
- `vault/docs/issue-workflow.md`

Claude and Codex use the same operating rules: preserve raw sources, use
Obsidian-aware tools for structural Markdown/Canvas/Base mutations, keep issue
work inside numbered issue directories, stage only explicit paths, and push only
when the user explicitly asks for `sync` or `push`.

## Core Workflows

Common operations are:

- INGEST: turn raw sources into linked wiki pages and a dated operation log.
- QUERY: answer from the existing vault, optionally filing reusable synthesis.
- LINT: audit the wiki for dead links, stale claims, frontmatter gaps, and
  cross-link problems.
- SAVE: preserve a durable insight from the current conversation.
- ISSUE: plan, review, implement, review, and close bounded workflow changes.

`vault/index.md` and `vault/log.md` are Dataview views. They are not manually
maintained; page frontmatter and per-operation log files drive their output.

## Requirements

- Obsidian with Dataview enabled for dashboard views.
- PDF Plus and Tag Wrangler for the documented vault workflows.
- Claude Code or Codex for agent workflows.
- Git and PowerShell for hooks, scripts, and release verification.

## Maintainers

### Update The Public Template Repository

These steps are for maintainers updating an existing public template repository
from the private source vault, not for normal use of a public clone.

The source vault may contain private `raw/`, `wiki/`, `note/`, `paper/`, `log/`,
and `exp/` content. The main release-update workflow exports a sanitized public
tree to a temporary directory, mirrors that tree into an existing public
repository root while preserving `.git`, runs the public tree scan before any
commit, and stops before staging, committing, or pushing:

```powershell
pwsh -File scripts/update-public-template-repo.ps1 -Destination <existing-public-repo> -ConfirmMirror
```

The destination must already be the public template Git repository root, have a
reachable `HEAD`, have a clean work tree, and contain the expected public
template markers. A successful mirror intentionally leaves working-tree changes;
re-running the helper before committing or discarding those changes fails by
design because the clean-worktree precondition protects uncommitted maintainer
work.

The helper's PASS gate is the pre-commit tree scan:

```powershell
pwsh -File scripts/scan-public-tree.ps1 -TreeRoot <existing-public-repo> -AllowRootGit
```

The repository/history scan is the post-commit, pre-push gate. After the helper
passes, inspect, stage explicit paths, commit, then run the repo scan against
the committed result before pushing:

```powershell
git status
git diff
git add <explicit paths>
git commit -m "Update public workflow template export"
pwsh -File scripts/scan-public-repo.ps1 -RepoRoot .
git push   # only if the post-commit repo scan passed
```

Do not push unless the post-commit repository scan passes. From `vault/`, Claude
can run `/release-check` and Codex can run the `release-check` skill; both run
the same public tree and repository scanners against the committed candidate
and are the equivalent post-commit release gate.

Direct clean exports are for disposable reproduction and inspection, not the
main way to update an existing public repository:

```powershell
pwsh -File scripts/export-public-template.ps1 -Destination <scratch-public-export> -Clean
```

Open `<scratch-public-export>/vault` in Obsidian, Claude Code, or Codex. The
generated vault includes empty starter folders for `raw/`, `wiki/`, `log/`, and
`exp/`, plus seed specs under `vault/docs/specs/`. If you initialize a
disposable generated repository, activate hooks only after inspecting the tree:

```powershell
Set-Location <scratch-public-export>
git init
pwsh -File .githooks/install.ps1
git config --get core.hooksPath
```

Do not publish by adding a public remote to the private source vault.

### Public Export Policy

The exporter uses an allowlist for release verification. It does not copy
personal knowledge content, historical operation logs, historical exploration
notes, private issue directories, local workspace state, cache/trash folders,
plugin bundles, per-user settings, or local machine paths.

The generated public vault includes:

- Runtime loaders and workflow docs.
- Claude and Codex agents, hooks, scripts, and skills.
- Issue templates and the issue dashboard.
- Root Git hooks adapted for the nested `vault/` layout.
- A root `.gitignore` for local scratch files plus a vault `.gitignore` for
  Obsidian and agent ephemera.
- Obsidian config files needed to name expected community plugins.
- Seed `docs/specs/` files with no private session history.

Plugin code bundles are intentionally not vendored. Install Dataview, PDF Plus,
and Tag Wrangler through Obsidian after opening the generated vault.

The public export omits the source vault's Claude pre-edit `git pull` hook. Add
pull or sync automation only after deciding how a public clone should handle
remotes and collaboration.

The seed specs are starter state. The first real workflow closeout in a new
vault should update `vault/docs/specs/hot.md` and the relevant spec for that
user's local state.
