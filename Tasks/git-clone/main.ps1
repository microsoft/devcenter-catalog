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
$PsInstallScope = "CurrentUser"
if ($(whoami.exe) -eq "nt authority\system") {
    $PsInstallScope = "AllUsers"
}
$TargetRepoDirectory = Join-Path -Path $Directory -ChildPath "$($RepositoryUrl -replace "^.+\/([^\/]+?)(?:\.git)?$", '$1')"

# Set the progress preference to silently continue
# in order to avoid progress bars in the output
# as this makes web requests very slow
# Reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables
$ProgressPreference = 'SilentlyContinue'

function SetupScheduledTasks {
    Write-Host "Setting up scheduled tasks"
    if (!(Test-Path -PathType Container $CustomizationScriptsDir)) {
        New-Item -Path $CustomizationScriptsDir -ItemType Directory
        New-Item -Path "$($CustomizationScriptsDir)\$($LockFile)" -ItemType File
        Copy-Item "./$($RunAsUserScript)" -Destination $CustomizationScriptsDir
        Copy-Item "./$($CleanupScript)" -Destination $CustomizationScriptsDir
    }

    # Reference: https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-objects
    $SchedService = New-Object -comobject "Schedule.Service"
    $SchedService.Connect()

    # Schedule the cleanup script to run every minute as SYSTEM
    $Task = $SchedService.NewTask(0)
    $Task.RegistrationInfo.Description = "Dev Box Customizations Cleanup"
    $Task.Settings.Enabled = $true
    $Task.Settings.AllowDemandStart = $false

    $Trigger = $Task.Triggers.Create(9)
    $Trigger.Enabled = $true
    $Trigger.Repetition.Interval="PT1M"

    $Action = $Task.Actions.Create(0)
    $Action.Path = "PowerShell.exe"
    $Action.Arguments = "Set-ExecutionPolicy Bypass -Scope Process -Force; $($CustomizationScriptsDir)\$($CleanupScript)"

    $TaskFolder = $SchedService.GetFolder("\")
    $TaskFolder.RegisterTaskDefinition("$($CleanupTask)", $Task , 6, "NT AUTHORITY\SYSTEM", $null, 5)

    # Schedule the script to be run in the user context on login
    $Task = $SchedService.NewTask(0)
    $Task.RegistrationInfo.Description = "Dev Box Customizations"
    $Task.Settings.Enabled = $true
    $Task.Settings.AllowDemandStart = $false
    $Task.Principal.RunLevel = 1

    $Trigger = $Task.Triggers.Create(9)
    $Trigger.Enabled = $true

    $Action = $Task.Actions.Create(0)
    $Action.Path = "C:\Program Files\PowerShell\7\pwsh.exe"
    $Action.Arguments = "-MTA -Command $($CustomizationScriptsDir)\$($RunAsUserScript)"

    $TaskFolder = $SchedService.GetFolder("\")
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
        pwsh.exe -MTA -Command "Install-Module Microsoft.WinGet.Configuration -AllowPrerelease -Scope $PsInstallScope"
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
        # Under a user account, the way to materialize winget.exe and make it work is by installing DesktopAppInstaller appx,
        # which in turn may have Xaml and VC++ redistributable requirements.
        
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
            # install Microsoft.UI.Xaml
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


function InstallPackage{
    param (
        [string]$PackageId,
        [string]$PackageCommand,
        [string]$PackagePath
    )

    # install package if it's not already installed
    if (!(Get-Command $PackageCommand -ErrorAction SilentlyContinue)) {
        # if winget is available, use it to install package
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "Installing $PackageId with winget"
            winget install --id $PackageId -e --source winget --silent
            $installExitCode = $LASTEXITCODE
            Write-Host "'winget install --id $PackageId -e --source winget --silent' exited with code: $($installExitCode)"
            if ($installExitCode -eq 0) {
                # add package path to path
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + $PackagePath
            }
        }

        # If we reached here without being able to install the package, try with Install-WinGetPackage
        if (!(Get-Command $PackageCommand -ErrorAction SilentlyContinue)) {
            # install winget and use that to install packages
            
            # winget is not available for system context, so we need to leverage WingGet cmdlets for system context.
            # The WinGet cmdlets aren't supported in PowerShell 5, so we need to install Powershell7 here. 
            InstallPS7
            InstallWinGet

            # install package via winget client
            Write-Host "Installing $PackageId with Install-WinGetPackage"
            $mtaFlag = "-MTA"
            $scopeFlagValue = "SystemOrUnknown"
            if ($PsInstallScope -eq "CurrentUser") {
                $mtaFlag = ""
                $scopeFlagValue = "UserOrUnknown"
            }

            $tempOutFile = [System.IO.Path]::GetTempFileName() + ".out.json"

            $installCommandBlock = {
                $installPackageCommand = "Install-WinGetPackage -Scope $($scopeFlagValue) -Mode Silent -Source winget -Id $($PackageId) | ConvertTo-Json -Depth 10 | Tee-Object -FilePath '$($tempOutFile)'"
                $processCreation = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine="C:\Program Files\PowerShell\7\pwsh.exe $($mtaFlag) -Command `"$($installPackageCommand)`""}
                if (!($processCreation) -or !($processCreation.ProcessId)) {
                    Write-Error "Failed to install $PackageId package. Process creation failed."
                    exit 1
                }
        
                $process = Get-Process -Id $processCreation.ProcessId
                $handle = $process.Handle # cache process.Handle so ExitCode isn't null when we need it below
                $process.WaitForExit()
                $installExitCode = $process.ExitCode
                if ($installExitCode -ne 0) {
                    Write-Error "Failed to install $PackageId with Install-WinGetPackage, error code $($installExitCode)."
                    # this was the last try, so exit with the install exit code
                    exit $installExitCode
                }
        
                # read the output file and write it to the console
                if (Test-Path -Path $tempOutFile) {
                    $unitResults = Get-Content -Path $tempOutFile -Raw | Out-String
                    Write-Host $unitResults
                    Remove-Item -Path $tempOutFile -Force
                    # If there are any errors in the package installation, we need to exit with a non-zero code
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
                    Write-Host "Couldn't find output file for $PackageId installation, assuming fail."
                    exit 1
                }
            }
            .$installCommandBlock

            # add git to path
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + $PackagePath
        }
    }
}

InstallPackage -PackageId "Git.Git" -PackagePath "C:\Program Files\Git\cmd" -PackageCommand "git"

Write-Host "git version: $(git --version)"

$repoCloned = $false

# Disable credential prompting when running under system context to make sure the clone operation doesn't hang
$credentialInteractiveFlag = @('-c', 'credential.interactive=Never')
if ($PsInstallScope -eq "CurrentUser") {
    $credentialInteractiveFlag = @()
}

if ($Pat) {
    # When a PAT is provided, we'll attempt to clone the repository during provisioning time.
    # If this fails, we'll try again when the user logs in.
    Write-Host "Cloning repository: $($RepositoryUrl) to directory: $($TargetRepoDirectory)"
    if ($Branch) {
        Write-Host "Using branch: $($Branch)"
    }

    # First we'll try to clone the repository using the provided PAT.
    try {
        # ensure the target directory doesn't exist
        if (Test-Path -PathType Container $TargetRepoDirectory) {
            Remove-Item -Recurse -Force $TargetRepoDirectory
        }

        if (!(Test-Path -PathType Container $TargetRepoDirectory)) {
            New-Item -Path $TargetRepoDirectory -ItemType Directory
        }

        # Attempt to clone
        Push-Location $TargetRepoDirectory
        $b64pat = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("user:$Pat"))
        
        # Disable credential prompting here to make sure the clone operation doesn't hang
        if ($Branch) {
            git $credentialInteractiveFlag -c http.extraHeader="Authorization: Basic $b64pat" clone -b $Branch $RepositoryUrl . 3>&1 2>&1
        }
        else {
            git $credentialInteractiveFlag -c http.extraHeader="Authorization: Basic $b64pat" clone $RepositoryUrl . 3>&1 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            throw "git clone exited with code: $($LASTEXITCODE)"
        }

        # Mark the directory as safe for git operations
        $TargetRepoDirectorySafe = $TargetRepoDirectory -replace '\\', '/'
        if ($PsInstallScope -eq "CurrentUser") {
            git config --global --add safe.directory "$($TargetRepoDirectorySafe)"
        }
        else {
            git config --system --add safe.directory "$($TargetRepoDirectorySafe)"
        }

        # If the code reaches this point, we've successfully cloned the repository.
        Write-Host "Successfully cloned repository: $($RepositoryUrl) to directory: $($TargetRepoDirectory)"
        $repoCloned = $true
    }
    catch {
        Write-Error $_
        Write-Host "Failed to clone repository: $($RepositoryUrl) to directory: $($TargetRepoDirectory), we'll try again assuming it's an access token."
    }
    finally {
        Pop-Location
    }

    # If the repo wasn't cloned successfully, it may be that the PAT is actually an access token, which requires
    # a different approach. We'll try to clone the repository using the provided PAT as an access token.
    if (!$repoCloned) {
        try {

            # ===== Normalize the repository clone link

            # Sample repo clone links:
            # https://organization@dev.azure.com/organization/project-name/_git/sample-repo.name
            # https://dev.azure.com/organization/project-name/_git/Sample-repo.name
            # https://organization.visualstudio.com/project-name/_git/sample-repo.name
            # https://organization.visualstudio.com/DefaultCollection/project-name/_git/sample-repo.name

            $Pattern1 = '^https://(?<org>[a-zA-Z0-9]+)@dev.azure.com/(?<org_dup>[a-zA-Z0-9]+)/(?<project>[\.\-a-zA-Z0-9]+)/_git/(?<reponame>[\.\-a-zA-Z0-9]+)/?$'
            $Pattern2 = '^https://dev.azure.com/(?<org>[a-zA-Z0-9]+)/(?<project>[\.\-a-zA-Z0-9]+)/_git/(?<reponame>[\.\-a-zA-Z0-9]+)/?$'
            $Pattern3 = '^https://(?<org>[a-zA-Z0-9]+).visualstudio.com/(?<project>[\.\-a-zA-Z0-9]+)/_git/(?<reponame>[\.\-a-zA-Z0-9]+)/?$'
            $Pattern4 = '^https://(?<org>[a-zA-Z0-9]+).visualstudio.com/[Dd]efault[Cc]ollection/(?<project>[\.\-a-zA-Z0-9]+)/_git/(?<reponame>[\.\-a-zA-Z0-9]+)/?$'

            $RepositoryUrl = $RepositoryUrl.ToLower()
            if ($RepositoryUrl -match $Pattern1) {
                Write-Output "Match Pattern1"
            }
            elseif ($RepositoryUrl -match $Pattern2) {
                Write-Output "Match Pattern2"
            }
            elseif ($RepositoryUrl -match $Pattern3) {
                Write-Output "Match Pattern3"
            }
            elseif ($RepositoryUrl -match $Pattern4) {
                Write-Output "Match Pattern4"
            }
            else {
                throw "RepositoryUrl doesnot match any known pattern"
            }

            $NormalizedRepositoryUrl = 'https://{org}:{at}@dev.azure.com/{org}/{project}/_git/{reponame}'
            $NormalizedRepositoryUrl = $NormalizedRepositoryUrl.Replace('{org}', $Matches.org)
            $NormalizedRepositoryUrl = $NormalizedRepositoryUrl.Replace('{project}', $Matches.project)
            $NormalizedRepositoryUrl = $NormalizedRepositoryUrl.Replace('{reponame}', $Matches.reponame)
            $NormalizedRepositoryUrl = $NormalizedRepositoryUrl.Replace('{at}', $Pat)

            # ensure the target directory doesn't exist
            if (Test-Path -PathType Container $TargetRepoDirectory) {
                Remove-Item -Recurse -Force $TargetRepoDirectory
            }

            if (!(Test-Path -PathType Container $TargetRepoDirectory)) {
                New-Item -Path $TargetRepoDirectory -ItemType Directory
            }

            # Attempt to clone
            Push-Location $TargetRepoDirectory
            if ($Branch) {
                git clone -b $Branch $NormalizedRepositoryUrl . 3>&1 2>&1
            }
            else {
                git clone $NormalizedRepositoryUrl . 3>&1 2>&1
            }

            if ($LASTEXITCODE -ne 0) {
                throw "git clone exited with code: $($LASTEXITCODE)"
            }

            # Mark the directory as safe for git operations
            $TargetRepoDirectorySafe = $TargetRepoDirectory -replace '\\', '/'
            if ($PsInstallScope -eq "CurrentUser") {
                git config --global --add safe.directory "$($TargetRepoDirectorySafe)"
            }
            else {
                git config --system --add safe.directory "$($TargetRepoDirectorySafe)"
            }

            # If the code reaches this point, we've successfully cloned the repository.
            Write-Host "Successfully cloned repository: $($RepositoryUrl) to directory: $($TargetRepoDirectory)"
            $repoCloned = $true
        }
        catch {
            Write-Error $_
            Write-Host "Failed to clone repository: $($RepositoryUrl) to directory: $($TargetRepoDirectory), cloning attempt will be queued for user login"
        }
        finally {
            Pop-Location
        }
    }
}

# Check if the repository is hosted in GitHub
if (!$repoCloned -and ($RepositoryUrl -match "github.com")) {
    # attempt to clone without credentials
    Write-Host "Attempting to clone repository: $($RepositoryUrl) to directory: $($TargetRepoDirectory) without credentials"
    if ($Branch) {
        Write-Host "Using branch: $($Branch)"
    }

    try {
        # ensure the target directory doesn't exist
        if (Test-Path -PathType Container $TargetRepoDirectory) {
            Remove-Item -Recurse -Force $TargetRepoDirectory
        }

        if (!(Test-Path -PathType Container $TargetRepoDirectory)) {
            New-Item -Path $TargetRepoDirectory -ItemType Directory
        }

        # Attempt to clone
        Push-Location $TargetRepoDirectory

        # Disable credential prompting here to make sure the clone operation doesn't hang
        if ($Branch) {
            git $credentialInteractiveFlag clone -b $Branch $RepositoryUrl . 3>&1 2>&1
        }
        else {
            git $credentialInteractiveFlag clone $RepositoryUrl . 3>&1 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            throw "git clone exited with code: $($LASTEXITCODE)"
        }

        # Mark the directory as safe for git operations
        $TargetRepoDirectorySafe = $TargetRepoDirectory -replace '\\', '/'
        if ($PsInstallScope -eq "CurrentUser") {
            git config --global --add safe.directory "$($TargetRepoDirectorySafe)"
        }
        else {
            git config --system --add safe.directory "$($TargetRepoDirectorySafe)"
        }

        # If the code reaches this point, we've successfully cloned the repository.
        Write-Host "Successfully cloned repository: $($RepositoryUrl) to directory: $($TargetRepoDirectory)"
        $repoCloned = $true
    }
    catch {
        Write-Error $_
        Write-Host "Failed to clone repository: $($RepositoryUrl) to directory: $($TargetRepoDirectory), cloning attempt will be queued for user login"
    }
    finally {
        Pop-Location
    }
}


if ($repoCloned)
{
    exit 0 #Success!
}

# If the code reaches this point, we failed to clone the repository during provisioning time or
# a PAT was not provided. We'll queue the clone attempt for user login.

# install powershell 7
InstallPS7

if (!(Test-Path -PathType Leaf "$($CustomizationScriptsDir)\$($LockFile)")) {
    SetupScheduledTasks
}

Write-Host "Writing commands to user script"

function AppendToUserScript {
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Content
    )

    Add-Content -Path "$($CustomizationScriptsDir)\$($RunAsUserScript)" -Value $Content
}

# Work from C:\
AppendToUserScript "Push-Location C:\"

# Write intent to output stream
AppendToUserScript "Write-Host 'Cloning repository: $($RepositoryUrl) to directory: $($TargetRepoDirectory)'"
if ($Branch) {
    AppendToUserScript "Write-Host 'Using branch: $($Branch)'"
}

# make directory if it doesn't exist
AppendToUserScript "if (Test-Path -PathType Container '$($TargetRepoDirectory)') {"
AppendToUserScript "    Remove-Item -Recurse -Force '$($TargetRepoDirectory)'"
AppendToUserScript "}"
AppendToUserScript "if (!(Test-Path -PathType Container '$($TargetRepoDirectory)')) {"
AppendToUserScript "    New-Item -Path '$($TargetRepoDirectory)' -ItemType Directory"
AppendToUserScript "}"

# Attempt to clone the repository
AppendToUserScript "Push-Location $($TargetRepoDirectory)"
if ($Branch) {
    AppendToUserScript "git clone -b $($Branch) $($RepositoryUrl) ."
}
else {
    AppendToUserScript "git clone $($RepositoryUrl) ."
}

AppendToUserScript "Pop-Location"

# Mark the directory as safe for git operations
$TargetRepoDirectorySafe = $TargetRepoDirectory -replace '\\', '/'
AppendToUserScript "git config --global --add safe.directory '$($TargetRepoDirectorySafe)'"

AppendToUserScript "Pop-Location"

Write-Host "Done writing commands to user script"

exit 0 #Success!