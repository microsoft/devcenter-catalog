param(
    [Parameter()]
    [string]$Command,
    [Parameter()]
    [string]$WorkingDirectory,
    [Parameter()]
    [string]$RunAsUser
 )

# Check if workingDirectory is set and not empty and if so, change to it.
if ($WorkingDirectory -and $WorkingDirectory -ne "") {
    # Check if the working directory exists.
    if (-not (Test-Path $WorkingDirectory)) {
        # Create the working directory if it does not exist.
        Write-Output "Creating working directory $WorkingDirectory"
        New-Item -ItemType Directory -Force -Path $WorkingDirectory
    }

    Write-Output "Changing to working directory $WorkingDirectory"
    Set-Location $WorkingDirectory
}

# Note we're calling powershell.exe directly, instead
# of running Invoke-Expression, as suggested by
# https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/avoid-using-invoke-expression?view=powershell-7.3
# Note that this will run powershell.exe
# even if the system has pwsh.exe.
if($RunAsUser -ne "true") {
    Write-Output "Running command as sysadmin: $Command"
    powershell.exe -Command $($Command)
    $CommandExitCode = $LASTEXITCODE
    Write-Output "Command exited with code $CommandExitCode"

    # Task powershell scripts should always end with an
    # exit code reported up to the runner agent.
    # This is how the runner agent knows whether the
    # command succeeded or failed.
    exit $CommandExitCode
} else {
    Write-Output "Running command as user: $Command"

    # Run the command as user, it will write the command to a powershell script and start a shedule task to run this script when the user login devbox
    $REMOVE_LOCKFILE_LAST_LINE = @'
Remove-Item -Path "$($CustomizationScriptsDir)\$($LockFile)" -Force
'@

    # This function will remove the last line of the file if it is the same as $REMOVE_LOCKFILE_LAST_LINE
    function removeLastLinewithRemoveItem {
        param(
            [string]$Path
        )

        $lines = (Get-Content -Path $Path).TrimEnd()
        $lastLine = $lines[$lines.Length - 1]
        if($lastLine.TrimEnd() -eq $REMOVE_LOCKFILE_LAST_LINE.TrimEnd()){
            $lines = $lines[0..($lines.Length - 2)]
            $lines | Set-Content -Path $Path
        }
    }

    # This function will setup the scheduled tasks to run the script when the user login devbox
    function SetupScheduledTasks {
        param(
            [string]$RunAsUserScriptPath,
            [string]$lockFileFullPath,
            [string]$cleanupfullPath
        )

        $RunAsUserTask = "DevBoxCustomizations"
        $CleanupTask = "DevBoxCustomizationsCleanup"

        if(!(Test-Path -Path $lockFileFullPath)){
            New-Item -Path $lockFileFullPath -ItemType File
        }

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
        $Action.Arguments = "Set-ExecutionPolicy Bypass -Scope Process -Force; $cleanupfullPath"

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
        $Action.Arguments = "-MTA -Command $RunAsUserScriptPath"

        $TaskFolder = $ShedService.GetFolder("\")
        $TaskFolder.RegisterTaskDefinition("$($RunAsUserTask)", $Task , 6, "Users", $null, 4)
    }

    $CustomizationScriptsDir = "C:\DevBoxCustomizations"
    $LockFile = "lockfile"
    $RunAsUserAppendScript = "runAsUser.ps1"
    $CleanupScript = "cleanup.ps1"

    $RunAsUserScriptPath = "$($CustomizationScriptsDir)\$($RunAsUserAppendScript)"
    if(!(Test-Path -Path $CustomizationScriptsDir)){
        New-Item -Path $CustomizationScriptsDir -ItemType Directory
        Copy-Item -Path $RunAsUserAppendScript -Destination $RunAsUserScriptPath -Force
    }

    $lockFileFullPath = "$($CustomizationScriptsDir)\$($LockFile)"
    $cleanupfullPath = "$($CustomizationScriptsDir)\$($CleanupScript)"

    if(![string]::IsNullOrEmpty($Command)){
        removeLastLinewithRemoveItem($RunAsUserScriptPath)
        Add-Content -Path $RunAsUserScriptPath -Value $Command
        Add-Content -Path $RunAsUserScriptPath -Value $REMOVE_LOCKFILE_LAST_LINE
    }

    Copy-Item "./$($CleanupScript)" -Destination $CustomizationScriptsDir -Force

    if (!(Test-Path -PathType Leaf "$lockFileFullPath")) {
        SetupScheduledTasks $RunAsUserScriptPath $lockFileFullPath $cleanupfullPath
    }
}