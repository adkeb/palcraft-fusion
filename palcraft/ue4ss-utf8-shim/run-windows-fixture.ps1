$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$work='D:\PalworldServer-LAN\PalCraft-Dev\workstreams\utf8-iat-next-probe'
$root=Join-Path ([IO.Path]::GetTempPath()) ('Pc 玩家 IAT 🌱 '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
Expand-Archive -LiteralPath (Join-Path $work 'fixture-payload.zip') -DestinationPath $root
$env:PALCRAFT_WINDOWS_ROOT=$root
$env:PALCRAFT_UTF8_BOOTSTRAP_SCRIPT=Join-Path $root '最初 脚本.lua'
$env:PALCRAFT_UTF8_FLOW_SCRIPT=Join-Path $root '全部 接口.lua'
$results=@();foreach($mode in @('control','candidate')) {
$dir=if($mode -eq 'control'){'control'}else{'ue4ss'}
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $root 'probe.exe'
$info.Arguments='"'+(Join-Path (Join-Path $root $dir) 'UE4SS.dll')+'" '+$mode
$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
$p=[Diagnostics.Process]::new();$p.StartInfo=$info;[void]$p.Start()
if(-not $p.WaitForExit(15000)){throw 'isolated source fixture timeout'}
$results+=@{mode=$mode;exit_code=$p.ExitCode;stdout=$p.StandardOutput.ReadToEnd();stderr=$p.StandardError.ReadToEnd()};$p.Dispose()
}
$report=@{root=$root;platform='native_windows';results=$results;actual_ue4ss_or_game_loaded=$false;source_pin='2281fa311e417b1dfddedbcd49972d764fddb244';fixture='same-pin pristine 33C LuaRaw with module-attach first-script initialization'}
[IO.File]::WriteAllText((Join-Path $work 'probe.json'),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$results|Select-Object mode,exit_code,stdout,stderr|ConvertTo-Json -Depth 4 -Compress
