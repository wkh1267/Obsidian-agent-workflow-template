# pre-commit.ps1 - git pre-commit hook orchestrator.
# Three phases: (1) frontmatter auto-bump; (2) dead-link linter;
# (3) issue closeout discipline check.
# Phase 1 mutates and re-stages staged wiki/spec files.
# Phase 2 scans staged wiki files.
# Phase 3 gates staged issue README status flips to accepted.
# Exit 0 = commit proceeds; non-zero = commit aborts with stderr message.
# Bypass: `git commit --no-verify` skips this hook entirely (git built-in).

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Invoke-GitCommand {
    param([Parameter(Mandatory=$true)][string[]]$GitArgs)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git @GitArgs 2>$null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $code
    }
}

$RepoRootHint = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$repoResult = Invoke-GitCommand @("-C", $RepoRootHint, "rev-parse", "--show-toplevel")
if ($repoResult.ExitCode -ne 0 -or $repoResult.Output.Count -eq 0) {
    [Console]::Error.WriteLine("Pre-commit failed: unable to determine repository root.")
    exit 1
}
$RepoRoot = ($repoResult.Output -join "`n").Trim()
$VaultRoot = [System.IO.Path]::GetFullPath($RepoRootHint)
$repoFullForVault = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
))
$vaultFullForPrefix = [System.IO.Path]::GetFullPath($VaultRoot).TrimEnd([char[]]@(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
))
$VaultPathPrefix = ''
if (-not $vaultFullForPrefix.Equals($repoFullForVault, [System.StringComparison]::OrdinalIgnoreCase) -and
    $vaultFullForPrefix.StartsWith($repoFullForVault + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    $VaultPathPrefix = ($vaultFullForPrefix.Substring($repoFullForVault.Length + 1) -replace '\\', '/') + '/'
}

function ConvertTo-VaultRelativePath {
    param([Parameter(Mandatory=$true)][string]$Path)

    $normalized = ($Path -replace '\\', '/').TrimStart('/')
    if ($VaultPathPrefix -ne '' -and $normalized.StartsWith($VaultPathPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $normalized.Substring($VaultPathPrefix.Length)
    }
    return $normalized
}

function Get-StagedMarkdownPaths {
    $result = Invoke-GitCommand @("-C", $RepoRoot, "-c", "core.quotepath=false", "diff", "--cached", "--name-only", "--diff-filter=ACMR")
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) { return @() }

    $paths = @($result.Output) |
        ForEach-Object { ($_ -replace '\\', '/').Trim() } |
        Where-Object { $_ -ne "" -and $_ -like "*.md" }
    return @($paths)
}

function Read-GitObjectText {
    param([Parameter(Mandatory=$true)][string]$ObjectSpec)

    $result = Invoke-GitCommand @("-C", $RepoRoot, "-c", "core.quotepath=false", "show", $ObjectSpec)
    if ($result.ExitCode -ne 0) { return $null }
    if ($result.Output.Count -eq 0) { return "" }
    return ($result.Output -join "`n")
}

function ConvertFrom-YamlScalarText {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return $null }
    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2) {
        $quote = $trimmed.Substring(0, 1)
        if ($quote -eq '"' -or $quote -eq "'") {
            $end = $trimmed.LastIndexOf($quote)
            if ($end -gt 0) {
                return $trimmed.Substring(1, $end - 1)
            }
        }
    }

    $commentStart = $trimmed.IndexOf('#')
    if ($commentStart -ge 0) {
        $trimmed = $trimmed.Substring(0, $commentStart).Trim()
    }
    return $trimmed
}

function Get-FrontmatterStatus {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, "(?s)\A---\s*\r?\n(?<fm>.*?)\r?\n---")
    if (-not $match.Success) { return $null }

    foreach ($line in ($match.Groups["fm"].Value -split "\r?\n")) {
        if ($line -match "^\s*status\s*:\s*(?<value>.*?)\s*$") {
            return ConvertFrom-YamlScalarText $Matches["value"]
        }
    }

    return $null
}

$stagedFiles = @(Get-StagedMarkdownPaths)
if ($stagedFiles.Count -eq 0) { exit 0 }

$today = Get-Date -Format "yyyy-MM-dd"

# --- Phase 1: frontmatter auto-bump ---
# For wiki/**.md: bump `updated:` to today.
# For docs/specs/**.md: bump `last_updated:` to today.
# Byte-preserving I/O via [System.IO.File] so encoding and line endings survive untouched.
$bumpedFiles = @()
foreach ($f in $stagedFiles) {
    $vaultRel = ConvertTo-VaultRelativePath $f
    $isWiki = $vaultRel -like "wiki/*"
    $isSpec = $vaultRel -like "docs/specs/*"
    if (-not ($isWiki -or $isSpec)) { continue }
    $absPath = Join-Path $RepoRoot $f
    if (-not (Test-Path $absPath)) { continue }

    $content = [System.IO.File]::ReadAllText($absPath)
    $field = if ($isSpec) { "last_updated" } else { "updated" }

    # Lenient form: capture date (group 2), preserve any trailing text (group 3).
    # Matches: `updated: 2026-05-05`, `last_updated: 2026-05-12 (context)`, etc.
    $pattern = "(?m)^($field):\s*(\d{4}-\d{2}-\d{2})(.*)$"
    if ($content -notmatch $pattern) { continue }
    $replacement = "`${1}: ${today}`${3}"
    $newContent = [regex]::Replace($content, $pattern, $replacement)

    if ($newContent -ne $content) {
        [System.IO.File]::WriteAllText($absPath, $newContent, [System.Text.UTF8Encoding]::new($false))
        $bumpedFiles += $f
    }
}

