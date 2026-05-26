$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Stop hook: non-mutating closeout warning for uncommitted work.

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

$statusLines = @(Invoke-GitLines -Arguments @('-C', $RepoRoot, 'status', '--porcelain=v1'))
if ($statusLines.Count -eq 0) { exit 0 }

$paths = @()
foreach ($line in $statusLines) {
    if ($line.Length -lt 4) { continue }
    $paths += $line.Substring(3)
}

$sample = @($paths | Select-Object -First 12)
$suffix = ''
if ($paths.Count -gt $sample.Count) {
    $suffix = " (+$($paths.Count - $sample.Count) more)"
}

$message = "Uncommitted work remains at closeout; Codex will not auto-stage or auto-commit. Commit with explicit paths and scope separation, or leave the files intentionally uncommitted. Paths: $($sample -join ', ')$suffix"
Write-HookMessage -Message $message

exit 0
