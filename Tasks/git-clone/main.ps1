param (
    [Parameter()]
    [string]$RepositoryUrl,
    [Parameter()]
    [string]$Directory,
    [Parameter()]
    [string]$Branch,
    [Parameter()]
    [string]$Pat
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
    Write-Host "Installing WinGet"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

    Install-Module Microsoft.WinGet.Client -Scope AllUsers

    pwsh.exe -MTA -Command "Install-Module Microsoft.WinGet.Configuration -AllowPrerelease -Scope AllUsers"
    Write-Host "Done Installing WinGet"
}

if ($Pat) {
    # When a PAT is provided, we'll attempt to clone the repository during provisioning time.
    # If this fails, we'll try again when the user logs in.
    Write-Host "Cloning repository: $($RepositoryUrl) to directory: $($Directory)"
    if ($Branch) {
        Write-Host "Using branch: $($Branch)"
    }
    Push-Location C:\
    try {
        if (!(Test-Path -PathType Container $Directory)) {
            New-Item -Path $Directory -ItemType Directory
        }
        Push-Location $Directory
        try {
            $b64pat = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("user:$Pat"))
            if ($Branch) {
                git -c http.extraHeader="Authorization: Basic $b64pat" clone -b $Branch $RepositoryUrl
            }
            else {
                git -c http.extraHeader="Authorization: Basic $b64pat" clone $RepositoryUrl
            }
            if ($LASTEXITCODE -ne 0) {
                throw "git clone exited with code: $($LASTEXITCODE)"
            }
            # If the code reaches this point, we've successfully cloned the repository.
            Write-Host "Successfully cloned repository: $($RepositoryUrl) to directory: $($Directory)"
            exit 0 #Success!
        }
        catch {
            Write-Error $_
            Write-Host "Failed to clone repository: $($RepositoryUrl) to directory: $($Directory), cloning attempt will be queued for user login"
        }
        finally {
            Pop-Location
        }
    }
    catch {
        Write-Error $_
        Write-Host "Failed to create directory: $($Directory), cloning attempt will be queued for user login"
    }
    finally {
        Pop-Location
    }
}

# Check if the repository is hosted in GitHub
if ($RepositoryUrl -match "github.com") {
    # attempt to clone without credentials
    Write-Host "Attempting to clone repository: $($RepositoryUrl) to directory: $($Directory) without credentials"
    if ($Branch) {
        Write-Host "Using branch: $($Branch)"
    }
    Push-Location C:\
    try {
        if (!(Test-Path -PathType Container $Directory)) {
            New-Item -Path $Directory -ItemType Directory
        }
        Push-Location $Directory
        try {
            if ($Branch) {
                git clone -b $Branch $RepositoryUrl
            }
            else {
                git clone $RepositoryUrl
            }
            if ($LASTEXITCODE -ne 0) {
                throw "git clone exited with code: $($LASTEXITCODE)"
            }
            # If the code reaches this point, we've successfully cloned the repository.
            Write-Host "Successfully cloned repository: $($RepositoryUrl) to directory: $($Directory)"
            exit 0 #Success!
        }
        catch {
            Write-Error $_
            Write-Host "Failed to clone repository: $($RepositoryUrl) to directory: $($Directory), cloning attempt will be queued for user login"
        }
        finally {
            Pop-Location
        }
    }
    catch {
        Write-Error $_
        Write-Host "Failed to create directory: $($Directory), cloning attempt will be queued for user login"
    }
    finally {
        Pop-Location
    }

}



# If the code reaches this point, we failed to clone the repository during provisioning time or
# a PAT was not provided. We'll queue the clone attempt for user login.

function AppendToUserScript {
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Content
    )

    Add-Content -Path "$($CustomizationScriptsDir)\$($RunAsUserScript)" -Value $Content
}

# install git if it's not already installed
$installed_winget = $false
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    # if winget is available, use it to install git
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing git with winget"
        winget install --id Git.Git -e --source winget
        Write-Host "'winget install --id Git.Git -e --source winget' exited with code: $($LASTEXITCODE)"
    }
    # if choco is available, use it to install git
    elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Installing git with choco"
        choco install git -y
        Write-Host "'choco install git -y' exited with code: $($LASTEXITCODE)"
    }
    else {
        # if neither winget nor choco are available, install winget and use that to install git
        InstallPS7
        InstallWinGet
        $installed_winget = $true
        Write-Host "Installing git with Install-WinGetPackage"
        $processCreation = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine="C:\Program Files\PowerShell\7\pwsh.exe -MTA -Command `"Install-WinGetPackage -Id Git.Git`""}
        if ($processCreation.ReturnValue -ne 0) {
            Write-Host "Failed to create process to install git with Install-WinGetPackage, error code $($processCreation.ReturnValue)"
            exit $processCreation.ReturnValue
        }
        Write-Host "Waiting for Install-WinGetPackage (pid: $($processCreation.ProcessId)) to complete"
        $process = Get-Process -Id $processCreation.ProcessId
        $handle = $process.Handle # cache process.Handle so ExitCode isn't null when we need it below
        $process.WaitForExit()
        Write-Host "'Install-WinGetPackage -Id Git.Git' exited with code: $($process.ExitCode)"
        if ($process.ExitCode -ne 0) {
            Write-Host "Failed to install git with Install-WinGetPackage, error code $($process.ExitCode)"
            exit $process.ExitCode
        }
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
AppendToUserScript "  Push-Location C:\"
if ($installed_winget) {
    AppendToUserScript "  Repair-WinGetPackageManager -Latest"
}

# make directory if it doesn't exist
AppendToUserScript "  if (!(Test-Path -PathType Container '$($Directory)')) {"
AppendToUserScript "      New-Item -Path '$($Directory)' -ItemType Directory"
AppendToUserScript "  }"

# Work from specified directory, clone the repo and change branch if needed
AppendToUserScript "  Push-Location $($Directory)"
AppendToUserScript "  git clone $($RepositoryUrl)"
if ($Branch) {
    AppendToUserScript "  git checkout $($Branch)"
}
AppendToUserScript "  Pop-Location"
AppendToUserScript "  Pop-Location"

# Send output streams to log file
AppendToUserScript "} *>> `$env:TEMP\git-cloning.log"

Write-Host "Done writing commands to user script"
