$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# PreToolUse hook: block broad staging and commit-all commands.

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

function Write-HookMessage {
    param([string]$Message)
    @{ systemMessage = $Message } | ConvertTo-Json -Compress
}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try {
    $event = $raw | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = Get-CommandText -Event $event
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

$gitPrefix = '\bgit(?:\s+-[A-Za-z]\s+(?:"[^"]+"|''[^'']+''|\S+))*'
$patterns = @(
    "$gitPrefix\s+add\s+-A\b",
    "$gitPrefix\s+add\s+--all\b",
    "$gitPrefix\s+add\s+\.(?:\s|$|;|&|\|)",
    "$gitPrefix\s+commit(?:\s+[^\r\n;|&]*)?\s+(?:-[A-Za-z]*a[A-Za-z]*|--all)\b"
)

foreach ($pattern in $patterns) {
    if ($cmd -match $pattern) {
        $matched = $Matches[0]
        $diagnostic = @"
BLOCKED: '$matched' is forbidden during regular operations.

Reason: broad staging commands sweep in unrelated files such as Obsidian
autosaves, untracked drafts, and local workspace churn.

Fix: stage explicit paths only. See docs/git-workflow.md Pre-commit Staging
Rules and docs/issue-workflow.md Pre-commit staging discipline.
"@
        [Console]::Error.WriteLine($diagnostic)
        Write-HookMessage -Message "Blocked forbidden git staging command '$matched'. Stage explicit paths only; see docs/git-workflow.md."
        exit 2
    }
}

exit 0
