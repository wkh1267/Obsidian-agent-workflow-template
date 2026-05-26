$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Push only already-committed work. This script never stages or commits files.

$VaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $DefaultRepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $DefaultRepoRoot = $VaultRoot
}
$RepoRoot = if ([string]::IsNullOrWhiteSpace($env:CODEX_PUSH_REPO_ROOT)) {
    $DefaultRepoRoot
} else {
    $env:CODEX_PUSH_REPO_ROOT
}
$DryRun = ($env:CODEX_PUSH_DRY_RUN -eq '1')

function Write-HookMessage {
    param([string]$Message)
    @{ systemMessage = $Message } | ConvertTo-Json -Compress
}

function Invoke-Git {
    param(
        [string[]]$Arguments,
        [switch]$CaptureError
    )

    $gitArgs = @('-C', $RepoRoot, '-c', 'core.quotepath=false') + $Arguments
    $previousPreference = $ErrorActionPreference
    $previousPrompt = $env:GIT_TERMINAL_PROMPT
    $ErrorActionPreference = 'Continue'
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        if ($CaptureError) {
            $output = @(& git @gitArgs 2>&1)
        } else {
            $output = @(& git @gitArgs 2>$null)
        }
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previousPrompt) {
            Remove-Item Env:\GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
        } else {
            $env:GIT_TERMINAL_PROMPT = $previousPrompt
        }
        $ErrorActionPreference = $previousPreference
    }

    $lines = @($output | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
    [pscustomobject]@{
        ExitCode = $exitCode
        Lines = $lines
    }
}

function Join-Lines {
    param([string[]]$Lines, [int]$Limit = 12)

    if ($Lines.Count -eq 0) { return '' }
    $sample = @($Lines | Select-Object -First $Limit)
    $suffix = ''
    if ($Lines.Count -gt $sample.Count) {
        $suffix = " (+$($Lines.Count - $sample.Count) more line(s))"
    }
    return "$($sample -join ' | ')$suffix"
}

function Get-UncommittedSummary {
    $status = Invoke-Git -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    if ($status.ExitCode -ne 0 -or $status.Lines.Count -eq 0) { return '' }

    $paths = @()
    foreach ($line in $status.Lines) {
        if ($line.Length -lt 4) { continue }
        $paths += $line.Substring(3)
    }

    $sample = @($paths | Select-Object -First 8)
    $suffix = ''
    if ($paths.Count -gt $sample.Count) {
        $suffix = " (+$($paths.Count - $sample.Count) more)"
    }

    return "Warning: $($paths.Count) uncommitted path(s) were not staged or committed: $($sample -join ', ')$suffix."
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    Write-HookMessage -Message "Cannot push: repository root does not exist: $RepoRoot"
    exit 1
}

$inside = Invoke-Git -Arguments @('rev-parse', '--is-inside-work-tree')
if ($inside.ExitCode -ne 0 -or ($inside.Lines | Select-Object -First 1) -ne 'true') {
    Write-HookMessage -Message "Cannot push: $RepoRoot is not a Git worktree."
    exit 1
}

$messages = @()
$uncommittedSummary = Get-UncommittedSummary
if (-not [string]::IsNullOrWhiteSpace($uncommittedSummary)) {
    $messages += $uncommittedSummary
}

$branch = Invoke-Git -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD')
$branchName = ($branch.Lines | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($branchName)) {
    $messages += "Cannot push: detached HEAD has no branch upstream. No files were staged or committed."
    Write-HookMessage -Message ($messages -join ' ')
    exit 1
}

$upstream = Invoke-Git -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
if ($upstream.ExitCode -ne 0 -or $upstream.Lines.Count -eq 0) {
    $messages += "Cannot push: $branchName has no configured upstream. No files were staged or committed."
    Write-HookMessage -Message ($messages -join ' ')
    exit 1
}

$upstreamName = ($upstream.Lines | Select-Object -First 1)
$remote = Invoke-Git -Arguments @('config', '--get', "branch.$branchName.remote")
$mergeRef = Invoke-Git -Arguments @('config', '--get', "branch.$branchName.merge")
if ($remote.ExitCode -ne 0 -or $remote.Lines.Count -eq 0 -or
    $mergeRef.ExitCode -ne 0 -or $mergeRef.Lines.Count -eq 0) {
    $messages += "Cannot push: $branchName upstream configuration is incomplete. No files were staged or committed."
    Write-HookMessage -Message ($messages -join ' ')
    exit 1
}

$remoteName = ($remote.Lines | Select-Object -First 1)
$mergeRefName = ($mergeRef.Lines | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($remoteName) -or
    [string]::IsNullOrWhiteSpace($mergeRefName) -or
    $mergeRefName -notmatch '^refs/heads/') {
    $messages += "Cannot push: $branchName upstream target is not a branch ref. No files were staged or committed."
    Write-HookMessage -Message ($messages -join ' ')
    exit 1
}

$ahead = Invoke-Git -Arguments @('rev-list', '--count', "$upstreamName..HEAD")
if ($ahead.ExitCode -ne 0 -or $ahead.Lines.Count -eq 0) {
    $detail = Join-Lines -Lines $ahead.Lines
    $messages += "Cannot determine commits to push for $branchName against $upstreamName. $detail"
    Write-HookMessage -Message (($messages -join ' ').Trim())
    exit 1
}

$aheadCount = [int]($ahead.Lines | Select-Object -First 1)
if ($aheadCount -eq 0) {
    $messages += "Nothing to push; $branchName is up to date with $upstreamName."
    Write-HookMessage -Message ($messages -join ' ')
    exit 0
}

if ($DryRun) {
    $messages += "Dry run: would push $aheadCount committed change(s) from $branchName to $remoteName HEAD:$mergeRefName. No files were staged or committed."
    Write-HookMessage -Message ($messages -join ' ')
    exit 0
}

$push = Invoke-Git -Arguments @('push', $remoteName, "HEAD:$mergeRefName") -CaptureError
if ($push.ExitCode -eq 0) {
    $detail = Join-Lines -Lines $push.Lines
    $success = "Pushed $aheadCount committed change(s) from $branchName to $remoteName HEAD:$mergeRefName. No files were staged or committed."
    if (-not [string]::IsNullOrWhiteSpace($detail)) {
        $success = "$success Git output: $detail"
    }
    $messages += $success
    Write-HookMessage -Message ($messages -join ' ')
    exit 0
}

$failureDetail = Join-Lines -Lines $push.Lines
$messages += "Push failed for $branchName to $remoteName HEAD:$mergeRefName with exit code $($push.ExitCode). No files were staged or committed. $failureDetail"
Write-HookMessage -Message (($messages -join ' ').Trim())
exit $push.ExitCode
