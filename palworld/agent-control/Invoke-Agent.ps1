$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Console]::InputEncoding=[Text.Encoding]::UTF8
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$utf8=New-Object Text.UTF8Encoding($false)
$root='D:\PalworldServer-LAN\BridgeLab\rpc'
$request=[Console]::In.ReadToEnd()|ConvertFrom-Json
if($request.id -notmatch '^[0-9a-f-]{36}$'){throw 'Invalid operation UUID'}
if(@('status','operation','models','build','geometry','materials','catalog','dismantle','terrain','transform','finish','bases','storage','storage_plan','storage_apply','storage_operation') -notcontains $request.method){throw 'Invalid method'}
$mutex=New-Object Threading.Mutex($false,'Global\PalworldBridgeLabAgentQueue')
$locked=$mutex.WaitOne(15000)
try {
 if(!$locked){throw 'Agent queue is busy'}
 $result=Join-Path $root ("agent-result-$($request.id).json")
 if(!(Test-Path $result)){
  $path=Join-Path $root 'agent-request.json'
  [IO.File]::WriteAllText("$path.new",($request|ConvertTo-Json -Depth 64 -Compress),$utf8)
  if(Test-Path $path){[IO.File]::Replace("$path.new",$path,(Join-Path $root 'agent-request.previous.json'))}else{[IO.File]::Move("$path.new",$path)}
 }
 for($i=0;$i -lt 100;$i++){if(Test-Path $result){break};Start-Sleep -Milliseconds 100}
 if(!(Test-Path $result)){throw 'Agent response timed out; inspect the same operation UUID'}
 [Console]::Out.Write([IO.File]::ReadAllText($result,$utf8))
} finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
