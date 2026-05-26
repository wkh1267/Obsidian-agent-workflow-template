param(
    [Parameter(Mandatory=$true)]
    [string]$IssueDir,

    [Parameter(Mandatory=$true)]
    [string]$ReadmePath
)

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
    [Console]::Error.WriteLine("Closeout discipline check failed: unable to determine repository root.")
    exit 1
}
$RepoRoot = ($repoResult.Output -join "`n").Trim()
$VaultRoot = [System.IO.Path]::GetFullPath($RepoRootHint)

$Failures = @()

function Add-Failure {
    param(
        [Parameter(Mandatory=$true)][string]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )

    $script:Failures += [pscustomobject]@{
        Condition = $Condition
        Message = $Message
    }
}

function ConvertTo-RepoRelativePath {
    param([Parameter(Mandatory=$true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $full = [System.IO.Path]::GetFullPath($Path)
        $repoFull = [System.IO.Path]::GetFullPath($RepoRoot) -replace '[\\/]+$', ''
        $fullNorm = $full -replace '\\', '/'
        $repoNorm = $repoFull -replace '\\', '/'
        if ($fullNorm.StartsWith($repoNorm + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $fullNorm.Substring($repoNorm.Length + 1)
        }
        return $fullNorm
    }

    return (($Path -replace '\\', '/') -replace '^\./', '')
}

function Read-GitText {
    param([Parameter(Mandatory=$true)][string]$ObjectSpec)

    $result = Invoke-GitCommand @("-C", $RepoRoot, "-c", "core.quotepath=false", "show", $ObjectSpec)
    if ($result.ExitCode -ne 0) { return $null }
    if ($result.Output.Count -eq 0) { return "" }
    return ($result.Output -join "`n")
}

function Read-IndexOrHeadText {
    param([Parameter(Mandatory=$true)][string]$Path)

    # The index is the commit snapshot: unchanged tracked files are present
    # there, and paths staged for deletion are absent. Do not fall back to HEAD.
    return Read-GitText ":$Path"
}

function Get-FrontmatterBlock {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, "(?s)\A---\s*\r?\n(?<fm>.*?)\r?\n---")
    if (-not $match.Success) { return $null }
    return $match.Groups["fm"].Value
}

function Remove-InlineComment {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return "" }
    $idx = $Value.IndexOf('#')
    if ($idx -ge 0) {
        return $Value.Substring(0, $idx).Trim()
    }
    return $Value.Trim()
}

function Clean-YamlValue {
    param([AllowNull()][string]$Value)

    $clean = Remove-InlineComment $Value
    if ($clean.Length -ge 2) {
        if (($clean.StartsWith('"') -and $clean.EndsWith('"')) -or
            ($clean.StartsWith("'") -and $clean.EndsWith("'"))) {
            return $clean.Substring(1, $clean.Length - 2)
        }
    }
    return $clean
}

function Get-FrontmatterScalar {
    param(
        [AllowNull()][string]$Frontmatter,
        [Parameter(Mandatory=$true)][string]$Key
    )

    if ($null -eq $Frontmatter) { return $null }
    $escapedKey = [regex]::Escape($Key)
    $match = [regex]::Match($Frontmatter, "(?m)^$escapedKey\s*:\s*(?<value>.*?)\s*$")
    if (-not $match.Success) { return $null }
    return Clean-YamlValue $match.Groups["value"].Value
}

function Parse-InlineArray {
    param([AllowNull()][string]$Value)

    $clean = Clean-YamlValue $Value
    if (-not ($clean.StartsWith('[') -and $clean.EndsWith(']'))) {
        return @()
    }

    $inner = $clean.Substring(1, $clean.Length - 2).Trim()
    if ($inner -eq "") { return @() }
    $items = $inner -split ',' | ForEach-Object { Clean-YamlValue $_ } | Where-Object { $_ -ne "" }
    return @($items)
}

function Get-FrontmatterArray {
    param(
        [AllowNull()][string]$Frontmatter,
        [Parameter(Mandatory=$true)][string]$Key
    )

    if ($null -eq $Frontmatter) { return @() }
    $lines = $Frontmatter -split "\r?\n"
    $escapedKey = [regex]::Escape($Key)

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch "^$escapedKey\s*:\s*(?<tail>.*?)\s*$") { continue }

        $tail = Clean-YamlValue $Matches["tail"]
        if ($tail.StartsWith('[')) {
            return @(Parse-InlineArray $tail)
        }
        if ($tail -ne "") {
            return @($tail)
        }

        $items = @()
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $line = $lines[$j]
            if ($line -match '^[A-Za-z0-9_-]+\s*:') { break }
            if ($line -match '^\s*#') { continue }
            if ($line -match '^\s*-\s*(?<item>.*?)\s*$') {
                $item = Clean-YamlValue $Matches["item"]
                if ($item -ne "") { $items += $item }
            }
        }
        return @($items)
    }

    return @()
}

