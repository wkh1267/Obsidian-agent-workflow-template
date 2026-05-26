$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# PreToolUse hook: non-mutating replacement for Claude's pre-edit git pull.

$VaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $RepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $RepoRoot = $VaultRoot
}

function Write-HookMessage {
    param([string]$Message)
    @{ systemMessage = $Message } | ConvertTo-Json -Compress
}

$raw = [Console]::In.ReadToEnd()

function Invoke-GitLines {
    param([string[]]$Arguments)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& git @Arguments 2>$null)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) { return @() }
    return $lines
}

$statusLines = @(Invoke-GitLines -Arguments @('-C', $RepoRoot, 'status', '--porcelain=v1', '--branch'))
if ($statusLines.Count -eq 0) { exit 0 }

$branchLine = [string]$statusLines[0]
$staged = @($statusLines | Select-Object -Skip 1 | Where-Object {
    $_.Length -ge 2 -and $_[0] -ne ' ' -and $_[0] -ne '?'
})

$messages = @()
if ($branchLine -match '\[.*behind') {
    $messages += 'Local branch is behind its upstream according to local git status; review before editing.'
}
if ($branchLine -match '\[.*diverged') {
    $messages += 'Local branch appears diverged according to local git status; review before editing.'
}
if ($staged.Count -gt 0) {
    $messages += "There are $($staged.Count) staged path(s) before this edit; verify they belong to the next explicit-path commit."
}

if ($messages.Count -gt 0) {
    Write-HookMessage -Message ($messages -join ' ')
}

exit 0
