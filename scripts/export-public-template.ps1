[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot '..'))
$PublicScanLibrary = Join-Path $ScriptRoot 'lib/public-scan.ps1'
if (-not (Test-Path -LiteralPath $PublicScanLibrary -PathType Leaf)) {
    throw "Missing public scan library: $PublicScanLibrary"
}
. $PublicScanLibrary

function Normalize-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ))
}

function ConvertTo-SlashPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ($Path -replace '\\', '/')
}

function Test-SameOrChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $full = Normalize-FullPath $Path
    $parentFull = Normalize-FullPath $Parent
    if ($full.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    return $full.StartsWith($parentFull + $separator, [System.StringComparison]::OrdinalIgnoreCase)
}

function Join-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $nativeRel = $RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
    return Join-Path $Root $nativeRel
}

function Get-ChildRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ChildPath
    )

    $base = Normalize-FullPath $BasePath
    $child = [System.IO.Path]::GetFullPath($ChildPath)
    return ($child.Substring($base.Length).TrimStart([char[]]@('\', '/')) -replace '\\', '/')
}

function New-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Read-Text {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    New-Directory (Split-Path -Parent $Path)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Replace-Regex {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement
    )

    return [regex]::Replace($Text, $Pattern, { param($Match) $Replacement })
}

function Assert-SafeDestination {
    param([Parameter(Mandatory = $true)][string]$DestinationPath)

    if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        throw 'Destination must not be empty.'
    }

    $full = Normalize-FullPath $DestinationPath
    $root = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "Destination is not an absolute or resolvable path: $DestinationPath"
    }

    if ($full.Equals((Normalize-FullPath $root), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing root-like destination: $full"
    }

    if (Test-SameOrChildPath -Path $full -Parent $SourceRoot) {
        throw "Refusing destination inside the private source vault: $full"
    }

    $highRisk = @(
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($risk in $highRisk) {
        if (Test-SameOrChildPath -Path $full -Parent $risk) {
            throw "Refusing high-risk system destination: $full"
        }
    }
}

function Get-LayoutSnippet {
    return @'
$VaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRootResult = @(& git -C $VaultRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repoRootResult.Count -gt 0) {
    $RepoRoot = ($repoRootResult -join "`n").Trim()
} else {
    $RepoRoot = $VaultRoot
}
'@
}

function Get-DefaultRepoRootSnippet {
    return @'
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
'@
}

function Remove-CodexProjectBlocks {
    param([Parameter(Mandatory = $true)][string]$Text)

    $lines = $Text -split "\r?\n"
    $kept = New-Object System.Collections.Generic.List[string]
    $skipping = $false
    foreach ($line in $lines) {
        if ($line -match '^\[projects\.') {
            $skipping = $true
            continue
        }
        if ($skipping -and $line -match '^\[') {
            $skipping = $false
        }
        if (-not $skipping) {
            $kept.Add($line)
        }
    }

    return (($kept -join "`n").TrimEnd() + "`n")
}

function Transform-JsonHookPaths {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sourceSlash = ConvertTo-SlashPath (Normalize-FullPath $SourceRoot)
    $text = $Text
    $text = $text.Replace("$sourceSlash/.claude/scripts/", '.claude/scripts/')
    $text = $text.Replace("$sourceSlash/.codex/hooks/", '.codex/hooks/')
    $text = $text.Replace("$sourceSlash/.codex/scripts/", '.codex/scripts/')
    return $text
}

function Transform-GitHook {
    param([Parameter(Mandatory = $true)][string]$Text)

    return $Text.Replace(
        '$(git rev-parse --show-toplevel)/.claude/hooks/pre-commit.ps1',
        '$(git rev-parse --show-toplevel)/vault/.claude/hooks/pre-commit.ps1'
    )
}

function Get-PublicGitIgnore {
    return @'
# Obsidian workspace state, cache, and trash
.obsidian/workspace*.json
.obsidian/cache/
.trash/

# Runtime and local-machine ephemera
server.log
.claude/worktrees/
.claude/*.local.json
'@
}

function Get-PublicRootGitIgnore {
    return @'
# Root-local scratch files
.env
.env.*
*.local
*.tmp
tmp/
temp/
scratch/

# Editor and OS noise
.DS_Store
Thumbs.db
.vscode/
.idea/

# Accidental app state at the public repository root
/.obsidian/
/.trash/
*.log
'@
}

function Get-PublicLicense {
    return @'
MIT License

Copyright (c) 2026 wkh1267

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
'@
}

function Transform-ClaudeSettingsJson {
    param([Parameter(Mandatory = $true)][string]$Text)

    $json = Transform-JsonHookPaths $Text | ConvertFrom-Json
    if ($null -ne $json.hooks -and $null -ne $json.hooks.PreToolUse) {
        $filtered = @($json.hooks.PreToolUse) | Where-Object {
            $hookCommands = @($_.hooks | ForEach-Object { $_.command })
            -not ($_.matcher -eq 'Write|Edit' -and $hookCommands -contains 'git pull; exit 0')
        }
        $json.hooks.PreToolUse = @($filtered)
    }

    return (($json | ConvertTo-Json -Depth 100) + "`n")
}

function Transform-ClaudeScript {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $layout = Get-LayoutSnippet
    $sourceSlash = ConvertTo-SlashPath (Normalize-FullPath $SourceRoot)
    $text = $Text

    switch ($RelativePath) {
        'vault/.claude/scripts/git-push.ps1' {
            $text = $text.Replace("Set-Location `"$sourceSlash`"", "$layout`nSet-Location `$RepoRoot")
        }
        'vault/.claude/scripts/git-sync.ps1' {
            $text = $text.Replace("Set-Location `"$sourceSlash`"", "$layout`nSet-Location `$RepoRoot")
        }
        'vault/.claude/scripts/log-check.ps1' {
            $text = $text.Replace("Set-Location `"$sourceSlash`"", "$layout`nSet-Location `$VaultRoot")
            $text = $text.Replace("`$triggersFile = `"$sourceSlash/.claude/scripts/log-triggers.json`"", "`$triggersFile = Join-Path `$VaultRoot '.claude/scripts/log-triggers.json'")
        }
        'vault/.claude/scripts/hot-check.ps1' {
            $text = $text.Replace("Set-Location `"$sourceSlash`"", "$layout`nSet-Location `$VaultRoot")
        }
        'vault/.claude/scripts/closeout-check.ps1' {
            $text = $text.Replace("`$RepoRoot = '$sourceSlash'", $layout.TrimEnd())
        }
    }

    return $text
}

function Transform-CodexScript {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $layout = Get-LayoutSnippet
    $sourceSlash = ConvertTo-SlashPath (Normalize-FullPath $SourceRoot)
    $text = $Text

    switch ($RelativePath) {
        'vault/.codex/scripts/git-push.ps1' {
            $text = Replace-Regex `
                -Text $text `
                -Pattern "(?s)\`$RepoRoot = if \(\[string\]::IsNullOrWhiteSpace\(\`$env:CODEX_PUSH_REPO_ROOT\)\) \{.*?\} else \{\s*\`$env:CODEX_PUSH_REPO_ROOT\s*\}" `
                -Replacement (Get-DefaultRepoRootSnippet).TrimEnd()
        }
        'vault/.codex/hooks/log-check.ps1' {
            $text = $text.Replace("`$RepoRoot = '$sourceSlash'", $layout.TrimEnd())
            $text = $text.Replace("`$TriggersFile = Join-Path `$RepoRoot '.codex/hooks/log-triggers.json'", "`$TriggersFile = Join-Path `$VaultRoot '.codex/hooks/log-triggers.json'")
            $text = $text.Replace("`$logRoot = Join-Path `$RepoRoot 'log'", "`$logRoot = Join-Path `$VaultRoot 'log'")
        }
        'vault/.codex/hooks/hot-check.ps1' {
            $text = $text.Replace("`$RepoRoot = '$sourceSlash'", $layout.TrimEnd())
            $text = $text.Replace("`$hotPath = Join-Path `$RepoRoot 'docs/specs/hot.md'", "`$hotPath = Join-Path `$VaultRoot 'docs/specs/hot.md'")
        }
        'vault/.codex/hooks/user-prompt-router.ps1' {
            $text = $text.Replace("`$RepoRoot = '$sourceSlash'", $layout.TrimEnd())
            $text = $text.Replace("`$pushScript = Join-Path `$RepoRoot '.codex/scripts/git-push.ps1'", "`$pushScript = Join-Path `$VaultRoot '.codex/scripts/git-push.ps1'")
        }
        'vault/.codex/hooks/worktree-status-check.ps1' {
            $text = $text.Replace("`$RepoRoot = '$sourceSlash'", $layout.TrimEnd())
        }
        'vault/.codex/hooks/closeout-check.ps1' {
            $text = $text.Replace("`$RepoRoot = '$sourceSlash'", $layout.TrimEnd())
        }
    }

    return $text
}

function Transform-PreCommitScript {
    param([Parameter(Mandatory = $true)][string]$Text)

    $helper = @'

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
'@

    $text = $Text.Replace('$RepoRoot = ($repoResult.Output -join "`n").Trim()', '$RepoRoot = ($repoResult.Output -join "`n").Trim()' + $helper)

    $text = $text.Replace(@'
    $isWiki = $f -like "wiki/*"
    $isSpec = $f -like "docs/specs/*"
'@, @'
    $vaultRel = ConvertTo-VaultRelativePath $f
    $isWiki = $vaultRel -like "wiki/*"
    $isSpec = $vaultRel -like "docs/specs/*"
'@)

    $text = $text.Replace('$wikiStaged = @($stagedFiles | Where-Object { $_ -like "wiki/*" })', '$wikiStaged = @($stagedFiles | Where-Object { (ConvertTo-VaultRelativePath $_) -like "wiki/*" })')
    $text = $text.Replace('$resolveRoots += Get-ChildItem -Path $RepoRoot -Filter "*.md" -File', '$resolveRoots += Get-ChildItem -Path $VaultRoot -Filter "*.md" -File')
    $text = $text.Replace('$resolveRoots += Get-ChildItem -Path (Join-Path $RepoRoot "wiki") -Filter "*.md" -Recurse -File', '$resolveRoots += Get-ChildItem -Path (Join-Path $VaultRoot "wiki") -Filter "*.md" -Recurse -File')
    $text = $text.Replace('$docsPath = Join-Path $RepoRoot "docs"', '$docsPath = Join-Path $VaultRoot "docs"')
    $text = $text.Replace('$rel = ($vf.FullName.Substring($RepoRoot.Length + 1)) -replace ''\\'', ''/'' -replace ''\.md$'', ''''', '$rel = ($vf.FullName.Substring($VaultRoot.Length + 1)) -replace ''\\'', ''/'' -replace ''\.md$'', ''''')
    $text = $text.Replace('$issueReadmes = @($stagedFiles | Where-Object { $_ -match ''^issues/[0-9]{4}-[^/]+/README\.md$'' })', '$issueReadmes = @($stagedFiles | Where-Object { (ConvertTo-VaultRelativePath $_) -match ''^issues/[0-9]{4}-[^/]+/README\.md$'' })')
    $text = $text.Replace('$checker = Join-Path $RepoRoot ".claude/hooks/closeout-discipline-check.ps1"', '$checker = Join-Path $VaultRoot ".claude/hooks/closeout-discipline-check.ps1"')

    return $text
}

function Transform-CloseoutDisciplineScript {
    param([Parameter(Mandatory = $true)][string]$Text)

    $helper = @'

$VaultRoot = [System.IO.Path]::GetFullPath($RepoRootHint)
'@

    $text = $Text.Replace('$RepoRoot = ($repoResult.Output -join "`n").Trim()', '$RepoRoot = ($repoResult.Output -join "`n").Trim()' + $helper)
    $text = $text.Replace("if (`$issueDirRel -notmatch '^issues/(?<issue>[0-9]{4})-[^/]+$') {", "if (`$issueDirRel -notmatch '^(?:[^/]+/)*issues/(?<issue>[0-9]{4})-[^/]+$') {")
    return $text
}

function Sanitize-PublicDocText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $localSettingsFile = 'settings' + '.local' + '.json'
    $claudeLocalSettingsFile = '.claude/' + $localSettingsFile
    $workspaceFile = '.obsidian/workspace' + '.json'
    $mobileWorkspaceFile = 'workspace-mobile' + '.json'
    $pluginBundleFile = '.obsidian/plugins/tag-wrangler/main' + '.js'
    $text = $Text
    $text = $text.Replace("``$claudeLocalSettingsFile``", 'the local Claude settings file')
    $text = $text.Replace($claudeLocalSettingsFile, 'the local Claude settings file')
    $text = $text.Replace($localSettingsFile, 'local settings file')
    $text = $text.Replace("``$workspaceFile``", 'the Obsidian workspace file')
    $text = $text.Replace($workspaceFile, 'the Obsidian workspace file')
    $text = $text.Replace($mobileWorkspaceFile, 'the Obsidian mobile workspace file')
    $text = $text.Replace("``$pluginBundleFile``", 'an Obsidian plugin bundle file')
    $text = $text.Replace($pluginBundleFile, 'an Obsidian plugin bundle file')
    return $text
}

function Transform-ExportText {
    param(
        [Parameter(Mandatory = $true)][string]$PublicRelativePath,
        [Parameter(Mandatory = $true)][string]$Text
    )

    switch ($PublicRelativePath) {
        '.gitignore' { return Get-PublicRootGitIgnore }
        'vault/.gitignore' { return Get-PublicGitIgnore }
        '.githooks/pre-commit' { return Transform-GitHook $Text }
        'vault/.claude/settings.json' { return Transform-ClaudeSettingsJson $Text }
        'vault/.codex/hooks.json' { return Transform-JsonHookPaths $Text }
        'vault/.codex/config.toml' { return Remove-CodexProjectBlocks $Text }
        'vault/.claude/hooks/pre-commit.ps1' { return Transform-PreCommitScript $Text }
        'vault/.claude/hooks/closeout-discipline-check.ps1' { return Transform-CloseoutDisciplineScript $Text }
        default {
            if ($PublicRelativePath -like 'vault/docs/*.md') {
                $Text = Sanitize-PublicDocText $Text
            }
            if ($PublicRelativePath -like 'vault/.claude/scripts/*.ps1') {
                return Transform-ClaudeScript -RelativePath $PublicRelativePath -Text $Text
            }
            if ($PublicRelativePath -like 'vault/.codex/hooks/*.ps1' -or $PublicRelativePath -like 'vault/.codex/scripts/*.ps1') {
                return Transform-CodexScript -RelativePath $PublicRelativePath -Text $Text
            }
            return $Text
        }
    }
}

function Copy-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRelativePath,
        [Parameter(Mandatory = $true)][string]$PublicRelativePath
    )

    $sourcePath = Join-RelativePath -Root $SourceRoot -RelativePath $SourceRelativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Missing source file: $SourceRelativePath"
    }

    $content = Read-Text $sourcePath
    $content = Transform-ExportText -PublicRelativePath $PublicRelativePath -Text $content
    Write-Text -Path (Join-RelativePath -Root $DestinationRoot -RelativePath $PublicRelativePath) -Content $content
}

function Test-ExcludedSourcePath {
    param([Parameter(Mandatory = $true)][string]$SourceRelativePath)

    $rel = ConvertTo-SlashPath $SourceRelativePath
    $localSettings = '^\.claude/settings' + '\.local\.json$'
    $workspaceJson = '^\.obsidian/workspace' + '.*\.json$'
    $patterns = @(
        '^\.git/',
        '^\.obsidian/plugins/',
        $workspaceJson,
        '^\.obsidian/cache/',
        '^\.trash/',
        '^\.claude/worktrees/',
        $localSettings,
        '^docs/specs/',
        '^issues/[0-9]{4}-',
        '^raw/',
        '^wiki/',
        '^log/',
        '^exp/',
        '^note/',
        '^paper/',
        '^Clippings/',
        '^tips\.md$',
        '^server\.log$'
    )

    foreach ($pattern in $patterns) {
        if ($rel -match $pattern) {
            return $true
        }
    }
    return $false
}

function Copy-DirectoryTree {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRelativePath,
        [Parameter(Mandatory = $true)][string]$PublicRelativePath
    )

    $sourcePath = Join-RelativePath -Root $SourceRoot -RelativePath $SourceRelativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "Missing source directory: $SourceRelativePath"
    }

    Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force | ForEach-Object {
        $sourceRel = ConvertTo-SlashPath (Get-ChildRelativePath -BasePath $SourceRoot -ChildPath $_.FullName)
        if (Test-ExcludedSourcePath $sourceRel) {
            return
        }

        $childRel = Get-ChildRelativePath -BasePath $sourcePath -ChildPath $_.FullName
        $destRel = ConvertTo-SlashPath (Join-Path $PublicRelativePath $childRel)
        Copy-TextFile -SourceRelativePath $sourceRel -PublicRelativePath $destRel
    }
}

function Write-GitKeep {
    param([Parameter(Mandatory = $true)][string]$PublicDirectoryPath)

    Write-Text -Path (Join-RelativePath -Root $DestinationRoot -RelativePath (ConvertTo-SlashPath (Join-Path $PublicDirectoryPath '.gitkeep'))) -Content ''
}

function Write-SeedHotSpec {
    param([Parameter(Mandatory = $true)][string]$ExportDate)

    $content = @'
---
title: Hot Cache
type: meta
last_updated: {{EXPORT_DATE}} (public template seed)
---

# Hot Cache

Compact session-bridge cache. This public template starts with no private
session history.

## Current Focus

Public-template initialization.

## Recent Changes

- Public template seed created. No local workflow history has been recorded yet.

## Pending Threads

N/A until this vault has local work.

## Pointers

- shared agent rules - `docs/agent-runtime.md`
- knowledge work - `docs/specs/knowledge-ingestion.md`
- system work - `docs/specs/system-development.md`
- issue dashboard - `issues/README.md`
'@
    Write-Text -Path (Join-RelativePath -Root $DestinationRoot -RelativePath 'vault/docs/specs/hot.md') -Content ($content.Replace('{{EXPORT_DATE}}', $ExportDate))
}

function Write-SeedKnowledgeSpec {
    param([Parameter(Mandatory = $true)][string]$ExportDate)

    $content = @'
---
title: Knowledge Ingestion Spec
track: knowledge-ingestion
last_updated: {{EXPORT_DATE}} (public template seed)
---

# Knowledge Ingestion

## Goal

Turn raw sources into a structured, cross-linked Obsidian wiki with durable
operation logs and updated local specs.

## Current State

This public vault is blank. It has zero ingested knowledge pages, no raw backlog,
no topic clusters, and generated empty folders for `raw/`, `wiki/`, and `log/`.

## Active Decisions

- Raw sources go in `raw/` and are treated as immutable.
- Curated pages live under `wiki/concepts/`, `wiki/entities/`, and
  `wiki/synthesis/`.
- Each durable operation writes one dated log entry under `log/`.
- Wiki pages follow `docs/wiki-conventions.md`.

## Open Questions

N/A until sources are added.

## Next Steps

1. Add source files to `raw/`.
2. Run INGEST from the vault root.
3. Update this spec and `docs/specs/hot.md` during closeout.

## Update Protocol

After ingestion or wiki maintenance, update page counts, active clusters, open
questions, and next steps for the local vault.
'@
    Write-Text -Path (Join-RelativePath -Root $DestinationRoot -RelativePath 'vault/docs/specs/knowledge-ingestion.md') -Content ($content.Replace('{{EXPORT_DATE}}', $ExportDate))
}

function Write-SeedSystemSpec {
    param([Parameter(Mandatory = $true)][string]$ExportDate)

    $content = @'
---
title: System Development Spec
track: system-development
last_updated: {{EXPORT_DATE}} (public template seed)
---

# System Development

## Goal

Keep the public workflow template reproducible while each local vault evolves
through documented schema, wiki, and spec changes.

## Current State

This vault starts from the public template baseline: shared runtime docs,
Claude and Codex loaders, copied agents/hooks/scripts/skills, root Git hooks,
and a nested `vault/` directory inside the Git repository root. Generated specs
are starter state only and contain no private source history.

## Active Decisions

- The Git repository root can be outside the Obsidian vault; in the public
  template the vault is `vault/`.
- `docs/agent-runtime.md` is the shared runtime source of truth.
- Claude and Codex loaders stay thin and defer to shared docs.
- Commits use explicit paths and documented scopes.
- `sync` and `push` are manual actions; agents do not auto-publish work.

## Open Questions

N/A for a fresh public template.

## Next Steps

1. Open `vault/` in Obsidian and install the community plugins listed in
   `.obsidian/community-plugins.json`.
2. Run the first local workflow operation.
3. Update this spec and `docs/specs/hot.md` during the first closeout.

## Update Protocol

After schema or workflow changes, update Current State, Active Decisions, Open
Questions, and Next Steps to match the local vault.
'@
    Write-Text -Path (Join-RelativePath -Root $DestinationRoot -RelativePath 'vault/docs/specs/system-development.md') -Content ($content.Replace('{{EXPORT_DATE}}', $ExportDate))
}

function Assert-SourceSpecPolicy {
    $expected = @('hot.md', 'system-development.md', 'knowledge-ingestion.md')
    $specRoot = Join-RelativePath -Root $SourceRoot -RelativePath 'docs/specs'
    $actual = @(Get-ChildItem -LiteralPath $specRoot -File -Filter '*.md' | ForEach-Object { $_.Name })
    $unexpected = @($actual | Where-Object { $expected -notcontains $_ })
    $missing = @($expected | Where-Object { $actual -notcontains $_ })

    if ($unexpected.Count -gt 0 -or $missing.Count -gt 0) {
        throw "docs/specs export policy is stale. Unexpected: $($unexpected -join ', '); missing: $($missing -join ', ')"
    }
}

function Assert-PendingDetectorLayout {
    $detectorRel = 'vault/scripts/get-pending-raw.ps1'
    $detectorPath = Join-RelativePath -Root $DestinationRoot -RelativePath $detectorRel
    if (-not (Test-Path -LiteralPath $detectorPath -PathType Leaf)) {
        throw "Generated pending detector is missing: $detectorRel"
    }

    $entryPoints = @(
        'vault/.agents/skills/ingest-inbox/SKILL.md',
        'vault/.claude/commands/ingest-inbox.md',
        'vault/docs/operations.md'
    )
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $entryPoints) {
        $path = Join-RelativePath -Root $DestinationRoot -RelativePath $rel
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $failures.Add("missing:$rel")
            continue
        }

        $text = Read-Text $path
        if ($text -notmatch 'scripts/get-pending-raw\.ps1') {
            $failures.Add("${rel}:missing-detector-reference")
        }
        if ($text -match '\.\./scripts/get-pending-raw\.ps1') {
            $failures.Add("${rel}:repo-root-detector-reference")
        }
    }

    if ($failures.Count -gt 0) {
        throw "Generated pending detector layout failed: $($failures -join ', ')"
    }
}

$DestinationRoot = Normalize-FullPath $Destination
Assert-SafeDestination $DestinationRoot
Assert-SourceSpecPolicy

if (Test-Path -LiteralPath $DestinationRoot) {
    if (-not $Clean) {
        throw "Destination already exists. Re-run with -Clean after confirming it is disposable: $DestinationRoot"
    }
    Remove-Item -LiteralPath $DestinationRoot -Recurse -Force
}

New-Directory $DestinationRoot

# Public repository root.
Write-Text -Path (Join-RelativePath -Root $DestinationRoot -RelativePath '.gitignore') -Content (Get-PublicRootGitIgnore)
Write-Text -Path (Join-RelativePath -Root $DestinationRoot -RelativePath 'LICENSE') -Content ((Get-PublicLicense) + "`n")
Copy-TextFile -SourceRelativePath 'README.md' -PublicRelativePath 'README.md'
Copy-TextFile -SourceRelativePath 'scripts/export-public-template.ps1' -PublicRelativePath 'scripts/export-public-template.ps1'
Copy-TextFile -SourceRelativePath 'scripts/lib/public-scan.ps1' -PublicRelativePath 'scripts/lib/public-scan.ps1'
Copy-TextFile -SourceRelativePath 'scripts/scan-public-tree.ps1' -PublicRelativePath 'scripts/scan-public-tree.ps1'
Copy-TextFile -SourceRelativePath 'scripts/scan-public-repo.ps1' -PublicRelativePath 'scripts/scan-public-repo.ps1'
Copy-TextFile -SourceRelativePath 'scripts/test-public-scan.ps1' -PublicRelativePath 'scripts/test-public-scan.ps1'
Copy-TextFile -SourceRelativePath 'scripts/update-public-template-repo.ps1' -PublicRelativePath 'scripts/update-public-template-repo.ps1'
Copy-TextFile -SourceRelativePath '.githooks/pre-commit' -PublicRelativePath '.githooks/pre-commit'
Copy-TextFile -SourceRelativePath '.githooks/install.ps1' -PublicRelativePath '.githooks/install.ps1'

# Public Obsidian vault root.
Copy-TextFile -SourceRelativePath 'AGENTS.md' -PublicRelativePath 'vault/AGENTS.md'
Copy-TextFile -SourceRelativePath 'CLAUDE.md' -PublicRelativePath 'vault/CLAUDE.md'
Copy-TextFile -SourceRelativePath '.gitignore' -PublicRelativePath 'vault/.gitignore'
Copy-TextFile -SourceRelativePath 'index.md' -PublicRelativePath 'vault/index.md'
Copy-TextFile -SourceRelativePath 'log.md' -PublicRelativePath 'vault/log.md'
Copy-TextFile -SourceRelativePath 'scripts/get-pending-raw.ps1' -PublicRelativePath 'vault/scripts/get-pending-raw.ps1'
Copy-TextFile -SourceRelativePath 'scripts/test-get-pending-raw.ps1' -PublicRelativePath 'vault/scripts/test-get-pending-raw.ps1'

Copy-TextFile -SourceRelativePath 'docs/agent-runtime.md' -PublicRelativePath 'vault/docs/agent-runtime.md'
Copy-TextFile -SourceRelativePath 'docs/operations.md' -PublicRelativePath 'vault/docs/operations.md'
Copy-TextFile -SourceRelativePath 'docs/issue-workflow.md' -PublicRelativePath 'vault/docs/issue-workflow.md'
Copy-TextFile -SourceRelativePath 'docs/git-workflow.md' -PublicRelativePath 'vault/docs/git-workflow.md'
Copy-TextFile -SourceRelativePath 'docs/wiki-conventions.md' -PublicRelativePath 'vault/docs/wiki-conventions.md'

$exportDate = Get-Date -Format 'yyyy-MM-dd'
Write-SeedHotSpec $exportDate
Write-SeedSystemSpec $exportDate
Write-SeedKnowledgeSpec $exportDate

Copy-TextFile -SourceRelativePath '.obsidian/app.json' -PublicRelativePath 'vault/.obsidian/app.json'
Copy-TextFile -SourceRelativePath '.obsidian/appearance.json' -PublicRelativePath 'vault/.obsidian/appearance.json'
Copy-TextFile -SourceRelativePath '.obsidian/community-plugins.json' -PublicRelativePath 'vault/.obsidian/community-plugins.json'
Copy-TextFile -SourceRelativePath '.obsidian/core-plugins.json' -PublicRelativePath 'vault/.obsidian/core-plugins.json'
Copy-TextFile -SourceRelativePath '.obsidian/graph.json' -PublicRelativePath 'vault/.obsidian/graph.json'

Copy-TextFile -SourceRelativePath '.claude/settings.json' -PublicRelativePath 'vault/.claude/settings.json'
Copy-TextFile -SourceRelativePath '.codex/hooks.json' -PublicRelativePath 'vault/.codex/hooks.json'
Copy-TextFile -SourceRelativePath '.codex/config.toml' -PublicRelativePath 'vault/.codex/config.toml'

Copy-DirectoryTree -SourceRelativePath '.agents/skills' -PublicRelativePath 'vault/.agents/skills'
Copy-DirectoryTree -SourceRelativePath '.codex/agents' -PublicRelativePath 'vault/.codex/agents'
Copy-DirectoryTree -SourceRelativePath '.codex/hooks' -PublicRelativePath 'vault/.codex/hooks'
Copy-DirectoryTree -SourceRelativePath '.codex/scripts' -PublicRelativePath 'vault/.codex/scripts'
Copy-DirectoryTree -SourceRelativePath '.claude/agents' -PublicRelativePath 'vault/.claude/agents'
Copy-DirectoryTree -SourceRelativePath '.claude/commands' -PublicRelativePath 'vault/.claude/commands'
Copy-DirectoryTree -SourceRelativePath '.claude/hooks' -PublicRelativePath 'vault/.claude/hooks'
Copy-DirectoryTree -SourceRelativePath '.claude/scripts' -PublicRelativePath 'vault/.claude/scripts'
Copy-DirectoryTree -SourceRelativePath '.claude/obsidian-skills' -PublicRelativePath 'vault/.claude/obsidian-skills'
Copy-TextFile -SourceRelativePath 'issues/README.md' -PublicRelativePath 'vault/issues/README.md'
Copy-DirectoryTree -SourceRelativePath 'issues/_template' -PublicRelativePath 'vault/issues/_template'

Write-GitKeep 'vault/raw'
Write-GitKeep 'vault/wiki/concepts'
Write-GitKeep 'vault/wiki/entities'
Write-GitKeep 'vault/wiki/synthesis'
Write-GitKeep 'vault/log'
Write-GitKeep 'vault/exp'

Assert-PublicGeneratedPathPolicy -TreeRoot $DestinationRoot
Assert-PendingDetectorLayout
Assert-PublicNoTextHazards -TreeRoot $DestinationRoot -SourceRoot $SourceRoot -UserProfile $env:USERPROFILE
Assert-PublicDocsAndLoaderLayoutSafety -TreeRoot $DestinationRoot -SourceRoot $SourceRoot
Assert-PublicSeedSpecsClean -TreeRoot $DestinationRoot

Write-Host "Public template exported to $DestinationRoot"
