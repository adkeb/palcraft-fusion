$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$work='D:\PalworldServer-LAN\PalCraft-Dev\workstreams\utf8-iat-next-probe'
$old=Get-Content -LiteralPath (Join-Path $work 'probe.json') -Raw -Encoding UTF8|ConvertFrom-Json;$root=$old.root
Copy-Item -LiteralPath (Join-Path $work 'PcUtf8EarlyProbe.exe') -Destination (Join-Path $root 'probe.exe') -Force
Copy-Item -LiteralPath (Join-Path $work 'flow.lua') -Destination (Join-Path $root '全部 接口.lua') -Force
$env:PALCRAFT_WINDOWS_ROOT=$root;$env:PALCRAFT_UTF8_BOOTSTRAP_SCRIPT=Join-Path $root '最初 脚本.lua';$env:PALCRAFT_UTF8_FLOW_SCRIPT=Join-Path $root '全部 接口.lua'
$results=@();foreach($mode in @('control','candidate')) {
$dir=if($mode -eq 'control'){'control'}else{'ue4ss'}
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $root 'probe.exe';$info.Arguments='"'+(Join-Path (Join-Path $root $dir) 'UE4SS.dll')+'" '+$mode
$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
$p=[Diagnostics.Process]::new();$p.StartInfo=$info;[void]$p.Start();if(-not $p.WaitForExit(15000)){throw 'isolated fixture timeout'}
$results+=@{mode=$mode;exit_code=$p.ExitCode;stdout=$p.StandardOutput.ReadToEnd();stderr=$p.StandardError.ReadToEnd()};$p.Dispose()
}
$report=@{root=$root;platform='native_windows';results=$results;actual_ue4ss_or_game_loaded=$false;source_pin='2281fa311e417b1dfddedbcd49972d764fddb244'}
[IO.File]::WriteAllText((Join-Path $work 'probe.json'),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false));$results|ConvertTo-Json -Depth 4 -Compress
