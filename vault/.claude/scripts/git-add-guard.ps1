# git-add-guard.ps1 — PreToolUse hook on Bash: blocks bulk-staging commands.
# Fires before Claude's `git add -A`, `git add .`, `git add --all`, `git commit -a`,
# or `git commit --all` runs. Exits 2 to deny the tool call (PreToolUse contract).

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $event = $raw | ConvertFrom-Json } catch { exit 0 }

$cmd = $event.tool_input.command
if (-not $cmd) { exit 0 }

# Forbidden patterns
$patterns = @(
    '\bgit\s+add\s+-A\b',
    '\bgit\s+add\s+--all\b',
    '\bgit\s+add\s+\.(?:\s|$|;|&|\|)',
    '\bgit\s+commit\s+(-a\b|--all\b|-[a-zA-Z]*a[a-zA-Z]*\b)'
)

foreach ($p in $patterns) {
    if ($cmd -match $p) {
        $matched = $Matches[0]
        $msg = @"
BLOCKED: '$matched' is forbidden during regular operations.

Reason: bulk-staging commands sweep in unrelated files (Obsidian autosaves, untracked drafts, vault config churn). See `docs/git-workflow.md` §Pre-commit Staging Rules and the Hermes Agent ingest contamination (commit 5237c34, 2026-05-12).

Fix: stage by explicit path. Examples:
  git add wiki/foo.md log/2026-05-12-ingest-foo.md
  git add docs/specs/hot.md docs/specs/knowledge-ingestion.md

For issue-stage commits, follow `docs/issue-workflow.md` §Pre-commit staging discipline (which adds an unstage-drift step before the explicit re-stage).

Closeout: the Stop hook is now non-mutating (`.claude/scripts/closeout-check.ps1`) and receives no bulk-staging exemption. Tracked by issue 0009.
"@
        Write-Error $msg
        exit 2  # PreToolUse exit-2: deny the tool call, surface stderr to Claude.
    }
}

exit 0
