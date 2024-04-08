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

# install Microsoft.DesktopAppInstaller
if (!(Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Microsoft.DesktopAppInstaller"
    # download the DesktopAppInstaller appx package to $env:TEMP
    $tempFileName = [System.IO.Path]::GetRandomFileName()
    $DesktopAppInstallerAppx = "$env:TEMP\$tempFileName-DesktopAppInstaller.appx"
    try {
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
else {
    Write-Host "Microsoft.DesktopAppInstaller is already installed"
}

