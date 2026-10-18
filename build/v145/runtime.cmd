@echo off
setlocal
set "CORMAN_RUNTIME_HELPER=%~f0"
set "CORMAN_SOURCE=%~1"
set "CORMAN_OUTPUT=%~2"
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $text=[IO.File]::ReadAllText($env:CORMAN_RUNTIME_HELPER); & ([scriptblock]::Create(($text -split '# BEGIN POWERSHELL\r?\n',2)[1]))"
exit /b %errorlevel%
# BEGIN POWERSHELL
$ErrorActionPreference='Stop'
function FileHash([string]$path){
 $stream=[IO.File]::OpenRead($path);$sha=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$sha.Dispose();$stream.Dispose()}
}
$source=[IO.Path]::GetFullPath($env:CORMAN_SOURCE).TrimEnd('\')
$output=[IO.Path]::GetFullPath($env:CORMAN_OUTPUT).TrimEnd('\')
$expected=Join-Path $source '.build\v145\ide\Win32\Standard'
if($output -ne $expected){throw 'Unexpected output root'}
$runtime=Join-Path $output 'runtime'
$logs=Join-Path $output 'logs'
New-Item -ItemType Directory -Path $runtime,$logs -Force|Out-Null
$lock=Join-Path $logs 'runtime.lock'
$deadline=[DateTime]::UtcNow.AddSeconds(15)
while($true){try{$lease=[IO.File]::Open($lock,'OpenOrCreate','ReadWrite','None');break}catch{if([DateTime]::UtcNow -gt $deadline){throw 'Runtime staging already active'};Start-Sleep -Milliseconds 200}}
$stamp=Join-Path $logs 'image-inputs.sha256'
$image=Join-Path $runtime 'CormanLisp.img'
try {
 $previousSignature=$null
 if(Test-Path $stamp){$previousSignature=[IO.File]::ReadAllText($stamp);Remove-Item -LiteralPath $stamp}
 $resources=@()
 foreach($dir in @('Sys','Modules','Libraries','examples','documentation')){
  $resources+=@(Get-ChildItem (Join-Path $source $dir) -Recurse -File |Where-Object {$_.Extension -notin @('.obj','.pdb','.img','.exe','.fasl','.fsl','.lib','.exp')})
 }
 foreach($file in @('init.lisp','LICENSE.txt','LICENSE.OpenSSL.txt','RDNZL.dll','libcrypto-1_1.dll','libssl-1_1.dll')){
  if(Test-Path (Join-Path $source $file)){$resources+=Get-Item (Join-Path $source $file)}
 }
 $map=@{};$hashes=@()
 foreach($file in $resources){
  $rel=$file.FullName.Substring($source.Length+1);$map[$rel]=$true
  $hash=FileHash $file.FullName
  $hashes+="$rel=$hash"
  $target=Join-Path $runtime $rel
  if(!(Test-Path $target) -or (FileHash $target) -ne $hash){
   New-Item -ItemType Directory -Path (Split-Path $target) -Force|Out-Null
   Copy-Item -LiteralPath $file.FullName -Destination $target
  }
 }
 $manifest=Join-Path $logs 'staged-files.txt'
 if(Test-Path $manifest){foreach($rel in Get-Content $manifest){if(!$map.ContainsKey($rel)){
   $target=[IO.Path]::GetFullPath((Join-Path $runtime $rel))
   if(!$target.StartsWith($runtime+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe staged deletion'}
   if(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target}
 }}}
 [IO.File]::WriteAllLines($manifest,@($map.Keys|Sort-Object))
 foreach($file in @('clconsole.exe','CormanLispServer.dll')){$hashes+="$file=$(FileHash (Join-Path $runtime $file))"}
 $signature=$hashes|Sort-Object|Out-String
 if((Test-Path $image) -and $previousSignature -eq $signature){[IO.File]::WriteAllText($stamp,$signature);Write-Output 'Image up to date';exit 0}
 if(Test-Path $image){Remove-Item -LiteralPath $image}
 $stdout=Join-Path $logs 'bootstrap.stdout.log';$stderr=Join-Path $logs 'bootstrap.stderr.log'
 $timer=[Diagnostics.Stopwatch]::StartNew()
 $p=Start-Process -FilePath (Join-Path $runtime 'clconsole.exe') -ArgumentList @('-execute',('"'+(Join-Path $runtime 'Sys\compile-sys.lisp')+'"'),'-image','""') -WorkingDirectory $runtime -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
 $handle=$p.Handle;$failure=''
 try{
  while(!$p.WaitForExit(1000)){
   $text=(Get-Content $stdout -Raw -ErrorAction SilentlyContinue)+(Get-Content $stderr -Raw -ErrorAction SilentlyContinue)
   if($text -match 'Entering Corman Lisp debug loop|Function not defined:'){$failure='HARNESS/SETUP FAILURE';break}
   if($timer.Elapsed.TotalSeconds -ge 300){$failure='TIMEOUT/HANG';break}
  }
  if($failure){& taskkill.exe /PID $p.Id /T /F|Out-File (Join-Path $logs 'bootstrap.termination.log');if(!$p.WaitForExit(5000)){throw 'Bootstrap child did not terminate'}}
  $p.WaitForExit();$text=Get-Content $stdout -Raw
  @{ExitCode=$p.ExitCode;Failure=$failure;Seconds=$timer.Elapsed.TotalSeconds}|ConvertTo-Json|Set-Content (Join-Path $logs 'bootstrap.result.json')
  if($failure -or $p.ExitCode -ne 0 -or $text -notmatch 'The file CormanLisp.img was created successfully\.' -or !(Test-Path $image)){throw "Bootstrap failed: $failure; see $logs"}
  [IO.File]::WriteAllText($stamp,$signature)
  Write-Output 'Bootstrap PASS'
 }finally{
  try{
   if(!$p.HasExited){
    & taskkill.exe /PID $p.Id /T /F|Out-File (Join-Path $logs 'bootstrap.termination.log')
    if(!$p.WaitForExit(5000)){throw 'Bootstrap child did not terminate'}
   }
  }finally{$p.Dispose()}
 }
}catch{
 if(Test-Path $stamp){Remove-Item -LiteralPath $stamp}
 if(Test-Path $image){Remove-Item -LiteralPath $image}
 throw
}finally{$lease.Dispose()}
