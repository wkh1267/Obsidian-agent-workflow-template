[CmdletBinding()]
param(
    [string]$VaultRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-VaultRoot {
    param([AllowEmptyString()][string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            Split-Path -Parent $MyInvocation.MyCommand.Path
        } else {
            $PSScriptRoot
        }
        $Root = Join-Path $scriptRoot '..'
    }

    return [System.IO.Path]::GetFullPath($Root)
}

function Read-FrontmatterLines {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $lines = [regex]::Split($text, '\r?\n')
    if ($lines.Count -eq 0) {
        return @()
    }

    $first = $lines[0].Trim().TrimStart([char]0xFEFF)
    if ($first -ne '---') {
        return @()
    }

    $frontmatter = [System.Collections.Generic.List[string]]::new()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') {
            return $frontmatter.ToArray()
        }
        [void]$frontmatter.Add($lines[$i])
    }

    return @()
}

function ConvertFrom-YamlScalar {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $text = $Value.Trim()
    if ($text.Length -ge 2) {
        $first = $text[0]
        $last = $text[$text.Length - 1]
        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            $text = $text.Substring(1, $text.Length - 2)
        }
    }

    return $text
}

function Normalize-SourcePath {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $path = ConvertFrom-YamlScalar $Value
    $path = $path.Trim()

    if ($path -match '^\[\[(?<target>.*)\]\]$') {
        $path = $Matches.target.Trim()
    }

    $aliasIndex = $path.IndexOf('|')
    if ($aliasIndex -ge 0) {
        $path = $path.Substring(0, $aliasIndex)
    }

    $path = (ConvertFrom-YamlScalar $path).Trim()
    $path = $path -replace '\\', '/'

    if ($path.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
        $path = $path.Substring(0, $path.Length - 3)
    }

    $path = $path.Trim()
    if ($path -eq '') {
        return $null
    }

    return $path
}

function Get-IngestSources {
    param([Parameter(Mandatory = $true)][string[]]$FrontmatterLines)

    $operation = $null
    $sources = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $FrontmatterLines.Count; $i++) {
        $line = $FrontmatterLines[$i]
        if ($line -match '^\s*(#.*)?$') {
            continue
        }

        if ($line -notmatch '^(?<key>[A-Za-z0-9_-]+)\s*:\s*(?<value>.*)$') {
            continue
        }

        $key = $Matches.key
        $value = $Matches.value

        if ($key -eq 'operation') {
            $operation = ConvertFrom-YamlScalar $value
            continue
        }

        if ($key -ne 'source') {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $normalized = Normalize-SourcePath $value
            if ($null -ne $normalized) {
                [void]$sources.Add($normalized)
            }
            continue
        }

        for ($j = $i + 1; $j -lt $FrontmatterLines.Count; $j++) {
            $next = $FrontmatterLines[$j]
            if ($next -match '^[A-Za-z0-9_-]+\s*:') {
                break
            }

            if ($next -match '^\s*-\s*(?<item>.*)$') {
                $normalized = Normalize-SourcePath $Matches.item
                if ($null -ne $normalized) {
                    [void]$sources.Add($normalized)
                }
            }
        }
    }

    if ($operation -ne 'ingest') {
        return @()
    }

    return $sources.ToArray()
}

function Sort-Ordinal {
    param([AllowEmptyCollection()][string[]]$Values)

    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($value in $Values) {
        [void]$items.Add($value)
    }
    $items.Sort([System.StringComparer]::Ordinal)
    return $items.ToArray()
}

$resolvedVaultRoot = Resolve-VaultRoot $VaultRoot
$rawRoot = Join-Path $resolvedVaultRoot 'raw'
$logRoot = Join-Path $resolvedVaultRoot 'log'

$processed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
if (Test-Path -LiteralPath $logRoot -PathType Container) {
    $logFiles = @(Get-ChildItem -LiteralPath $logRoot -File -Filter '*.md')
    foreach ($logFile in $logFiles) {
        $frontmatter = Read-FrontmatterLines $logFile.FullName
        foreach ($source in (Get-IngestSources $frontmatter)) {
            [void]$processed.Add($source)
        }
    }
}

$rawSources = [System.Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $rawRoot -PathType Container) {
    $rawFiles = @(Get-ChildItem -LiteralPath $rawRoot -File -Filter '*.md')
    foreach ($rawFile in $rawFiles) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($rawFile.Name)
        [void]$rawSources.Add("raw/$name")
    }
}

$pending = [System.Collections.Generic.List[string]]::new()
foreach ($source in $rawSources) {
    if (-not $processed.Contains($source)) {
        [void]$pending.Add($source)
    }
}

foreach ($source in (Sort-Ordinal $pending.ToArray())) {
    Write-Output $source
}
