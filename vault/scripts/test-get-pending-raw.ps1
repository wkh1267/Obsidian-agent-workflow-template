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
$DetectorPath = Join-Path $ScriptRoot 'get-pending-raw.ps1'

function New-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Write-Text {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $path = Join-Path $FixtureRoot $RelativePath
    New-Directory (Split-Path -Parent $path)
    [System.IO.File]::WriteAllText($path, $Content, $Utf8NoBom)
}

function Assert-EqualLines {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Expected,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Actual
    )

    $expectedText = ($Expected -join "`n")
    $actualText = ($Actual -join "`n")
    if ($expectedText -ne $actualText) {
        throw "$Name failed.`nExpected:`n$expectedText`nActual:`n$actualText"
    }
}

function Assert-SafeFixturePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $leaf = Split-Path -Leaf $Path
    if (-not $leaf.StartsWith('get-pending-raw-test-', [System.StringComparison]::Ordinal)) {
        throw "Unsafe fixture path leaf: $Path"
    }
}

if (-not (Test-Path -LiteralPath $DetectorPath -PathType Leaf)) {
    throw "Detector script not found: $DetectorPath"
}

$baseRoot = if ([string]::IsNullOrWhiteSpace($TempRoot)) {
    [System.IO.Path]::GetTempPath()
} else {
    [System.IO.Path]::GetFullPath($TempRoot)
}

$FixtureRoot = Join-Path $baseRoot ("get-pending-raw-test-$([guid]::NewGuid().ToString('N'))")
Assert-SafeFixturePath $FixtureRoot

try {
    New-Directory $FixtureRoot

    $NonAsciiName = -join ([char[]]@(0x8CC7, 0x6599, 0x20, 0x540D, 0x7A31))

    foreach ($name in @(
        'scalar',
        'list-one',
        'list two',
        'alias',
        'trailing',
        'backslash',
        'body-only',
        'unprocessed',
        $NonAsciiName
    )) {
        Write-Text -RelativePath "raw/$name.md" -Content ''
    }

    Write-Text -RelativePath 'log/2026-01-01-scalar.md' -Content @'
---
date: 2026-01-01
operation: ingest
source: "[[raw/scalar]]"
pages_created: []
---
'@

    Write-Text -RelativePath 'log/2026-01-02-list.md' -Content @"
---
date: 2026-01-02
operation: ingest
source:
  - "[[raw/list-one]]"
  - "[[raw/list two]]"
  - "[[raw/$NonAsciiName]]"
pages_created: []
---
"@

    Write-Text -RelativePath 'log/2026-01-03-normalization.md' -Content @'
---
date: 2026-01-03
operation: ingest
source:
  - "[[raw/alias|Alias text]]"
  - "[[raw/trailing.md]]"
  - "raw\backslash.md"
pages_created: []
---
'@

    Write-Text -RelativePath 'log/2026-01-04-query.md' -Content @'
---
date: 2026-01-04
operation: query
source: "[[raw/unprocessed]]"
pages_created: []
---
'@

    Write-Text -RelativePath 'log/2026-01-05-body-only.md' -Content @'
---
date: 2026-01-05
operation: ingest
source: "[[wiki/not-raw]]"
pages_created: []
---

Body prose mentions [[raw/body-only]], but body links are not processed-source evidence.
'@

    $expected = @(
        'raw/body-only',
        'raw/unprocessed'
    )

    $explicitOutput = @(& $DetectorPath -VaultRoot $FixtureRoot)
    Assert-EqualLines -Name 'explicit -VaultRoot detector run' -Expected $expected -Actual $explicitOutput

    New-Directory (Join-Path $FixtureRoot 'scripts')
    Copy-Item -LiteralPath $DetectorPath -Destination (Join-Path $FixtureRoot 'scripts/get-pending-raw.ps1') -Force
    $defaultOutput = @(& (Join-Path $FixtureRoot 'scripts/get-pending-raw.ps1'))
    Assert-EqualLines -Name 'default vault-root detector run' -Expected $expected -Actual $defaultOutput

    Write-Host 'All get-pending-raw tests passed.'
} finally {
    if (Test-Path -LiteralPath $FixtureRoot) {
        Assert-SafeFixturePath $FixtureRoot
        Remove-Item -LiteralPath $FixtureRoot -Recurse -Force
    }
}
