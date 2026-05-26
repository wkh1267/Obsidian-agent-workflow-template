$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# UserPromptSubmit hook: route exact prompt commands without staging or committing.

$VaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $RepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $RepoRoot = $VaultRoot
}

function Get-PromptText {
    param($Event)

    if ($null -eq $Event) { return $null }
    foreach ($name in @('prompt', 'user_prompt', 'input', 'message')) {
        if ($Event.PSObject.Properties.Name -contains $name) {
            $value = $Event.$name
            if ($null -eq $value) { continue }
            if ($value -is [string]) { return $value }
            if ($value.PSObject.Properties.Name -contains 'content') {
                return [string]$value.content
            }
        }
    }
    if ($Event.PSObject.Properties.Name -contains 'tool_input') {
        $toolInput = $Event.tool_input
        if ($null -ne $toolInput -and $toolInput.PSObject.Properties.Name -contains 'prompt') {
            return [string]$toolInput.prompt
        }
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

$prompt = Get-PromptText -Event $event
if ([string]::IsNullOrWhiteSpace($prompt)) { exit 0 }

$normalized = $prompt.Trim()
if ($normalized -notmatch '^(?i:sync|push)$') { exit 0 }

$pushScript = Join-Path $VaultRoot '.codex/scripts/git-push.ps1'
if (Test-Path -LiteralPath $pushScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $pushScript
    exit $LASTEXITCODE
}

Write-HookMessage -Message "Codex push routing recognized '$normalized', but .codex/scripts/git-push.ps1 is not available. No files were staged, committed, or pushed."
exit 0