function Get-RequiredActivations {
    param([AllowNull()][string]$Frontmatter)

    if ($null -eq $Frontmatter) { return @() }
    $lines = $Frontmatter -split "\r?\n"

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^required-activations\s*:\s*(?<tail>.*?)\s*$') { continue }

        $tail = Clean-YamlValue $Matches["tail"]
        if ($tail -eq "[]") { return @() }
        if ($tail -ne "") {
            return @(@{ type = "__unsupported_inline__"; raw = $tail })
        }

        $items = @()
        $current = $null
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $line = $lines[$j]
            if ($line -match '^[A-Za-z0-9_-]+\s*:') { break }
            if ($line -match '^\s*#' -or $line.Trim() -eq "") { continue }

            if ($line -match '^\s*-\s*(?<rest>.*?)\s*$') {
                if ($null -ne $current) { $items += ,$current }
                $current = @{}
                $rest = Clean-YamlValue $Matches["rest"]
                if ($rest -match '^(?<key>[A-Za-z0-9_-]+)\s*:\s*(?<value>.*?)\s*$') {
                    $current[$Matches["key"]] = Clean-YamlValue $Matches["value"]
                } elseif ($rest -ne "") {
                    $current["type"] = "__unsupported__"
                    $current["raw"] = $rest
                }
                continue
            }

            if ($null -ne $current -and $line -match '^\s+(?<key>[A-Za-z0-9_-]+)\s*:\s*(?<value>.*?)\s*$') {
                $current[$Matches["key"]] = Clean-YamlValue $Matches["value"]
            }
        }
        if ($null -ne $current) { $items += ,$current }
        return @($items)
    }

    return @()
}

function Get-CommitSubject {
    param([Parameter(Mandatory=$true)][string]$Sha)

    $result = Invoke-GitCommand @("-C", $RepoRoot, "log", "-1", "--format=%s", $Sha)
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) { return $null }
    return ($result.Output -join " ").Trim()
}

function Test-CommitAncestorOfHead {
    param([Parameter(Mandatory=$true)][string]$Sha)

    $result = Invoke-GitCommand @("-C", $RepoRoot, "merge-base", "--is-ancestor", $Sha, "HEAD")
    return $result.ExitCode -eq 0
}

function Get-OrchestratorRuntimeSteps {
    param([AllowNull()][string]$PlanText)

    $steps = @()
    $found = $false
    if ($null -eq $PlanText) {
        return [pscustomobject]@{ Found = $false; Steps = @() }
    }

    $lines = $PlanText -split "\r?\n"
    $verificationStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+Verification Plan\s*$') {
            $verificationStart = $i
            break
        }
    }

    if ($verificationStart -lt 0) {
        return [pscustomobject]@{ Found = $false; Steps = @() }
    }

    for ($i = $verificationStart + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+' -and $lines[$i] -notmatch '^###\s+') { break }
        if ($lines[$i] -match '^###\s+Orchestrator-run runtime tests\s*$') {
            $found = $true
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $line = $lines[$j]
                if ($line -match '^#{1,3}\s+') { break }
                if ($line -match '^\s*(?<step>[0-9]+)\.\s+') {
                    $steps += $Matches["step"]
                }
            }
            break
        }
    }

    return [pscustomobject]@{ Found = $found; Steps = @($steps) }
}

function Split-MarkdownTableRow {
    param([Parameter(Mandatory=$true)][string]$Line)

    $trimmed = $Line.Trim()
    if ($trimmed.StartsWith('|')) {
        $trimmed = $trimmed.Substring(1)
    }
    if ($trimmed.EndsWith('|')) {
        $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
    }

    $cells = $trimmed -split '\|' | ForEach-Object { $_.Trim() }
    return @($cells)
}

