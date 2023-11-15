<#
.SYNOPSIS
    Invokes the PopulateSolutionCache command of Visual Studio's devenv.exe.
.DESCRIPTION
    The PopulateSolutionCache command generates caches for the specified solution file. The resulting caches
    can improve the performance of various Visual Studio features in a first-run scenario.
.PARAMETER SolutionFilePath
    Required - The path to the .sln file for which caches should be generated.
.PARAMETER Build
    Optional. Default false. A switch indicating whether to run build as part of the populateSolutionCache process.
    This is useful as it allows the fast up to date check cache to be generated, which can improve F5
    performance. The drawback is that running the build causes populateSolutionCache to take longer
    to complete.
.PARAMETER NotLocalCache
    Optional. Default false. A switch indicating that the generated caches should be generalized such that they
    can be moved between machine (as opposed to being used on the same machine on which the populateSolutionCache
    command was run).
.PARAMETER SolnConfigName
    Optional. Only used in combination with the Build switch. The name of the solution configuration (such as Debug
    or Release) to be used to build the solution. If multiple solution platforms are available, you must also specify
    the platform (for example, Debug|Win32). If this argument is unspecified or an empty string (""), the tool uses
    the solution's active configuration.
.PARAMETER ProjectName
    Optional. Only used in combination with the Build switch. The path and name of a project file within the solution.
    You can enter a relative path from the solution file's folder to the project file, or the project's display name,
    or the full path and name of the project file.
.PARAMETER ProjConfigName
    Optional. Only used in combination with the ProjectName parameter. The name of a project build configuration (such as
    Debug or Release) to be used when building the named project. If more than one solution platform is available,
    you must also specify the platform (for example, Debug|Win32). If this switch is specified, it overrides the
    SolnConfigName argument.
.PARAMETER VSWherePath
    Optional. If the Visual Studio Installer is located in a non-default location you can use this VSWherePath to
    specify the full path to the vswhere.exe utility.
#>
param (
        [Parameter()]
        [string]$SolutionFilePath,

        [Parameter()]
        [string]$Build,

        [Parameter()]
        [switch]$NotLocalCache,

        [Parameter()]
        [string]$SolnConfigName,

        [Parameter()]
        [string]$ProjectName,

        [Parameter()]
        [string]$ProjConfigName,

        [Parameter()]
        [string]$VSWherePath
    )

if (![System.IO.File]::Exists($SolutionFilePath)) {
    Write-Host "File not found: $SolutionFilePath"
    return;
}

if ([System.String]::IsNullOrWhiteSpace($VSWherePath)) {
    $VSWherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" 
}
$vswhereArgs = "-latest", "-requires", "Microsoft.Component.MSBuild", "-find", "Common7\IDE\devenv.com"

if (![System.IO.File]::Exists($VSWherePath)) {
    Write-Host "Unable to locate vswhere.exe at '$VSWherePath'. Please provide the correct path using the VSWherePath parameter."
    return;
}
else {
    $devenvPath = & $vswherePath $vswhereArgs

    $devenvArgs = $SolutionFilePath, "/populateSolutionCache"
    
    if (!$NotLocalCache) {
        $devenvArgs += "/localCache"
    }

    if ($Build -eq "true") {
        $devenvArgs += "/build"

        if (![System.String]::IsNullOrWhiteSpace($SolnConfigName)) {
            $devenvArgs += $SolnConfigName
        }

        if (![System.String]::IsNullOrWhiteSpace($ProjectName)) {
            $devenvArgs += "/project"
            $devenvArgs += $ProjectName

            if (![System.String]::IsNullOrWhiteSpace($ProjConfigName)) {
                $devenvArgs += "/projectconfig"
                $devenvArgs += $ProjConfigName
            }
        }
    }

    Write-Host $devenvPath $devenvArgs
    & $devenvPath $devenvArgs
}