# log-check.ps1 — PostToolUse hook on Bash: warns after git commit if a log entry is missing.
# Claude sees the warning in the same turn and can act immediately.
# To extend to new scopes: add one line to log-triggers.json.

# Read hook event from stdin
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
$today        = Get-Date -Format "yyyy-MM-dd"
$triggersFile = Join-Path $VaultRoot '.claude/scripts/log-triggers.json'
if (-not (Test-Path $triggersFile)) { exit 0 }
$triggers = Get-Content $triggersFile -Raw | ConvertFrom-Json

# Parse scope from the latest commit (just made)
$latestMsg     = git log -1 --format="%s" 2>$null
$committedScopes = @()
if ($latestMsg -match "^([\w+]+):") {
    $Matches[1] -split "\+" | ForEach-Object { $committedScopes += $_ }
}
if ($committedScopes.Count -eq 0) { exit 0 }

# Collect today's logged operation values
$loggedOps = @()
Get-ChildItem "log" -Filter "${today}-*.md" -ErrorAction SilentlyContinue | ForEach-Object {
    if ((Get-Content $_.FullName -Raw) -match "(?m)^operation:\s*(.+)$") {
        $loggedOps += $Matches[1].Trim()
    }
}

# Check each triggered scope
$missing = @()
foreach ($prop in $triggers.PSObject.Properties) {
    if ($committedScopes -notcontains $prop.Name) { continue }
    $required = @($prop.Value)
    if (-not ($required | Where-Object { $loggedOps -contains $_ })) {
        $missing += $prop.Name
    }
}

if ($missing.Count -gt 0) {
    $list = $missing -join ", "
    $msg  = "No log entry for [$list] work — create log/${today}-<name>.md"
    Write-Output ('{"systemMessage":"' + $msg + '"}')
}

exit 0
