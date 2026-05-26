[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [switch]$ConfirmMirror,

    [switch]$PreflightRepoScan
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PSScriptRoot
}
$SourceRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot '..'))
$Exporter = Join-Path $ScriptRoot 'export-public-template.ps1'
$TreeScanner = Join-Path $ScriptRoot 'scan-public-tree.ps1'
$RepoScanner = Join-Path $ScriptRoot 'scan-public-repo.ps1'

function Normalize-ReleaseFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ))
}

function ConvertTo-ReleaseSlashPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return ($Path -replace '\\', '/')
}

function Join-ReleaseRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $nativeRel = $RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
    return Join-Path $Root $nativeRel
}

function Get-ReleaseChildRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ChildPath
    )

    $base = Normalize-ReleaseFullPath $BasePath
    $child = [System.IO.Path]::GetFullPath($ChildPath)
    return ($child.Substring($base.Length).TrimStart([char[]]@('\', '/')) -replace '\\', '/')
}

function Test-ReleaseSameOrChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $full = Normalize-ReleaseFullPath $Path
    $parentFull = Normalize-ReleaseFullPath $Parent
    if ($full.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $full.StartsWith($parentFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-ReleaseGitRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $rel = (ConvertTo-ReleaseSlashPath $RelativePath).TrimStart('/')
    return ($rel.Equals('.git', [System.StringComparison]::OrdinalIgnoreCase) -or
        $rel.StartsWith('.git/', [System.StringComparison]::OrdinalIgnoreCase))
}

function New-ReleaseDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Assert-ReleaseSafeDestination {
    param([Parameter(Mandatory = $true)][string]$DestinationPath)

    if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        throw 'Destination must not be empty.'
    }

    $full = Normalize-ReleaseFullPath $DestinationPath
    $root = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "Destination is not an absolute or resolvable path: $DestinationPath"
    }

    if ($full.Equals((Normalize-ReleaseFullPath $root), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing root-like destination: $full"
    }

    if (Test-ReleaseSameOrChildPath -Path $full -Parent $SourceRoot) {
        throw "Refusing destination inside the source vault: $full"
    }

    if (Test-ReleaseSameOrChildPath -Path $SourceRoot -Parent $full) {
        throw "Refusing destination that contains the source vault: $full"
    }

    $highRisk = @(
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($risk in $highRisk) {
        if (Test-ReleaseSameOrChildPath -Path $full -Parent $risk) {
            throw "Refusing high-risk system destination: $full"
        }
    }
}

function Invoke-ReleaseGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments
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

function Invoke-ReleaseScript {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Missing ${Name}: $FilePath"
    }

    $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host $line.ToString()
    }
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode."
    }
}

function Assert-ReleaseGitRepositoryTarget {
    param([Parameter(Mandatory = $true)][string]$DestinationRoot)

    if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container)) {
        throw "Destination does not exist: $DestinationRoot"
    }

    $topLevelResult = Invoke-ReleaseGit -Root $DestinationRoot -Arguments @('rev-parse', '--show-toplevel')
    if ($topLevelResult.ExitCode -ne 0 -or $topLevelResult.Output.Count -eq 0) {
        throw "Destination is not an existing Git repository root: $DestinationRoot"
    }

    $gitTopLevel = Normalize-ReleaseFullPath (($topLevelResult.Output -join "`n").Trim())
    if (-not $gitTopLevel.Equals($DestinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Destination must be the Git top level. Git reported: $gitTopLevel"
    }

    $gitDir = Join-Path $DestinationRoot '.git'
    if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
        throw "Destination must contain a root .git directory: $DestinationRoot"
    }

    $headResult = Invoke-ReleaseGit -Root $DestinationRoot -Arguments @('rev-parse', '--verify', 'HEAD')
    if ($headResult.ExitCode -ne 0) {
        throw "Destination Git repository has no reachable HEAD commit."
    }

    $statusResult = Invoke-ReleaseGit -Root $DestinationRoot -Arguments @('status', '--porcelain')
    if ($statusResult.ExitCode -ne 0) {
        throw "Could not inspect destination work tree status: $($statusResult.Output -join ' ')"
    }

    $dirty = @($statusResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($dirty.Count -gt 0) {
        throw "Destination work tree must be clean before mirroring. Commit or discard existing changes first."
    }
}

