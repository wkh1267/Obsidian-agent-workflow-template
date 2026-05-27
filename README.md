# Obsidian Agent Workflow Template

An Obsidian-based workflow template for agent-assisted knowledge work, shared by
Claude Code and Codex through human-readable Markdown state, commands, hooks,
skills, and issue artifacts.

## What This Template Is

This template turns an Obsidian vault into the durable source of truth for
working with coding and knowledge agents. Instead of relying on opaque agent
memory, the vault records source material, curated wiki pages, operating rules,
issue plans, reviews, and operation logs as Markdown files a human can inspect
and edit.

The generated public repository has two layers:

- The repository root contains Git hooks and release-maintenance scripts.
- `vault/` is the Obsidian vault to open in Obsidian, Claude Code, or Codex.

Inside `vault/`, `CLAUDE.md` and `AGENTS.md` are thin loaders. Both point agents
to the shared runtime in `docs/agent-runtime.md` and task procedures in
`docs/operations.md`, `docs/wiki-conventions.md`, `docs/git-workflow.md`, and
`docs/issue-workflow.md`.

## Why Use This Workflow

- **Markdown-first state:** sources, decisions, plans, reviews, and specs stay
  in files instead of hidden chat context.
- **Obsidian as the workbench:** Dataview-backed `index.md` and `log.md` views
  summarize wiki pages and operation history from frontmatter.
- **Cross-agent consistency:** Claude Code and Codex share the same runtime
  rules, issue model, and safety expectations.
- **Bounded agent work:** issue stages hand agents only the relevant issue
  artifacts, and each stage writes reviewable files.
- **Human-controlled automation:** agents can help plan, review, implement, and
  verify, but pushes and high-risk transitions require explicit user intent.

## Quick Start

Clone the public template repository:

```powershell
git clone <repository-url>
Set-Location <repository-folder>
```

Open `vault/` in Obsidian.

Install the community plugins listed in `vault/.obsidian/community-plugins.json`:

- Dataview, for the generated index and log dashboards.
- PDF Plus, for PDF-heavy knowledge workflows.
- Tag Wrangler, for safe tag rename workflows when tag maintenance is needed.

Review the hook scripts before enabling them. The hook installer configures Git
to run PowerShell scripts from this repository during later Git and agent
workflows.

```powershell
pwsh -File .githooks/install.ps1
git config --get core.hooksPath
```

Start Claude Code or Codex from `vault/`, then use natural language or the
documented slash commands. Good first prompts:

```text
ingest raw/my-source.md
What do I know about spaced repetition?
save this as a decision
open an issue for adding a new workflow
review the plan for issue 0001
sync
```

## Vault Organization

| Path | Purpose |
|---|---|
| `vault/raw/` | Immutable source inbox for INGEST work |
| `vault/wiki/` | Curated concept, entity, synthesis, and comparison pages |
| `vault/docs/` | Shared runtime rules, operation procedures, and living specs |
| `vault/issues/` | Numbered issue directories with plans, reviews, and implementation logs |
| `vault/log/` | One operation log file per durable workflow change |
| `vault/exp/` | Exploration notes, test records, and temporary workflow artifacts |
| `vault/index.md` | Dataview-backed knowledge index |
| `vault/log.md` | Dataview-backed operation log dashboard |
| `vault/.claude/` | Claude commands, agents, hooks, scripts, and Obsidian skills |
| `vault/.codex/` | Codex agents, hooks, scripts, and config |
| `vault/.agents/skills/` | Codex-facing vault skills |
| `.githooks/` | Git hooks that call into vault workflow scripts |
| `scripts/` | Public export, mirror, and release-scan scripts |

`raw/` is treated as read-only source material. `wiki/` holds curated knowledge.
`docs/` and `issues/` hold the operating system for the agents. `log/` records
what changed and why.

## Agent Runtime Model

Claude Code and Codex share one runtime:

- `vault/CLAUDE.md` and `vault/AGENTS.md` load the shared rules.
- `vault/docs/agent-runtime.md` defines startup context, safety rules, trigger
  vocabulary, and structural mutation policy.
- `vault/docs/operations.md` defines INGEST, QUERY, LINT, SAVE, ISSUE, RELEASE,
  and push behavior.
- `vault/docs/issue-workflow.md` defines the staged issue pipeline and bounded
  subagent contracts.
- Claude slash commands live in `vault/.claude/commands/`.
- Codex skills live in `vault/.agents/skills/`.
- Claude and Codex issue subagents live in `vault/.claude/agents/` and
  `vault/.codex/agents/`.
- Hooks live in `vault/.claude/`, `vault/.codex/`, and root `.githooks/`.

The intended pattern is simple: the user gives a trigger, the agent reads the
runtime docs for that operation, the agent writes durable Markdown artifacts,
and Git hooks enforce the safety rules that can be checked automatically.

