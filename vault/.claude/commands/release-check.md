---
description: Run the public-template release security gate against a generated release candidate
argument-hint: "(optional path to public repository root)"
---

Run the release security check for a generated public-template repository.

This command is the post-commit, pre-push gate for a public release candidate.
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

Use the first argument as the public repository root when provided. Otherwise,
resolve it from the current vault with:

```powershell
$VaultRoot = (Get-Location).Path
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $RepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $VaultRoot '..'))
}
```

Then run the canonical scripts from the public repository root, tree scan first
and repository scan second:

```powershell
$TreeScript = Join-Path $RepoRoot 'scripts/scan-public-tree.ps1'
$RepoScript = Join-Path $RepoRoot 'scripts/scan-public-repo.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File $TreeScript -TreeRoot $RepoRoot -AllowRootGit
$treeExit = $LASTEXITCODE
powershell -NoProfile -ExecutionPolicy Bypass -File $RepoScript -RepoRoot $RepoRoot
$repoExit = $LASTEXITCODE
```

Report one summary: PASS only when both scripts exit 0; otherwise FAIL and
summarize each script's findings. Do not reimplement scan patterns or policy in
the command response. Do not stage, commit, or push; the maintainer may push
only after this post-commit gate passes.
