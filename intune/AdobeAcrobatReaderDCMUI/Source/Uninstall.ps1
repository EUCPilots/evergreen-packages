<#
    .SYNOPSIS
    Uninstalls the application
#>
[CmdletBinding()]
param ()

#region Restart if running in a 32-bit session
if (!([System.Environment]::Is64BitProcess)) {
    if ([System.Environment]::Is64BitOperatingSystem) {
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Definition)`""
        $ProcessPath = $(Join-Path -Path $Env:SystemRoot -ChildPath "\Sysnative\WindowsPowerShell\v1.0\powershell.exe")
        $params = @{
            FilePath     = $ProcessPath
            ArgumentList = $Arguments
            Wait         = $True
            WindowStyle  = "Hidden"
        }
        Start-Process @params
        exit 0
    }
}
#endregion

try {
    Get-Process -ErrorAction "SilentlyContinue" | `
        Where-Object { $_.Path -like "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\*" } | `
        Stop-Process -Force -ErrorAction "SilentlyContinue"
}
catch {
    Write-Warning -Message "Failed to stop Adobe Acrobat Reader DC processes."
}


try {
    function Get-InstalledSoftware {
        $PropertyNames = "DisplayName", "DisplayVersion", "Publisher", "UninstallString", "PSPath", "WindowsInstaller",
        "InstallDate", "InstallSource", "HelpLink", "Language", "EstimatedSize", "SystemComponent" 
        ("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", 
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*") | `
            ForEach-Object { 
            Get-ItemProperty -Path $_ -Name $PropertyNames -ErrorAction "SilentlyContinue" | ` 
            . { process { if ($null -ne $_.DisplayName) { $_ } } } | `
                Where-Object { $_.SystemComponent -ne 1 } | `
                Select-Object -Property @{n = "Name"; e = { $_.DisplayName } }, @{n = "Version"; e = { $_.DisplayVersion } }, "Publisher",
            "UninstallString", @{n = "RegistryPath"; e = { $_.PSPath -replace "Microsoft.PowerShell.Core\\Registry::", "" } },
            "PSChildName", "WindowsInstaller", "InstallDate", "InstallSource", "HelpLink", "Language", "EstimatedSize" | `
                Sort-Object -Property "Name", "Publisher"
        }
    }
    $result = @{ ExitCode = 0 }
    Get-InstalledSoftware | Where-Object { $_.Name -match "Adobe Acrobat Reader MUI" } | ForEach-Object {
        $ArgumentList = "/uninstall `"$($_.PSChildName)`" /quiet /norestart"
        $params = @{ 
            FilePath     = "$Env:SystemRoot\System32\msiexec.exe"
            ArgumentList = $ArgumentList
            NoNewWindow  = $true
            PassThru     = $true
            Wait         = $true
            ErrorAction  = "Continue"
        }
        $result = Start-Process @params
    }
}
catch {
    throw $_
}
finally {
    exit $result.ExitCode
}
