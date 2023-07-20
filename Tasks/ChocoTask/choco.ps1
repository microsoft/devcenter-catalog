[CmdletBinding()]
param(
    [Parameter()]
    [string] $Package,

    [Parameter()]
    [string] $Version,

    [Parameter()]
    [string] $ignoreChecksums
)

###################################################################################################
#
# PowerShell configurations
#

# Ensure we force use of TLS 1.2 for all downloads.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Expected path of the choco.exe file.
$choco = "$Env:ProgramData/chocolatey/choco.exe"

###################################################################################################
#
# Functions used in this script.
#

function Ensure-Chocolatey
{
    [CmdletBinding()]
    param(
        [string] $ChocoExePath
    )

    if (-not (Test-Path "$ChocoExePath"))
    {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        $installScript = (New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')
        $expression = "$installScript | powershell.exe -NoProfile -ExecutionPolicy Bypass -Command -"
        Execute -Expression $expression
        if ($LastExitCode -eq 3010)
        {
            Write-Host 'The recent changes indicate a reboot is necessary. Please reboot at your earliest convenience.'
        }
    }
}

function Install-Package
{
    [CmdletBinding()]
    param(
        [string] $ChocoExePath,
        [string] $Package,
        [string] $Version,
        [string] $ignoreChecksums
    )

    $expression = "$ChocoExePath install -y -f --acceptlicense --no-progress --stoponfirstfailure $Package --version $Version"
    
    if ($ignoreChecksums -eq "true") {
        $expression = "$expression --ignorechecksums"
    }

    Execute -Expression $expression
}

function Execute
{
    [CmdletBinding()]
    param(
        $Expression
    )

    # Note we're calling powershell.exe directly, instead
    # of running Invoke-Expression, as suggested by
    # https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/avoid-using-invoke-expression?view=powershell-7.3
    # Note that this will run powershell.exe
    # even if the system has pwsh.exe.
    $process = Start-Process powershell.exe -ArgumentList "-Command $Expression" -NoNewWindow -PassThru -Wait
    $expError = $process.ExitCode.Exception
    
    # This check allows us to capture cases where the command we execute exits with an error code.
    # In that case, we do want to throw an exception with whatever is in stderr. Normally, when
    # Invoke-Expression throws, the error will come the normal way (i.e. $Error) and pass via the
    # catch below.
    if ($process.ExitCode -or $expError)
    {
        if ($process.ExitCode -eq 3010)
        {
            # Expected condition. The recent changes indicate a reboot is necessary. Please reboot at your earliest convenience.
        }
        elseif ($expError)
        {
            throw $expError
        }
        else
        {
            throw "Installation failed ($LastExitCode). Please see the Chocolatey logs in %ALLUSERSPROFILE%\chocolatey\logs folder for details."
        }
    }
}


###################################################################################################
#
# Main execution block.
#

Write-Host 'Ensuring latest Chocolatey version is installed.'
Ensure-Chocolatey -ChocoExePath "$choco"

Write-Host "Preparing to install Chocolatey package: $Package."
Install-Package -ChocoExePath "$choco" -Package $Package -Version $Version -ignoreChecksums $ignoreChecksums

Write-Host "`nThe artifact was applied successfully.`n"