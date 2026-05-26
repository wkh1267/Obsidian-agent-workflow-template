# Push committed changes to remote.
# Triggered when user types "sync" or "push".
# Does NOT auto-commit — warns about uncommitted files instead.

$VaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $RepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $RepoRoot = $VaultRoot
}
Set-Location $RepoRoot

# Report uncommitted files without staging them
$modified  = (git diff --name-only 2>$null) -split "`n" | Where-Object { $_ -ne "" }
$untracked = (git ls-files --others --exclude-standard 2>$null) -split "`n" | Where-Object { $_ -ne "" }
$uncommitted = @($modified) + @($untracked) | Where-Object { $_ -ne "" }

if ($uncommitted.Count -gt 0) {
    Write-Host "Warning: $($uncommitted.Count) uncommitted file(s) not included in push:"
    $uncommitted | ForEach-Object { Write-Host "  - $_" }
}

# Push only pre-committed work
$ahead = git rev-list --count origin/main..HEAD 2>$null
if ($ahead -eq "0" -or -not $ahead) {
    Write-Host "Nothing to push — already up to date."
    exit 0
}

Write-Host "Pushing $ahead commit(s) to origin/main..."
git push
exit $LASTEXITCODE
