param (
    [Parameter()]
    [string]$ConfigurationFile,
    [Parameter()]
    [string]$DownloadUrl,
    [Parameter()]
    [string]$InlineConfigurationBase64,
    [Parameter()]
    [string]$Package,
    [Parameter()]
    [string]$Version = '',
    [Parameter()]
    [string]$RunAsUser
)

$CustomizationScriptsDir = "C:\DevBoxCustomizations"
$LockFile = "lockfile"
$RunAsUserScript = "runAsUser.ps1"
$CleanupScript = "cleanup.ps1"
$RunAsUserTask = "DevBoxCustomizations"
$CleanupTask = "DevBoxCustomizationsCleanup"
$PsInstallScope = "CurrentUser"
if ($(whoami.exe) -eq "nt authority\system") {
    $PsInstallScope = "AllUsers"
}

# Set the progress preference to silently continue
# in order to avoid progress bars in the output
# as this makes web requests very slow
# Reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables
$ProgressPreference = 'SilentlyContinue'

function SetupScheduledTasks {
    Write-Host "Setting up scheduled tasks"
    if (!(Test-Path -PathType Container $CustomizationScriptsDir)) {
        New-Item -Path $CustomizationScriptsDir -ItemType Directory
    }

    if (!(Test-Path -PathType Leaf "$($CustomizationScriptsDir)\$($LockFile)")) {
        New-Item -Path "$($CustomizationScriptsDir)\$($LockFile)" -ItemType File
    }

    if (!(Test-Path -PathType Leaf "$($CustomizationScriptsDir)\$($RunAsUserScript)")) {
        Copy-Item "./$($RunAsUserScript)" -Destination $CustomizationScriptsDir
    }

    if (!(Test-Path -PathType Leaf "$($CustomizationScriptsDir)\$($CleanupScript)")) {
        Copy-Item "./$($CleanupScript)" -Destination $CustomizationScriptsDir
    }

    # Reference: https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-objects
    $ShedService = New-Object -comobject "Schedule.Service"
    $ShedService.Connect()

    # Schedule the cleanup script to run every minute as SYSTEM
    $Task = $ShedService.NewTask(0)
    $Task.RegistrationInfo.Description = "Dev Box Customizations Cleanup"
    $Task.Settings.Enabled = $true
    $Task.Settings.AllowDemandStart = $false

    $Trigger = $Task.Triggers.Create(9)
    $Trigger.Enabled = $true
    $Trigger.Repetition.Interval="PT1M"

    $Action = $Task.Actions.Create(0)
    $Action.Path = "PowerShell.exe"
    $Action.Arguments = "Set-ExecutionPolicy Bypass -Scope Process -Force; $($CustomizationScriptsDir)\$($CleanupScript)"

    $TaskFolder = $ShedService.GetFolder("\")
    $TaskFolder.RegisterTaskDefinition("$($CleanupTask)", $Task , 6, "NT AUTHORITY\SYSTEM", $null, 5)

    # Schedule the script to be run in the user context on login
    $Task = $ShedService.NewTask(0)
    $Task.RegistrationInfo.Description = "Dev Box Customizations"
    $Task.Settings.Enabled = $true
    $Task.Settings.AllowDemandStart = $false
    $Task.Principal.RunLevel = 1

    $Trigger = $Task.Triggers.Create(9)
    $Trigger.Enabled = $true

    $Action = $Task.Actions.Create(0)
    $Action.Path = "C:\Program Files\PowerShell\7\pwsh.exe"
    $Action.Arguments = "-MTA -Command $($CustomizationScriptsDir)\$($RunAsUserScript)"

    $TaskFolder = $ShedService.GetFolder("\")
    $TaskFolder.RegisterTaskDefinition("$($RunAsUserTask)", $Task , 6, "Users", $null, 4)
    Write-Host "Done setting up scheduled tasks"
}

function WithRetry {
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Position=1, Mandatory=$false)]
        [int]$Maximum = 5,

        [Parameter(Position=2, Mandatory=$false)]
        [int]$Delay = 100
    )

    $iterationCount = 0
    $lastException = $null
    do {
        $iterationCount++
        try {
            Invoke-Command -Command $ScriptBlock
            return
        } catch {
            $lastException = $_
            Write-Error $_

            # Sleep for a random amount of time with exponential backoff
            $randomDouble = Get-Random -Minimum 0.0 -Maximum 1.0
            $k = $randomDouble * ([Math]::Pow(2.0, $iterationCount) - 1.0)
            Start-Sleep -Milliseconds ($k * $Delay)
        }
    } while ($iterationCount -lt $Maximum)

    throw $lastException
}

