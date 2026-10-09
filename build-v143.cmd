@echo off
setlocal
set "CORMAN_BUILD_DRIVER=%~f0"
set "CORMAN_BUILD_MODE=%~1"
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $text=[IO.File]::ReadAllText($env:CORMAN_BUILD_DRIVER); & ([scriptblock]::Create(($text -split '# BEGIN POWERSHELL\r?\n',2)[1]))"
exit /b %errorlevel%
# BEGIN POWERSHELL
$ErrorActionPreference='Stop'
$mode=$env:CORMAN_BUILD_MODE
if(!$mode){$mode='core'}
if($mode -notin @('core','full')){throw 'Usage: build-v143.cmd [core|full]'}
$repo=Split-Path -Parent $env:CORMAN_BUILD_DRIVER
if($repo -match '[%!^&|<>"]'){throw 'Unsupported command-shell characters in repository path'}
function InvokeGit([string[]]$arguments){
 $output=& git.exe -c "safe.directory=$repo" -C $repo @arguments
 if($LASTEXITCODE){throw "Git failed: $($arguments -join ' ')"}
 return $output
}
$sha=InvokeGit @('rev-parse','HEAD')
& git.exe -c "safe.directory=$repo" -C $repo diff --quiet HEAD --
if($LASTEXITCODE -ne 0){throw 'Tracked files must match HEAD; commit changes before building. Untracked files are excluded.'}
$programFilesX86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$vswhere=Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
$requirements=@('Microsoft.VisualStudio.Component.VC.Tools.x86.x64')
if($mode -eq 'full'){$requirements+='Microsoft.VisualStudio.Component.VC.ATLMFC'}
$vs=& $vswhere -latest -products '*' -version '[17.0,18.0)' -requires $requirements -property installationPath
if($LASTEXITCODE -ne 0 -or !$vs){throw 'Required VS2022 x86 C++ installation not found'}
$vcvars=Join-Path $vs 'VC\Auxiliary\Build\vcvarsall.bat'
$msbuild=Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe'
$compiler=Join-Path $vs 'VC\Tools\MSVC\14.41.34120\bin\HostX86\x86\cl.exe'
$sdk=Join-Path $programFilesX86 'Windows Kits\10\Lib\10.0.26100.0\um\x86\kernel32.lib'
foreach($path in @($vcvars,$msbuild,$compiler,$sdk)){if(!(Test-Path -LiteralPath $path)){throw "Required validated component missing: $path"}}
if($vs -match '[%!^&|<>"]'){throw 'Unsupported command-shell characters in toolchain path'}
$id=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$run=Join-Path $repo ".build\v143\Win32\Standard\$id"
$tree=Join-Path $run 'tree'
$logs=Join-Path $run 'logs'
$empty=Join-Path $run 'empty-user'
foreach($file in @(InvokeGit @('ls-files'))){if((Join-Path $tree $file).Length -gt 240){throw "Snapshot path too long: $file"}}
New-Item -ItemType Directory -Path $tree,$logs,$empty|Out-Null
InvokeGit @('archive','--format=tar',"--output=$run\source.tar",$sha)|Out-Null
& tar.exe -xf "$run\source.tar" -C $tree
if($LASTEXITCODE){throw 'Snapshot extraction failed'}
$manifest=[ordered]@{Commit=$sha;Mode=$mode;Architecture='x86';MSVC='14.41.34120';SDK='10.0.26100.0';CompilerVersion=(Get-Item $compiler).VersionInfo.FileVersion;Source=$tree;Status='BUILDING'}
$manifest|ConvertTo-Json|Set-Content "$run\build-manifest.json"
Write-Host "BUILD_ROOT=$run"
function RunChild($name,$file,$arguments,$work,$limit){
 $stdout=Join-Path $logs "$name.stdout.log"
 $stderr=Join-Path $logs "$name.stderr.log"
 $timer=[Diagnostics.Stopwatch]::StartNew()
 $p=Start-Process -FilePath $file -ArgumentList $arguments -WorkingDirectory $work -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
 $processHandle=$p.Handle
 $timeout=$false;$setup=$false
 try{
  while(!$p.WaitForExit(1000)){
   $text=(Get-Content $stdout -Raw -ErrorAction SilentlyContinue)+(Get-Content $stderr -Raw -ErrorAction SilentlyContinue)
   if($text -match 'Entering Corman Lisp debug loop|Function not defined:'){$setup=$true;break}
   if($timer.Elapsed.TotalSeconds -ge $limit){$timeout=$true;break}
  }
  if($timeout -or $setup){
   & taskkill.exe /PID $p.Id /T /F|Out-File (Join-Path $logs "$name.termination.log")
   if(!$p.WaitForExit(5000)){throw 'Owned build process did not terminate'}
  }
  $p.WaitForExit()
  $timer.Stop()
  $result=[ordered]@{Name=$name;ExitCode=$p.ExitCode;Timeout=$timeout;SetupFailure=$setup;Seconds=$timer.Elapsed.TotalSeconds}
  $result|ConvertTo-Json|Set-Content (Join-Path $logs "$name.result.json")
  if($timeout -or $setup -or $p.ExitCode -ne 0){throw "$name failed; inspect $logs"}
 }finally{$p.Dispose()}
}
function Build($name,$project){
 $batch=Join-Path $run "$name.cmd"
 $lines=@('@echo off',('call "'+$vcvars+'" x86 10.0.26100.0 -vcvars_ver=14.41'),'if errorlevel 1 exit /b %errorlevel%','set CL=','set _CL_=','set LINK=','set _LINK_=',('cd /d "'+$tree+'"'),('"'+$msbuild+'" "'+(Join-Path $tree $project)+'" /t:Build /p:Configuration=Standard /p:Platform=Win32 /p:PlatformToolset=v143 /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:SolutionDir="'+$tree+'\\" /p:UserRootDir="'+$empty+'" /m:1 /v:minimal /fl "/flp:logfile='+(Join-Path $logs "$name.msbuild.log")+';verbosity=normal"'),'exit /b %errorlevel%')
 [IO.File]::WriteAllLines($batch,$lines,[Text.Encoding]::ASCII)
 RunChild $name $env:ComSpec @('/d','/c',('"'+$batch+'"')) $tree 900
 Write-Host "$name passed"
}
try{
 Build 'dynamic' 'clconsole\clconsole.vcxproj'
 RunChild 'bootstrap' (Join-Path $tree 'clconsole.exe') @('-execute',('"'+(Join-Path $tree 'Sys\compile-sys.lisp')+'"'),'-image','""') $tree 300
 $output=Get-Content (Join-Path $logs 'bootstrap.stdout.log') -Raw
 if($output -notmatch 'The file CormanLisp.img was created successfully\.' -or !(Test-Path (Join-Path $tree 'CormanLisp.img'))){throw 'Bootstrap success evidence missing'}
 Build 'static' 'clconsoleapp\clconsoleapp.vcxproj'
 if($mode -eq 'full'){Build 'solution' 'src_vc15.sln'}
 $manifest.Status='PASS'
}catch{
 $manifest.Status='FAIL'
 $manifest.Error=$_.Exception.Message
 throw
}finally{$manifest|ConvertTo-Json|Set-Content "$run\build-manifest.json"}
Write-Host "PASS: $tree"