if ($bumpedFiles.Count -gt 0) {
    $addArgs = @("-C", $RepoRoot, "add", "--") + $bumpedFiles
    $addResult = Invoke-GitCommand $addArgs
    if ($addResult.ExitCode -ne 0) {
        [Console]::Error.WriteLine("Pre-commit failed: unable to re-stage frontmatter-updated file(s).")
        exit 1
    }
}

# Refresh staged Markdown paths after phase 1 because files may have been rewritten and re-staged.
$stagedFiles = @(Get-StagedMarkdownPaths)
if ($stagedFiles.Count -eq 0) { exit 0 }

# --- Phase 2: dead-link linter ---
# For staged wiki/**.md: scan `[[wikilink]]` and `![[embed]]` in body (frontmatter stripped).
$wikiStaged = @($stagedFiles | Where-Object { (ConvertTo-VaultRelativePath $_) -like "wiki/*" })
if ($wikiStaged.Count -gt 0) {
    # Build vault page index for resolution. SCAN scope is `wiki/**/*.md` only.
    # RESOLVE scope is broader: root-level Markdown, `wiki/**/*.md`, and `docs/**/*.md`
    # excluding `docs/specs/**`. `issues/`, `log/`, `raw/`, `exp/`, `.claude/`,
    # `.codex/`, and `.agents/` are not valid wiki link targets.
    $resolveRoots = @()
    $resolveRoots += Get-ChildItem -Path $VaultRoot -Filter "*.md" -File
    $resolveRoots += Get-ChildItem -Path (Join-Path $VaultRoot "wiki") -Filter "*.md" -Recurse -File
    $docsPath = Join-Path $VaultRoot "docs"
    if (Test-Path $docsPath) {
        $resolveRoots += Get-ChildItem -Path $docsPath -Filter "*.md" -Recurse -File |
            Where-Object { $_.FullName -notmatch '[\\/]docs[\\/]specs[\\/]' }
    }

    $pathIndex = @{}
    $basenameIndex = @{}
    foreach ($vf in $resolveRoots) {
        $rel = ($vf.FullName.Substring($VaultRoot.Length + 1)) -replace '\\', '/' -replace '\.md$', ''
        $pathIndex[$rel] = $true
        $basenameIndex[$vf.BaseName] = $true
    }

    $deadLinks = @()
    $linkPattern = '!?\[\[([^\]\|#]+)(?:#[^\]\|]*)?(?:\|[^\]]+)?\]\]'

    foreach ($wf in $wikiStaged) {
        $absPath = Join-Path $RepoRoot $wf
        if (-not (Test-Path $absPath)) { continue }
        $content = [System.IO.File]::ReadAllText($absPath)

        $bodyText = $content -replace '(?ms)\A---\s*\r?\n.*?^---\s*\r?\n', ''
        $bodyText = $bodyText -replace '(?ms)^(`{3,}|~{3,})[^\r\n]*\r?\n.*?^\1\s*$', ''

        $regexMatches = [regex]::Matches($bodyText, $linkPattern)
        foreach ($m in $regexMatches) {
            $target = $m.Groups[1].Value.Trim()
            if (-not $target) { continue }

            $resolved = $false
            if ($pathIndex.ContainsKey($target)) { $resolved = $true }
            elseif ($basenameIndex.ContainsKey($target)) { $resolved = $true }
            elseif ($pathIndex.ContainsKey("wiki/$target")) { $resolved = $true }

            if (-not $resolved) {
                $deadLinks += [pscustomobject]@{ File = $wf; Link = $m.Value; Target = $target }
            }
        }
    }

    if ($deadLinks.Count -gt 0) {
        [Console]::Error.WriteLine("Pre-commit blocked: $($deadLinks.Count) dead wikilink(s) in staged files:")
        foreach ($d in $deadLinks) {
            [Console]::Error.WriteLine("  $($d.File): $($d.Link)  ->  no page resolves '$($d.Target)'")
        }
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("Fix by either: (a) creating the missing page; (b) correcting the link; (c) converting to an external URL via [label](https://...). To bypass: git commit --no-verify")
        exit 1
    }
}

# --- Phase 3: issue closeout discipline check ---
# Gate only staged per-issue README status flips to accepted. Timeline edits,
# abandoned flips, and non-README issue artifacts are ignored.
$issueReadmes = @($stagedFiles | Where-Object { (ConvertTo-VaultRelativePath $_) -match '^issues/[0-9]{4}-[^/]+/README\.md$' })
foreach ($readme in $issueReadmes) {
    $postImage = Read-GitObjectText ":$readme"
    if ($null -eq $postImage) { continue }

    $preImage = Read-GitObjectText "HEAD:$readme"
    $postStatus = Get-FrontmatterStatus $postImage
    $preStatus = Get-FrontmatterStatus $preImage

    if ($postStatus -eq "accepted" -and $preStatus -ne "accepted") {
        $issueDir = Split-Path -Parent $readme
        $checker = Join-Path $VaultRoot ".claude/hooks/closeout-discipline-check.ps1"
        $psExe = "powershell"
        if (Get-Command pwsh -ErrorAction SilentlyContinue) {
            $psExe = "pwsh"
        }

        & $psExe -NoProfile -ExecutionPolicy Bypass -File $checker -IssueDir $issueDir -ReadmePath $readme
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
}

exit 0
