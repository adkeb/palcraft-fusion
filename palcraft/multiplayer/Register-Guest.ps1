param(
 [ValidateSet('init','enroll','verify')][string]$Mode='enroll',
 [Parameter(Mandatory=$true)][string]$ToolJar,
 [string]$AuthRoot='D:/PalworldServer-LAN/BridgeLab/rpc/session-auth',
 [string]$Presence='D:/PalworldServer-LAN/BridgeLab/rpc/session-auth/pal-presence.json',
 [string]$PalUid,
 [string]$Credential,
 [string]$ImportName,
 [string]$ImportUuid,
 [string]$JavaExe='C:/Users/PLAYER/AppData/Roaming/.minecraft/runtime/java-runtime-epsilon/windows-x64/java-runtime-epsilon/bin/java.exe',
 [string]$GsonJar
)
$ErrorActionPreference='Stop'
if(!$GsonJar){
 $GsonJar=(Get-ChildItem -LiteralPath 'D:/PalworldServer-LAN/PalCraft-Dev/gradle-cache/caches/modules-2/files-2.1/com.google.code.gson/gson' -Recurse -Filter '*.jar'|Where-Object {$_.Name -notlike '*sources*'}|Select-Object -First 1).FullName
}
foreach($multiplayerFile in @($JavaExe,$ToolJar,$GsonJar)){if(!(Test-Path -LiteralPath $multiplayerFile)){throw 'Registration runtime/classpath file is missing'}}
$multiplayerArgs=@('-XX:ActiveProcessorCount=1','-cp',($ToolJar+';'+$GsonJar),'dev.rehan.passthrough.session.SessionEnrollment',$Mode)
if($Mode -eq 'verify'){
 if(!$Credential){throw 'verify requires -Credential'}
 $multiplayerArgs+=@('--authority',($AuthRoot+'/authority-public.json'),'--credential',$Credential)
}else{
 $multiplayerArgs+=@('--root',$AuthRoot,'--presence',$Presence)
 if($Mode -eq 'enroll'){
  if(!$PalUid -or !$Credential){throw 'enroll requires an exact online -PalUid and -Credential target'}
  $multiplayerArgs+=@('--pal-uid',$PalUid,'--credential',$Credential)
  if($ImportName){$multiplayerArgs+=@('--import-name',$ImportName)}
  if($ImportUuid){$multiplayerArgs+=@('--import-uuid',$ImportUuid)}
 }
}
[Diagnostics.Process]::GetCurrentProcess().PriorityClass='BelowNormal'
& $JavaExe @multiplayerArgs
if($LASTEXITCODE -ne 0){throw 'Registration rejected; read the tool reason above. No game process was started.'}
