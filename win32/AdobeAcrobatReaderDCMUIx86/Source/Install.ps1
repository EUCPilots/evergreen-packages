#Requires -RunAsAdministrator
<#
    .SYNOPSIS
        Installs Adobe Acrobat Reader DC MUI x86 silently from packaged media.

    .DESCRIPTION
        This script locates the bundled Acrobat installer executable (Acro*.exe), extracts its contents,
        and installs Acrobat Reader using AcroRead.msi with the Reader-MUI-x86.mst transform and
        AcroRdrDCUpd*.msp patch. The install is performed silently with configured MSI properties and
        logging enabled.

        If the script starts in a 32-bit PowerShell session on a 64-bit operating system, it relaunches
        itself in 64-bit PowerShell before continuing. After installation, it removes Adobe scheduled
        update tasks and deletes extracted temporary files.

    .EXAMPLE
        PS C:\> .\Install.ps1
        Installs Adobe Acrobat Reader DC MUI x86 from the current package source.

    .OUTPUTS
        System.Int32
        Returns the exit code from the final installer process.

    .NOTES
        Author: Aaron Parker
        - Requires administrative rights
        - Requires packaged Acrobat installer media in the current working directory
        - Uses Intune Management Extension log path when available:
          $Env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeAcrobatReaderDC-Install.log
        - Falls back to the current directory if the Intune log folder is unavailable
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param ()

# Set strict mode and error handling
Set-StrictMode -Version "Latest"
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

# Log file path. Parent directory should exist if device is enrolled in Intune
if (Test-Path -Path "$Env:ProgramData\Microsoft\IntuneManagementExtension\Logs" -PathType "Container") {
    $Script:LogFile = "$Env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeAcrobatReaderDC-Install.log"
    $MsiLogFile = "$Env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeAcrobatReaderDC-Install.log"
}
else {
    $Script:LogFile = "$($PWD.Path)\AdobeAcrobatReaderDC-Install.log"
    $MsiLogFile = "$($PWD.Path)\AdobeAcrobatReaderDC-Install.log"
}

#region Logging Function
function Write-LogFile {
    <#
        .SYNOPSIS
            This function creates or appends a line to a log file

        .DESCRIPTION
            This function writes a log line to a log file in the form synonymous with
            ConfigMgr logs so that tools such as CMtrace and SMStrace can easily parse
            the log file.  It uses the ConfigMgr client log format's file section
            to add the line of the script in which it was called.

        .PARAMETER  Message
            The message parameter is the log message you'd like to record to the log file

        .PARAMETER  LogLevel
            The logging level is the severity rating for the message you're recording. Like ConfigMgr
            clients, you have 3 severity levels available; 1, 2 and 3 from informational messages
            for FYI to critical messages that stop the install. This defaults to 1.

        .EXAMPLE
            PS C:\> Write-LogFile -Message 'Value1' -LogLevel 'Value2'
            This example shows how to call the Write-LogFile function with named parameters.

        .NOTES
            Constantin Lotz;
            Adam Bertram, https://github.com/adbertram/PowerShellTipsToWriteBy/blob/f865c4212284dc25fe613ca70d9a4bafb6c7e0fe/chapter_7.ps1#L5
    #>
    [CmdletBinding(SupportsShouldProcess = $false)]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, Mandatory = $true)]
        [System.String] $Message,

        [Parameter(Position = 1, Mandatory = $false)]
        [ValidateSet(1, 2, 3)]
        [System.Int16] $LogLevel = 1
    )

    process {
        ## Build the line which will be recorded to the log file
        $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
        $LineFormat = $Message, $TimeGenerated, (Get-Date -Format "yyyy-MM-dd"), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $LogLevel
        $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">' -f $LineFormat

        Write-Information -MessageData $Message -InformationAction "Continue"
        Add-Content -Value $Line -Path $Script:LogFile
    }
}
#endregion

