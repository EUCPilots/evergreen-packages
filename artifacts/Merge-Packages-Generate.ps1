#Requires -Version 5.1
<#
.SYNOPSIS
    Generates the combined package tree from the package map.
    
.DESCRIPTION
    Reads the package map from Merge-Packages.ps1, creates normalized folder structure,
    generates merged App.json files, and copies supporting files.
    
    Matched packages: Full merge with Intune schema + shell-app metadata
    Intune-only: Copy as-is into combined/Publisher/Application
    Shell-only: Generate into combined/shell-only-draft/ for manual curation
    
.PARAMETER SourceRoot
    Workspace root containing intune, shell-apps, and combined directories.
    
.EXAMPLE
    .\Merge-Packages-Generate.ps1 -SourceRoot 'C:\projects\_EUCPilots\evergreen-packages'
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
$draftDir = Join-Path $combinedDir 'shell-only-draft'

# Load the package map
$mapCachePath = Join-Path $SourceRoot '.migration-map.clixml'
if (-not (Test-Path $mapCachePath)) {
    throw "Package map not found. Run Merge-Packages.ps1 first."
}

$packageMap = Import-Clixml $mapCachePath
Write-Verbose "Package map loaded from $mapCachePath"

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

function New-MergedAppJson {
    <#
    .SYNOPSIS
        Create merged App.json for matched packages (Intune schema + shell-app metadata).
    #>
    param(
        [PSCustomObject]$IntuneItem,
        [PSCustomObject]$ShellItem
    )
    
    # Load source files
    $appJson = Get-Content $IntuneItem.AppJsonPath | ConvertFrom-Json
    $defJson = Get-Content $ShellItem.DefJsonPath | ConvertFrom-Json
    
    # Merge: Replace Application.Filter with Application.source (nested)
    $appJson.Application | Add-Member -MemberType NoteProperty -Name 'source' -Value $defJson.source -Force
    $appJson.Application | Add-Member -MemberType NoteProperty -Name 'Description' -Value $defJson.description -Force
    
    # Add ShellApp block
    $shellAppBlock = @{
        isPublic           = $defJson.isPublic
        detectScript       = $defJson.detectScript
        installScript      = $defJson.installScript
        uninstallScript    = $defJson.uninstallScript
        fileUnzip          = $defJson.fileUnzip
        versions           = $defJson.versions
    }
    
    $appJson | Add-Member -MemberType NoteProperty -Name 'ShellApp' -Value $shellAppBlock -Force
    
    return $appJson
}

function New-ShellOnlyAppJson {
    <#
    .SYNOPSIS
        Create fallback App.json for shell-only packages (empty Intune sections, shell-app metadata).
    #>
    param([PSCustomObject]$ShellItem)
    
    $defJson = Get-Content $ShellItem.DefJsonPath | ConvertFrom-Json
    
    # Build shell-only App.json following fallback schema
    $appJson = @{
        Application = @{
            Name         = $ShellItem.FolderName
            Title        = $defJson.name
            Language     = 'en-US'
            Architecture = 'x64'
            source       = $defJson.source
        }
        PackageInformation = @{
            SetupType      = 'EXE'
            SetupFile      = ''
            Version        = 'auto'
            SourceFolder   = 'Source'
            OutputFolder   = 'Package'
            IconFile       = ''
        }
        Information = @{
            DisplayName     = $defJson.name
            Description     = $defJson.description
            Publisher       = $defJson.publisher
            InformationURL  = ''
            PrivacyURL      = ''
            Categories      = @()
        }
        RequirementRule = @{
            MinimumRequiredOperatingSystem = 'W10_1809'
            Architecture                   = 'x64'
        }
        CustomRequirementRule = @()
        DetectionRule         = @()
        Supersedence          = @()
        ShellApp = @{
            isPublic      = $defJson.isPublic
            detectScript  = $defJson.detectScript
            installScript = $defJson.installScript
            uninstallScript = $defJson.uninstallScript
            fileUnzip     = $defJson.fileUnzip
            versions      = $defJson.versions
        }
    }
    
    return $appJson
}

function Copy-PackageContent {
    <#
    .SYNOPSIS
        Copy supporting files from source to destination package folder.
    #>
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [string[]]$ScriptsToCopy = @()
    )
    
    if (-not (Test-Path $DestPath)) {
        $null = New-Item -ItemType Directory -Path $DestPath -Force
    }
    
    # Copy Source directory if it exists
    $sourceSubDir = Join-Path $SourcePath 'Source'
    if (Test-Path $sourceSubDir) {
        $destSourceDir = Join-Path $DestPath 'Source'
        if (-not (Test-Path $destSourceDir)) {
            Copy-Item $sourceSubDir -Destination $destSourceDir -Recurse -Force
        }
    }
    
    # Copy specified scripts
    foreach ($script in $ScriptsToCopy) {
        if (Test-Path $script) {
            $scriptName = Split-Path $script -Leaf
            $destScript = Join-Path $DestPath $scriptName
            Copy-Item $script -Destination $destScript -Force
        }
    }
}

