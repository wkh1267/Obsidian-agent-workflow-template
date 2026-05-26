# hot-check.ps1 — PostToolUse hook on Bash: warns after a vault-state git commit
# if docs/specs/hot.md hasn't been touched recently. Modeled on log-check.ps1 —
# same stdin/JSON contract, same post-commit `git log -1` parse, same exit-0 paths.

# Read hook event from stdin (matches log-check.ps1)
$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $event = $raw | ConvertFrom-Json } catch { exit 0 }

# Only act on git commit calls
if ($event.tool_input.command -notmatch "git\s+commit") { exit 0 }

$VaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $RepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $RepoRoot = $VaultRoot
}
Set-Location $VaultRoot

# Parse scope from the latest commit (just made)
$latestMsg = git log -1 --format="%s" 2>$null
if ($latestMsg -notmatch "^([\w+]+):") { exit 0 }
$committedScopes = $Matches[1] -split "\+"

# Enforce only on scopes that change durable vault state.
# - schema: pure tooling (settings, scripts) — no vault-state change
# - meta:   index.md / log.md are Dataview views; auto-derived, no manual context
# - raw:    immutable inputs; not relevant to session-bridge cache
# - init:   one-time bootstrap
$enforced = @('wiki', 'spec')
if (-not ($committedScopes | Where-Object { $enforced -contains $_ })) { exit 0 }

$hot = "docs/specs/hot.md"
if (-not (Test-Path $hot)) { exit 0 }    # bootstrap-safe: silent no-op until hot.md exists

$mtime = (Get-Item $hot).LastWriteTime
$staleAfter = (Get-Date).AddMinutes(-30)
if ($mtime -lt $staleAfter) {
    $msg = "Hot cache stale: docs/specs/hot.md last updated $mtime. Before ending the turn, update hot.md (Current Focus, Recent Changes, Pending Threads, last_updated) and commit it with scope spec."
    Write-Output ('{"systemMessage":"' + $msg + '"}')
}

exit 0