function Get-VerificationRows {
    param([AllowNull()][string]$ImplLogText)

    $rows = @{}
    if ($null -eq $ImplLogText) { return $rows }

    $lines = $ImplLogText -split "\r?\n"
    $section = @()
    $inSection = $false
    foreach ($line in $lines) {
        if (-not $inSection) {
            if ($line -match '^##\s+Verification Run\s*$') {
                $inSection = $true
            }
            continue
        }

        if ($line -match '^##\s+') { break }
        $section += $line
    }

    $headerIndex = -1
    $stepIndex = -1
    $statusIndex = -1
    $actualIndex = -1
    for ($i = 0; $i -lt $section.Count; $i++) {
        if ($section[$i].Trim() -notlike '|*') { continue }
        $cells = Split-MarkdownTableRow $section[$i]
        $lower = @($cells | ForEach-Object { $_.ToLowerInvariant() })
        $stepIndex = [array]::IndexOf($lower, 'step')
        $statusIndex = [array]::IndexOf($lower, 'status')
        $actualIndex = [array]::IndexOf($lower, 'actual')
        if ($stepIndex -ge 0 -and $statusIndex -ge 0 -and $actualIndex -ge 0) {
            $headerIndex = $i
            break
        }
    }

    if ($headerIndex -lt 0) { return $rows }

    for ($i = $headerIndex + 1; $i -lt $section.Count; $i++) {
        $line = $section[$i]
        if ($line.Trim() -notlike '|*') { continue }
        if ($line -match '^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$') { continue }

        $cells = Split-MarkdownTableRow $line
        $maxNeeded = [Math]::Max($stepIndex, [Math]::Max($statusIndex, $actualIndex))
        if ($cells.Count -le $maxNeeded) { continue }
        if ($cells[$stepIndex] -notmatch '^\s*(?<step>[0-9]+)') { continue }

        $step = $Matches["step"]
        $rows[$step] = [pscustomobject]@{
            Status = $cells[$statusIndex].Trim().ToUpperInvariant()
            Actual = $cells[$actualIndex].Trim()
        }
    }

    return $rows
}

$issueDirRel = ConvertTo-RepoRelativePath $IssueDir
$readmeRel = ConvertTo-RepoRelativePath $ReadmePath

if ($issueDirRel -notmatch '^(?:[^/]+/)*issues/(?<issue>[0-9]{4})-[^/]+$') {
    Add-Failure "a" "Issue directory '$issueDirRel' is not a numbered issue directory."
    $issueNumber = "0000"
} else {
    $issueNumber = $Matches["issue"]
}

$planPath = "$issueDirRel/plan.md"
$implLogPath = "$issueDirRel/impl-log.md"

$planText = Read-IndexOrHeadText $planPath
$implLogText = Read-IndexOrHeadText $implLogPath
$planFm = Get-FrontmatterBlock $planText
$implLogFm = Get-FrontmatterBlock $implLogText

if ($null -eq $planText) {
    Add-Failure "b" "Cannot read plan.md from Git's index snapshot."
    Add-Failure "c" "Cannot read plan.md, so required-spec-followup cannot be evaluated."
    Add-Failure "d" "Cannot read plan.md, so runtime verification steps cannot be evaluated."
} elseif ($null -eq $planFm) {
    Add-Failure "b" "plan.md has no YAML frontmatter."
    Add-Failure "c" "plan.md has no YAML frontmatter, so required-spec-followup cannot be evaluated."
}

if ($null -eq $implLogText) {
    Add-Failure "a" "Cannot read impl-log.md from Git's index snapshot."
    Add-Failure "d" "Cannot read impl-log.md, so runtime verification evidence cannot be evaluated."
} elseif ($null -eq $implLogFm) {
    Add-Failure "a" "impl-log.md has no YAML frontmatter."
}

# Condition (a): impl-log commits are non-empty, resolve, and use one allowed scope token.
$listedCommits = @(Get-FrontmatterArray $implLogFm "commits")
$lastImplSha = $null
$lastImplShaUsable = $false

if ($listedCommits.Count -eq 0) {
    Add-Failure "a" "impl-log.md frontmatter commits: is missing or empty."
} else {
    $lastImplSha = $listedCommits[$listedCommits.Count - 1]
    foreach ($sha in $listedCommits) {
        $subject = Get-CommitSubject $sha
        if ($null -eq $subject) {
            Add-Failure "a" "Listed commit '$sha' does not resolve to a commit."
            continue
        }

        if ($subject -notmatch '^(wiki|raw|meta|schema|spec|init):') {
            Add-Failure "a" "Listed commit '$sha' has non-scope-pure subject '$subject'."
        }
    }

    if ($null -ne (Get-CommitSubject $lastImplSha)) {
        if (Test-CommitAncestorOfHead $lastImplSha) {
            $lastImplShaUsable = $true
        } else {
            Add-Failure "a" "Last listed implementation commit '$lastImplSha' is not an ancestor of HEAD."
        }
    }
}

# Condition (b): declarative activation requirements.
if ($null -ne $planFm) {
    $activations = @(Get-RequiredActivations $planFm)
    foreach ($activation in $activations) {
        $type = $activation["type"]
        if ([string]::IsNullOrWhiteSpace($type)) {
            Add-Failure "b" "Activation requirement is missing type."
            continue
        }

        if ($type -ne "git-config") {
            Add-Failure "b" "Unsupported activation requirement type '$type'."
            continue
        }

        $key = $activation["key"]
        $expected = $activation["equals"]
        if ([string]::IsNullOrWhiteSpace($key) -or $null -eq $expected) {
            Add-Failure "b" "git-config activation requirement must include key and equals."
            continue
        }

        $configResult = Invoke-GitCommand @("-C", $RepoRoot, "config", "--get", $key)
        $actual = ($configResult.Output -join "`n").Trim()
        if ($actual -ne $expected) {
            Add-Failure "b" "git config '$key' is '$actual'; expected '$expected'."
        }
    }
}

