# Commit and push Claude Code session changes following AI commit best practices.
# Runs automatically via the Stop hook after each Claude Code session.

$VaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $RepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $RepoRoot = $VaultRoot
}
Set-Location $RepoRoot

# Stage all changes
git add -A

# Exit silently if nothing to commit
$staged = git diff --cached --name-only 2>$null
if (-not $staged) { exit 0 }

# Build subject line from changed files
$files = $staged -split "`n" | Where-Object { $_ -ne "" }
$count = $files.Count

if ($count -le 3) {
    $names = ($files | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) }) -join ", "
    $subject = "vault: update $names"
} else {
    $subject = "vault: update $count files"
}

# Commit message: subject + AI attribution body + machine-readable Git trailers
$date = Get-Date -Format "yyyy-MM-dd"
$message = @"
$subject
"@

git commit -m $message
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

git push
