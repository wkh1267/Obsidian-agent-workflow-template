---
name: release-check
description: Use when the user asks to run the public-template release security check, verify a generated public release candidate, or perform the final release gate before publishing. Do not use for ordinary vault linting, issue implementation, or git commits.
---

# Release Check

Run the public-template release security gate against a generated public
repository candidate. The scan policy lives only in the root scripts; this skill
must not reimplement patterns or make release decisions from ad hoc searches.

This skill is the post-commit, pre-push gate for a public release candidate.
For the maintainer export + mirror workflow that updates an existing public
repository and runs only the pre-commit tree scan, use
the source-vault copy of `scripts/update-public-template-repo.ps1` from the
private source vault:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update-public-template-repo.ps1 -Destination <existing-public-repo> -ConfirmMirror
```

That helper derives its source root from its own `scripts/` location and treats
`-Destination` as the existing public repository root. Do not run the public
repository's copied helper against the same public repository as its
destination.

## Resolve Root

If the user provides a path, treat it as the public repository root. Otherwise,
resolve the root from the current nested vault:

```powershell
$VaultRoot = (Get-Location).Path
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $RepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $VaultRoot '..'))
}
```

## Run Gate

Run the tree scanner first and the repository scanner second:

```powershell
$TreeScript = Join-Path $RepoRoot 'scripts/scan-public-tree.ps1'
$RepoScript = Join-Path $RepoRoot 'scripts/scan-public-repo.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File $TreeScript -TreeRoot $RepoRoot -AllowRootGit
$treeExit = $LASTEXITCODE
powershell -NoProfile -ExecutionPolicy Bypass -File $RepoScript -RepoRoot $RepoRoot
$repoExit = $LASTEXITCODE
```

Report PASS only if both scripts exit 0. On failure, summarize the findings
printed by the scripts and stop without committing, pushing, rewriting history,
or editing the candidate tree. The maintainer may push only after this
post-commit gate passes.
