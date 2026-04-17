# Variables
$RegPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

# Detection logic
if ([System.String]::IsNullOrEmpty($Context.TargetVersion)) {
    # This should be an uninstall action
    if (Test-Path -Path $RegPath) { return $true }
    else {
        if ($Context.Versions -is [System.Array]) { return $null } else { return $false }
    }
}
else {
    if (Test-Path -Path $RegPath) {
        $Context.Log("Key found: $RegPath")

        # Retrieve additional properties for logging and potential future use
        [System.String] $VersionToReport = (Get-ItemProperty -Path $RegPath).VersionToReport
        $Context.Log("VersionToReport from registry: $VersionToReport")

        [System.String] $ProductReleaseIds = (Get-ItemProperty -Path $RegPath).ProductReleaseIds
        $Context.Log("ProductReleaseIds from registry: $ProductReleaseIds")

        [System.String] $SharedComputerLicensing = (Get-ItemProperty -Path $RegPath).SharedComputerLicensing
        $Context.Log("SharedComputerLicensing from registry: $SharedComputerLicensing")


        # Just use the VersionToReport for detection against the TargetVersion
        # Will update with other detection logic in the future
        if ([System.Version]::Parse($VersionToReport) -ge [System.Version]::Parse($Context.TargetVersion)) {
            $Context.Log("No update required. Found '$VersionToReport' against '$($Context.TargetVersion)'.")
            if ($Context.Versions -is [System.Array]) { return $VersionToReport } else { return $true }
        }
        else {
            $Context.Log("Update required. Found '$VersionToReport' less than '$($Context.TargetVersion)'.")
            if ($Context.Versions -is [System.Array]) { return $null } else { return $false }
        }
    }
    else {
        $Context.Log("Path does not exist at: $($RegPath)")
        if ($Context.Versions -is [System.Array]) { return $null } else { return $false }
    }
}
