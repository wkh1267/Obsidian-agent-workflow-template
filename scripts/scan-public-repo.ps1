[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [string[]]$AllowedAuthorEmail = @(),

    [string]$AllowedAuthorEmailPattern = '^[^@]+@users\.noreply\.github\.com$',

    [string]$SourceRoot,

    [string]$PrivateRepositoryName = ('2nd' + 'Brain'),

    [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PSScriptRoot
}
$LibraryPath = Join-Path $ScriptRoot 'lib/public-scan.ps1'
if (-not (Test-Path -LiteralPath $LibraryPath -PathType Leaf)) {
    throw "Public scan library not found: $LibraryPath"
}
. $LibraryPath

function Invoke-PublicRepoGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -c core.autocrlf=false -C $Root @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { $_.ToString() })
    }
}

function Test-PublicRepoAllowedEmail {
    param([AllowEmptyString()][string]$Email)

    if ([string]::IsNullOrWhiteSpace($Email)) {
        return $false
    }

    foreach ($allowed in $AllowedAuthorEmail) {
        if ($Email.Equals($allowed, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($AllowedAuthorEmailPattern) -and [regex]::IsMatch($Email, $AllowedAuthorEmailPattern)) {
        return $true
    }

    return $false
}

$resolvedRepoRoot = Normalize-PublicScanFullPath $RepoRoot
$findings = [System.Collections.Generic.List[object]]::new()

if (-not (Test-Path -LiteralPath $resolvedRepoRoot -PathType Container)) {
    [void]$findings.Add((New-PublicScanFinding -Path $resolvedRepoRoot -Kind 'missing-repo-root' -Detail 'Repository root does not exist.'))
    Write-PublicScanReport -Name "public repo scan for $resolvedRepoRoot" -Findings $findings.ToArray()
    exit 1
}

$topLevelResult = Invoke-PublicRepoGit -Root $resolvedRepoRoot -Arguments @('rev-parse', '--show-toplevel')
if ($topLevelResult.ExitCode -ne 0 -or $topLevelResult.Output.Count -eq 0) {
    [void]$findings.Add((New-PublicScanFinding -Path $resolvedRepoRoot -Kind 'not-a-git-repository' -Detail ($topLevelResult.Output -join ' ')))
    Write-PublicScanReport -Name "public repo scan for $resolvedRepoRoot" -Findings $findings.ToArray()
    exit 1
}

$gitTopLevel = Normalize-PublicScanFullPath (($topLevelResult.Output -join "`n").Trim())
if (-not $gitTopLevel.Equals($resolvedRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    [void]$findings.Add((New-PublicScanFinding -Path $resolvedRepoRoot -Kind 'repo-root-mismatch' -Detail "Git top level is $gitTopLevel."))
}

$remoteResult = Invoke-PublicRepoGit -Root $resolvedRepoRoot -Arguments @('remote', '-v')
if ($remoteResult.ExitCode -eq 0) {
    $sourceSlash = $null
    $sourceBackslash = $null
    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        $sourceFull = Normalize-PublicScanFullPath $SourceRoot
        $sourceSlash = ConvertTo-PublicScanSlashPath $sourceFull
        $sourceBackslash = $sourceFull
    }

    foreach ($line in $remoteResult.Output) {
        if (-not [string]::IsNullOrWhiteSpace($PrivateRepositoryName) -and
            $line.IndexOf($PrivateRepositoryName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            [void]$findings.Add((New-PublicScanFinding -Path 'git-remotes' -Kind 'private-remote-url' -Detail $line))
        }
        if ($null -ne $sourceSlash -and $line.IndexOf($sourceSlash, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            [void]$findings.Add((New-PublicScanFinding -Path 'git-remotes' -Kind 'private-source-remote-url' -Detail $line))
        }
        if ($null -ne $sourceBackslash -and $line.IndexOf($sourceBackslash, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            [void]$findings.Add((New-PublicScanFinding -Path 'git-remotes' -Kind 'private-source-remote-url' -Detail $line))
        }
    }
}

$logResult = Invoke-PublicRepoGit -Root $resolvedRepoRoot -Arguments @('log', '--all', '--format=%H%x09%an%x09%ae%x09%cn%x09%ce')
if ($logResult.ExitCode -ne 0) {
    [void]$findings.Add((New-PublicScanFinding -Path 'git-log' -Kind 'git-log-failed' -Detail ($logResult.Output -join ' ')))
} elseif ($logResult.Output.Count -eq 0) {
    [void]$findings.Add((New-PublicScanFinding -Path 'git-log' -Kind 'no-reachable-commits' -Detail 'No reachable commits exist to validate.'))
} else {
    foreach ($line in $logResult.Output) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $parts = $line -split "`t", 5
        if ($parts.Count -lt 5) {
            [void]$findings.Add((New-PublicScanFinding -Path 'git-log' -Kind 'unexpected-log-row' -Detail $line))
            continue
        }
        $commit = $parts[0]
        $authorName = $parts[1]
        $authorEmail = $parts[2]
        $committerName = $parts[3]
        $committerEmail = $parts[4]

        if (-not (Test-PublicRepoAllowedEmail $authorEmail)) {
            [void]$findings.Add((New-PublicScanFinding -Path $commit -Kind 'disallowed-author-email' -Detail "$authorName <$authorEmail>"))
        }
        if (-not (Test-PublicRepoAllowedEmail $committerEmail)) {
            [void]$findings.Add((New-PublicScanFinding -Path $commit -Kind 'disallowed-committer-email' -Detail "$committerName <$committerEmail>"))
        }
        foreach ($finding in (Find-PublicTextHazards -Text $authorName -Path "${commit}:author-name" -SourceRoot $SourceRoot -UserProfile $UserProfile)) {
            [void]$findings.Add($finding)
        }
        foreach ($finding in (Find-PublicTextHazards -Text $committerName -Path "${commit}:committer-name" -SourceRoot $SourceRoot -UserProfile $UserProfile)) {
            [void]$findings.Add($finding)
        }
    }
}

$trackedResult = Invoke-PublicRepoGit -Root $resolvedRepoRoot -Arguments @('ls-files')
$trackedFiles = @()
if ($trackedResult.ExitCode -ne 0) {
    [void]$findings.Add((New-PublicScanFinding -Path 'git-ls-files' -Kind 'git-ls-files-failed' -Detail ($trackedResult.Output -join ' ')))
} else {
    $trackedFiles = @($trackedResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($path in $trackedFiles) {
        $slashPath = ConvertTo-PublicScanSlashPath $path
        $segments = @($slashPath -split '/')
        if ($segments -contains '.git') {
            [void]$findings.Add((New-PublicScanFinding -Path $slashPath -Kind 'tracked-git-metadata-path' -Detail 'Tracked paths must not include .git segments.'))
        }
        foreach ($finding in (Find-PublicTextHazards -Text $slashPath -Path "tracked-path:$slashPath" -SourceRoot $SourceRoot -UserProfile $UserProfile)) {
            [void]$findings.Add($finding)
        }
    }
}

foreach ($path in $trackedFiles) {
    $slashPath = ConvertTo-PublicScanSlashPath $path
    $showResult = Invoke-PublicRepoGit -Root $resolvedRepoRoot -Arguments @('show', "HEAD:$path")
    if ($showResult.ExitCode -ne 0) {
        continue
    }
    $text = $showResult.Output -join "`n"
    foreach ($finding in (Find-PublicTextHazards -Text $text -Path "HEAD:$slashPath" -SourceRoot $SourceRoot -UserProfile $UserProfile)) {
        [void]$findings.Add($finding)
    }
}

$objectResult = Invoke-PublicRepoGit -Root $resolvedRepoRoot -Arguments @('rev-list', '--objects', '--all')
if ($objectResult.ExitCode -ne 0) {
    [void]$findings.Add((New-PublicScanFinding -Path 'git-objects' -Kind 'git-rev-list-failed' -Detail ($objectResult.Output -join ' ')))
} else {
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($line in $objectResult.Output) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $space = $line.IndexOf(' ')
        $objectId = if ($space -ge 0) { $line.Substring(0, $space) } else { $line }
        $objectPath = if ($space -ge 0) { $line.Substring($space + 1) } else { $objectId }
        if (-not $seen.Add($objectId)) {
            continue
        }

        $typeResult = Invoke-PublicRepoGit -Root $resolvedRepoRoot -Arguments @('cat-file', '-t', $objectId)
        if ($typeResult.ExitCode -ne 0 -or (($typeResult.Output -join "`n").Trim()) -ne 'blob') {
            continue
        }

        $blobResult = Invoke-PublicRepoGit -Root $resolvedRepoRoot -Arguments @('cat-file', '-p', $objectId)
        if ($blobResult.ExitCode -ne 0) {
            continue
        }

        $text = $blobResult.Output -join "`n"
        foreach ($finding in (Find-PublicTextHazards -Text $text -Path "blob:${objectId}:$objectPath" -SourceRoot $SourceRoot -UserProfile $UserProfile)) {
            [void]$findings.Add($finding)
        }
    }
}

Write-PublicScanReport -Name "public repo scan for $resolvedRepoRoot" -Findings $findings.ToArray()
if ($findings.Count -gt 0) {
    exit 1
}
exit 0