function Assert-ReleasePublicTemplateMarkers {
    param([Parameter(Mandatory = $true)][string]$DestinationRoot)

    $markers = @(
        'README.md',
        '.githooks/pre-commit',
        'scripts/scan-public-tree.ps1',
        'scripts/scan-public-repo.ps1',
        'scripts/lib/public-scan.ps1',
        'vault/AGENTS.md',
        'vault/docs/agent-runtime.md',
        'vault/issues/README.md'
    )

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($marker in $markers) {
        $path = Join-ReleaseRelativePath -Root $DestinationRoot -RelativePath $marker
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            [void]$missing.Add($marker)
        }
    }

    if ($missing.Count -gt 0) {
        throw "Destination does not look like the public template. Missing marker(s): $($missing -join ', ')"
    }
}

function Assert-ReleaseMirrorIntent {
    if (-not $ConfirmMirror) {
        throw 'Refusing to mirror without -ConfirmMirror. The mirror removes stale destination files outside .git.'
    }
}

function Assert-ReleaseSafeMirrorPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $rel = (ConvertTo-ReleaseSlashPath $RelativePath).TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($rel)) {
        throw 'Refusing to operate on the destination root as a mirror item.'
    }
    if (Test-ReleaseGitRelativePath $rel) {
        throw "Refusing to operate on Git metadata path: $rel"
    }

    $candidate = Normalize-ReleaseFullPath (Join-ReleaseRelativePath -Root $Root -RelativePath $rel)
    if (-not (Test-ReleaseSameOrChildPath -Path $candidate -Parent $Root)) {
        throw "Mirror candidate escaped the destination root: $rel"
    }

    return $candidate
}

function Get-ReleaseFileMap {
    param([Parameter(Mandatory = $true)][string]$Root)

    $map = @{}
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object {
        $rel = ConvertTo-ReleaseSlashPath (Get-ReleaseChildRelativePath -BasePath $Root -ChildPath $_.FullName)
        if (Test-ReleaseGitRelativePath $rel) {
            return
        }
        $map[$rel] = $_.FullName
    }

    return $map
}

function Get-ReleaseDirectorySet {
    param([Parameter(Mandatory = $true)][string]$Root)

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$set.Add('')
    Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force | ForEach-Object {
        $rel = ConvertTo-ReleaseSlashPath (Get-ReleaseChildRelativePath -BasePath $Root -ChildPath $_.FullName)
        if (Test-ReleaseGitRelativePath $rel) {
            return
        }
        [void]$set.Add($rel)
    }

    return ,$set
}

function Test-ReleaseSameFileContent {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    if (-not (Test-Path -LiteralPath $Left -PathType Leaf) -or -not (Test-Path -LiteralPath $Right -PathType Leaf)) {
        return $false
    }

    $leftInfo = Get-Item -LiteralPath $Left
    $rightInfo = Get-Item -LiteralPath $Right
    if ($leftInfo.Length -ne $rightInfo.Length) {
        return $false
    }

    $leftHash = (Get-FileHash -LiteralPath $Left -Algorithm SHA256).Hash
    $rightHash = (Get-FileHash -LiteralPath $Right -Algorithm SHA256).Hash
    return $leftHash.Equals($rightHash, [System.StringComparison]::OrdinalIgnoreCase)
}

function Sync-ReleaseMirror {
    param(
        [Parameter(Mandatory = $true)][string]$FromRoot,
        [Parameter(Mandatory = $true)][string]$ToRoot
    )

    $sourceFiles = Get-ReleaseFileMap -Root $FromRoot
    $sourceDirs = Get-ReleaseDirectorySet -Root $FromRoot
    $destinationFiles = Get-ReleaseFileMap -Root $ToRoot

    $removedFiles = 0
    foreach ($rel in @($destinationFiles.Keys | Sort-Object)) {
        if (-not $sourceFiles.ContainsKey($rel)) {
            $path = Assert-ReleaseSafeMirrorPath -Root $ToRoot -RelativePath $rel
            Remove-Item -LiteralPath $path -Force
            $removedFiles++
        }
    }

    $removedDirs = 0
    $destinationDirs = @(Get-ChildItem -LiteralPath $ToRoot -Recurse -Directory -Force | Sort-Object FullName -Descending)
    foreach ($dir in $destinationDirs) {
        $rel = ConvertTo-ReleaseSlashPath (Get-ReleaseChildRelativePath -BasePath $ToRoot -ChildPath $dir.FullName)
        if (Test-ReleaseGitRelativePath $rel) {
            continue
        }
        if (-not $sourceDirs.Contains($rel)) {
            $path = Assert-ReleaseSafeMirrorPath -Root $ToRoot -RelativePath $rel
            Remove-Item -LiteralPath $path -Recurse -Force
            $removedDirs++
        }
    }

    $copiedFiles = 0
    $unchangedFiles = 0
    foreach ($rel in @($sourceFiles.Keys | Sort-Object)) {
        $destinationPath = Assert-ReleaseSafeMirrorPath -Root $ToRoot -RelativePath $rel
        $sourcePath = $sourceFiles[$rel]
        New-ReleaseDirectory (Split-Path -Parent $destinationPath)

        if ((Test-Path -LiteralPath $destinationPath -PathType Leaf) -and
            (Test-ReleaseSameFileContent -Left $sourcePath -Right $destinationPath)) {
            $unchangedFiles++
            continue
        }

        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        $copiedFiles++
    }

    return [pscustomobject]@{
        CopiedFiles = $copiedFiles
        UnchangedFiles = $unchangedFiles
        RemovedFiles = $removedFiles
        RemovedDirectories = $removedDirs
    }
}

