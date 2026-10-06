"""Minimal compile and two actual renderer-submit CPU references, one worker."""
import base64,hashlib,json,subprocess
from pathlib import Path
base=Path('work/minecraft-fusion/entity-visuals')
for name in['VanillaEntityCapture.java','RendererCaptureOracle.java']:
    subprocess.run(['scp',str(base/'java'/name),'5090:D:/PalworldServer-LAN/PalCraft-Dev/'+name],check=True)
script=r'''
$ProgressPreference='SilentlyContinue'
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass='BelowNormal'
$env:JAVA_TOOL_OPTIONS='-XX:ActiveProcessorCount=1 -Xms16m -Xmx256m -Djava.awt.headless=true'
$jdk='C:\Users\PLAYER\AppData\Roaming\.minecraft\runtime\java-runtime-epsilon\windows-x64\java-runtime-epsilon\bin'
$jar='D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache\caches\fabric-loom\26.3\minecraft-client.jar'
$jars=@(Get-ChildItem 'D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache\caches\modules-2\files-2.1' -Filter '*.jar' -Recurse | Select-Object -ExpandProperty FullName)
$cp=$jar+';D:\PalworldServer-LAN\PalCraft-Dev;'+($jars-join';')
$classes='D:\PalworldServer-LAN\PalCraft-Dev\entity-visual-capture-classes'
New-Item -ItemType Directory -Force $classes | Out-Null
& "$jdk\javac.exe" -d $classes -cp $cp 'D:\PalworldServer-LAN\PalCraft-Dev\VanillaEntityCapture.java' 'D:\PalworldServer-LAN\PalCraft-Dev\RendererCaptureOracle.java'
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "$jdk\java.exe" -cp ($classes+';'+$cp) RendererCaptureOracle
exit $LASTEXITCODE
'''
r=subprocess.run(['ssh','-o','BatchMode=yes','5090','powershell -NoProfile -NonInteractive -EncodedCommand '+base64.b64encode(script.encode('utf-16le')).decode()],capture_output=True)
out=base/'research/actual-renderer-capture.ndjson';out.write_bytes(r.stdout)
out.with_suffix('.meta.json').write_text(json.dumps({'minecraft_version':'26.3','minecraft_client_sha256':hashlib.sha256(Path('work/minecraft-fusion/palcraft/mc/minecraft-client-26.3.jar').read_bytes()).hexdigest(),'source':'actual CreeperRenderer/EnderDragonRenderer.submit with real collector','night_low_power':True,'data_only':True},indent=2))
print('exit',r.returncode,'bytes',len(r.stdout));print(r.stderr.decode('utf-8','replace')[:2000]);raise SystemExit(r.returncode)
