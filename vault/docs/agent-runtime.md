# Agent Runtime

Shared operating rules for all agents working in this Obsidian vault. `CLAUDE.md`
and `AGENTS.md` are thin loaders; this file is the single source of truth for
cross-agent behavior.

## Startup Context

Agent instructions are layered so each session loads only what the request
needs: thin root loaders (`CLAUDE.md`, `AGENTS.md`) carry agent-specific entry
behavior; this file is the always-read shared runtime SSOT; `docs/specs/hot.md`
plus the relevant spec carry current state; task-specific procedure docs and
long syntax references are read only when the request calls for them. Both root
loaders import or load-first only `docs/agent-runtime.md` — they do not eagerly
load the task-specific procedure docs.

For non-trivial implementation and review work, state assumptions before
settling on a design, call out non-goals, choose the simplest sufficient
change, keep each changed line traceable to the accepted request or plan, and
define verification before declaring the work complete.

Before starting any operation, read context in this order:

1. `docs/specs/hot.md` first. If it answers the request, stop there.
2. `docs/specs/knowledge-ingestion.md` for knowledge work: INGEST, QUERY, LINT,
   SAVE, wiki edits, and source synthesis.
3. `docs/specs/system-development.md` for workflow, tooling, schema, hook,
   skill, agent, loader, or migration work.
4. The task-specific procedure doc for the operation at hand — read on demand
   using the quick map below; do not load every workflow doc up front.

### Read-on-demand quick map

Read the matching doc only when the request calls for it. This is routing
guidance, not a substitute for the procedure docs themselves.

| Trigger / situation | Read on demand |
|---|---|
| INGEST, QUERY, LINT, SAVE, SCHEMA, ISSUE procedure steps | `docs/operations.md` |
| Knowledge work — wiki state, clusters, ingestion context | `docs/specs/knowledge-ingestion.md` |
| Workflow, tooling, schema, hook, skill, agent, loader, migration work | `docs/specs/system-development.md` |
| Tracked issue lifecycle, role boundaries, orchestration modes, closeout gates | `docs/issue-workflow.md` |
| Git staging, commit scopes, validation hooks, push rules | `docs/git-workflow.md` |
| Wiki page schema, types, writing style, cross-linking rules | `docs/wiki-conventions.md` |
| Structural Obsidian rename / move / delete / heading / tag changes | §Structural Mutations below, then the Obsidian-aware CLI skill |

## Vault Architecture

| Layer | Folder | Owner | Rule |
|---|---|---|---|
| Raw sources | `raw/` | Human | Immutable. Agents read but never edit. |
| Wiki | `wiki/` | Agent | Agents create, update, and cross-link curated pages. |
| Log | `log/` | Agent | One file per operation; never edit past entries. |
| Specs | `docs/specs/` | Agent | Living state documents; update after operation closeout. |
| Issues | `issues/` | Shared | Numbered issue dirs (`NNNN-slug/`) for tracked feature work. |
| Exploration | `exp/` | Shared | Plans, reviews, notes, and implementation logs. |
| Docs | `docs/` | Agent | Canonical operating procedures and shared runtime rules. |
| Claude layer | `.claude/` | Claude | Existing Claude commands, hooks, agents, and skills. |
| Codex layer | `.codex/`, `.agents/skills/` | Codex | Codex-native config, hooks, agents, and skills as migration phases add them. |
| Obsidian config | `.obsidian/` | Human/local | Do not modify unless explicitly asked. |
| Root metadata | root | Shared | `index.md` and `log.md` are Dataview views; root loaders route agents. |

The active Obsidian vault is the directory containing these runtime docs. In
this private workspace that vault is also the repository root; public-template
exports place the vault under `<destination>/vault` inside a separate Git root.

## Core Safety Rules

- Treat `raw/` as read-only.
- Do not modify `.obsidian/` config files unless explicitly asked.
- During the Claude-to-Codex migration, do not delete, rename, disable, or
  rewrite `.claude/`, `.claude/settings.json`, the local Claude settings file,
  `.githooks/`, or existing Claude skills unless a later approved phase says so.
- Never push unless the user explicitly requests `sync` or `push`.
- Never use `git add -A`, `git add --all`, `git add .`, `git commit -a`, or
  `git commit --all` during normal operations. Stage explicit paths only.
- Keep `spec:` commits separate from `wiki:` commits.
- Do not use destructive git operations or filesystem deletes unless the user
  explicitly asks and the operation has been scoped.

## Wiki Content Rules

- All wiki pages require YAML frontmatter with `title`, `type`, `tags`,
  `created`, `updated`, `status`, and `sources`.
- Use page types consistently:
  - `concept` in `wiki/concepts/`
  - `entity` in `wiki/entities/`
  - `synthesis` or `comparison` in `wiki/synthesis/`
