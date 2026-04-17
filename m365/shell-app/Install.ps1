# Unzip the attached binary to the current directory
Expand-Archive -Path $Context.GetAttachedBinary() -DestinationPath $PWD -Force

$SetupFile = Get-ChildItem -Path $PWD -Recurse -Include "setup.exe"
$ConfigurationFile = Get-ChildItem -Path $PWD -Recurse -Include "Install-Microsoft365Apps.xml"
$Context.Log("Installing Microsoft 365 Apps from: $($ConfigurationFile.FullName)")
$params = @{
    FilePath     = $SetupFile.FullName
    ArgumentList = "/configure `"$($ConfigurationFile.FullName)`""
    Wait         = $true
    NoNewWindow  = $true
    PassThru     = $true
    ErrorAction  = "Stop"
}
$result = Start-Process @params
$Context.Log("Install complete. Return code: $($result.ExitCode)")
