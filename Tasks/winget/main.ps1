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
    [string]$RunAsUser
)

$CustomizationScriptsDir = "C:\DevBoxCustomizations"
$LockFile = "lockfile"
$RunAsUserScript = "runAsUser.ps1"
$CleanupScript = "cleanup.ps1"
$RunAsUserTask = "DevBoxCustomizations"
$CleanupTask = "DevBoxCustomizationsCleanup"

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
            Install-PowerShell -UseMSI -Quiet
        } -Maximum 5 -Delay 100
        # Need to update the path post install
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "Done Installing PowerShell 7"
    }
    else {
        Write-Host "PowerShell 7 is already installed"
    }
}

function InstallWinGet {
    $actionTaken = $false
    # check if the Microsoft.Winget.Client module is installed
    if (!(Get-Module -ListAvailable -Name Microsoft.Winget.Client)) {
        Write-Host "Installing Microsoft.Winget.Client"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

        Install-Module Microsoft.WinGet.Client -Scope AllUsers

        Write-Host "Done Installing Microsoft.Winget.Client"
        $actionTaken = $true
    }
    else {
        Write-Host "Microsoft.Winget.Client is already installed"
    }

    # check if the Microsoft.WinGet.Configuration module is installed
    if (!(Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration)) {
        Write-Host "Installing Microsoft.WinGet.Configuration"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

        pwsh.exe -MTA -Command "Install-Module Microsoft.WinGet.Configuration -AllowPrerelease -Scope AllUsers"
        pwsh.exe -MTA -Command "Install-Module winget -Scope AllUsers"
        
        Write-Host "Done Installing Microsoft.WinGet.Configuration"
        $actionTaken = $true
    }
    else {
        Write-Host "Microsoft.WinGet.Configuration is already installed"
    }

    return $actionTaken
}

InstallPS7
$installed_winget = InstallWinGet

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
    if(-Not (Test-Path -Path $ConfigurationFileDir))
    {
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

# We're running as user via scheduled task:
if ($RunAsUser -eq "true") {
    Write-Host "Running as user via scheduled task"

    if (!(Test-Path -PathType Leaf "$($CustomizationScriptsDir)\$($LockFile)")) {
        SetupScheduledTasks
    }

    Write-Host "Writing commands to user script"

    if ($installed_winget) {
        AppendToUserScript "try {"
        AppendToUserScript "    Repair-WinGetPackageManager -Latest"
        AppendToUserScript "} catch {"
        AppendToUserScript '    Write-Error $_'
        AppendToUserScript "}"
    }

    # We're running in package mode:
    if ($Package) {
        Write-Host "Appending package install: $($Package)"
        AppendToUserScript "Install-WinGetPackage -Id $($Package)"
    }
    # We're running in configuration file mode:
    elseif ($ConfigurationFile) {
        Write-Host "Appending installation of configuration file: $($ConfigurationFile)"

        AppendToUserScript "Get-WinGetConfiguration -File $($ConfigurationFile) | Invoke-WinGetConfiguration -AcceptConfigurationAgreements"
        AppendToUserScript '$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")'
    }
    else {
        Write-Error "No package or configuration file specified"
        exit 1
    }
}
# We're running in the provisioning context:
else {
    Write-Host "Running in the provisioning context"

    # We're running in package mode:
    if ($Package) {
        Write-Host "Running package install: $($Package)"
        $processCreation = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine="C:\Program Files\PowerShell\7\pwsh.exe -MTA -Command `"Install-WinGetPackage -Id $($Package)`""}
        $process = Get-Process -Id $processCreation.ProcessId
        $handle = $process.Handle # cache process.Handle so ExitCode isn't null when we need it below
        $process.WaitForExit()
        $installExitCode = $process.ExitCode
        if ($installExitCode -ne 0) {
            Write-Error "Failed to install package. Exit code: $installExitCode"
            exit 1
        }
    }
    # We're running in configuration file mode:
    elseif ($ConfigurationFile) {
        Write-Host "Running installation of configuration file: $($ConfigurationFile)"

        $processCreation = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine="C:\Program Files\PowerShell\7\pwsh.exe -MTA -Command `"Get-WinGetConfiguration -File $($ConfigurationFile) | Invoke-WinGetConfiguration -AcceptConfigurationAgreements`""}
        $process = Get-Process -Id $processCreation.ProcessId
        $handle = $process.Handle # cache process.Handle so ExitCode isn't null when we need it below
        $process.WaitForExit()
        $installExitCode = $process.ExitCode
        if ($installExitCode -ne 0) {
            Write-Error "Failed to install packages. Exit code: $installExitCode"
            exit 1
        }
    }
    else {
        Write-Error "No package or configuration file specified"
        exit 1
    }
}

exit 0
