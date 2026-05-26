# Wiki Page Conventions

## Frontmatter (required on all wiki pages)

```yaml
---
title: Page Title
# summary: One-line gist for Grep and Dataview previews. Optional.
type: concept | entity | synthesis | comparison
tags:
  - topic/subtopic
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: seed | developing | mature | evergreen
sources:
  - "[[raw/filename]]"  # wikilink if a raw/ file exists for this source
  - "https://..."       # URL if sourced directly from the web, no raw file
---
```

`summary:` is optional. Use it when a one-line gist helps an agent or Dataview
view decide whether to open the full page; omit it when the title is already
specific enough.

## Typed relations (optional frontmatter)

Typed relation fields add labeled edges while keeping Markdown as the source of
truth. Values must be lists of Obsidian `[[wikilinks]]`, not plain IDs, bare
paths, or generated relation records.

Supported optional fields:

- `supersedes` - older pages or decisions this page replaces.
- `superseded_by` - newer pages or decisions that replace this page.
- `blocked_by` - work that must finish before this page's action can proceed.
- `depends_on` - prerequisite pages, issues, decisions, or concepts.
- `conflicts_with` - pages or decisions that make incompatible claims.
- `related` - useful nearby context that is not a stronger relation.

When a clean inverse exists, add both directions. For example, if page A uses
`supersedes: [[Page B]]`, page B should use `superseded_by: [[Page A]]`.

Example:

```yaml
summary: Markdown remains the memory source of truth; derived stores wait for a measured retrieval problem.
supersedes:
  - "[[Earlier Memory Architecture Decision]]"
conflicts_with:
  - "[[Claude-Mem Adoption Decision]]"
related:
  - "[[wiki/concepts/Cross-Session Context Management]]"
```

## Page types

- **concept** — an idea, framework, theory, domain, or mental model (e.g. `Compound Interest`, `Systems Thinking`)
- **entity** — a person, tool, project, organization, or named thing (e.g. `Andrej Karpathy`, `Obsidian`)
- **synthesis** — a query response, analysis, or discovered connection filed for reuse
- **comparison** — an explicit structured comparison of two or more named things (tools, approaches, implementations); lives in `wiki/synthesis/` with additional frontmatter (see below)

## Type → folder mapping

| `type` | Folder |
|---|---|
| concept | `wiki/concepts/` |
| entity | `wiki/entities/` |
| synthesis | `wiki/synthesis/` |
| comparison | `wiki/synthesis/` |

- Reclassifying a page's `type` (e.g., concept → entity) is a folder move and therefore a structural mutation — must route through `obsidian-cli`, not `Edit`-then-`Bash mv`. See `docs/agent-runtime.md` Structural Mutations.

## Cross-referencing rules

- Always use `[[wikilinks]]` to link to other wiki pages. Never use bare filenames.
- When creating or updating a page, check if related pages exist and add bidirectional context.
- A single ingest operation should touch **10–15 pages**: update existing pages, create new ones.
- Use `#tags` for broad categorization; use wikilinks for specific connections.
- Structural mutations on wiki pages (rename, move, delete, tag rename, heading rename, block-id changes) must use Obsidian-aware tools to preserve the link graph. See [[docs/agent-runtime]] for the full rule and non-wikilink path reference guardrails.

## Writing style

- Write in third-person, encyclopedic style for concepts and entities.
- Write in first-person or analytical style for synthesis pages.
- Be dense and precise — these pages are reference material, not blog posts.
- End each page with a `## See Also` section listing related wikilinks.

## Status values

All wiki pages must include a `status` field:

- **seed** — stub; needs filling. LINT flags `seed` pages older than 30 days.
- **developing** — actively being expanded across recent ingests.
- **mature** — content settled; updates only on substantive new info.
- **evergreen** — reference page; expected to remain stable indefinitely.

Default new pages to `status: developing`.

## Comparison page frontmatter

```yaml
---
title: Page Title
type: comparison
subjects:
  - "[[Page A]]"
  - "[[Page B]]"
dimensions:
  - dimension one
  - dimension two
verdict: one-line conclusion
tags:
  - topic/subtopic
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: developing
sources:
  - "[[raw/filename]]"     # if built from a raw source
  - "[[chat session]]"     # if built from in-conversation thinking (common for /save)
  - "[[wiki/concepts/X]]"  # if synthesized from existing wiki pages
---
```

## Decision page convention

Durable decisions are SAVE `decision` pages. They live in `wiki/synthesis/` as
`type: synthesis`, include `decision` in `tags` alongside topical tags, and may
set `decision-status: active | superseded` when status is worth tracking.
Typed relations such as `supersedes`, `superseded_by`, `conflicts_with`, and
`related` should be used when they make the decision easier to navigate.

Use the full decision body only for choices likely to be re-opened or
re-litigated; routine issue updates do not need this ceremony.

Standard body:

```markdown
## Decision

State the selected course in one or two sentences.

## Rationale

Explain why this option fits the current constraints.

## Rejected Alternatives

List credible alternatives and why they were rejected.

## Do Not Repeat

- Do not <rejected action>; <one-line reason>.

## Consequences

Record expected follow-up work, tradeoffs, or review triggers.
```

`## Do Not Repeat` is the actionable distillation. Write imperative bullets,
and pair each instruction with the reason so future agents can avoid reopening
settled choices.

## Contradiction convention

When a new source disagrees with an existing claim on another page, add a `[!contradiction]` callout on **both** pages:

```markdown
> [!contradiction]
> [[Other Page]] (sourced from [[raw/file]]) claims X; this page asserts Y.
```

Bidirectional contradiction callouts keep disputes findable from either side.

## Page length

Wiki pages should stay under **300 lines**. When a page exceeds the cap, split sub-concepts into their own pages and replace the section with a `## See Also` link. This is a guideline, not a hard rule — use judgment.
