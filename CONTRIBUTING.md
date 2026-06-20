## Contributing Package Definitions

Thanks for contributing to Evergreen package definitions.

This guide focuses on adding and updating definitions in:

- [intune](intune)
- [m365](m365)
- [shell-apps](shell-apps)

## Quick Start

1. Fork the repository and create a feature branch.
2. Add or update one package definition at a time.
3. Run local validation:

   ```powershell
   pwsh -File ./tools/Test-PackageDefinitions.ps1
   ```

4. Open a pull request with a clear summary of changes and validation results.

## Definition Types

### Intune Win32 Definitions

Path pattern:

```text
intune/<AppName>/
  App.json
  Source/
    Install.ps1 or Install.json
    Uninstall.ps1 (when used by Program.UninstallCommand)
    Detect.ps1 (optional)
    additional package files as required
```

Expectations:

- Keep `Application.Filter` aligned to a stable `Get-EvergreenApp` query.
- Ensure `PackageInformation.Version` and `DetectionRule` values align.
- Include either `Install.json` (shared install framework) or a custom
  `Install.ps1` in `Source`.
- Include `Uninstall.ps1` when `Program.UninstallCommand` calls it.
- Match architecture and channel naming with the selected Evergreen release.

### Microsoft 365 ODT Profiles

Path pattern:

```text
m365/*.xml
```

Expectations:

- Keep XML well-formed and readable.
- Preserve placeholders used by automation, such as `#Channel`, `#TenantId`,
  and `#Company`.
- Only change app inclusion and properties needed for the scenario.

### Nerdio Shell App Definitions

Path pattern:

```text
shell-apps/<Vendor>/<AppName>/
  Definition.json
  Detect.ps1
  Install.ps1
  Uninstall.ps1
```

Expectations:

- Keep `Definition.json` properties complete (`name`, `publisher`, scripts,
  `versions`, and `source`).
- Ensure `source.type` and `source.app` map to the intended Evergreen app.
- Confirm scripts exist and remain aligned with the definition file.

## Local Validation

Run the repository validation script before you commit:

```powershell
pwsh -File ./tools/Test-PackageDefinitions.ps1
```

What it validates:

- JSON parsing for `App.json` and `Definition.json` files.
- Required top-level and nested properties in those JSON definitions.
- Required companion scripts and folders for Intune and shell app definitions.
- XML parsing for Microsoft 365 profile files.

## Pull Request Checklist

1. Scope changes to relevant package definition files only.
2. Include architecture, channel, or language rationale in the PR description.
3. Include validation output from the local script.
4. For new definitions, include all required files for that definition type.
5. For version updates, verify detection logic still matches installed binaries.

## Tips For High-Quality Contributions

- Prefer deterministic filters over broad matching expressions.
- Avoid unrelated formatting-only changes in existing definitions.
- Keep script changes minimal and focused on packaging behavior.
- Use existing package definitions as examples for naming and structure.