#region Restart if running in a 32-bit session
if (!([System.Environment]::Is64BitProcess)) {
    if ([System.Environment]::Is64BitOperatingSystem) {

        # Create a string from the passed parameters
        [System.String]$ParameterString = ""
        foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
            $ParameterString += " -$($Parameter.Key) $($Parameter.Value)"
        }

        # Execute the script in a 64-bit process with the passed parameters
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Definition)`"$ParameterString"
        $ProcessPath = $(Join-Path -Path $Env:SystemRoot -ChildPath "\Sysnative\WindowsPowerShell\v1.0\powershell.exe")
        Write-LogFile -Message "Restarting in 64-bit PowerShell."
        Write-LogFile -Message "File path: $ProcessPath."
        Write-LogFile -Message "Arguments: $Arguments."
        $params = @{
            FilePath     = $ProcessPath
            ArgumentList = $Arguments
            Wait         = $true
            WindowStyle  = "Hidden"
        }
        Start-Process @params
        exit 0
    }
}
#endregion

#region Installer functions
function Get-Installer {
    [CmdletBinding()]
    param (
        [System.String] $File,
        [System.Management.Automation.PathInfo] $Path = $PWD
    )
    $Installer = Get-ChildItem -Path $Path -Filter $File -Recurse | Select-Object -First 1
    if ($null -eq $Installer -or [System.String]::IsNullOrEmpty($Installer.FullName)) {
        Write-LogFile -Message "File not found: $File" -LogLevel 3
        throw [System.IO.FileNotFoundException]::New("File not found: $File")
    }
    else {
        Write-LogFile -Message "Found installer: $($Installer.FullName)"
        return $Installer.FullName
    }
}
#endregion

#region Install logic
# Trim log if greater than 50 MB
if (Test-Path -Path $Script:LogFile) {
    if ((Get-Item -Path $Script:LogFile).Length -gt 50MB) {
        Clear-Content -Path $Script:LogFile
        Write-LogFile -Message "Log file size greater than 50MB. Clearing log." -LogLevel 2
    }
}

# Get the install details for this application
$Installer = Get-Installer -File "Acro*.exe"

if ([System.String]::IsNullOrEmpty($Installer)) {
    Write-LogFile -Message "File not found: $Installer" -LogLevel 3
    throw [System.IO.FileNotFoundException]::New("File not found: $Installer")
}
else {
    try {
        # Perform the application install
        $result = @{ ExitCode = 0 }

        # Extract the installer to the current directory
        Write-LogFile -Message "Extracting to: $($PWD.Path)\Extract"
        $params = @{
            FilePath     = $Installer
            ArgumentList = "-sfx_o`"$($PWD.Path)\Extract`" -sfx_ne -sfx_nu"
            Wait         = $true
            WindowStyle  = "Hidden"
            PassThru     = $true
        }
        $result = Start-Process @params

        # Get the extracted MSI, MST and MSP files
        $MsiFile = Get-Installer -File "AcroRead.msi"
        Write-LogFile -Message "MSI file: $MsiFile"
        $MsiTransform = Get-Installer -File "Reader-MUI-x86.mst"
        Write-LogFile -Message "MST file: $MsiTransform"
        $MsiPath = Get-Installer -File "AcroRdrDCUpd*.msp"
        Write-LogFile -Message "MSP file: $MsiPath"

        # Install the MSI with the MST and MSP
        $Properties = "EULA_ACCEPT=YES ENABLE_READER_MODE=1 ROAMIDENTITY=1 ROAMLICENSING=1 ENABLE_CHROMEEXT=0 DISABLE_BROWSER_INTEGRATION=1 ENABLE_OPTIMIZATION=YES ADD_THUMBNAILPREVIEW=0 DISABLEDESKTOPSHORTCUT=1"
        $MsiExec = "$Env:SystemRoot\System32\msiexec.exe"
        Write-LogFile -Message "Execute: $MsiExec"
        $Arguments = "/package `"$MsiFile`" TRANSFORMS=`"$MsiTransform`" /update `"$MsiPath`" $Properties /qn /norestart /log `"$MsiLogFile`""
        Write-LogFile -Message "Arguments: $Arguments"
        $params = @{
            FilePath     = $MsiExec
            ArgumentList = $Arguments
            Wait         = $true
            WindowStyle  = "Hidden"
            PassThru     = $true
        }
        $result = Start-Process @params

        if ($result.ExitCode -eq 0) {
            Get-ScheduledTask "Adobe Acrobat Update Task*" | Unregister-ScheduledTask -Confirm:$False -ErrorAction "SilentlyContinue"
        }
    }
    catch {
        Write-LogFile -Message $_.Exception.Message -LogLevel 3
        throw $_
    }
    finally {
        # Delete the extracted files
        Start-Sleep -Seconds 5 # Wait for any file locks to release
        Write-LogFile -Message "Cleaning up extracted files."
        Remove-Item -Path "$($PWD.Path)\Extract" -Recurse -Force -ErrorAction "SilentlyContinue"

        Write-LogFile -Message "Install.ps1 complete. Exit Code: $($result.ExitCode)"
        exit $result.ExitCode
    }
}
#endregion
