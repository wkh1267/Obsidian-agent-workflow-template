function Normalize-PublicScanFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ))
}

function ConvertTo-PublicScanSlashPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return ($Path -replace '\\', '/')
}

function Join-PublicScanRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $nativeRel = $RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
    return Join-Path $Root $nativeRel
}

function Get-PublicScanChildRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ChildPath
    )

    $base = Normalize-PublicScanFullPath $BasePath
    $child = [System.IO.Path]::GetFullPath($ChildPath)
    return ($child.Substring($base.Length).TrimStart([char[]]@('\', '/')) -replace '\\', '/')
}

function Read-PublicScanText {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function New-PublicScanFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Kind,
        [AllowEmptyString()][string]$Detail = ''
    )

    return [pscustomobject]@{
        Path = $Path
        Kind = $Kind
        Detail = $Detail
    }
}

function Format-PublicScanFinding {
    param([Parameter(Mandatory = $true)]$Finding)

    $detail = ''
    if (-not [string]::IsNullOrWhiteSpace($Finding.Detail)) {
        $detail = " - $($Finding.Detail)"
    }
    return "$($Finding.Path) [$($Finding.Kind)]$detail"
}

function Assert-PublicScanNoFindings {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowEmptyCollection()][object[]]$Findings
    )

    $items = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Findings) {
        foreach ($finding in $Findings) {
            if ($null -ne $finding) {
                [void]$items.Add($finding)
            }
        }
    }
    if ($items.Count -gt 0) {
        $formatted = @($items | ForEach-Object { Format-PublicScanFinding $_ })
        throw "${Message}: $($formatted -join ', ')"
    }
}

function Write-PublicScanReport {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyCollection()][object[]]$Findings
    )

    $items = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Findings) {
        foreach ($finding in $Findings) {
            if ($null -ne $finding) {
                [void]$items.Add($finding)
            }
        }
    }
    if ($items.Count -eq 0) {
        Write-Host "PASS: $Name found no hazards."
        return
    }

    Write-Host "FAIL: $Name found $($items.Count) hazard(s)."
    foreach ($finding in $items) {
        Write-Host "- $(Format-PublicScanFinding $finding)"
    }
}

function Get-PublicScanTextHazardPatterns {
    $authorization = 'Author' + 'ization'
    $bearer = 'Bear' + 'er'
    $localSettings = 'settings' + '\.local'
    $workspaceJson = 'workspace' + '\.json'
    $workspaceMobile = 'workspace-mobile' + '\.json'
    $pluginMain = 'main' + '\.js'
    $pluginData = 'data' + '\.json'

    return @(
        [pscustomobject]@{ Kind = 'secret-like-pattern'; Pattern = 'sk-[A-Za-z0-9_-]{20,}' },
        [pscustomobject]@{ Kind = 'secret-like-pattern'; Pattern = 'ghp_[A-Za-z0-9_]{20,}' },
        [pscustomobject]@{ Kind = 'secret-like-pattern'; Pattern = 'github_pat_[A-Za-z0-9_]{20,}' },
        [pscustomobject]@{ Kind = 'secret-like-pattern'; Pattern = 'AKIA[0-9A-Z]{16}' },
        [pscustomobject]@{ Kind = 'secret-like-pattern'; Pattern = 'AIza[0-9A-Za-z_-]{35}' },
        [pscustomobject]@{ Kind = 'secret-like-pattern'; Pattern = 'xox[A-Za-z]-[A-Za-z0-9-]{10,}' },
        [pscustomobject]@{ Kind = 'secret-like-pattern'; Pattern = 'api[_-]?key' },
        [pscustomobject]@{ Kind = 'secret-like-pattern'; Pattern = $authorization },
        [pscustomobject]@{ Kind = 'secret-like-pattern'; Pattern = $bearer },
        [pscustomobject]@{ Kind = 'plain-email'; Pattern = '(?<![\w.+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?![\w.:-])' },
        [pscustomobject]@{ Kind = 'local-state-marker'; Pattern = $localSettings },
        [pscustomobject]@{ Kind = 'local-state-marker'; Pattern = $workspaceJson },
        [pscustomobject]@{ Kind = 'local-state-marker'; Pattern = $workspaceMobile },
        [pscustomobject]@{ Kind = 'plugin-bundle-marker'; Pattern = $pluginMain },
        [pscustomobject]@{ Kind = 'plugin-bundle-marker'; Pattern = $pluginData }
    )
}