# Condition (c): issue-specific spec follow-up after the implementation boundary.
$requiredSpecFollowup = $true
if ($null -ne $planFm) {
    $specFlag = Get-FrontmatterScalar $planFm "required-spec-followup"
    if (-not [string]::IsNullOrWhiteSpace($specFlag)) {
        if ($specFlag -eq "true") {
            $requiredSpecFollowup = $true
        } elseif ($specFlag -eq "false") {
            $requiredSpecFollowup = $false
        } else {
            Add-Failure "c" "required-spec-followup must be true or false; found '$specFlag'."
            $requiredSpecFollowup = $true
        }
    }
}

if ($requiredSpecFollowup) {
    if (-not $lastImplShaUsable) {
        Add-Failure "c" "Cannot establish the implementation lower bound from impl-log.md commits:, so the issue-specific spec follow-up cannot be evaluated."
    } else {
        $logResult = Invoke-GitCommand @("-C", $RepoRoot, "log", "--format=%s", "$lastImplSha..HEAD")
        if ($logResult.ExitCode -ne 0) {
            Add-Failure "c" "git log failed while scanning for a spec follow-up after '$lastImplSha'."
        } else {
            $escapedIssue = [regex]::Escape($issueNumber)
            $specPattern = "^spec:.*\b(issue[ -]?)?$escapedIssue\b"
            $foundSpec = $false
            foreach ($subject in @($logResult.Output)) {
                if ([regex]::IsMatch($subject, $specPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                    $foundSpec = $true
                    break
                }
            }

            if (-not $foundSpec) {
                Add-Failure "c" "No later issue-specific spec: commit names issue $issueNumber after implementation commit '$lastImplSha'."
            }
        }
    }
}

# Condition (d): orchestrator runtime steps have impl-log evidence.
if ($null -ne $planText) {
    $runtime = Get-OrchestratorRuntimeSteps $planText
    if (-not $runtime.Found) {
        Add-Failure "d" "plan.md is missing the '### Orchestrator-run runtime tests' heading."
    } else {
        $runtimeSteps = @($runtime.Steps)
        if ($runtimeSteps.Count -gt 0) {
            $rows = Get-VerificationRows $implLogText
            if ($rows.Count -eq 0) {
                Add-Failure "d" "impl-log.md is missing a Verification Run table with Step, Status, and Actual columns."
            }

            $missing = @()
            $badStatus = @()
            $emptyActual = @()
            foreach ($step in $runtimeSteps) {
                if (-not $rows.ContainsKey($step)) {
                    $missing += $step
                    continue
                }

                $row = $rows[$step]
                if ($row.Status -notin @("PASS", "FAIL", "DEFERRED")) {
                    $badStatus += "$step=$($row.Status)"
                }
                if ([string]::IsNullOrWhiteSpace($row.Actual)) {
                    $emptyActual += $step
                }
            }

            if ($missing.Count -gt 0) {
                Add-Failure "d" "impl-log.md is missing Verification Run row(s) for runtime step(s): $($missing -join ', ')."
            }
            if ($badStatus.Count -gt 0) {
                Add-Failure "d" "impl-log.md has invalid runtime status value(s): $($badStatus -join ', '). Expected PASS, FAIL, or DEFERRED."
            }
            if ($emptyActual.Count -gt 0) {
                Add-Failure "d" "impl-log.md has empty Actual cell(s) for runtime step(s): $($emptyActual -join ', ')."
            }
        }
    }
}

if ($Failures.Count -gt 0) {
    $labels = @{
        a = "condition (a), commits"
        b = "condition (b), activations"
        c = "condition (c), spec follow-up"
        d = "condition (d), runtime evidence"
    }

    [Console]::Error.WriteLine("Pre-commit blocked: closeout discipline check failed for $readmeRel")
    foreach ($condition in @("a", "b", "c", "d")) {
        $items = @($Failures | Where-Object { $_.Condition -eq $condition })
        if ($items.Count -eq 0) { continue }
        [Console]::Error.WriteLine("  $($labels[$condition]):")
        foreach ($item in $items) {
            [Console]::Error.WriteLine("    - $($item.Message)")
        }
    }
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("Fix the closeout evidence and retry, or use git commit --no-verify for an emergency bypass.")
    exit 1
}

exit 0
