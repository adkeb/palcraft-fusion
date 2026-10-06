"""Bounded low-priority CPU oracle; no GPU/native image constructor or game."""
import base64,hashlib,json,subprocess
from pathlib import Path
base=Path('work/minecraft-fusion/entity-visuals');src=base/'java/PortableVisualOracle.java'
subprocess.run(['scp',str(src),'5090:D:/PalworldServer-LAN/PalCraft-Dev/'+src.name],check=True)
script=r'''
$ProgressPreference='SilentlyContinue'
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass='BelowNormal'
$env:JAVA_TOOL_OPTIONS='-XX:ActiveProcessorCount=1 -Xms16m -Xmx256m -Djava.awt.headless=true'
$jdk='C:\Users\PLAYER\AppData\Roaming\.minecraft\runtime\java-runtime-epsilon\windows-x64\java-runtime-epsilon\bin'
$jar='D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache\caches\fabric-loom\26.3\minecraft-client.jar'
$jars=@(Get-ChildItem 'D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache\caches\modules-2\files-2.1' -Filter '*.jar' -Recurse | Select-Object -ExpandProperty FullName)
$cp=$jar+';D:\PalworldServer-LAN\PalCraft-Dev;'+($jars-join';')
& "$jdk\javac.exe" -cp $cp 'D:\PalworldServer-LAN\PalCraft-Dev\PortableVisualOracle.java'
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "$jdk\java.exe" -cp $cp PortableVisualOracle
exit $LASTEXITCODE
'''
r=subprocess.run(['ssh','-o','BatchMode=yes','5090','powershell -NoProfile -NonInteractive -EncodedCommand '+base64.b64encode(script.encode('utf-16le')).decode()],capture_output=True)
out=base/'research/vanilla-portable.ndjson';out.write_bytes(r.stdout);out.with_suffix('.meta.json').write_text(json.dumps({'minecraft_version':'26.3','minecraft_client_sha256':hashlib.sha256(Path('work/minecraft-fusion/palcraft/mc/minecraft-client-26.3.jar').read_bytes()).hexdigest(),'source':'actual Arrow/Trident/ItemModelGenerator getSideFaces','night_low_power':True,'data_only':True},indent=2))
print('exit',r.returncode,'bytes',len(r.stdout));print(r.stderr.decode('utf-8','replace')[:1400]);raise SystemExit(r.returncode)
