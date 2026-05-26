[CmdletBinding()]
param(
    [string]$TempRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$ScriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PSScriptRoot
}
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot '..'))
$TreeScanner = Join-Path $ScriptRoot 'scan-public-tree.ps1'
$RepoScanner = Join-Path $ScriptRoot 'scan-public-repo.ps1'

function New-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Write-Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    New-Directory (Split-Path -Parent $Path)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Assert-SafeFixturePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $leaf = Split-Path -Leaf $Path
    if (-not $leaf.StartsWith('public-scan-test-', [System.StringComparison]::Ordinal)) {
        throw "Unsafe fixture path leaf: $Path"
    }
}

function New-FixtureRoot {
    param([Parameter(Mandatory = $true)][string]$Name)

    $path = Join-Path $FixtureRoot $Name
    New-Directory $path
    return $path
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory = $true)][bool]$ShouldPass,
        [string]$ExpectedPattern
    )

    $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"

    if ($ShouldPass -and $exitCode -ne 0) {
        throw "$Name expected PASS but exited $exitCode.`n$text"
    }
    if (-not $ShouldPass -and $exitCode -eq 0) {
        throw "$Name expected FAIL but exited 0.`n$text"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedPattern) -and $text -notmatch $ExpectedPattern) {
        throw "$Name did not report expected pattern '$ExpectedPattern'.`n$text"
    }

    Write-Host "PASS fixture: $Name"
}

function Invoke-Git {
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

    if ($exitCode -ne 0) {
        $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        throw "git $($Arguments -join ' ') failed in $Root.`n$text"
    }
}

function New-GitFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Email,
        [string]$UserName = 'Release Bot'
    )

    $root = New-FixtureRoot $Name
    Write-Text -Path (Join-Path $root 'README.md') -Content "# Fixture`n"
    Invoke-Git -Root $root -Arguments @('init')
    Invoke-Git -Root $root -Arguments @('add', 'README.md')
    Invoke-Git -Root $root -Arguments @('-c', "user.name=$UserName", '-c', "user.email=$Email", 'commit', '-m', 'init')
    return $root
}

function Resolve-WrapperVaultRoot {
    $nestedVault = Join-Path $RepoRoot 'vault'
    if (Test-Path -LiteralPath (Join-Path $nestedVault '.claude/commands/release-check.md') -PathType Leaf) {
        return $nestedVault
    }
    return $RepoRoot
}

function Assert-WrapperStaticPolicy {
    $vaultRoot = Resolve-WrapperVaultRoot
    $wrappers = @(
        (Join-Path $vaultRoot '.claude/commands/release-check.md'),
        (Join-Path $vaultRoot '.agents/skills/release-check/SKILL.md')
    )

    $authorization = 'Author' + 'ization'
    $bearer = 'Bear' + 'er'
    $privateRepo = '2nd' + 'Brain'
    $windowsUsers = 'C:' + '\\Users'
    $windowsDrive = 'D:' + '\\'
    $forbiddenPattern = 'sk-|github_pat_|AKIA|AIza|xox[A-Za-z]-|api[_-]?key|' +
        $authorization + '|' +
        $bearer + '|' +
        'users\.noreply\.github\.com|' +
        [regex]::Escape($privateRepo) + '|' +
        'D:/|' +
        [regex]::Escape($windowsDrive) + '|' +
        [regex]::Escape($windowsUsers)

    foreach ($wrapper in $wrappers) {
        if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
            throw "Wrapper is missing: $wrapper"
        }
        $text = [System.IO.File]::ReadAllText($wrapper, [System.Text.Encoding]::UTF8)
        if ($text -notmatch 'scripts[\\/]scan-public-tree\.ps1' -or $text -notmatch 'scripts[\\/]scan-public-repo\.ps1') {
            throw "Wrapper does not reference both scan scripts: $wrapper"
        }
        if ([regex]::IsMatch($text, $forbiddenPattern)) {
            throw "Wrapper contains inline scan policy or private literal: $wrapper"
        }
    }

    Write-Host 'PASS fixture: wrapper static policy'
}

if (-not (Test-Path -LiteralPath $TreeScanner -PathType Leaf)) {
    throw "Tree scanner missing: $TreeScanner"
}
if (-not (Test-Path -LiteralPath $RepoScanner -PathType Leaf)) {
    throw "Repo scanner missing: $RepoScanner"
}

$baseRoot = if ([string]::IsNullOrWhiteSpace($TempRoot)) {
    [System.IO.Path]::GetTempPath()
} else {
    [System.IO.Path]::GetFullPath($TempRoot)
}

$FixtureRoot = Join-Path $baseRoot ("public-scan-test-$([guid]::NewGuid().ToString('N'))")
Assert-SafeFixturePath $FixtureRoot

