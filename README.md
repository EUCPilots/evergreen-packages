# Evergreen Packages

Package definitions for Microsoft Intune Win32 apps, Microsoft 365 deployment
profiles, and Nerdio Manager Shell Apps used by Evergreen Workbench.

## Repository Overview

This repository is organised into three main definition sets:

- `m365/`: Office Deployment Tool XML profiles for Microsoft 365 Apps for importing into Microsoft Intune or Nerdio Manager Shell Apps
- `shell/`: Nerdio Manager Shell App definitions and scripts.
- `win32/`: Win32 app package definitions and source content for importing app packages into Microsoft Intune or installing locally.
- `tools/`: Script for validating package definitions

High-level structure:

```text
.
├── win32/
│   ├── Install.ps1
│   └── <AppName>/
│       ├── App.json
│       └── Source/
│           ├── Install.ps1
│           ├── Uninstall.ps1
│           ├── Detect.ps1 (optional)
│           └── Install.json (optional)
├── m365/
│   ├── O365*.xml
│   ├── Uninstall-Microsoft365Apps.xml
│   └── shell-app/
└── shell/
    └── <Vendor>/<AppName>/
        ├── Definition.json
        ├── Detect.ps1
        ├── Install.ps1
        └── Uninstall.ps1
```

## Intune Definitions (`win32/`)

Each app folder under `win32/` defines one Win32 app package.

Important files:

- `App.json`: Main package definition consumed by Evergreen Workbench.
- `Source/`: Installer scripts and supporting files bundled into the package.
- `Install.ps1` (root): Shared install framework script used by package source
  implementations.

Key `App.json` property groups:

- `Application`: identity and Evergreen discovery expression.
  - `Name`
  - `Filter` (typically `Get-EvergreenApp -Name ... | Where-Object ...`)
  - `Title`, `Language`, `Architecture`
- `PackageInformation`: package build inputs.
  - `SetupType`, `SetupFile`, `Version`, `SourceFolder`, `OutputFolder`, `IconFile`
- `Information`: end-user app metadata.
  - `DisplayName`, `Description`, `Publisher`, URLs, `PSPackageFactoryGuid`
- `Program`: command lines and install behaviour.
  - `InstallCommand`, `UninstallCommand`, `InstallExperience`,
    `DeviceRestartBehavior`
- `RequirementRule` and `CustomRequirementRule`: OS and architecture criteria.
- `DetectionRule`: file, registry, or MSI detection settings.
- `Dependencies`, `Supersedence`, `Assignments`: targeting and lifecycle control.

## Microsoft 365 Profiles (`m365/`)

The `m365/` folder stores Office Deployment Tool configuration XML files for
different app bundles and VDI/non-VDI scenarios.

Important files:

- `O365*.xml`: install configuration templates.
- `Uninstall-Microsoft365Apps.xml`: uninstall configuration profile.

Key XML elements and attributes:

- `<Add OfficeClientEdition="..." Channel="...">`: product architecture and
  servicing channel.
- `<Product ID="...">` with `<Language>` and `<ExcludeApp>`: workload and app
  composition.
- `<Property Name="..." Value="...">`: licensing and behaviour controls.
- `<Updates Enabled="TRUE|FALSE" />`: update management.
- `<RemoveMSI />`: migration from legacy MSI-based Office installations.
- `<AppSettings>` with `<User ...>` entries: Office and Outlook registry-backed
  defaults.
- `<Display Level="None" AcceptEULA="TRUE" />`: silent install behaviour.

Several templates include placeholder values such as `#Channel`, `#TenantId`,
and `#Company`, intended to be replaced by upstream automation.

## Nerdio Shell App Definitions (`shell/`)

The `shell/` folder contains app definitions used by Nerdio Manager shell
app workflows, grouped by vendor and application.

Important files per app:

- `Definition.json`: app metadata, version source, and script bindings.
- `Detect.ps1`: version and state detection logic.
- `Install.ps1`: installation logic and post-install configuration.
- `Uninstall.ps1`: removal logic.

Key `Definition.json` properties:

- `name`, `description`, `publisher`, `isPublic`
- `detectScript`, `installScript`, `uninstallScript`
- `versions[]` with `name`, `isPreview`, `file.sourceUrl`, `file.sha256`
- `source`: upstream release source configuration.
  - `type` is commonly `Evergreen`
  - `app` maps to an Evergreen application identifier
  - `filter` narrows architecture/channel/build selection

## Evergreen PowerShell Usage

Evergreen commands are central to how package versions and binaries are sourced:

- `Get-EvergreenApp` is used broadly in `intune/*/App.json` `Application.Filter`
  expressions to discover the latest valid release for each package.
- `Get-EvergreenApp` is also used through `shell-apps/*/*/Definition.json`
  `source` objects (`type: Evergreen`, `app`, `filter`) to resolve app versions.
- `Save-EvergreenApp` is used in selected implementation scripts (for example,
  Azure Pipelines Agent packaging) to download installer payloads.

In practice, definitions pair Evergreen discovery metadata with local detection,
install, and uninstall scripts to produce repeatable, updateable app packaging.

## Contributing Package Definitions

This repository accepts contributions for Intune Win32 packages, Microsoft 365
ODT XML profiles, and Nerdio shell app definitions.

Start here:

- [Contribution guide](CONTRIBUTING.md)
- [Definition validation script](tools/Test-PackageDefinitions.ps1)

Before opening a pull request:

1. Follow the structure and naming guidance in [CONTRIBUTING.md](CONTRIBUTING.md).
2. Run the validation script:

  ```powershell
  pwsh -File ./tools/Test-PackageDefinitions.ps1
  ```

3. Confirm your new or changed definitions include all required files and that
  PowerShell scripts in package source folders execute cleanly in your target
  packaging flow.
