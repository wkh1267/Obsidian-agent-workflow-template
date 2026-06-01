---
title: System Development Spec
track: system-development
last_updated: 2026-06-01 (public template seed)
---

# System Development

## Goal

Keep the public workflow template reproducible while each local vault evolves
through documented schema, wiki, and spec changes.

## Current State

This vault starts from the public template baseline: shared runtime docs,
Claude and Codex loaders, copied agents/hooks/scripts/skills, root Git hooks,
and a nested `vault/` directory inside the Git repository root. Generated specs
are starter state only and contain no private source history.

## Active Decisions

- The Git repository root can be outside the Obsidian vault; in the public
  template the vault is `vault/`.
- `docs/agent-runtime.md` is the shared runtime source of truth.
- Claude and Codex loaders stay thin and defer to shared docs.
- Commits use explicit paths and documented scopes.
- `sync` and `push` are manual actions; agents do not auto-publish work.

## Open Questions

N/A for a fresh public template.

## Next Steps

1. Open `vault/` in Obsidian and install the community plugins listed in
   `.obsidian/community-plugins.json`.
2. Run the first local workflow operation.
3. Update this spec and `docs/specs/hot.md` during the first closeout.

## Update Protocol

After schema or workflow changes, update Current State, Active Decisions, Open
Questions, and Next Steps to match the local vault.