try {
    New-Directory $FixtureRoot

    $privateRoot = Join-Path $FixtureRoot 'private-source-root'
    New-Directory $privateRoot
    $cleanEmail = 'release-bot' + '@' + 'users.noreply.github.com'
    $badEmail = 'release-bot' + '@' + 'example.test'
    $plantedToken = 'sk-' + ('A' * 24)
    $plantedEmail = 'person' + '@' + 'example.test'

    $cleanTree = New-FixtureRoot 'clean-tree'
    Write-Text -Path (Join-Path $cleanTree 'README.md') -Content "# Clean`n"
    Invoke-CheckedCommand -Name 'clean tree scan' -FilePath $TreeScanner -Arguments @('-TreeRoot', $cleanTree) -ShouldPass $true

    $localPathTree = New-FixtureRoot 'local-path-tree'
    Write-Text -Path (Join-Path $localPathTree 'leak.txt') -Content "source=$privateRoot`n"
    Invoke-CheckedCommand -Name 'local source path tree scan' -FilePath $TreeScanner -Arguments @('-TreeRoot', $localPathTree, '-SourceRoot', $privateRoot) -ShouldPass $false -ExpectedPattern 'local-source-path'

    $tokenTree = New-FixtureRoot 'token-tree'
    Write-Text -Path (Join-Path $tokenTree 'token.txt') -Content "$plantedToken`n"
    Invoke-CheckedCommand -Name 'token tree scan' -FilePath $TreeScanner -Arguments @('-TreeRoot', $tokenTree) -ShouldPass $false -ExpectedPattern 'secret-like-pattern'

    $emailTree = New-FixtureRoot 'email-tree'
    Write-Text -Path (Join-Path $emailTree 'email.txt') -Content "$plantedEmail`n"
    Invoke-CheckedCommand -Name 'plain email tree scan' -FilePath $TreeScanner -Arguments @('-TreeRoot', $emailTree) -ShouldPass $false -ExpectedPattern 'plain-email'

    $nestedGitTree = New-FixtureRoot 'nested-git-tree'
    Write-Text -Path (Join-Path $nestedGitTree 'nested/.git/config') -Content "[core]`n"
    Invoke-CheckedCommand -Name 'nested git tree scan' -FilePath $TreeScanner -Arguments @('-TreeRoot', $nestedGitTree) -ShouldPass $false -ExpectedPattern 'nested-git-path'

    $cleanRepo = New-GitFixture -Name 'clean-repo' -Email $cleanEmail
    Invoke-CheckedCommand -Name 'clean repo scan' -FilePath $RepoScanner -Arguments @('-RepoRoot', $cleanRepo) -ShouldPass $true

    $privateRemoteRepo = New-GitFixture -Name 'private-remote-repo' -Email $cleanEmail
    $privateRemote = 'https://example.invalid/' + ('2nd' + 'Brain') + '.git'
    Invoke-Git -Root $privateRemoteRepo -Arguments @('remote', 'add', 'origin', $privateRemote)
    Invoke-CheckedCommand -Name 'private remote repo scan' -FilePath $RepoScanner -Arguments @('-RepoRoot', $privateRemoteRepo) -ShouldPass $false -ExpectedPattern 'private-remote-url'

    $badEmailRepo = New-GitFixture -Name 'bad-email-repo' -Email $badEmail
    Invoke-CheckedCommand -Name 'bad author email repo scan' -FilePath $RepoScanner -Arguments @('-RepoRoot', $badEmailRepo) -ShouldPass $false -ExpectedPattern 'disallowed-author-email'

    $badNameRepo = New-GitFixture -Name 'bad-name-repo' -Email $cleanEmail -UserName ('Release ' + $plantedToken)
    Invoke-CheckedCommand -Name 'bad author name repo scan' -FilePath $RepoScanner -Arguments @('-RepoRoot', $badNameRepo) -ShouldPass $false -ExpectedPattern 'author-name.*secret-like-pattern'

    $historySecretRepo = New-FixtureRoot 'history-secret-repo'
    Invoke-Git -Root $historySecretRepo -Arguments @('init')
    Write-Text -Path (Join-Path $historySecretRepo 'secret.txt') -Content "$plantedToken`n"
    Invoke-Git -Root $historySecretRepo -Arguments @('add', 'secret.txt')
    Invoke-Git -Root $historySecretRepo -Arguments @('-c', 'user.name=Release Bot', '-c', "user.email=$cleanEmail", 'commit', '-m', 'secret')
    Write-Text -Path (Join-Path $historySecretRepo 'secret.txt') -Content "removed`n"
    Invoke-Git -Root $historySecretRepo -Arguments @('add', 'secret.txt')
    Invoke-Git -Root $historySecretRepo -Arguments @('-c', 'user.name=Release Bot', '-c', "user.email=$cleanEmail", 'commit', '-m', 'remove secret')
    Invoke-CheckedCommand -Name 'historical secret repo scan' -FilePath $RepoScanner -Arguments @('-RepoRoot', $historySecretRepo) -ShouldPass $false -ExpectedPattern 'secret-like-pattern'

    $privatePathRepo = New-GitFixture -Name 'private-path-repo' -Email $cleanEmail
    Write-Text -Path (Join-Path $privatePathRepo 'path.txt') -Content "$privateRoot`n"
    Invoke-Git -Root $privatePathRepo -Arguments @('add', 'path.txt')
    Invoke-Git -Root $privatePathRepo -Arguments @('-c', 'user.name=Release Bot', '-c', "user.email=$cleanEmail", 'commit', '-m', 'private path')
    Invoke-CheckedCommand -Name 'committed private path repo scan' -FilePath $RepoScanner -Arguments @('-RepoRoot', $privatePathRepo, '-SourceRoot', $privateRoot) -ShouldPass $false -ExpectedPattern 'local-source-path'

    Assert-WrapperStaticPolicy

    Write-Host 'All public scan tests passed.'
} finally {
    if (Test-Path -LiteralPath $FixtureRoot) {
        Assert-SafeFixturePath $FixtureRoot
        Remove-Item -LiteralPath $FixtureRoot -Recurse -Force
    }
}
