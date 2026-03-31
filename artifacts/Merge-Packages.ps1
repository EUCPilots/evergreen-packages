#Requires -Version 5.1
<#
.SYNOPSIS
    Merges intune and shell-apps package directories into a unified combined tree.
    
.DESCRIPTION
    Inventories intune/ and shell-apps/ directories, identifies matched/intune-only/shell-only packages,
    and generates a normalized structure in combined/ with merged App.json files following the refined schema.
    
    Source trees remain untouched; all output is copy-only into combined/.
    
.PARAMETER SourceRoot
    Workspace root containing intune, shell-apps, and combined directories.
    
.EXAMPLE
    .\Merge-Packages.ps1 -SourceRoot 'C:\projects\_EUCPilots\evergreen-packages'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SourceRoot
)

$ErrorActionPreference = 'Stop'

# Directories
$intuneDir = Join-Path $SourceRoot 'intune'
$shellAppsDir = Join-Path $SourceRoot 'shell-apps'
$combinedDir = Join-Path $SourceRoot 'combined'

# Report file
$reportPath = Join-Path $SourceRoot 'migration-report.json'

Write-Verbose "Source Root: $SourceRoot"
Write-Verbose "Intune Dir: $intuneDir"
Write-Verbose "Shell-Apps Dir: $shellAppsDir"
Write-Verbose "Combined Dir: $combinedDir"

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

function Normalize-ProductName {
    <#
    .SYNOPSIS
        Normalize product names for comparison and matching.
    #>
    param([string]$Name)
    
    # Remove VDI, Current, LTSR suffixes for base product matching
    $base = $Name -replace '(VDI|Current|LTSR)$', '' -replace '-$', ''
    
    # Standardize naming
    $base = $base -replace 'Reader$', 'Reader'
    $base = $base -replace 'Desktop$', ''
    $base = $base -replace 'Offline.*', ''
    
    return $base
}

function Get-VariantSuffix {
    <#
    .SYNOPSIS
        Extract variant suffix (VDI, Current, LTSR, etc.) from package name.
    #>
    param([string]$Name)
    
    if ($Name -match '(VDI)$') { return 'VDI' }
    if ($Name -match '(Current)$') { return 'Current' }
    if ($Name -match '(LTSR)$') { return 'LTSR' }
    
    return $null
}

function Normalize-FolderName {
    <#
    .SYNOPSIS
        Convert folder names to filesystem-safe names (replace dots, normalize case).
    #>
    param([string]$Name)
    
    # Replace dots with hyphens (Microsoft.NETLTS -> Microsoft-NETLTS)
    $Name = $Name -replace '\.', '-'
    
    return $Name
}

function Build-IntuneInventory {
    <#
    .SYNOPSIS
        Scan intune/ and build a package inventory.
    #>
    $inventory = @()
    
    Get-ChildItem $intuneDir -Directory | Where-Object { $_.Name -ne 'Source' } | ForEach-Object {
        $pkgFolder = $_
        $appJsonPath = Join-Path $pkgFolder 'App.json'
        
        if (Test-Path $appJsonPath) {
            try {
                $appJson = Get-Content $appJsonPath | ConvertFrom-Json
                
                $productName = Normalize-ProductName $pkgFolder.Name
                $variant = Get-VariantSuffix $pkgFolder.Name
                $publisher = $appJson.Information.Publisher
                
                $inventory += [PSCustomObject]@{
                    Source            = 'intune'
                    FolderName        = $pkgFolder.Name
                    FolderPath        = $pkgFolder.FullName
                    ProductName       = $productName
                    Variant           = $variant
                    Publisher         = $publisher
                    Title             = $appJson.Application.Title
                    AppJsonPath       = $appJsonPath
                    SourceDir         = Join-Path $pkgFolder 'Source'
                    HasSourceDir      = (Test-Path (Join-Path $pkgFolder 'Source'))
                }
            }
            catch {
                Write-Error "Failed to parse $appJsonPath : $_"
            }
        }
    }
    
    return $inventory
}

function Build-ShellAppsInventory {
    <#
    .SYNOPSIS
        Scan shell-apps/ and build a package inventory.
    #>
    $inventory = @()
    
    Get-ChildItem $shellAppsDir -Directory | ForEach-Object {
        $publisherFolder = $_
        
        Get-ChildItem $publisherFolder.FullName -Directory | ForEach-Object {
            $appFolder = $_
            $defJsonPath = Join-Path $appFolder.FullName 'Definition.json'
            
            if (Test-Path $defJsonPath) {
                try {
                    $defJson = Get-Content $defJsonPath | ConvertFrom-Json
                    
                    $productName = Normalize-ProductName $appFolder.Name
                    $variant = Get-VariantSuffix $appFolder.Name
                    $publisher = $defJson.publisher
                    
                    $inventory += [PSCustomObject]@{
                        Source             = 'shell-apps'
                        PublisherFolder    = $publisherFolder.Name
                        FolderName         = $appFolder.Name
                        FolderPath         = $appFolder.FullName
                        ProductName        = $productName
                        Variant            = $variant
                        Publisher          = $publisher
                        Title              = $defJson.name
                        Description        = $defJson.description
                        DefJsonPath        = $defJsonPath
                        DetectScriptPath   = Join-Path $appFolder.FullName 'Detect.ps1'
                        InstallScriptPath  = Join-Path $appFolder.FullName 'Install.ps1'
                        UninstallScriptPath = Join-Path $appFolder.FullName 'Uninstall.ps1'
                        HasDetect          = (Test-Path (Join-Path $appFolder.FullName 'Detect.ps1'))
                        HasInstall         = (Test-Path (Join-Path $appFolder.FullName 'Install.ps1'))
                        HasUninstall       = (Test-Path (Join-Path $appFolder.FullName 'Uninstall.ps1'))
                    }
                }
                catch {
                    Write-Error "Failed to parse $defJsonPath : $_"
                }
            }
        }
    }
    
    return $inventory
}

