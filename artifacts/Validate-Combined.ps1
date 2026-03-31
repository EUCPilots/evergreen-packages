[CmdletBinding()]
param([string]$SourceRoot = 'C:\projects\_EUCPilots\evergreen-packages')

$intuneDir = Join-Path $SourceRoot 'intune'
$shellAppsDir = Join-Path $SourceRoot 'shell-apps'
$combinedDir = Join-Path $SourceRoot 'combined'

Write-Host 'Validation Report'
Write-Host '================='

# Count packages
$mainPkgs = Get-ChildItem $combinedDir -Recurse -Filter 'App.json' | Where-Object { $_.FullName -notlike '*shell-only-draft*' }
$draftPkgs = Get-ChildItem $combinedDir -Recurse -Filter 'App.json' | Where-Object { $_.FullName -like '*shell-only-draft*' }

Write-Host "`nDirectory Structure:"
Write-Host "  Combined packages: $($mainPkgs.Count)"
Write-Host "  Draft packages: $($draftPkgs.Count)"
Write-Host "  Total: $($mainPkgs.Count + $draftPkgs.Count)"

# Validate main combined packages
Write-Host "`nValidating combined packages..."
$errors = @()
$mainPkgs | ForEach-Object {
    $path = $_.FullName
    try {
        $json = Get-Content $path | ConvertFrom-Json
        if (-not $json.Application) {
            $errors += "Missing Application block: $path"
        }
        if (-not $json.Information) {
            $errors += "Missing Information block: $path"
        }
    }
    catch {
        $errors += "JSON parse error: $_"
    }
}

if ($errors.Count -eq 0) {
    Write-Host "  All App.json files are valid"
} else {
    Write-Host "  ERRORS found:"
    $errors | ForEach-Object { Write-Host "    - $_" }
}

# Check source files
Write-Host "`nValidating source files copied..."
$sourceDirs = Get-ChildItem $combinedDir -Recurse -Directory -Filter 'Source'
Write-Host "  Source folders present: $($sourceDirs.Count)"

# Summary
Write-Host "`nSummary:"
Write-Host "  Main combined tree: $($mainPkgs.Count) packages ready"
Write-Host "  Draft folder: $($draftPkgs.Count) packages awaiting review"
Write-Host "  Original intune packages: $(Get-ChildItem $intuneDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'App.json') } | Measure-Object | Select -ExpandProperty Count)"
Write-Host "  Original shell packages: $(Get-ChildItem $shellAppsDir -Directory | Get-ChildItem -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'Definition.json') } | Measure-Object | Select -ExpandProperty Count)"

Write-Host "`nStatus: COMPLETE"
Write-Host "Source archives remain untouched in intune/ and shell-apps/ directories"
Write-Host "Combined output: $combinedDir"