function Get-PublicScanFiles {
    param(
        [Parameter(Mandatory = $true)][string]$TreeRoot,
        [switch]$AllowRootGit
    )

    $root = Normalize-PublicScanFullPath $TreeRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return @()
    }

    $files = [System.Collections.Generic.List[object]]::new()
    Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
        $rel = ConvertTo-PublicScanSlashPath (Get-PublicScanChildRelativePath -BasePath $root -ChildPath $_.FullName)
        if ($rel -eq '.git' -or $rel.StartsWith('.git/', [System.StringComparison]::Ordinal)) {
            return
        }
        if ($AllowRootGit -and ($rel -eq '.git' -or $rel.StartsWith('.git/', [System.StringComparison]::Ordinal))) {
            return
        }
        [void]$files.Add($_)
    }

    return $files.ToArray()
}

function Find-PublicTextHazards {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$SourceRoot,
        [AllowEmptyString()][string]$UserProfile
    )

    $findings = [System.Collections.Generic.List[object]]::new()

    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        $sourceFull = Normalize-PublicScanFullPath $SourceRoot
        $sourceSlash = [regex]::Escape((ConvertTo-PublicScanSlashPath $sourceFull))
        $sourceBackslash = [regex]::Escape($sourceFull)
        if ([regex]::IsMatch($Text, $sourceSlash) -or [regex]::IsMatch($Text, $sourceBackslash)) {
            [void]$findings.Add((New-PublicScanFinding -Path $Path -Kind 'local-source-path' -Detail $SourceRoot))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
        $profileFull = Normalize-PublicScanFullPath $UserProfile
        $profilePattern = [regex]::Escape($profileFull)
        if ([regex]::IsMatch($Text, $profilePattern)) {
            [void]$findings.Add((New-PublicScanFinding -Path $Path -Kind 'local-user-profile' -Detail $UserProfile))
        }
    }

    foreach ($pattern in (Get-PublicScanTextHazardPatterns)) {
        if ([regex]::IsMatch($Text, $pattern.Pattern)) {
            [void]$findings.Add((New-PublicScanFinding -Path $Path -Kind $pattern.Kind -Detail $pattern.Pattern))
        }
    }

    return $findings.ToArray()
}

function Find-PublicTreeTextHazards {
    param(
        [Parameter(Mandatory = $true)][string]$TreeRoot,
        [AllowEmptyString()][string]$SourceRoot,
        [AllowEmptyString()][string]$UserProfile,
        [switch]$AllowRootGit
    )

    $root = Normalize-PublicScanFullPath $TreeRoot
    $findings = [System.Collections.Generic.List[object]]::new()

    foreach ($file in (Get-PublicScanFiles -TreeRoot $root -AllowRootGit:$AllowRootGit)) {
        $rel = ConvertTo-PublicScanSlashPath (Get-PublicScanChildRelativePath -BasePath $root -ChildPath $file.FullName)
        try {
            $text = Read-PublicScanText $file.FullName
        } catch {
            continue
        }

        foreach ($finding in (Find-PublicTextHazards -Text $text -Path $rel -SourceRoot $SourceRoot -UserProfile $UserProfile)) {
            [void]$findings.Add($finding)
        }
    }

    return $findings.ToArray()
}

