# Download and unpack a released Corman Lisp build, and report where clconsole.exe ended up.
#
#   fetch-release.ps1 -Dest <dir> [-Url <asset url>] [-Repo owner/name]
#
# With no -Url it downloads the latest release of -Repo using the GitHub CLI (preinstalled on
# GitHub-hosted runners; needs GH_TOKEN in the environment). It accepts a .zip or an .msi asset.
# Writes corman_dir=<folder containing clconsole.exe> to $GITHUB_OUTPUT.
param(
    [Parameter(Mandatory = $true)][string]$Dest,
    [string]$Url = '',
    [string]$Repo = 'sharplispers/cormanlisp'
)
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$dl = Join-Path $env:RUNNER_TEMP 'release-download'
New-Item -ItemType Directory -Force -Path $dl | Out-Null

if ($Url) {
    $name = [System.IO.Path]::GetFileName(([Uri]$Url).AbsolutePath)
    if (-not $name) { throw "Cannot work out a file name from $Url" }
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile (Join-Path $dl $name)
}
else {
    Write-Host "Downloading the latest release of $Repo (*.zip, then *.msi)"
    gh release download --repo $Repo --dir $dl --pattern '*.zip'
    if ($LASTEXITCODE -ne 0 -or -not (Get-ChildItem $dl -Filter *.zip -ErrorAction SilentlyContinue)) {
        gh release download --repo $Repo --dir $dl --pattern '*.msi'
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Assets available:'
            gh release view --repo $Repo --json assets --jq '.assets[].name'
            throw "No .zip or .msi asset found in the latest release of $Repo. Pass -Url."
        }
    }
}

Get-ChildItem $dl -Filter *.zip | ForEach-Object {
    Write-Host "Unpacking $($_.Name)"
    Expand-Archive -Path $_.FullName -DestinationPath $Dest -Force
}
Get-ChildItem $dl -Filter *.msi | ForEach-Object {
    Write-Host "Extracting $($_.Name) (administrative install)"
    $p = Start-Process msiexec.exe -ArgumentList @('/a', "`"$($_.FullName)`"", '/qn', "TARGETDIR=`"$Dest`"") -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "msiexec exited with $($p.ExitCode)" }
}

$exe = Get-ChildItem -Path $Dest -Recurse -Filter clconsole.exe | Select-Object -First 1
if (-not $exe) { throw "clconsole.exe not found under $Dest" }
$dir = $exe.DirectoryName
Write-Host "Corman Lisp directory: $dir"
foreach ($f in 'CormanLispServer.dll', 'CormanLisp.img') {
    if (-not (Test-Path (Join-Path $dir $f))) { Write-Warning "$f is not next to clconsole.exe" }
}
if ($env:GITHUB_OUTPUT) { "corman_dir=$dir" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8 }