## Human Trigger Vocabulary

The table below summarizes the public trigger surface. Some entries are slash
commands, some are Codex skill triggers, some are Git hook prompts, and some are
natural-language prompts routed by the shared runtime.

| Workflow | Surface | Example trigger | What it does |
|---|---|---|---|
| Ingest source material | Natural language; Codex `vault-ingest` skill | `ingest raw/my-source.md` | Reads raw source material and turns it into linked wiki pages plus logs/spec updates. |
| Batch ingest | Natural language; Codex `vault-ingest` skill | `batch ingest these files` | Processes multiple raw sources, deferring cross-links between batch siblings until the end. |
| Structured inbox ingest | Claude `/ingest-inbox`; Codex `ingest-inbox` skill | `/ingest-inbox` or `run ingest-inbox` | Processes every pending raw source one worker at a time with run-state tracking and a final checkpoint. |
| Query the vault | Natural language | `What do I know about spaced repetition?` | Answers from existing vault knowledge, escalating from quick to deeper reads as needed. |
| Save durable memory | Claude `/save`; natural language; Codex `vault-save` skill | `/save decision Memory architecture` or `save this as a decision` | Files reusable analysis, decisions, comparisons, or concepts into `wiki/` with logs/spec updates. |
| Lint the wiki | Natural language; Codex `vault-lint` skill | `lint the vault` or `audit the wiki` | Checks for orphans, dead links, stale claims, missing frontmatter, missing cross-links, and related wiki health issues. |
| Open an issue | Claude `/issue`; natural language; Codex `vault-issue-workflow` skill | `/issue manual add a workflow` or `open an issue for adding a workflow` | Creates a numbered issue directory and starts the plan stage. |
| Auto-plan an issue | Claude `/issue auto-plan`; Codex natural language with explicit delegation consent | `/issue auto-plan add a workflow` | Runs planning and plan review loops until accepted or a pause gate fires. |
| Auto-full issue flow | Claude `/issue auto-full`; Codex natural language with explicit delegation consent | `/issue auto-full add a workflow` | Runs planning, reviews, implementation, required closeout, and accepted close when gates pass. It never pushes. |
| Advance issue stages | Natural language | `review the plan for issue 0001`; `implement issue 0001`; `review the implementation`; `close issue 0001`; `abandon issue 0001` | Moves a tracked issue through the bounded stage pipeline. |
| Revise issue artifacts | Natural language | `fix the plan per review`; `fix the impl per review` | Sends the issue back to the corresponding planner or implementer after requested changes. |
| Check issue status | Natural language | `what's the status of issue 0001` | Reads the issue README and summarizes current status. |
| Release workflow | Natural language | `export the template`; `preview the export`; `release the public template`; `update the public template` | Runs the documented public-template export or maintainer release workflow. Destructive re-init requires explicit confirmation. |
| Release security gate | Claude `/release-check`; Codex `release-check` skill | `/release-check <repo-root>` or `release-check <repo-root>` | Runs the public tree and repository scanners against a generated release candidate. |
| Push committed work | Exact prompt hook | `sync` or `push` | Pushes already-committed work only. Agents do not push on their own. |

## Core Workflows

### Knowledge Ingestion

Put source files in `vault/raw/` and ask an agent to ingest them. Raw files are
read-only inputs. The agent creates or updates pages under `vault/wiki/`, writes
a dated operation log under `vault/log/`, and refreshes the relevant specs at
closeout.

For many raw sources, use batch ingest or the structured `ingest-inbox`
workflow. The structured inbox workflow keeps mutable run state under
`vault/exp/ingest-inbox-runs/` and runs one `wiki-ingest` worker at a time.

### Query And Retrieval

Ask normal questions about the vault. The runtime starts with the hot cache and
index, then reads relevant pages as needed. If the answer creates reusable
analysis, the workflow can file it as a synthesis page instead of leaving it in
chat only.

### Save And Decision Memory

Use `/save` in Claude or natural language in either agent to preserve durable
thinking. Decision saves use a structured page body with decision, rationale,
rejected alternatives, do-not-repeat guidance, and consequences.

### Lint And Consistency

Ask for `lint`, `audit`, or `health-check` when the wiki needs maintenance. The
lint workflow checks dead links, orphaned pages, stale claims, missing pages,
frontmatter gaps, empty sections, stale index entries, and old seed pages.

### Issue Workflow

Issue work is the core feature for changing the vault or its workflows. A user
opens an issue, the planner writes a plan, the reviewer accepts or requests
changes, the implementer makes scoped edits, and a reviewer checks the
implementation before closeout.

### Release Workflow

Maintainers can export a sanitized public template, mirror it into an existing
public repository, and run tree/history scans before publishing. Normal users do
not need the release workflow to use the vault.