function Find-PublicGitPathFindings {
    param(
        [Parameter(Mandatory = $true)][string]$TreeRoot,
        [switch]$AllowRootGit
    )

    $root = Normalize-PublicScanFullPath $TreeRoot
    $findings = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        [void]$findings.Add((New-PublicScanFinding -Path $root -Kind 'missing-tree-root' -Detail 'Tree root does not exist.'))
        return $findings.ToArray()
    }

    Get-ChildItem -LiteralPath $root -Recurse -Force | Where-Object { $_.Name -eq '.git' } | ForEach-Object {
        $rel = ConvertTo-PublicScanSlashPath (Get-PublicScanChildRelativePath -BasePath $root -ChildPath $_.FullName)
        if ($AllowRootGit -and $rel -eq '.git') {
            return
        }
        $kind = if ($rel -eq '.git') { 'root-git-directory' } else { 'nested-git-path' }
        [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind $kind -Detail 'Git metadata is not part of the public tree content.'))
    }

    return $findings.ToArray()
}

function Find-PublicDocsAndLoaderLayoutFindings {
    param(
        [Parameter(Mandatory = $true)][string]$TreeRoot,
        [AllowEmptyString()][string]$SourceRoot,
        [AllowEmptyString()][string]$PrivateRootName
    )

    $root = Normalize-PublicScanFullPath $TreeRoot
    if ([string]::IsNullOrWhiteSpace($PrivateRootName) -and -not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        $PrivateRootName = Split-Path -Leaf (Normalize-PublicScanFullPath $SourceRoot)
    }

    $docsAndLoaders = [System.Collections.Generic.List[string]]::new()
    foreach ($rel in @('vault/AGENTS.md', 'vault/CLAUDE.md')) {
        if (Test-Path -LiteralPath (Join-PublicScanRelativePath -Root $root -RelativePath $rel) -PathType Leaf) {
            [void]$docsAndLoaders.Add($rel)
        }
    }

    $docsRoot = Join-PublicScanRelativePath -Root $root -RelativePath 'vault/docs'
    if (Test-Path -LiteralPath $docsRoot -PathType Container) {
        Get-ChildItem -LiteralPath $docsRoot -File -Recurse | Where-Object {
            $_.FullName -notmatch '[\\/]docs[\\/]specs[\\/]'
        } | ForEach-Object {
            [void]$docsAndLoaders.Add((ConvertTo-PublicScanSlashPath (Get-PublicScanChildRelativePath -BasePath $root -ChildPath $_.FullName)))
        }
    }

    $patterns = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($PrivateRootName)) {
        [void]$patterns.Add([regex]::Escape($PrivateRootName + "'s Second Brain"))
        [void]$patterns.Add([regex]::Escape($PrivateRootName + '/ directory'))
        [void]$patterns.Add([regex]::Escape('The whole `' + $PrivateRootName + '/` directory is one Obsidian vault'))
        [void]$patterns.Add([regex]::Escape('The whole ' + $PrivateRootName + '/ directory is one Obsidian vault'))
    }
    [void]$patterns.Add('repo root.*vault root.*same')
    [void]$patterns.Add('vault root.*repo root.*same')

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($rel in $docsAndLoaders) {
        $path = Join-PublicScanRelativePath -Root $root -RelativePath $rel
        $text = Read-PublicScanText $path
        foreach ($pattern in $patterns) {
            if ([regex]::IsMatch($text, $pattern)) {
                [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'stale-layout-wording' -Detail $pattern))
            }
        }
    }

    return $findings.ToArray()
}

function Find-PublicSeedSpecFindings {
    param([Parameter(Mandatory = $true)][string]$TreeRoot)

    $root = Normalize-PublicScanFullPath $TreeRoot
    $specRoot = Join-PublicScanRelativePath -Root $root -RelativePath 'vault/docs/specs'
    if (-not (Test-Path -LiteralPath $specRoot -PathType Container)) {
        return @()
    }

    $patterns = @(
        'Karpathy',
        'AlphaFold',
        'CrystalDiskInfo',
        'Nous Research',
        'Hermes Agent',
        'Codex migration Phase',
        'issue 000[0-9]',
        'issue 001[0-2]',
        'commit [0-9a-f]{7,}',
        '[0-9]+ wiki knowledge pages',
        'Page count: [1-9]',
        'raw sources processed'
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    Get-ChildItem -LiteralPath $specRoot -File -Filter '*.md' | ForEach-Object {
        $rel = ConvertTo-PublicScanSlashPath (Get-PublicScanChildRelativePath -BasePath $root -ChildPath $_.FullName)
        $text = Read-PublicScanText $_.FullName
        foreach ($pattern in $patterns) {
            if ([regex]::IsMatch($text, $pattern)) {
                [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'private-spec-marker' -Detail $pattern))
            }
        }
    }

    return $findings.ToArray()
}

