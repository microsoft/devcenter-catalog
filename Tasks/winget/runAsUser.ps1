$CustomizationScriptsDir = "C:\DevBoxCustomizations"
$LockFile = "lockfile"
$SetVariablesScript = "setVariables.ps1"
$RunAsUserScript = "runAsUser.ps1"
$CleanupScript = "cleanup.ps1"
$RunAsUserTask = "DevBoxCustomizations"
$CleanupTask = "DevBoxCustomizationsCleanup"

Start-Transcript -Path $env:TEMP\scheduled-task-customization.log -Append -IncludeInvocationHeader

Write-Host "Microsoft Dev Box - Customizations"
Write-Host "----------------------------------"
Write-Host "Setting up scheduled tasks..."

Write-Host "Waiting on OneDrive initialization..."
Start-Sleep -Seconds 120
Remove-Item -Path "$($CustomizationScriptsDir)\$($LockFile)"

Write-Host "Updating WinGet"

if (!(Get-AppxPackage -Name "Microsoft.UI.Xaml.2.8")){
    # instal Microsoft.UI.Xaml
    try{
        $architecture = "x64"
        if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
            $architecture = "arm64"
        }
        $MsUiXaml = "$env:TEMP\$([System.IO.Path]::GetRandomFileName())-Microsoft.UI.Xaml.2.8.6"
        $MsUiXamlZip = "$($MsUiXaml).zip"
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6" -OutFile $MsUiXamlZip
        Expand-Archive $MsUiXamlZip -DestinationPath $MsUiXaml
        Add-AppxPackage -Path "$($MsUiXaml)\tools\AppX\$($architecture)\Release\Microsoft.UI.Xaml.2.8.appx" -ForceApplicationShutdown
        Write-Host "Done Installing Microsoft.UI.Xaml"
    } catch {
        Write-Error "Failed to install Microsoft.UI.Xaml"
        Write-Error $_
    }
}

$desktopAppInstallerPackage = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller"
if (!($desktopAppInstallerPackage) -or ($desktopAppInstallerPackage.Version -lt "1.22.0.0")) {
    # install Microsoft.DesktopAppInstaller
    try {
        $DesktopAppInstallerAppx = "$env:TEMP\$([System.IO.Path]::GetRandomFileName())-DesktopAppInstaller.appx"
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile $DesktopAppInstallerAppx

        # install the DesktopAppInstaller appx package
        Add-AppxPackage -Path $DesktopAppInstallerAppx -ForceApplicationShutdown

        Write-Host "Done Installing Microsoft.DesktopAppInstaller"
    }
    catch {
        Write-Error "Failed to install DesktopAppInstaller appx package"
        Write-Error $_
    }
}

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Write-Host "Done Updating WinGet"


