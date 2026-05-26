$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# PostToolUse hook: warn after durable-state commits if docs/specs/hot.md is stale.

$VaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $RepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $RepoRoot = $VaultRoot
}

function Get-CommandText {
    param($Event)

    if ($null -eq $Event) { return $null }
    if ($Event.PSObject.Properties.Name -contains 'tool_input') {
        $toolInput = $Event.tool_input
        if ($null -ne $toolInput -and $toolInput.PSObject.Properties.Name -contains 'command') {
            return [string]$toolInput.command
        }
    }
    if ($Event.PSObject.Properties.Name -contains 'arguments') {
        $arguments = $Event.arguments
        if ($null -ne $arguments -and $arguments.PSObject.Properties.Name -contains 'command') {
            return [string]$arguments.command
        }
    }
    if ($Event.PSObject.Properties.Name -contains 'command') {
        return [string]$Event.command
    }
    return $null
}

function Get-ExitCode {
    param($Event)

    foreach ($name in @('tool_response', 'result', 'response')) {
        if ($Event.PSObject.Properties.Name -notcontains $name) { continue }
        $container = $Event.$name
        if ($null -ne $container -and $container.PSObject.Properties.Name -contains 'exit_code') {
            return $container.exit_code
        }
    }
    if ($Event.PSObject.Properties.Name -contains 'exit_code') { return $Event.exit_code }
    return $null
}

function Test-GitCommitCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    $gitPrefix = '\bgit(?:\s+-[A-Za-z]\s+(?:"[^"]+"|''[^'']+''|\S+))*'
    return ($Command -match "$gitPrefix\s+commit\b")
}

function Write-HookMessage {
    param([string]$Message)
    @{ systemMessage = $Message } | ConvertTo-Json -Compress
}

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

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try {
    $event = $raw | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = Get-CommandText -Event $event
if (-not (Test-GitCommitCommand -Command $cmd)) { exit 0 }

$exitCode = Get-ExitCode -Event $event
if ($null -ne $exitCode -and [int]$exitCode -ne 0) { exit 0 }

$latestMsg = (Invoke-GitLines -Arguments @('-C', $RepoRoot, 'log', '-1', '--format=%s') | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($latestMsg) -or $latestMsg -notmatch '^([\w+]+):') {
    exit 0
}

$committedScopes = @($Matches[1] -split '\+')
$enforcedScopes = @('wiki', 'spec')
if (-not ($committedScopes | Where-Object { $enforcedScopes -contains $_ })) {
    exit 0
}

$hotPath = Join-Path $VaultRoot 'docs/specs/hot.md'
if (-not (Test-Path -LiteralPath $hotPath)) { exit 0 }

$mtime = (Get-Item -LiteralPath $hotPath).LastWriteTime
$staleAfter = (Get-Date).AddMinutes(-30)
if ($mtime -lt $staleAfter) {
    Write-HookMessage -Message "Hot cache stale: docs/specs/hot.md last updated $mtime. Update hot.md and commit it with scope spec before ending the turn."
}

exit 0