function Find-PublicGeneratedPathPolicyFindings {
    param([Parameter(Mandatory = $true)][string]$TreeRoot)

    $root = Normalize-PublicScanFullPath $TreeRoot
    $files = Get-PublicScanFiles -TreeRoot $root
    $rels = @($files | ForEach-Object {
        ConvertTo-PublicScanSlashPath (Get-PublicScanChildRelativePath -BasePath $root -ChildPath $_.FullName)
    })
    $relSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($rel in $rels) {
        [void]$relSet.Add($rel)
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($rel in $rels) {
        if ($rel -match '^vault/issues/[0-9]{4}-') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'private-issue-history')) }
        if ($rel -match '^vault/\.obsidian/plugins/') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'plugin-bundle-path')) }
        if ($rel -match '^vault/\.obsidian/workspace.*\.json$') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'workspace-state-path')) }
        if ($rel -match '^vault/\.obsidian/cache/') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'obsidian-cache-path')) }
        if ($rel -match '^vault/\.trash/') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'trash-path')) }
        if ($rel -match '^vault/\.claude/worktrees/') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'claude-worktree-path')) }
        if ($rel -match ('^vault/\.claude/settings' + '\.local\.json$')) { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'local-settings-path')) }
        if ($rel -match '^vault/raw/' -and $rel -ne 'vault/raw/.gitkeep') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'raw-content-path')) }
        if ($rel -match '^vault/log/' -and $rel -ne 'vault/log/.gitkeep') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'historical-log-path')) }
        if ($rel -match '^vault/exp/' -and $rel -ne 'vault/exp/.gitkeep') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'historical-exp-path')) }
        if ($rel -match '^vault/wiki/' -and $rel -notmatch '^vault/wiki/(concepts|entities|synthesis)/\.gitkeep$') { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'wiki-content-path')) }
    }

    $expectedObsidian = @(
        'vault/.obsidian/app.json',
        'vault/.obsidian/appearance.json',
        'vault/.obsidian/community-plugins.json',
        'vault/.obsidian/core-plugins.json',
        'vault/.obsidian/graph.json'
    )
    $actualObsidian = @($rels | Where-Object { $_ -match '^vault/\.obsidian/' })
    foreach ($rel in $actualObsidian) {
        if ($expectedObsidian -notcontains $rel) { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'unexpected-obsidian-path')) }
    }
    foreach ($rel in $expectedObsidian) {
        if (-not $relSet.Contains($rel)) { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'missing-path')) }
    }

    $expectedSpecs = @(
        'vault/docs/specs/hot.md',
        'vault/docs/specs/system-development.md',
        'vault/docs/specs/knowledge-ingestion.md'
    )
    $actualSpecs = @($rels | Where-Object { $_ -match '^vault/docs/specs/' })
    foreach ($rel in $actualSpecs) {
        if ($expectedSpecs -notcontains $rel) { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'unexpected-spec-path')) }
    }
    foreach ($rel in $expectedSpecs) {
        if (-not $relSet.Contains($rel)) { [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'missing-path')) }
    }

    $expectedRootPaths = @(
        '.gitignore',
        'scripts/export-public-template.ps1',
        'scripts/lib/public-scan.ps1',
        'scripts/scan-public-tree.ps1',
        'scripts/scan-public-repo.ps1',
        'scripts/test-public-scan.ps1',
        'scripts/update-public-template-repo.ps1',
        'vault/scripts/get-pending-raw.ps1',
        'vault/scripts/test-get-pending-raw.ps1',
        'vault/.claude/commands/release-check.md',
        'vault/.agents/skills/release-check/SKILL.md'
    )
    foreach ($rel in $expectedRootPaths) {
        if (-not $relSet.Contains($rel)) {
            [void]$findings.Add((New-PublicScanFinding -Path $rel -Kind 'missing-path'))
        }
    }

    foreach ($wrapperRel in @('vault/.claude/commands/release-check.md', 'vault/.agents/skills/release-check/SKILL.md')) {
        if (-not $relSet.Contains($wrapperRel)) {
            continue
        }

        $wrapperPath = Join-PublicScanRelativePath -Root $root -RelativePath $wrapperRel
        $wrapperText = Read-PublicScanText $wrapperPath
        $matches = [regex]::Matches($wrapperText, 'scripts[\\/](?<script>[A-Za-z0-9_.-]+\.ps1)')
        foreach ($match in $matches) {
            $scriptRel = "scripts/$($match.Groups['script'].Value)"
            if (-not $relSet.Contains($scriptRel)) {
                [void]$findings.Add((New-PublicScanFinding -Path $wrapperRel -Kind 'missing-wrapper-dependency' -Detail $scriptRel))
            }
        }
    }

    return $findings.ToArray()
}

