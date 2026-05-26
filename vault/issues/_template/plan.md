---
issue: NNNN
artifact: plan
revision: 1
status: pending
author: issue-planner
updated: YYYY-MM-DD
# Declarative closeout requirements only; do not put commands here.
# Supported required-activations entries are allowlisted, e.g. type: git-config.
required-activations: []
required-spec-followup: true
---

# Plan v1: <title>

## Goal

## Assumptions

<!-- required; use explicit None or N/A if trivial -->

## Non-goals

<!-- required; use explicit None or N/A if trivial -->

## Success Criteria

<!-- required; use explicit None or N/A if trivial -->

## Context Referenced

<!-- specs read, related code, prior issues -->

## Approach

## Files to Modify

<!-- grouped by commit scope so the orchestrator can stage cleanly -->

- schema files:
- wiki files:
- spec files:

## Commit Boundaries

<!-- commit-by-commit: scope, log entry name, files touched -->

1. `wiki:` — ...
2. `spec:` — hot.md refresh (Current Focus: "issue NNNN implementation") + any spec edits
3. `schema:` — impl-log.md (commits: backfilled), per-issue README, log entry (operation: implement)

## Verification Plan

### Implementer-run predictions

<!-- static inspection checks the implementer records in impl-log.md -->

### Orchestrator-run runtime tests

<!--
Accepted issue closes require this heading to exist, even when there are zero
numbered runtime steps. Numbered steps here must have matching impl-log.md
Verification Run table rows with Step, Status, Actual, and Evidence columns.
-->

## Open Questions for Reviewer
