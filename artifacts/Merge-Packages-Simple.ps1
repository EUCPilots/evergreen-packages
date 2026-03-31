#Requires -Version 5.1
<#
.SYNOPSIS
    Simplified merge script for combining intune and shell-apps packages.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SourceRoot
)

$ErrorActionPreference = 'Continue'  # Don't fail on individual errors

$intuneDir = Join-Path $SourceRoot 'intune'
$shellAppsDir = Join-Path $SourceRoot 'shell-apps'
$combinedDir = Join-Path $SourceRoot 'combined'

Write-Host "Scanning intune directory..."
$intunePackages = @()
Get-ChildItem $intuneDir -Directory | ForEach-Object {
    $folder = $_
    $appJsonPath = Join-Path $folder.FullName 'App.json'
    
    if (Test-Path $appJsonPath) {
        try {
            $json = Get-Content $appJsonPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $intunePackages += @{
                Source = 'intune'
                Folder = $folder.Name
                Path = $folder.FullName
                AppJsonPath = $appJsonPath
                Publisher = $json.Information.Publisher
                Title = $json.Application.Title
                Json = $json
            }
        }
        catch {
            Write-Warning "Failed to parse $appJsonPath : $_"
        }
    }
}

Write-Host "Found $($intunePackages.Count) intune packages"
Write-Host "  Examples: $(($intunePackages | Select -First 3 | ForEach-Object {$_.Folder}) -join ', ')"

Write-Host "`nScanning shell-apps directory..."
$shellAppPackages = @()
Get-ChildItem $shellAppsDir -Directory | ForEach-Object {
    $publisherFolder = $_
    
    Get-ChildItem $publisherFolder.FullName -Directory | ForEach-Object {
        $appFolder = $_
        $defJsonPath = Join-Path $appFolder.FullName 'Definition.json'
        
        if (Test-Path $defJsonPath) {
            try {
                $json = Get-Content $defJsonPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $shellAppPackages += @{
                    Source = 'shell-apps'
                    PublisherFolder = $publisherFolder.Name
                    Folder = $appFolder.Name
                    Path = $appFolder.FullName
                    DefJsonPath = $defJsonPath
                    Publisher = $json.publisher
                    Title = $json.name
                    Json = $json
                }
            }
            catch {
                Write-Warning "Failed to parse $defJsonPath : $_"
            }
        }
    }
}

Write-Host "Found $($shellAppPackages.Count) shell-apps packages"
Write-Host "  Publishers: $(($shellAppPackages | Select -ExpandProperty PublisherFolder -Unique) -join ', ')"

Write-Host "`nGenerating reports..."

# Create combined directory if it doesn't exist
if (-not (Test-Path $combinedDir)) {
    $null = New-Item -ItemType Directory -Path $combinedDir -Force
}

# Save inventories
$intunePackages | ConvertTo-Json | Set-Content (Join-Path $SourceRoot 'intune-inventory.json')
$shellAppPackages | ConvertTo-Json | Set-Content (Join-Path $SourceRoot 'shell-inventory.json')

Write-Host "Inventory complete!"
Write-Host "  Intune packages: $(Join-Path $SourceRoot 'intune-inventory.json')"
Write-Host "  Shell packages: $(Join-Path $SourceRoot 'shell-inventory.json')"