function Assert-ReleaseTempRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $leaf = Split-Path -Leaf $Path
    if (-not $leaf.StartsWith('public-template-update-', [System.StringComparison]::Ordinal)) {
        throw "Unsafe temporary release path: $Path"
    }
}

if (-not (Test-Path -LiteralPath $Exporter -PathType Leaf)) {
    throw "Missing exporter: $Exporter"
}
if (-not (Test-Path -LiteralPath $TreeScanner -PathType Leaf)) {
    throw "Missing tree scanner: $TreeScanner"
}
if (-not (Test-Path -LiteralPath $RepoScanner -PathType Leaf)) {
    throw "Missing repo scanner: $RepoScanner"
}

$DestinationRoot = Normalize-ReleaseFullPath $Destination
Assert-ReleaseSafeDestination $DestinationRoot
Assert-ReleaseGitRepositoryTarget $DestinationRoot
Assert-ReleasePublicTemplateMarkers $DestinationRoot
Assert-ReleaseMirrorIntent

if ($PreflightRepoScan) {
    Write-Host 'Running optional prior-HEAD repository scan preflight. This validates the destination history before mirroring, not the release commit.'
    Invoke-ReleaseScript `
        -Name 'prior-HEAD public repo scan preflight' `
        -FilePath $RepoScanner `
        -Arguments @('-RepoRoot', $DestinationRoot, '-SourceRoot', $SourceRoot)
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("public-template-update-$([guid]::NewGuid().ToString('N'))")
Assert-ReleaseTempRoot $tempRoot
$exportRoot = Join-Path $tempRoot 'export'

try {
    New-ReleaseDirectory $tempRoot
    Write-Host "Exporting sanitized public template to temporary directory: $exportRoot"
    & $Exporter -Destination $exportRoot -Clean

    Write-Host "Mirroring sanitized export into existing public repository: $DestinationRoot"
    $summary = Sync-ReleaseMirror -FromRoot $exportRoot -ToRoot $DestinationRoot
    Write-Host "Mirror summary: copied=$($summary.CopiedFiles), unchanged=$($summary.UnchangedFiles), removed-files=$($summary.RemovedFiles), removed-directories=$($summary.RemovedDirectories)"

    Write-Host 'Running post-mirror public tree scan before commit.'
    Invoke-ReleaseScript `
        -Name 'post-mirror public tree scan' `
        -FilePath $TreeScanner `
        -Arguments @(
            '-TreeRoot', $DestinationRoot,
            '-SourceRoot', $SourceRoot,
            '-PrivateRootName', (Split-Path -Leaf $SourceRoot),
            '-AllowRootGit'
        )

    $statusResult = Invoke-ReleaseGit -Root $DestinationRoot -Arguments @('status', '--short')
    if ($statusResult.ExitCode -ne 0) {
        throw "Could not inspect post-mirror status: $($statusResult.Output -join ' ')"
    }

    Write-Host ''
    Write-Host 'Post-mirror working-tree status:'
    $statusLines = @($statusResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($statusLines.Count -eq 0) {
        Write-Host '  (clean - no file changes were needed)'
    } else {
        foreach ($line in $statusLines) {
            Write-Host "  $line"
        }
    }

    Write-Host ''
    Write-Host 'Manual next steps from the public repository root:'
    Write-Host '  git status'
    Write-Host '  git diff'
    Write-Host '  git add <explicit paths>'
    Write-Host '  git commit -m "Update public workflow template export"'
    Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/scan-public-repo.ps1 -RepoRoot .'
    Write-Host '  git push   # only if the post-commit repo scan passed'
    Write-Host 'Do not push unless the post-commit repository scan passes.'
    Write-Host 'Claude /release-check or the Codex release-check skill runs both scans against the committed candidate and is the equivalent post-commit gate.'
    Write-Host 'A successful mirror intentionally leaves working-tree changes; re-running this helper before committing or discarding them fails the clean-worktree precondition.'
    Write-Host 'PASS: public-template mirror completed; post-mirror tree scan passed.'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Assert-ReleaseTempRoot $tempRoot
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
