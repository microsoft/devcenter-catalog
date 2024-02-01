param (
    [Parameter()]
    [string]$RepositoryUrl,
    [Parameter()]
    [string]$At,
    [Parameter()]
    [string]$Directory,
    [Parameter()]
    [string]$Branch
)

# ====== Create repository folder is it doesnot exist.

try {
    if (!([System.IO.Directory]::Exists($Directory))){
        New-Item -Path $Directory -ItemType "directory"
        Write-Output "Creating dir ${Directory} done."
    }
}
catch {
    Write-Error "ExceptionInfo for touching dir ${Directory}: $_"
    exit 1
}

# ===== Reform repository clone link

# Sample repo clone link
# https://dev.azure.com/devdiv/OnlineServices/_git/vssaas-intellicode
# https://devdiv@dev.azure.com/devdiv/OnlineServices/_git/OnlineServices.wiki
# https://microsoft.visualstudio.com/CMD/_git/CMD-Svc-FirstPartyApi
# https://microsoft.visualstudio.com/DefaultCollection/CMD/_git/CMD-Svc-FirstPartyApi

$Pattern1 = '^https://(?<org>[a-zA-Z]+)@dev.azure.com/(?<org_dup>[a-zA-Z]+)/(?<project>[\.\-a-zA-Z]+)/_git/(?<reponame>[\.\-a-zA-Z]+)/?$'
$Pattern2 = '^https://dev.azure.com/(?<org>[a-zA-Z]+)/(?<project>[\.\-a-zA-Z]+)/_git/(?<reponame>[\.\-a-zA-Z]+)/?$'
$Pattern3 = '^https://(?<org>[a-zA-Z]+).visualstudio.com/(?<project>[\.\-a-zA-Z]+)/_git/(?<reponame>[\.\-a-zA-Z]+)/?$'
$Pattern4 = '^https://(?<org>[a-zA-Z]+).visualstudio.com/[Dd]efaultCollection/(?<project>[\.\-a-zA-Z]+)/_git/(?<reponame>[\.\-a-zA-Z]+)/?$'

if ($RepositoryUrl -match $Pattern1)
{
    Write-Output "Match Pattern1"
}
elseif ($RepositoryUrl -match $Pattern2)
{
    Write-Output "Match Pattern2"
}
elseif ($RepositoryUrl -match $Pattern3) {
    Write-Output "Match Pattern3"
}
elseif ($RepositoryUrl -match $Pattern4) {
    Write-Output "Match Pattern4"
}
else
{
    Write-Error "RepositoryUrl doesnot match any known pattern. Exit 1."
    Exit 1
}

$ReformPattern = 'https://{org}:{at}@dev.azure.com/{org}/{project}/_git/{reponame}'
$Link = $ReformPattern.Replace('{org}', $Matches.org)
$Link = $Link.Replace('{project}', $Matches.project)
$Link = $Link.Replace('{reponame}', $Matches.reponame)
$Link = $Link.Replace('{at}', $At)

# ===== Git clone

Push-Location $Directory

if ($Branch)
{
    git clone -b $Branch $Link
}
else 
{
    git clone $Link
}

Pop-Location

Write-Output "The repository has been successfully cloned."

Exit 0