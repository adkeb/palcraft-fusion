param(
    [Parameter(Mandatory=$true)][string]$Snapshot,
    [string]$TaskJdk='C:/Users/PLAYER/AppData/Roaming/.minecraft/runtime/java-runtime-epsilon/windows-x64/java-runtime-epsilon',
    [string]$Tasks='clean build'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Console]::OutputEncoding
[Diagnostics.Process]::GetCurrentProcess().PriorityClass=[Diagnostics.ProcessPriorityClass]::BelowNormal
$base='D:/PalworldServer-LAN/PalCraft-Dev'
$integration=$base+'/workstreams/integration'
if($Snapshot -notmatch '^[a-z0-9-]+$'){throw 'Invalid snapshot name'}
$snapshotRoot=$integration+'/'+$Snapshot
$source=$snapshotRoot+'/mc'
$privateCache=$integration+'/gradle-home'
$lockPath=$base+'/workstreams/.gradle-build.lock'
$manifest=Get-Content ($snapshotRoot+'/source-manifest.json') -Raw | ConvertFrom-Json
if((Get-FileHash ($snapshotRoot+'/source.zip') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.archive_sha256){throw 'Archive hash mismatch'}
$lock=$null
try {
    # A live handle is the lease. A leftover file does not block later builds.
    $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $lock.SetLength(0)
    $lease=[Text.Encoding]::UTF8.GetBytes((@{owner='integration_build';snapshot=$Snapshot;pid=$PID;started_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Compress))
    $lock.Write($lease,0,$lease.Length)
    $lock.Flush()
    if(Test-Path $source){throw 'Snapshot already expanded; use a fresh snapshot name'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($snapshotRoot+'/source.zip',$source)
    foreach($item in $manifest.files.PSObject.Properties){
        $path=$source+'/'+$item.Name
        if((Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.Value){throw ('Source hash mismatch: '+$item.Name)}
    }
    New-Item -ItemType Directory -Force ($privateCache+'/caches') | Out-Null
    # Shared caches are sources only. Gradle never writes to the running project's cache.
    if(!(Test-Path ($privateCache+'/caches/modules-2'))){
        & robocopy ($base+'/gradle-cache/caches') ($privateCache+'/caches') /E /XF *.lock /NFL /NDL /NJH /NJS /NP /R:0 /W:0 | Out-Null
        if($LASTEXITCODE -ge 8){throw 'Dependency cache copy failed'}
    }
    New-Item -ItemType Directory -Force ($source+'/.gradle/loom-cache') | Out-Null
    & robocopy ($base+'/mc/.gradle/loom-cache') ($source+'/.gradle/loom-cache') /E /XF *.lock launch.cfg /NFL /NDL /NJH /NJS /NP /R:0 /W:0 | Out-Null
    if($LASTEXITCODE -ge 8){throw 'Project Loom cache copy failed'}
    $env:JAVA_HOME=$TaskJdk
    $env:PATH=$TaskJdk+'/bin;'+$env:PATH
    $env:GRADLE_USER_HOME=$privateCache
    $jdkVersion=& ($TaskJdk+'/bin/java.exe') --version
    $gradle=$base+'/gradle/gradle-9.7.1/bin/gradle.bat'
    $log=$snapshotRoot+'/gradle-build.log'
    $start=[DateTime]::UtcNow
    Push-Location $source
    try {
        $ErrorActionPreference='Continue'
        & $gradle --offline --no-daemon --max-workers=1 --no-parallel --no-configuration-cache --console=plain '-Dorg.gradle.priority=low' '-Dorg.gradle.jvmargs=-Xmx1G -Dfile.encoding=UTF-8 -Duser.language=en -Duser.country=US' @($Tasks.Split(' ',[StringSplitOptions]::RemoveEmptyEntries)) 2>&1 | ForEach-Object { $_.ToString() } | Out-File $log -Encoding UTF8
        $buildExit=$LASTEXITCODE
        $ErrorActionPreference='Stop'
    } finally { Pop-Location }
    $artifacts=@()
    if(Test-Path ($source+'/build/libs')){
        $artifacts=@(Get-ChildItem ($source+'/build/libs') -File | ForEach-Object {@{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant();path=$_.FullName}})
    }
    $result=@{schema_version=1;owner='integration_build';snapshot=$Snapshot;source_hash=$manifest.source_hash;started_utc=$start.ToString('o');finished_utc=[DateTime]::UtcNow.ToString('o');jdk=@($jdkVersion);gradle='9.7.1';tasks=$Tasks;exit_code=$buildExit;private_cache=$privateCache;source_root=$source;runtime_touched=$false;environment='night_low_power';build_priority='low';max_workers=1;build_heap='1G';artifacts=$artifacts}
    $result | ConvertTo-Json -Depth 8 | Set-Content ($snapshotRoot+'/build-result.json') -Encoding UTF8
    $result | ConvertTo-Json -Depth 8 -Compress
    if($buildExit -ne 0){Get-Content $log -Tail 100;exit $buildExit}
} finally {
    if($null -ne $lock){$lock.Dispose()}
}