function Match-Packages {
    <#
    .SYNOPSIS
        Match intune and shell-apps packages by product name and publisher.
    #>
    param(
        [PSCustomObject[]]$IntuneInventory,
        [PSCustomObject[]]$ShellAppsInventory
    )
    
    $matches = @()
    $unmatched_intune = @()
    $unmatched_shell = @()
    $shell_matched = @()
    
    foreach ($intuneItem in $IntuneInventory) {
        $shellMatch = $ShellAppsInventory | Where-Object {
            $_.ProductName -eq $intuneItem.ProductName -and
            $_.Publisher -eq $intuneItem.Publisher -and
            $_.Variant -eq $intuneItem.Variant
        }
        
        if ($shellMatch) {
            $matches += [PSCustomObject]@{
                Status        = 'matched'
                IntuneFolder  = $intuneItem.FolderName
                IntunePath    = $intuneItem.FolderPath
                ShellFolder   = $shellMatch.FolderName
                ShellPath     = $shellMatch.FolderPath
                Publisher     = $intuneItem.Publisher
                ProductName   = $intuneItem.ProductName
                Variant       = $intuneItem.Variant
                Title         = $intuneItem.Title
                IntuneItem    = $intuneItem
                ShellItem     = $shellMatch
            }
            $shell_matched += $shellMatch
        }
        else {
            $unmatched_intune += [PSCustomObject]@{
                Status      = 'intune-only'
                Folder      = $intuneItem.FolderName
                Path        = $intuneItem.FolderPath
                Publisher   = $intuneItem.Publisher
                ProductName = $intuneItem.ProductName
                Variant     = $intuneItem.Variant
                Title       = $intuneItem.Title
                Item        = $intuneItem
            }
        }
    }
    
    foreach ($shellItem in $ShellAppsInventory) {
        if ($shellItem -notin $shell_matched) {
            $unmatched_shell += [PSCustomObject]@{
                Status      = 'shell-only'
                Folder      = $shellItem.FolderName
                Path        = $shellItem.FolderPath
                Publisher   = $shellItem.Publisher
                ProductName = $shellItem.ProductName
                Variant     = $shellItem.Variant
                Title       = $shellItem.Title
                Item        = $shellItem
            }
        }
    }
    
    return @{
        Matched        = $matches
        IntuneOnly     = $unmatched_intune
        ShellOnly      = $unmatched_shell
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "Phase 1: Building inventory..."
$intuneInv = Build-IntuneInventory
$shellAppsInv = Build-ShellAppsInventory

Write-Host "  Found $($intuneInv.Count) intune packages"
Write-Host "  Found $($shellAppsInv.Count) shell-apps packages"

Write-Host "Phase 2: Matching packages..."
$packageMap = Match-Packages $intuneInv $shellAppsInv

Write-Host "  Matched pairs: $($packageMap.Matched.Count)"
Write-Host "  Intune-only: $($packageMap.IntuneOnly.Count)"
Write-Host "  Shell-only: $($packageMap.ShellOnly.Count)"

# Export report
$report = @{
    Timestamp       = (Get-Date -Format 'o')
    SourceRoot      = $SourceRoot
    Matched         = $packageMap.Matched | Select-Object Status, Publisher, ProductName, Variant, Title, IntuneFolder, ShellFolder
    IntuneOnly      = $packageMap.IntuneOnly | Select-Object Status, Publisher, ProductName, Variant, Title, Folder
    ShellOnly       = $packageMap.ShellOnly | Select-Object Status, Publisher, ProductName, Variant, Title, Folder
    Summary         = @{
        TotalIntune     = $intuneInv.Count
        TotalShellApps  = $shellAppsInv.Count
        Matched         = $packageMap.Matched.Count
        IntuneOnly      = $packageMap.IntuneOnly.Count
        ShellOnly       = $packageMap.ShellOnly.Count
        Expected_Total  = $intuneInv.Count + $shellAppsInv.Count - $packageMap.Matched.Count
    }
}

$report | ConvertTo-Json -Depth 10 | Set-Content $reportPath
Write-Host "Migration report saved: $reportPath"

# Save the full object map for the generation phase
$mapCachePath = Join-Path $SourceRoot '.migration-map.clixml'
$packageMap | Export-Clixml -Path $mapCachePath
Write-Host "Package map cached: $mapCachePath"

Write-Host "`nInventory Phase Complete"
Write-Host "Next: Run Merge-Packages-Generate.ps1 to create the combined tree"