function InstallPS7 {
    if (!(Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Host "Installing PowerShell 7"
        $code = Invoke-RestMethod -Uri https://aka.ms/install-powershell.ps1
        $null = New-Item -Path function:Install-PowerShell -Value $code
        WithRetry -ScriptBlock {
            if ("$($PsInstallScope)" -eq "CurrentUser") {
                Install-PowerShell -UseMSI
            }
            else {
                # The -Quiet flag requires admin permissions
                Install-PowerShell -UseMSI -Quiet
            }
        } -Maximum 5 -Delay 100
        # Need to update the path post install
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") + ";C:\Program Files\PowerShell\7"
        Write-Host "Done Installing PowerShell 7"
    }
    else {
        Write-Host "PowerShell 7 is already installed"
    }
}

function InstallWinGet {
    Write-Host "Installing powershell modules in scope: $PsInstallScope"

    # ensure NuGet provider is installed
    if (!(Get-PackageProvider | Where-Object { $_.Name -eq "NuGet" -and $_.Version -gt "2.8.5.201" })) {
        Write-Host "Installing NuGet provider"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $PsInstallScope
        Write-Host "Done Installing NuGet provider"
    }
    else {
        Write-Host "NuGet provider is already installed"
    }

    # Set PSGallery installation policy to trusted
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
    pwsh.exe -MTA -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted"

    # check if the Microsoft.Winget.Client module is installed
    $wingetClientPackage = pwsh.exe -Command "Get-Module -ListAvailable -Name Microsoft.WinGet.Client | Where-Object { `$_.Version -ge '1.9.2411' }"
    if (!($wingetClientPackage)) {
        Write-Host "Installing Microsoft.Winget.Client"
        pwsh.exe -MTA -Command "Install-Module Microsoft.WinGet.Client -Scope $PsInstallScope"
        Write-Host "Done Installing Microsoft.Winget.Client"
    }
    else {
        Write-Host "Microsoft.Winget.Client is already installed"
    }

    # check if the Microsoft.WinGet.Configuration module is installed
    $wingetConfigurationPackage = pwsh.exe -Command "Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration | Where-Object { `$_.Version -ge '1.8.1911' }"
    if (!($wingetConfigurationPackage)) {
        Write-Host "Installing Microsoft.WinGet.Configuration"
        pwsh.exe -MTA -Command "Install-Module Microsoft.WinGet.Configuration -Scope $PsInstallScope"
        Write-Host "Done Installing Microsoft.WinGet.Configuration"
    }
    else {
        Write-Host "Microsoft.WinGet.Configuration is already installed"
    }

    Write-Host "Updating WinGet"
    try {
        Write-Host "Attempting to repair WinGet Package Manager"
        pwsh.exe -MTA -Command "Repair-WinGetPackageManager -Latest -Force -Verbose"
        Write-Host "Done Reparing WinGet Package Manager"
    }
    catch {
        Write-Host "Failed to repair WinGet Package Manager"
        Write-Error $_
    }

    if ($PsInstallScope -eq "CurrentUser") {

        $architecture = "x64"
        if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
            $architecture = "arm64"
        }

        $msVCLibsPackage = Get-AppxPackage -Name "Microsoft.VCLibs.140.00.UWPDesktop" | Where-Object { $_.Version -ge "14.0.30035.0" }
        if (!($msVCLibsPackage)) {
        # Install Microsoft.VCLibs.140.00.UWPDesktop
            try {
                Write-Host "Installing Microsoft.VCLibs.140.00.UWPDesktop"
                $MsVCLibs = "$env:TEMP\$([System.IO.Path]::GetRandomFileName())-Microsoft.VCLibs.140.00.UWPDesktop"
                $MsVCLibsAppx = "$($MsVCLibs).appx"
    
                Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.$($architecture).14.00.Desktop.appx" -OutFile $MsVCLibsAppx
                Add-AppxPackage -Path $MsVCLibsAppx -ForceApplicationShutdown
                Write-Host "Done Installing Microsoft.VCLibs.140.00.UWPDesktop"
            } catch {
                Write-Host "Failed to install Microsoft.VCLibs.140.00.UWPDesktop"
                Write-Error $_
            }
        }

        $msUiXamlPackage = Get-AppxPackage -Name "Microsoft.UI.Xaml.2.8" | Where-Object { $_.Version -ge "8.2310.30001.0" }
        if (!($msUiXamlPackage)) {
            # instal Microsoft.UI.Xaml
            try {
                Write-Host "Installing Microsoft.UI.Xaml"
                $MsUiXaml = "$env:TEMP\$([System.IO.Path]::GetRandomFileName())-Microsoft.UI.Xaml.2.8.6"
                $MsUiXamlZip = "$($MsUiXaml).zip"
                Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6" -OutFile $MsUiXamlZip
                Expand-Archive $MsUiXamlZip -DestinationPath $MsUiXaml
                Add-AppxPackage -Path "$($MsUiXaml)\tools\AppX\$($architecture)\Release\Microsoft.UI.Xaml.2.8.appx" -ForceApplicationShutdown
                Write-Host "Done Installing Microsoft.UI.Xaml"
            } catch {
                Write-Host "Failed to install Microsoft.UI.Xaml"
                Write-Error $_
            }
        }

        $desktopAppInstallerPackage = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller"
        if (!($desktopAppInstallerPackage) -or ($desktopAppInstallerPackage.Version -lt "1.22.0.0")) {
            # install Microsoft.DesktopAppInstaller
            try {
                Write-Host "Installing Microsoft.DesktopAppInstaller"
                $DesktopAppInstallerAppx = "$env:TEMP\$([System.IO.Path]::GetRandomFileName())-DesktopAppInstaller.appx"
                Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile $DesktopAppInstallerAppx
                Add-AppxPackage -Path $DesktopAppInstallerAppx -ForceApplicationShutdown
                Write-Host "Done Installing Microsoft.DesktopAppInstaller"
            }
            catch {
                Write-Host "Failed to install DesktopAppInstaller appx package"
                Write-Error $_
            }
        }

        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") + ";C:\Program Files\PowerShell\7"
        Write-Host "WinGet version: $(winget -v)"
    }

    # Revert PSGallery installation policy to untrusted
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Untrusted
    pwsh.exe -MTA -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted"
}

