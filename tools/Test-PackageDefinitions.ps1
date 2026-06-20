[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [System.String] $RepositoryRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

[System.Collections.Generic.List[System.String]]$script:ValidationErrors = [System.Collections.Generic.List[System.String]]::new()
[System.Collections.Generic.List[System.String]]$script:ValidationWarnings = [System.Collections.Generic.List[System.String]]::new()

function Add-ValidationError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.String] $Message
    )

    $script:ValidationErrors.Add($Message)
}

function Add-ValidationWarning {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.String] $Message
    )

    $script:ValidationWarnings.Add($Message)
}

function Test-NestedProperty {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Object] $InputObject,

        [Parameter(Mandatory = $true)]
        [System.String] $PropertyPath
    )

    $current = $InputObject
    foreach ($segment in ($PropertyPath -split "\.")) {
        if ($null -eq $current) {
            return $false
        }

        if ($current -is [System.Array]) {
            if ($current.Count -lt 1) {
                return $false
            }

            $current = $current[0]
        }

        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) {
            return $false
        }

        $current = $property.Value
    }

    return $true
}

function Test-JsonDefinition {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.String] $Path,

        [Parameter(Mandatory = $true)]
        [System.String[]] $RequiredProperties
    )

    try {
        [System.String]$content = Get-Content -Path $Path -Raw -Encoding UTF8
        $json = $content | ConvertFrom-Json -ErrorAction Stop

        foreach ($requiredProperty in $RequiredProperties) {
            if (-not (Test-NestedProperty -InputObject $json -PropertyPath $requiredProperty)) {
                Add-ValidationError -Message "Missing property '$requiredProperty' in $Path"
            }
        }
    }
    catch {
        Add-ValidationError -Message "Invalid JSON in ${Path}: $($_.Exception.Message)"
    }
}

function Test-XmlDefinition {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.String] $Path
    )

    try {
        [void][xml](Get-Content -Path $Path -Raw -Encoding UTF8)
    }
    catch {
        Add-ValidationError -Message "Invalid XML in ${Path}: $($_.Exception.Message)"
    }
}

if (-not (Test-Path -Path $RepositoryRoot -PathType Container)) {
    throw "Repository root not found: $RepositoryRoot"
}

$intuneRoot = Join-Path -Path $RepositoryRoot -ChildPath "intune"
$m365Root = Join-Path -Path $RepositoryRoot -ChildPath "m365"
$shellRoot = Join-Path -Path $RepositoryRoot -ChildPath "shell-apps"

$intuneRequiredProperties = @(
    "Application.Name",
    "Application.Filter",
    "PackageInformation.SetupFile",
    "PackageInformation.Version",
    "Program.InstallCommand",
    "Program.UninstallCommand",
    "RequirementRule.Architecture",
    "DetectionRule"
)

$shellRequiredProperties = @(
    "name",
    "description",
    "publisher",
    "detectScript",
    "installScript",
    "uninstallScript",
    "versions",
    "source.type",
    "source.app",
    "source.filter"
)

if (Test-Path -Path $intuneRoot -PathType Container) {
    Get-ChildItem -Path $intuneRoot -Filter "App.json" -Recurse -File | ForEach-Object {
        $appJson = $_.FullName
        Test-JsonDefinition -Path $appJson -RequiredProperties $intuneRequiredProperties

        $appDefinition = $null
        try {
            $appDefinition = Get-Content -Path $appJson -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Add-ValidationError -Message "Unable to parse Intune definition ${appJson}: $($_.Exception.Message)"
            return
        }

        $appFolder = Split-Path -Path $appJson -Parent
        $sourcePath = Join-Path -Path $appFolder -ChildPath "Source"
        $installScriptPath = Join-Path -Path $sourcePath -ChildPath "Install.ps1"
        $installJsonPath = Join-Path -Path $sourcePath -ChildPath "Install.json"
        $uninstallScriptPath = Join-Path -Path $sourcePath -ChildPath "Uninstall.ps1"

        if (-not (Test-Path -Path $sourcePath -PathType Container)) {
            Add-ValidationError -Message "Missing Source folder for Intune app: $appFolder"
        }

        # Most packages use the shared root Install.ps1 + app-specific Install.json.
        # Some packages include a dedicated Source/Install.ps1 implementation.
        if ((-not (Test-Path -Path $installScriptPath -PathType Leaf)) -and (-not (Test-Path -Path $installJsonPath -PathType Leaf))) {
            Add-ValidationWarning -Message "Missing Install.ps1 or Install.json for Intune app: $appFolder"
        }

        $uninstallCommand = [System.String]$appDefinition.Program.UninstallCommand
        if (($uninstallCommand -match "Uninstall\.ps1") -and (-not (Test-Path -Path $uninstallScriptPath -PathType Leaf))) {
            Add-ValidationWarning -Message "Missing Uninstall.ps1 for Intune app: $appFolder"
        }
    }
}

if (Test-Path -Path $shellRoot -PathType Container) {
    Get-ChildItem -Path $shellRoot -Filter "Definition.json" -Recurse -File | ForEach-Object {
        $definitionJson = $_.FullName
        Test-JsonDefinition -Path $definitionJson -RequiredProperties $shellRequiredProperties

        $definitionFolder = Split-Path -Path $definitionJson -Parent
        $detectScriptPath = Join-Path -Path $definitionFolder -ChildPath "Detect.ps1"
        $installScriptPath = Join-Path -Path $definitionFolder -ChildPath "Install.ps1"
        $uninstallScriptPath = Join-Path -Path $definitionFolder -ChildPath "Uninstall.ps1"

        if (-not (Test-Path -Path $detectScriptPath -PathType Leaf)) {
            Add-ValidationError -Message "Missing Detect.ps1 for shell app: $definitionFolder"
        }

        if (-not (Test-Path -Path $installScriptPath -PathType Leaf)) {
            Add-ValidationError -Message "Missing Install.ps1 for shell app: $definitionFolder"
        }

        if (-not (Test-Path -Path $uninstallScriptPath -PathType Leaf)) {
            Add-ValidationError -Message "Missing Uninstall.ps1 for shell app: $definitionFolder"
        }
    }
}

if (Test-Path -Path $m365Root -PathType Container) {
    Get-ChildItem -Path $m365Root -Filter "*.xml" -File | ForEach-Object {
        Test-XmlDefinition -Path $_.FullName
    }
}

if ($script:ValidationErrors.Count -gt 0) {
    Write-Host "Package definition validation failed with $($script:ValidationErrors.Count) issue(s):" -ForegroundColor Red
    foreach ($validationError in $script:ValidationErrors) {
        Write-Host " - $validationError" -ForegroundColor Red
    }

    exit 1
}

if ($script:ValidationWarnings.Count -gt 0) {
    Write-Host "Package definition validation warnings: $($script:ValidationWarnings.Count)" -ForegroundColor Yellow
    foreach ($validationWarning in $script:ValidationWarnings) {
        Write-Host " - $validationWarning" -ForegroundColor Yellow
    }
}

Write-Host "Package definition validation passed." -ForegroundColor Green
exit 0