### Git And Sync

Git is deliberately explicit. Agents stage only explicit paths during documented
operations. The exact prompts `sync` and `push` trigger push routing for already
committed work; they are not general-purpose auto-commit commands.

## Issue Workflow Deep Dive

The issue workflow keeps agent work reviewable and bounded. Each issue lives in:

```text
vault/issues/NNNN-slug/
```

Typical artifacts:

| File | Purpose |
|---|---|
| `README.md` | Issue metadata, original idea, acceptance criteria, and timeline |
| `plan.md` | Goal, assumptions, non-goals, success criteria, approach, files, commits, and verification |
| `plan-review.md` | Reviewer verdict and required changes |
| `impl-log.md` | Implementer record of files changed, deviations, verification, and commit placeholders |
| `impl-review.md` | Implementation reviewer verdict |

The stage model is:

1. Open issue.
2. Plan.
3. Review plan.
4. Revise plan if needed.
5. Implement.
6. Review implementation.
7. Revise implementation if needed.
8. Close or abandon.

The orchestrator does not need to carry all context in chat. Durable state lives
in the issue directory. Each subagent reads the issue files, receives bounded
context, writes a reviewable artifact, and returns control. In manual mode the
user advances each stage. In authorized auto modes, the orchestrator may
continue through accepted stages while pause gates pass, but agents still do not
push and do not widen their write scopes.

## Hooks And Safety Gates

Hooks are optional but recommended after review:

- Root `.githooks/pre-commit` invokes the vault pre-commit checks.
- The pre-commit path can bump staged wiki/spec timestamps, lint staged wiki
  links, and enforce issue closeout evidence.
- Claude and Codex shell hooks warn about missing logs or stale hot-cache specs
  after relevant commands.
- Git-add guard hooks block broad staging forms such as `git add .` and
  `git add -A` during normal operations.
- Closeout hooks report uncommitted work; they do not stage or commit it.
- Exact `sync` or `push` prompts route through push scripts and push only
  already-committed work.

Because hooks run local PowerShell scripts, inspect `.githooks/`,
`vault/.claude/hooks/`, `vault/.claude/scripts/`, `vault/.codex/hooks/`, and
`vault/.codex/scripts/` before installing or adapting them.

## Customizing The Template

After cloning:

- Replace the seed specs in `vault/docs/specs/` with state from your own
  operations over time.
- Edit `vault/docs/agent-runtime.md` for shared rules that both agents must
  follow.
- Edit task procedures in `vault/docs/operations.md`,
  `vault/docs/wiki-conventions.md`, `vault/docs/git-workflow.md`, and
  `vault/docs/issue-workflow.md`.
- Adjust Claude commands in `vault/.claude/commands/` and Codex skills in
  `vault/.agents/skills/` only when the trigger behavior actually changes.
- Adapt issue templates under `vault/issues/_template/` before opening many
  project-specific issues.
- Keep raw source material, private wiki content, and local settings out of any
  public template release.

## Maintainers

### Update An Existing Public Template Repository

Use the source-vault helper to export a sanitized tree, mirror it into an
existing public repository, run the pre-commit tree scan, and stop before
staging, committing, or pushing:

```powershell
pwsh -File scripts/update-public-template-repo.ps1 -Destination <existing-public-repo> -ConfirmMirror
```

After the helper passes, inspect the public repository, stage explicit paths,
commit, then run the post-commit repository scan before pushing:

```powershell
pwsh -File scripts/scan-public-repo.ps1 -RepoRoot <existing-public-repo>
```

Claude `/release-check` and the Codex `release-check` skill run the same public
tree and repository scanners against a committed release candidate.

### Preview Or Rebuild A Disposable Export

For inspection or a confirmed one-time rebuild, export to a disposable
destination:

```powershell
pwsh -File scripts/export-public-template.ps1 -Destination <scratch-public-export> -Clean
```

`-Clean` deletes the destination first. Use it only for disposable exports or a
confirmed re-init workflow, not as the normal way to update an existing public
repository.

The exporter copies only the public workflow surface, creates seed specs, keeps
private knowledge content out, omits plugin bundles, and generates empty
starter folders for `raw/`, `wiki/`, `log/`, and `exp/`.

## Security And Privacy Notes

- Review hooks before enabling them; they execute local PowerShell scripts.
- Do not put secrets, personal notes, or non-public source material in a public
  template repository.
- Public export scans are fail-closed for common token patterns, plain email
  addresses, local paths, private remotes, nested `.git` paths, plugin bundles,
  and source-root leaks.
- Plugin code is not vendored into public exports. Install community plugins
  through Obsidian after opening the vault.
- The template is a workflow scaffold. Each new vault should evolve its own
  specs, issues, logs, and wiki content through local operations.