InstallPS7
InstallWinGet

function AppendToUserScript {
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Content
    )

    Add-Content -Path "$($CustomizationScriptsDir)\$($RunAsUserScript)" -Value $Content
}

function EnsureConfigurationFileIsSet ($ConfigurationFile) {
    # if $ConfigurationFile is not specified, we need to write the configuration to a temporary file
    if (-not $ConfigurationFile) {
        if ($RunAsUser -eq "true") {
            # when running as user, we need to write the configuration to a file in the customization scripts directory
            $ConfigurationFile = "$($CustomizationScriptsDir)\$([System.IO.Path]::GetRandomFileName()).yaml"
        }
        else {
            # when running in the provisioning context, we need to write the configuration to a temporary file
            # when this is run as system, it will end up somewhere under C:\Windows\system32\config\systemprofile\AppData\Local\Temp\
            # when running as a user, it will end up somewhere under C:\Users\<username>\AppData\Local\Temp\
            $ConfigurationFile = [System.IO.Path]::GetTempFileName() + ".yaml"
        }
    }

    # Ensure the directory exists
    $ConfigurationFileDir = Split-Path -Path $ConfigurationFile
    if(-Not (Test-Path -Path $ConfigurationFileDir)) {
        $null = New-Item -ItemType Directory -Path $ConfigurationFileDir
    }

    return $ConfigurationFile
}

# If an inline base64 configuration is specified, we need to write the decoded version to the file
if ($InlineConfigurationBase64) {
    Write-Host "Decoding base64 inline configuration and writing to file"

    $ConfigurationFile = EnsureConfigurationFileIsSet($ConfigurationFile)
    $InlineConfiguration = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($InlineConfigurationBase64))
    $InlineConfiguration | Out-File -FilePath $ConfigurationFile -Encoding utf8

    Write-Host "Wrote configuration to file: $($ConfigurationFile)"
}
# If a download URL is specified, we need to download the contents and write them to the file
elseif ($DownloadUrl) {
    Write-Host "Downloading configuration file from: $($DownloadUrl)"

    $ConfigurationFile = EnsureConfigurationFileIsSet($ConfigurationFile)
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ConfigurationFile

    Write-Host "Downloaded configuration to: $($ConfigurationFile)"
}