- Always use Obsidian `[[wikilinks]]`, never bare filenames, for wiki links.
- Notes use Obsidian Markdown: `[[wikilinks]]`, `![[embeds]]`, `#tags`, and
  callouts.
- Cross-link bidirectionally when creating or updating related wiki pages.
- End wiki pages with `## See Also`.
- Keep wiki pages under the 300-line guideline unless splitting would make the
  page less useful.

## Structural Mutations

Structural mutations on Obsidian-tracked files (`.md`, `.canvas`, `.base`) must
use Obsidian-aware tools so the link graph stays intact. The rule applies to
wiki pages and any other Markdown, Canvas, or Base file in the vault.

### Rename, Move, Delete

Use:

```text
obsidian rename file=<name> name=<new>
obsidian move file=<name> to=<path>
obsidian delete file=<name>
```

Never use the `permanent` flag on `obsidian delete`; deletions go to Obsidian's
trash for reversibility.

For operations not exposed by the CLI, use `obsidian eval` with Obsidian's file
manager APIs, for example `app.fileManager.renameFile` or
`app.fileManager.trashFile`. Use `trashFile`, never `app.vault.delete`.

Do not use raw filesystem moves or deletes (`mv`, `rm`, `git mv`,
`Move-Item`, `Remove-Item`) for Obsidian-tracked files.

### Tag Rename

Vault-wide tag rename requires the Tag Wrangler plugin (`pjeby/tag-wrangler`).
The agent escalates to the user, and the user performs the rename from the
Obsidian tag pane. Never use search-and-replace for tag rename; regex over raw
Markdown can corrupt tags inside fenced code blocks, nested tags, frontmatter,
and link fragments.

If Tag Wrangler is not installed, install it only with explicit user approval.

### Heading Rename And Block IDs

For heading rename or block-id changes, use an exposed Obsidian API through
`obsidian eval` if available. Otherwise edit the source heading or block ID, then
search for `![[file#heading]]` and `[[file#^id]]` references and update each one.
Manual search-and-edit is allowed here because the failure mode is a visible
dangling reference on next render.

### Non-Wikilink Path References

Obsidian does not track plain path strings. Before renaming files in `docs/`,
`.claude/`, `.codex/`, `.agents/skills/`, or root loaders, search for references
in:

- Loader files such as `CLAUDE.md` and `AGENTS.md`.
- Script and hook paths in `.claude/**/*.ps1`, `.codex/**/*.ps1`, JSON, and TOML.
- Agent, skill, and command files.
- Prose path mentions in `docs/*.md`, `exp/*.md`, and issue artifacts.
- `.obsidian/` config files, if the user explicitly asked to touch that layer.

### Plain File Edits

Normal file-edit tools are appropriate for content edits inside a file,
frontmatter property changes that do not move the file, creating new pages,
config files (`.json`, `.toml`, `.ps1`, `.gitignore`), and non-Obsidian files.

## Operations And Closeout

Use `docs/operations.md` for operation procedures.

Every operation that changes persistent vault state requires a log entry:

- Path: `log/YYYY-MM-DD-operation-name.md`
- Frontmatter: `date`, `operation`, `source`, and `pages_created`
- Past log entries are immutable.

After an operation, update the relevant spec and `docs/specs/hot.md` when the
operation changes persistent wiki, workflow, tooling, or issue state. Commit
spec updates separately from wiki updates.

## Git Discipline

Follow `docs/git-workflow.md`.

- Inspect candidate changes with `git status --porcelain`.
- Stage only explicit paths that belong to the current scope.
- Verify staged paths with `git diff --cached --name-only`.
- Commit format: `<scope>: <what changed and why>`.
- Valid scopes: `wiki`, `raw`, `meta`, `schema`, `spec`, `init`.
- `spec:` commits include only `docs/specs/` files and are never bundled with
  `wiki:` commits.
- Push only when the user says `sync` or `push`.

## Human Trigger Vocabulary

| User says | Operation |
|---|---|
| `ingest`, `batch ingest`, or a request to process `raw/` files | INGEST |
| A question about existing vault knowledge | QUERY |
| `lint`, `audit`, `health-check`, or repair the wiki | LINT |
| `/save` or a request to preserve in-conversation thinking | SAVE |
| Change workflows, hooks, skills, agents, loaders, or operating docs | SCHEMA |
| `/issue`, open/plan/review/implement/close/abandon an issue | ISSUE |
| `/issue auto-plan`, `/issue auto-full`, or Codex auto-mode prompts with explicit subagent/delegation consent | ISSUE |
| `sync` or `push` | Push committed work only |

## See Also

- [[docs/operations]]
- [[docs/wiki-conventions]]
- [[docs/git-workflow]]
- [[docs/issue-workflow]]
- [[docs/specs/hot]]
- [[docs/specs/knowledge-ingestion]]
- [[docs/specs/system-development]]