function Get-DestinationPath {
    <#
    .SYNOPSIS
        Normalize folder name and compute destination path.
    #>
    param(
        [string]$FolderName,
        [string]$Publisher,
        [string]$Variant = $null,
        [string]$Root = $combinedDir,
        [bool]$IsDraft = $false
    )
    
    # Normalize folder name (replace dots)
    $normalized = $FolderName -replace '\.', '-'
    
    # Remove Variant suffix from normalized name for base path
    if ($Variant) {
        $base = $normalized -replace "$Variant`$", '' -replace '-$', ''
    } else {
        $base = $normalized
    }
    
    if ($IsDraft) {
        $path = Join-Path $Root 'shell-only-draft' $Publisher $base
    } else {
        $path = Join-Path $Root $Publisher $base
    }
    
    # Add variant as suffix folder if present
    if ($Variant) {
        $path = Join-Path $path $Variant
    }
    
    return $path
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Generation
# ─────────────────────────────────────────────────────────────────────────────

$stats = @{
    MatchedGenerated = 0
    IntuneOnlyGenerated = 0
    ShellOnlyGenerated = 0
    Errors = @()
}

Write-Host "Phase 3: Generating matched packages..."
foreach ($match in $packageMap.Matched) {
    try {
        $destPath = Get-DestinationPath -FolderName $match.IntuneFolder -Publisher $match.Publisher -Variant $match.Variant -Root $combinedDir
        
        # Generate merged App.json
        $mergedJson = New-MergedAppJson -IntuneItem $match.IntuneItem -ShellItem $match.ShellItem
        
        # Create destination folder
        $null = New-Item -ItemType Directory -Path $destPath -Force -ErrorAction SilentlyContinue
        
        # Write merged App.json
        $appJsonDest = Join-Path $destPath 'App.json'
        $mergedJson | ConvertTo-Json -Depth 32 | Set-Content $appJsonDest -Encoding UTF8
        
        # Copy shell-app scripts
        $scriptsToCopy = @(
            $match.ShellItem.DetectScriptPath,
            $match.ShellItem.InstallScriptPath,
            $match.ShellItem.UninstallScriptPath
        )
        
        # Copy intune Source and shell scripts
        Copy-PackageContent -SourcePath $match.IntunePath -DestPath $destPath -ScriptsToCopy $scriptsToCopy
        
        Write-Host "  ✓ $($match.Publisher)/$($match.ProductName)" -ForegroundColor Green
        $stats.MatchedGenerated++
    }
    catch {
        Write-Host "  ✗ $($match.Publisher)/$($match.ProductName): $_" -ForegroundColor Red
        $stats.Errors += "Matched $($match.Publisher)/$($match.ProductName): $_"
    }
}

Write-Host "Phase 4: Generating intune-only packages..."
foreach ($intuneOnly in $packageMap.IntuneOnly) {
    try {
        $destPath = Get-DestinationPath -FolderName $intuneOnly.Folder -Publisher $intuneOnly.Publisher -Variant $intuneOnly.Variant -Root $combinedDir
        
        # Create destination folder
        $null = New-Item -ItemType Directory -Path $destPath -Force -ErrorAction SilentlyContinue
        
        # Copy Intune App.json as-is
        $appJsonSrc = Join-Path $intuneOnly.Path 'App.json'
        $appJsonDest = Join-Path $destPath 'App.json'
        Copy-Item $appJsonSrc -Destination $appJsonDest -Force
        
        # Copy package content
        Copy-PackageContent -SourcePath $intuneOnly.Path -DestPath $destPath
        
        Write-Host "  ✓ $($intuneOnly.Publisher)/$($intuneOnly.ProductName)" -ForegroundColor Green
        $stats.IntuneOnlyGenerated++
    }
    catch {
        Write-Host "  ✗ $($intuneOnly.Publisher)/$($intuneOnly.ProductName): $_" -ForegroundColor Red
        $stats.Errors += "Intune-only $($intuneOnly.Publisher)/$($intuneOnly.ProductName): $_"
    }
}

Write-Host "Phase 5: Generating shell-only packages to draft folder..."
foreach ($shellOnly in $packageMap.ShellOnly) {
    try {
        $destPath = Get-DestinationPath -FolderName $shellOnly.Folder -Publisher $shellOnly.Publisher -Variant $shellOnly.Variant -Root $combinedDir -IsDraft $true
        
        # Generate fallback App.json
        $shellJson = New-ShellOnlyAppJson -ShellItem $shellOnly.Item
        
        # Create destination folder
        $null = New-Item -ItemType Directory -Path $destPath -Force -ErrorAction SilentlyContinue
        
        # Write fallback App.json
        $appJsonDest = Join-Path $destPath 'App.json'
        $shellJson | ConvertTo-Json -Depth 32 | Set-Content $appJsonDest -Encoding UTF8
        
        # Copy shell-app scripts
        $scriptsToCopy = @(
            $shellOnly.Item.DetectScriptPath,
            $shellOnly.Item.InstallScriptPath,
            $shellOnly.Item.UninstallScriptPath
        )
        
        Copy-PackageContent -SourcePath $shellOnly.Item.FolderPath -DestPath $destPath -ScriptsToCopy $scriptsToCopy
        
        Write-Host "  ✓ $($shellOnly.Publisher)/$($shellOnly.ProductName) → draft/" -ForegroundColor Yellow
        $stats.ShellOnlyGenerated++
    }
    catch {
        Write-Host "  ✗ $($shellOnly.Publisher)/$($shellOnly.ProductName): $_" -ForegroundColor Red
        $stats.Errors += "Shell-only $($shellOnly.Publisher)/$($shellOnly.ProductName): $_"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Report
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n" + ("=" * 80)
Write-Host "Generation Complete"
Write-Host "=" * 80
Write-Host "Matched packages generated: $($stats.MatchedGenerated)"
Write-Host "Intune-only packages generated: $($stats.IntuneOnlyGenerated)"
Write-Host "Shell-only packages (draft): $($stats.ShellOnlyGenerated)"

if ($stats.Errors.Count -gt 0) {
    Write-Host "`nErrors encountered:" -ForegroundColor Red
    $stats.Errors | ForEach-Object { Write-Host "  - $_" }
}

Write-Host "`nOutput folder: $combinedDir"
Write-Host "Shell-only draft folder: $draftDir"
Write-Host "`nNext: Review shell-only packages in $draftDir and move to main combined/ tree as needed"
