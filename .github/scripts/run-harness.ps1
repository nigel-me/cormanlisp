# Run the Corman Lisp test harness (test/harness.lisp) with a given Corman Lisp build and check the result.
#
#   run-harness.ps1 -CormanDir <dir with clconsole.exe> -Label <name> -OutFile <results.jsonl>
#                   [-Baseline <baseline.jsonl>] [-TimeoutMinutes 20]
#
# Run from the repository root. Exit code:
#   0  the run finished and (if a baseline exists) nothing regressed
#   1  the run did not finish (crash, hang, no results) or the results file is damaged
#   2  the run finished but tests regressed against the baseline
# Failing tests are NOT an error by themselves: many HyperSpec examples fail on Corman Lisp by design.
param(
    [Parameter(Mandatory = $true)][string]$CormanDir,
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [string]$Baseline = '',
    [int]$TimeoutMinutes = 20
)
$ErrorActionPreference = 'Stop'

$repo = (Get-Location).Path
$OutFile = [System.IO.Path]::GetFullPath($OutFile)
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $OutFile
$safeLabel = $Label -replace '[^A-Za-z0-9._-]', '_'
$repoFwd = $repo -replace '\\', '/'
$outFwd = $OutFile -replace '\\', '/'

# A small wrapper file so the label and paths need no quoting on the command line.
$wrapper = Join-Path $env:RUNNER_TEMP 'ci-run.lisp'
@"
(load "$repoFwd/test/harness.lisp")
(test-harness:run-all :label "$safeLabel" :output-file "$outFwd" :trace-tests t :exit t)
"@ | Set-Content -Path $wrapper -Encoding ascii

$stdin = Join-Path $env:RUNNER_TEMP 'empty-stdin.txt'
New-Item -ItemType File -Force -Path $stdin | Out-Null
$log = "$OutFile.console.log"
$errLog = "$OutFile.console.err.log"

Write-Host "Starting $CormanDir\clconsole.exe -execute $wrapper"
$p = Start-Process -FilePath (Join-Path $CormanDir 'clconsole.exe') `
    -ArgumentList @('-execute', "`"$wrapper`"") -WorkingDirectory $CormanDir `
    -RedirectStandardInput $stdin -RedirectStandardOutput $log -RedirectStandardError $errLog `
    -PassThru -NoNewWindow

# Wait for the process, but do not depend on it exiting: as soon as the results file has its summary
# record the run is complete, and the console gets 15 more seconds to exit by itself.
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$doneAt = $null
$timedOut = $false
while (-not $p.HasExited) {
    Start-Sleep -Seconds 5
    if ((Get-Date) -gt $deadline) { $timedOut = $true; break }
    if (-not $doneAt) {
        try {
            if ((Test-Path $OutFile) -and (Select-String -Path $OutFile -Pattern '"type":"summary"' -Quiet)) {
                $doneAt = Get-Date
            }
        }
        catch { }   # the file may be locked while the harness is writing
    }
    elseif (((Get-Date) - $doneAt).TotalSeconds -gt 15) {
        Write-Host 'Results are complete but the console is still running; stopping it.'
        break
    }
}
if (-not $p.HasExited) {
    if ($timedOut) { Write-Warning "Timed out after $TimeoutMinutes minutes; killing the console." }
    Stop-Process -Id $p.Id -Force
}
else {
    Write-Host "Console exited with code $($p.ExitCode)"
}

foreach ($f in $log, $errLog) {
    if (Test-Path $f) {
        Write-Host "----- tail of $f"
        Get-Content $f -Tail 40
    }
}

$summaryFile = $env:GITHUB_STEP_SUMMARY
function Add-Summary([string]$text) { if ($summaryFile) { Add-Content -Path $summaryFile -Value $text } }

if (-not (Test-Path $OutFile)) {
    Add-Summary "### $Label`n**No results file was written.** See the console log artifact."
    Write-Error "No results file: $OutFile"
    exit 1
}

Add-Summary "### $Label"
$sum = & python test/tools/results.py summary $OutFile --failures --limit 25 2>&1 | Out-String
Add-Summary ("``````" + "`n" + $sum + "``````")
Write-Host $sum

& python test/tools/results.py check $OutFile
if ($LASTEXITCODE -ne 0) {
    Add-Summary "**The run did not finish cleanly** (see PROBLEM lines above)."
    exit 1
}

if ($Baseline -and (Test-Path $Baseline)) {
    $diff = & python test/tools/results.py diff $Baseline $OutFile --limit 25 2>&1 | Out-String
    Add-Summary "#### Compared with $Baseline"
    Add-Summary ("``````" + "`n" + $diff + "``````")
    Write-Host $diff
    if ($LASTEXITCODE -ne 0) { exit 2 }
}
else {
    Add-Summary "_No baseline at '$Baseline'; nothing to compare with. Download the results artifact and commit it there to start gating on regressions._"
}
exit 0