function Find-PublicTreeScanFindings {
    param(
        [Parameter(Mandatory = $true)][string]$TreeRoot,
        [AllowEmptyString()][string]$SourceRoot,
        [AllowEmptyString()][string]$PrivateRootName,
        [AllowEmptyString()][string]$UserProfile,
        [switch]$AllowRootGit
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($finding in (Find-PublicGitPathFindings -TreeRoot $TreeRoot -AllowRootGit:$AllowRootGit)) {
        [void]$findings.Add($finding)
    }
    foreach ($finding in (Find-PublicTreeTextHazards -TreeRoot $TreeRoot -SourceRoot $SourceRoot -UserProfile $UserProfile -AllowRootGit:$AllowRootGit)) {
        [void]$findings.Add($finding)
    }
    foreach ($finding in (Find-PublicDocsAndLoaderLayoutFindings -TreeRoot $TreeRoot -SourceRoot $SourceRoot -PrivateRootName $PrivateRootName)) {
        [void]$findings.Add($finding)
    }
    foreach ($finding in (Find-PublicSeedSpecFindings -TreeRoot $TreeRoot)) {
        [void]$findings.Add($finding)
    }

    return $findings.ToArray()
}

function Assert-PublicGeneratedPathPolicy {
    param([Parameter(Mandatory = $true)][string]$TreeRoot)

    Assert-PublicScanNoFindings `
        -Message 'Generated path policy failed' `
        -Findings (Find-PublicGeneratedPathPolicyFindings -TreeRoot $TreeRoot)
}

function Assert-PublicNoTextHazards {
    param(
        [Parameter(Mandatory = $true)][string]$TreeRoot,
        [AllowEmptyString()][string]$SourceRoot,
        [AllowEmptyString()][string]$UserProfile
    )

    Assert-PublicScanNoFindings `
        -Message 'Generated text hazard scan failed' `
        -Findings (Find-PublicTreeTextHazards -TreeRoot $TreeRoot -SourceRoot $SourceRoot -UserProfile $UserProfile)
}

function Assert-PublicDocsAndLoaderLayoutSafety {
    param(
        [Parameter(Mandatory = $true)][string]$TreeRoot,
        [AllowEmptyString()][string]$SourceRoot,
        [AllowEmptyString()][string]$PrivateRootName
    )

    Assert-PublicScanNoFindings `
        -Message 'Copied docs/loaders are not public-layout-safe' `
        -Findings (Find-PublicDocsAndLoaderLayoutFindings -TreeRoot $TreeRoot -SourceRoot $SourceRoot -PrivateRootName $PrivateRootName)
}

function Assert-PublicSeedSpecsClean {
    param([Parameter(Mandatory = $true)][string]$TreeRoot)

    Assert-PublicScanNoFindings `
        -Message 'Generated seed specs contain private-state markers' `
        -Findings (Find-PublicSeedSpecFindings -TreeRoot $TreeRoot)
}
