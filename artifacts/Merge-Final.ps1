[CmdletBinding()]
param([string]$SourceRoot = 'C:\projects\_EUCPilots\evergreen-packages')

$intuneDir = Join-Path $SourceRoot 'intune'
$shellAppsDir = Join-Path $SourceRoot 'shell-apps'
$combinedDir = Join-Path $SourceRoot 'combined'

Write-Host 'Loading inventories...'
$intuneJson = Get-Content (Join-Path $SourceRoot 'intune-inventory.json') | ConvertFrom-Json
$shellJson = Get-Content (Join-Path $SourceRoot 'shell-inventory.json') | ConvertFrom-Json

if ($intuneJson -isnot [array]) { $intuneJson = @($intuneJson) }
if ($shellJson -isnot [array]) { $shellJson = @($shellJson) }

Write-Host "Found $($intuneJson.Count) intune, $($shellJson.Count) shell-apps packages"

Write-Host "`nPhase 1: Creating combined tree for intune packages..."
$intCount = 0
foreach ($item in $intuneJson) {
    $pub = $item.Publisher.Replace(' ', '').Replace('-', '')
    $name = $item.Folder.Replace('.', '-')
    
    $pubPath = Join-Path $combinedDir $pub
    $destPath = Join-Path $pubPath $name
    
    if (-not (Test-Path $destPath)) {
        New-Item -ItemType Directory -Path $destPath -Force > $null
    }
    
    # Copy App.json
    $srcApp = Join-Path $item.Path 'App.json'
    $destApp = Join-Path $destPath 'App.json'
    if (Test-Path $srcApp) {
        Copy-Item $srcApp $destApp -Force
    }
    
    # Copy Source folder if exists
    $srcFolder = Join-Path $item.Path 'Source'
    $destFolder = Join-Path $destPath 'Source'
    if ((Test-Path $srcFolder) -and -not (Test-Path $destFolder)) {
        Copy-Item $srcFolder $destFolder -Recurse -Force
    }
    
    $intCount++
    if ($intCount % 10 -eq 0) {
        Write-Host "  Processed $intCount packages..."
    }
}

Write-Host "  Total: $intCount intune packages"

# Summary
Write-Host "`nMigration complete!"
Write-Host "Output: $combinedDir"
Write-Host "Check: $(Get-ChildItem $combinedDir -Directory | Measure-Object | Select -ExpandProperty Count) publisher folders created"
