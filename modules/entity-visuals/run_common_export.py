"""Single-worker BelowNormal export; no game or graphical renderer is launched."""
import base64,hashlib,json,subprocess
from pathlib import Path
base=Path('work/minecraft-fusion/entity-visuals')
sources=[base/'java/VanillaPoseExport.java',base/'java/CommonMobOracle.java']
for p in sources:subprocess.run(['scp',str(p),'5090:D:/PalworldServer-LAN/PalCraft-Dev/'+p.name],check=True)
script=r'''
$ProgressPreference='SilentlyContinue'
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass='BelowNormal'
$env:JAVA_TOOL_OPTIONS='-XX:ActiveProcessorCount=1 -Xms16m -Xmx256m'
$jdk='C:\Users\PLAYER\AppData\Roaming\.minecraft\runtime\java-runtime-epsilon\windows-x64\java-runtime-epsilon\bin'
$jar='D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache\caches\fabric-loom\26.3\minecraft-client.jar'
$jars=@(Get-ChildItem 'D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache\caches\modules-2\files-2.1' -Filter '*.jar' -Recurse | Select-Object -ExpandProperty FullName)
$cp=$jar+';D:\PalworldServer-LAN\PalCraft-Dev;'+($jars-join';')
& "$jdk\javac.exe" -cp $cp 'D:\PalworldServer-LAN\PalCraft-Dev\VanillaPoseExport.java' 'D:\PalworldServer-LAN\PalCraft-Dev\CommonMobOracle.java'
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "$jdk\java.exe" -cp $cp CommonMobOracle
exit $LASTEXITCODE
'''
r=subprocess.run(['ssh','-o','BatchMode=yes','5090','powershell -NoProfile -NonInteractive -EncodedCommand '+base64.b64encode(script.encode('utf-16le')).decode()],capture_output=True)
out=base/'research/vanilla-common.ndjson';out.write_bytes(r.stdout)
out.with_suffix('.meta.json').write_text(json.dumps({'minecraft_version':'26.3','minecraft_client_sha256':hashlib.sha256(Path('work/minecraft-fusion/palcraft/mc/minecraft-client-26.3.jar').read_bytes()).hexdigest(),'source_class':'VanillaPoseExport/CommonMobOracle','data_only':True,'night_low_power':True},indent=2))
print('exit',r.returncode,'bytes',len(r.stdout));print(r.stderr.decode('utf-8','replace')[:900]);raise SystemExit(r.returncode)
