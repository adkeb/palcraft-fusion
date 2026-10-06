$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Diagnostics.Process]::GetCurrentProcess().PriorityClass=[Diagnostics.ProcessPriorityClass]::BelowNormal
$base='D:/PalworldServer-LAN/PalCraft-Dev'
$snapshot=$base+'/workstreams/integration/boundary-9-2-bb2a57976399'
$mc=$snapshot+'/mc'
$jdk='C:/Users/PLAYER/AppData/Roaming/.minecraft/runtime/java-runtime-epsilon/windows-x64/java-runtime-epsilon'
$jar=$mc+'/build/libs/passthrough-0.2.0-integration.9.2.jar'
$expectedJar='9d2745971d81ac517ead6e2801e573b331c11b922f85f228ee8f735e9b60f35a'
$manifest=Get-Content ($snapshot+'/source-manifest.json') -Raw | ConvertFrom-Json
function Assert-FrozenSource {
    if((Get-FileHash $jar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedJar){throw 'Frozen 9.2 jar mismatch'}
    foreach($entry in $manifest.files.PSObject.Properties){
        if((Get-FileHash ($mc+'/'+$entry.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value){throw ('Frozen source mismatch: '+$entry.Name)}
    }
}
Assert-FrozenSource
$lock=[IO.File]::Open($base+'/workstreams/.gradle-build.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
    $env:JAVA_HOME=$jdk
    $env:PATH=$jdk+'/bin;'+$env:PATH
    $env:GRADLE_USER_HOME=$base+'/workstreams/integration/gradle-home'
    $env:JAVA_TOOL_OPTIONS=''
    Push-Location $mc
    try {
        $ErrorActionPreference='Continue'
        & ($base+'/gradle/gradle-9.7.1/bin/gradle.bat') prepareFrozenDliMetadata --init-script ($snapshot+'/Generate-DLI-Metadata.init.gradle') '-PpalcraftGuestManifest=D:/PalworldServer-LAN/PalCraft-Dev/sessions/11111111-1111-1111-1111-111111111111/guest-manifest.json' '-PpalcraftSharedServerRunDir=D:/PalworldServer-LAN/PalCraft-Dev/mc/run-shared' --offline --no-daemon --max-workers=1 --no-parallel --no-configuration-cache --console=plain '-Dorg.gradle.priority=low' '-Dorg.gradle.jvmargs=-Xmx768m -XX:ActiveProcessorCount=1 -Dfile.encoding=UTF-8 -Duser.language=en -Duser.country=US' 2>&1 | ForEach-Object {$_.ToString()} | Out-File ($snapshot+'/launch-preparation.log') -Encoding UTF8
        $rc=$LASTEXITCODE
        $ErrorActionPreference='Stop'
    } finally { Pop-Location }
    Get-Content ($snapshot+'/launch-preparation.log') -Tail 65
    if($rc -ne 0){exit $rc}
    Assert-FrozenSource
} finally { $lock.Dispose() }