$versionFlag = ""
# We're running as user via scheduled task:
if ($RunAsUser -eq "true") {
    Write-Host "Running as user via scheduled task"

    if (!(Test-Path -PathType Leaf "$($CustomizationScriptsDir)\$($LockFile)")) {
        SetupScheduledTasks
    }

    Write-Host "Writing commands to user script"

    # We're running in package mode:
    if ($Package) {
        # If there's a version passed, add the version flag for CLI
        if ($Version -ne '') {
            Write-Host "Specifying version: $($Version)"
            $versionFlag = "--version `"$($Version)`""
        }
        Write-Host "Appending package install: $($Package)"
        AppendToUserScript "winget install --id `"$($Package)`" $($versionFlag) --accept-source-agreements --accept-package-agreements --silent"
        AppendToUserScript "Write-Host `"winget exit code: `$LASTEXITCODE`""
    }
    # We're running in configuration file mode:
    elseif ($ConfigurationFile) {
        Write-Host "Appending installation of configuration file: $($ConfigurationFile)"
        AppendToUserScript "winget configure --file `"$($ConfigurationFile)`" --accept-configuration-agreements"
        AppendToUserScript "Write-Host `"winget exit code: `$LASTEXITCODE`""
    }
    else {
        Write-Error "No package or configuration file specified"
        exit 1
    }
}
# We're running in the provisioning context:
else {
    Write-Host "Running in the provisioning context"
    $tempOutFile = [System.IO.Path]::GetTempFileName() + ".out.json"

    $mtaFlag = "-MTA"
    $scopeFlagValue = "SystemOrUnknown"
    if ($PsInstallScope -eq "CurrentUser") {
        $mtaFlag = ""
        $scopeFlagValue = "UserOrUnknown"
    }

    # We're running in package mode:
    if ($Package) {
        Write-Host "Running package install: $($Package)"
        # If there's a version passed, add the version flag for PS
        if ($Version -ne '') {
            Write-Host "Specifying version: $($Version)"
            $versionFlag = "-Version '$($Version)'"
        }

        $installCommandBlock = {
            $installPackageCommand = "Install-WinGetPackage -Scope $($scopeFlagValue) -Mode Silent -Source winget -Id '$($Package)' $($versionFlag) | ConvertTo-Json -Depth 10 | Tee-Object -FilePath '$($tempOutFile)'"
            $processCreation = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine="C:\Program Files\PowerShell\7\pwsh.exe $($mtaFlag) -Command `"$($installPackageCommand)`""}
            if (!($processCreation) -or !($processCreation.ProcessId)) {
                Write-Error "Failed to install package. Process creation failed."
                exit 1
            }

            $process = Get-Process -Id $processCreation.ProcessId
            $handle = $process.Handle # cache process.Handle so ExitCode isn't null when we need it below
            $process.WaitForExit()
            $installExitCode = $process.ExitCode
            if ($installExitCode -ne 0) {
                Write-Error "Failed to install package. Exit code: $($installExitCode)."
                exit 1
            }

            # read the output file and write it to the console
            if (Test-Path -Path $tempOutFile) {
                $unitResults = Get-Content -Path $tempOutFile -Raw | Out-String
                Write-Host $unitResults
                Remove-Item -Path $tempOutFile -Force
                $unitResultsObject = $unitResults | ConvertFrom-Json

                # If the initial scope didn't produce an installer, retry with an "Any" scope
                if (($unitResultsObject.Status -eq "NoApplicableInstallers") -and ($scopeFlagValue -ne "Any")) {
                    ([ref]$scopeFlagValue).Value = "Any"
                    .$installCommandBlock
                }

                # If there are any errors in the package installation, we need to exit with a non-zero code
                if ($unitResultsObject.Status -ne "Ok") {
                    Write-Error "There were errors installing the package."
                    exit 1
                }
            }
            else {
                Write-Host "Couldn't find output file for package installation, assuming fail."
                exit 1
            }
        }
        .$installCommandBlock
    }
    # We're running in configuration file mode:
    elseif ($ConfigurationFile) {
        Write-Host "Running installation of configuration file: $($ConfigurationFile)"
        $applyConfigCommand = "Get-WinGetConfiguration -File '$($ConfigurationFile)' | Invoke-WinGetConfiguration -AcceptConfigurationAgreements | Select-Object -ExpandProperty UnitResults | ConvertTo-Json -Depth 10 | Tee-Object -FilePath '$($tempOutFile)'"
        $processCreation = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine="C:\Program Files\PowerShell\7\pwsh.exe -Command `"$($applyConfigCommand)`""}
        if (!($processCreation) -or !($processCreation.ProcessId)) {
            Write-Error "Failed to run configuration file installation. Process creation failed."
            exit 1
        }

        $process = Get-Process -Id $processCreation.ProcessId
        $handle = $process.Handle # cache process.Handle so ExitCode isn't null when we need it below
        $process.WaitForExit()
        $installExitCode = $process.ExitCode
        if ($installExitCode -ne 0) {
            Write-Error "Failed to run configuration file installation. Exit code: $($installExitCode)."
            exit 1
        }

        # read the output file and write it to the console
        if (Test-Path -Path $tempOutFile) {
            $unitResults = Get-Content -Path $tempOutFile -Raw | Out-String
            Write-Host $unitResults
            Remove-Item -Path $tempOutFile -Force
            # If there are any errors in the unit results, we need to exit with a non-zero code
            $unitResultsObject = $unitResults | ConvertFrom-Json
            $errors = $unitResultsObject | Where-Object { $_.ResultCode -ne "0" }
            if ($errors) {
                Write-Error "There were errors applying the configuration."
                exit 1
            }
        }
        else {
            Write-Host "Couldn't find output file for configuration application, assuming fail."
            exit 1
        }
    }
    else {
        Write-Error "No package or configuration file specified"
        exit 1
    }
}

exit 0