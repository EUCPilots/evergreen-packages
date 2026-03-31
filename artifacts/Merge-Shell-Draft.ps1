[CmdletBinding()]
param([string]$SourceRoot = 'C:\projects\_EUCPilots\evergreen-packages')

$shellAppsDir = Join-Path $SourceRoot 'shell-apps'
$combinedDir = Join-Path $SourceRoot 'combined'
$draftDir = Join-Path $combinedDir 'shell-only-draft'

Write-Host 'Loading shell-apps inventory...'
$shellJson = Get-Content (Join-Path $SourceRoot 'shell-inventory.json') | ConvertFrom-Json
if ($shellJson -isnot [array]) { $shellJson = @($shellJson) }

Write-Host "Found $($shellJson.Count) shell-apps packages"

Write-Host "`nPhase: Creating shell-only packages in draft folder..."
$draftCount = 0

foreach ($item in $shellJson) {
    $pub = $item.Publisher.Replace(' ', '').Replace('-', '')
    $name = $item.Folder.Replace('.', '-')
    
    $pubPath = Join-Path $draftDir $pub
    $destPath = Join-Path $pubPath $name
    
    if (-not (Test-Path $destPath)) {
        New-Item -ItemType Directory -Path $destPath -Force > $null
    }
    
    # Create fallback App.json
    $appJson = @{
        'Application' = @{
            'Name' = $name
            'Title' = $item.Title
            'Language' = 'en-US'
            'Architecture' = 'x64'
            'source' = $item.Json.source
        }
        'PackageInformation' = @{
            'SetupType' = 'EXE'
            'SetupFile' = ''
            'Version' = 'auto'
            'SourceFolder' = 'Source'
            'OutputFolder' = 'Package'
            'IconFile' = ''
        }
        'Information' = @{
            'DisplayName' = $item.Title
            'Description' = $item.Description
            'Publisher' = $item.Publisher
            'InformationURL' = ''
            'PrivacyURL' =''
            'Categories' = @()
        }
        'RequirementRule' = @{
            'MinimumRequiredOperatingSystem' = 'W10_1809'
            'Architecture' = 'x64'
        }
        'CustomRequirementRule' = @()
        'DetectionRule' = @()
        'Supersedence' = @()
        'ShellApp' = @{
            'isPublic' = $item.Json.isPublic
            'detectScript' = $item.Json.detectScript
            'installScript' = $item.Json.installScript
            'uninstallScript' = $item.Json.uninstallScript
            'fileUnzip' = $item.Json.fileUnzip
            'versions' = $item.Json.versions
        }
    }
    
    # Write App.json
    $appJsonDest = Join-Path $destPath 'App.json'
    $appJson | ConvertTo-Json -Depth 10 | Set-Content $appJsonDest
    
    # Copy scripts
    foreach ($scriptName in @('Detect.ps1', 'Install.ps1', 'Uninstall.ps1')) {
        $srcScript = Join-Path $item.Path $scriptName
        $destScript = Join-Path $destPath $scriptName
        if (Test-Path $srcScript) {
            Copy-Item $srcScript $destScript -Force
        }
    }
    
    $draftCount++
}

Write-Host "Created $draftCount shell-only packages in draft folder"
Write-Host "Draft folder: $draftDir"
Write-Host "`nNext step: Review packages in draft folder and move to main combined tree as needed"
