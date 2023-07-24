param (
    [Parameter()]
    [string]$ConfigurationFile,
    [Parameter()]
    [string]$DownloadUrl,
    [Parameter()]
    [string]$RunAsUser,
    [Parameter()]
    [string]$Package
)

$CustomizationScriptsDir = "C:\DevBoxCustomizations"
$LockFile = "lockfile"
$RunAsUserScript = "runAsUser.ps1"
$CleanupScript = "cleanup.ps1"
$RunAsUserTask = "DevBoxCustomizations"
$CleanupTask = "DevBoxCustomizationsCleanup"

function SetupScheduledTasks {
    if (!(Test-Path -PathType Container $CustomizationScriptsDir)) {
        New-Item -Path $CustomizationScriptsDir -ItemType Directory
        New-Item -Path "$($CustomizationScriptsDir)\$($LockFile)" -ItemType File
        Copy-Item "./$($RunAsUserScript)" -Destination $CustomizationScriptsDir
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
}

function InstallPS7 {
    $code = Invoke-RestMethod -Uri https://aka.ms/install-powershell.ps1
    $null = New-Item -Path function:Install-PowerShell -Value $code
    Install-PowerShell -UseMSI -Quiet
    # Need to update the path post install
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

function InstallWinGet {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

    Install-Module Microsoft.WinGet.Client -Scope AllUsers
    Add-Content -Path "$($CustomizationScriptsDir)\$($RunAsUserScript)" -Value "Repair-WinGetPackageManager -Latest"

    pwsh.exe -MTA -Command "Install-Module Microsoft.WinGet.Configuration -AllowPrerelease -Scope AllUsers"
}

# TODO only need to setup scheduled tasks if running as user
if (!(Test-Path -PathType Leaf "$($CustomizationScriptsDir)\$($LockFile)")) {
    SetupScheduledTasks
    InstallPS7
    InstallWinGet
}

if ($Package) {
    if ($RunAsUser -eq "true") {
        Add-Content -Path "$($CustomizationScriptsDir)\$($RunAsUserScript)" -Value "Install-WinGetPackage -Id $($Package)"
    } else {
        Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine="C:\Program Files\PowerShell\7\pwsh.exe -MTA -Command `"Install-WinGetPackage -Id $($Package)`""}
    }
}

if ($ConfigurationFile) {
    if ($DownloadUrl) {
        $ConfigurationFileDir = Split-Path -Path $ConfigurationFile
        if(-Not (Test-Path -Path $ConfigurationFileDir))
        {
            New-Item -ItemType Directory -Path $ConfigurationFileDir
        }

        Invoke-WebRequest -Uri $DownloadUrl -OutFile $ConfigurationFile
    }

    if ($RunAsUser -eq "true") {
        Add-Content -Path "$($CustomizationScriptsDir)\$($RunAsUserScript)" -Value "Get-WinGetConfiguration -File $($ConfigurationFile) | Invoke-WinGetConfiguration -AcceptConfigurationAgreements"
        Add-Content -Path "$($CustomizationScriptsDir)\$($RunAsUserScript)" -Value '$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")'
    } else {
        Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine="C:\Program Files\PowerShell\7\pwsh.exe -MTA -Command `"Get-WinGetConfiguration -File $($ConfigurationFile) | Invoke-WinGetConfiguration -AcceptConfigurationAgreements`""}
    }
}
