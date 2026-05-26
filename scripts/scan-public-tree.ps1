[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TreeRoot,

    [string]$SourceRoot,

    [string]$PrivateRootName,

    [string]$UserProfile = $env:USERPROFILE,

    [switch]$AllowRootGit
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

$resolvedTreeRoot = Normalize-PublicScanFullPath $TreeRoot
$findings = @(Find-PublicTreeScanFindings `
    -TreeRoot $resolvedTreeRoot `
    -SourceRoot $SourceRoot `
    -PrivateRootName $PrivateRootName `
    -UserProfile $UserProfile `
    -AllowRootGit:$AllowRootGit)

Write-PublicScanReport -Name "public tree scan for $resolvedTreeRoot" -Findings $findings
if ($findings.Count -gt 0) {
    exit 1
}
exit 0
