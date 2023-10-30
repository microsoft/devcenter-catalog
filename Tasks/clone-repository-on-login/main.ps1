param (
    [Parameter()]
    [string]$RepositoryUrl,
    [Parameter()]
    [string]$Directory,
    [Parameter()]
    [string]$Branch
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
    Write-Host "Done setting up scheduled tasks"
}

function InstallPS7 {
    if (!(Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Host "Installing PowerShell 7"
        $code = Invoke-RestMethod -Uri https://aka.ms/install-powershell.ps1
        $null = New-Item -Path function:Install-PowerShell -Value $code
        Install-PowerShell -UseMSI -Quiet
        # Need to update the path post install
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "Done Installing PowerShell 7"
    }
    else
    {
        Write-Host "PowerShell 7 is already installed"
    }
}

function InstallWinGet {
    Write-Host "Installing WinGet"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

    Install-Module Microsoft.WinGet.Client -Scope AllUsers

    pwsh.exe -MTA -Command "Install-Module Microsoft.WinGet.Configuration -AllowPrerelease -Scope AllUsers"
    Write-Host "Done Installing WinGet"
}

function AppendToUserScript($content) {
    Add-Content -Path "$($CustomizationScriptsDir)\$($RunAsUserScript)" -Value $content
}

# install git if it's not already installed
$installed_winget = $false
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    # if winget is available, use it to install git
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Git.Git -e --source winget
        Write-Host "'winget install --id Git.Git -e --source winget' exited with code: $($LASTEXITCODE)"
    }
    # if choco is available, use it to install git
    elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install git -y
        Write-Host "'choco install git -y' exited with code: $($LASTEXITCODE)"
    }
    else {
        # if neither winget nor choco are available, install winget and use that to install git
        InstallPS7
        InstallWinGet
        $installed_winget = $true
        pwsh.exe -MTA -Command "Install-WinGetPackage -Id Git.Git"
        Write-Host "'Install-WinGetPackage -Id Git.Git' exited with code: $($LASTEXITCODE)"
    }
}

# install powershell 7
InstallPS7

if (!(Test-Path -PathType Leaf "$($CustomizationScriptsDir)\$($LockFile)")) {
    SetupScheduledTasks
}

Write-Host "Writing commands to user script"
# Write intent to output stream
AppendToUserScript "Write-Host 'Cloning repository: $($RepositoryUrl) to directory: $($Directory)'"
if ($Branch) {
    AppendToUserScript "Write-Host 'Using branch: $($Branch)'"
}

# Capture output streams
AppendToUserScript "&{"

# Work from C:\
AppendToUserScript "  pushd C:\"
if ($installed_winget)
{
    AppendToUserScript "  Repair-WinGetPackageManager -Latest"
}

# make directory if it doesn't exist
AppendToUserScript "  if (!(Test-Path -PathType Container '$($Directory)')) {"
AppendToUserScript "      New-Item -Path '$($Directory)' -ItemType Directory"
AppendToUserScript "  }"

# Work from specified directory, clone the repo and change branch if needed
AppendToUserScript "  pushd $($Directory)"
AppendToUserScript "  git clone $($RepositoryUrl)"
if ($Branch) {
    AppendToUserScript "  git checkout $($Branch)"
}
AppendToUserScript "  popd"
AppendToUserScript "  popd"

# Send output streams to log file
AppendToUserScript "} *>> `$env:TEMP\git-cloning.log"

Write-Host "Done writing commands to user script"
