param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][ValidateSet('server','guest')][string]$Role,
    [Parameter(Mandatory=$true)][string]$RuntimeConfig,
    [string]$GuestManifest,
    [string]$MetadataOutputDirectory
)
$ErrorActionPreference='Stop'
$rootPath=(Resolve-Path -LiteralPath $Root).Path
$recipe=Get-Content (Join-Path $rootPath 'normal-launch-recipe.json') -Raw | ConvertFrom-Json
$cfg=Get-Content -LiteralPath $RuntimeConfig -Raw | ConvertFrom-Json
if($cfg.schema -ne 1){throw 'Expected public runtime configuration schema1'}
$jvm=@('-Dfabric.development=false','-XX:ActiveProcessorCount=1','--enable-native-access=ALL-UNNAMED','--sun-misc-unsafe-memory-access=allow')
if($Role -eq 'server'){
    $cwd=Join-Path $rootPath 'server'
    $launcher=Join-Path $cwd 'fabric-server-launch.jar'
    if(!(Test-Path -LiteralPath $launcher)){throw 'Official Fabric server launcher missing'}
    if(!(Test-Path -LiteralPath $cfg.authority_public)){throw 'Existing public authority file required'}
    $jvm+=@('-Xmx2G','-Dpalcraft.shared=true','-Dpalcraft.sessions.mode=strict',('-Dpalcraft.sessions.authority='+$cfg.authority_public),('-Dpalcraft.bridgeDir='+$cfg.server_bridge_dir),('-Dpalcraft.entityDir='+$cfg.entity_dir),('-Dpalcraft.serverJournal='+$cfg.server_journal),('-Dpalcraft.travelAckJournal='+$cfg.travel_ack_journal))
    $extra=@($cfg.server_jvm_args)
    $tail=@('-jar',$launcher,'nogui')
    $identity=$null
    $main='net.fabricmc.loader.impl.launch.server.FabricServerLauncher (official launcher JAR Main-Class)'
}else{
    if(!$GuestManifest){throw 'Existing enrolled guest manifest required'}
    $guest=Get-Content -LiteralPath $GuestManifest -Raw | ConvertFrom-Json
    if($guest.schema -ne 1 -or $guest.kind -ne 'palcraft_guest' -or $guest.environment -ne 'BridgeLab'){throw 'Expected existing enrolled BridgeLab guest'}
    $identity=$guest.identity
    $uuid=$identity.mc_uuid
    [Guid]$parsed=[Guid]::Empty
    if(![Guid]::TryParse($uuid,[ref]$parsed)){throw 'Invalid enrolled UUID'}
    $cwd=Join-Path $rootPath ('players/'+$uuid+'/minecraft')
    if(!(Test-Path -LiteralPath $cwd)){throw 'Normal player game directory missing'}
    $credential=@($guest.guest.jvm_args | Where-Object {$_ -like '-Dpalcraft.session.credential=*'})
    if($credential.Count -ne 1){throw 'Exactly one existing credential file reference required'}
    # The credential is referenced only. Its contents are never opened here.
    if(!(Test-Path -LiteralPath $credential[0].Substring('-Dpalcraft.session.credential='.Length))){throw 'Referenced enrolled credential file missing'}
    $jvm+=@('-Xms256M','-Xmx1G','-XX:HeapDumpPath=MojangTricksIntelDriversForPerformance_javaw.exe_minecraft.exe.heapdump','-XX:StackShadowPages=32','--add-exports','java.base/jdk.internal.misc=ALL-UNNAMED',('-Djava.library.path='+$cwd+'/natives/java'),('-Djna.tmpdir='+$cwd+'/natives/jna'),('-Dorg.lwjgl.system.SharedLibraryExtractPath='+$cwd+'/natives/lwjgl'),('-Dio.netty.native.workdir='+$cwd+'/natives/netty'),'-Dminecraft.launcher.brand=PalCraft-Standard','-Dminecraft.launcher.version=1')
    foreach($arg in $guest.guest.jvm_args){
        if($arg -like '-Dpalcraft.*' -or $arg -like '-Dpassthrough.*'){
            if($arg -notlike '-Dpalcraft.bridgeDir=*'){$jvm+=$arg}
        }
    }
    $jvm+=('-Dpalcraft.bridgeDir='+$cfg.guest_bridge_dir)
    $extra=@($cfg.guest_jvm_args)
    $libraries=@($recipe.client_libraries | ForEach-Object {
        if($_ -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($_)){throw 'Invalid library path'}
        $path=Join-Path $rootPath ('client/libraries/'+$_)
        if(!(Test-Path -LiteralPath $path)){throw ('Normal library missing: '+$_)}
        $path
    })
    $libraries+=(Join-Path $rootPath 'client/versions/26.3/26.3.jar')
    $profile=Get-Content (Join-Path $rootPath ('client/versions/'+$recipe.client_profile+'/'+$recipe.client_profile+'.json')) -Raw | ConvertFrom-Json
    $jvm+=@($profile.arguments.jvm)
    $jvm+=@('-classpath',($libraries -join [IO.Path]::PathSeparator))
    $main=$recipe.client_main
    $tail=@($main,'--username',$identity.mc_name,'--version',$recipe.client_profile,'--gameDir',$cwd,'--assetsDir',(Join-Path $rootPath 'client/assets'),'--assetIndex','34','--uuid',$uuid,'--accessToken','0','--clientId','00000000-0000-0000-0000-000000000000','--xuid','','--versionType','release','--width','1920','--height','1080')
}
foreach($arg in $extra){
    if($arg -notmatch '^-D(palcraft|passthrough)\.' -or $arg -match '(?i)token|password|private.?key|secret'){throw 'Additional runtime args must be public PalCraft properties'}
}
if(($jvm+$tail) -match 'fabric\.dli|devlaunchinjector|\.gradle[\\/]|build[\\/]classes|build[\\/]resources'){throw 'Development launch dependency refused'}
$out=if($MetadataOutputDirectory){[IO.Path]::GetFullPath($MetadataOutputDirectory)}else{Join-Path $rootPath 'launch'}
New-Item -ItemType Directory -Force $out | Out-Null
$quote={param([string]$x) '"'+$x.Replace('\','\\').Replace('"','\"').Replace("`n",'\n').Replace("`r",'\r')+'"'}
$all=@($jvm+$extra+$tail)
$argsFile=Join-Path $out ($Role+'.args')
[IO.File]::WriteAllText($argsFile, (($all | ForEach-Object { & $quote $_ }) -join "`n")+"`n", [Text.UTF8Encoding]::new($false))
$record=@{schema=1;role=$Role;root=$rootPath;cwd=$cwd;main=$main;args_file=$argsFile;java_major=25;minecraft='26.3';loader='0.19.5';development=$false;identity=$identity;auth_mode= $(if($Role -eq 'guest'){'registered BridgeLab identity on existing offline local server; no Microsoft token read'}else{'existing server policy'});runtime_config=(Resolve-Path $RuntimeConfig).Path;configured_for_runtime_batch=($cfg.configured_for_runtime_batch -eq $true);normal_launch_prepared=$true;minecraft_started=$false;runtime_accepted=$false}
$record.expected_mod_version='0.2.0-integration.10.2-maintenance'
$record.expected_mod_sha256='3b782bb7308ea9926bd57e330103f2fa07abd323b817a074117101387a65f831'
$record | ConvertTo-Json -Depth 7 | Set-Content (Join-Path $out ($Role+'.json')) -Encoding UTF8
'Prepared normal '+$Role+' arguments: '+$argsFile
