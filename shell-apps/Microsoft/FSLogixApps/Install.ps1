# Unzip the attached binary to the current directory
Expand-Archive -Path $Context.GetAttachedBinary() -DestinationPath $PWD -Force

# Install FSLogix Apps agent
foreach ($File in "FSLogixAppsSetup.exe") {
    $Installers = Get-ChildItem -Path $PWD -Recurse -Include $File | Where-Object { $_.Directory -match "x64" }
    foreach ($Installer in $Installers) {
        $Context.Log("Installing Microsoft FSLogix Apps agent from: $($Installer.FullName)")
        $params = @{
            FilePath     = $Installer.FullName
            ArgumentList = "/install /quiet /norestart"
            Wait         = $true
            NoNewWindow  = $true
            PassThru     = $true
            ErrorAction  = "Stop"
        }
        $result = Start-Process @params
        $Context.Log("Install complete. Return code: $($result.ExitCode)")
    }
}
