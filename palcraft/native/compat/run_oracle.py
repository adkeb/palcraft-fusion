"""Run a data-only oracle with the installed MC jar and its existing libraries."""
import argparse
import base64
import hashlib
import json
import re
import subprocess
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument("source")
p.add_argument("output")
a=p.parse_args()
source=Path(a.source)
assert re.fullmatch(r"[A-Za-z0-9_]+",source.stem)
remote="D:/PalworldServer-LAN/PalCraft-Dev/"+source.name
subprocess.run(["scp",str(source),"5090:"+remote],check=True)
script=r"""
$ProgressPreference='SilentlyContinue'
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass='BelowNormal'
$env:JAVA_TOOL_OPTIONS='-XX:ActiveProcessorCount=1 -Xms16m -Xmx256m'
$jdk='C:\Users\PLAYER\AppData\Roaming\.minecraft\runtime\java-runtime-epsilon\windows-x64\java-runtime-epsilon\bin'
$jar='D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache\caches\fabric-loom\26.3\minecraft-client.jar'
$jars=@(Get-ChildItem 'D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache\caches\modules-2\files-2.1' -Filter '*.jar' -Recurse | Select-Object -ExpandProperty FullName)
$cp=$jar+';'+($jars-join';')
"""
script+="& \"$jdk\\javac.exe\" -cp ($cp+';D:\\PalworldServer-LAN\\PalCraft-Dev') '"+remote+"'\nif ($LASTEXITCODE -ne 0){exit $LASTEXITCODE}\n"
script+='& "$jdk\\java.exe" -cp ($cp+\';D:\\PalworldServer-LAN\\PalCraft-Dev\') '+source.stem+'\nexit $LASTEXITCODE'
r=subprocess.run(["ssh","-o","BatchMode=yes","5090","powershell -NoProfile -NonInteractive -EncodedCommand "+base64.b64encode(script.encode("utf-16le")).decode()],capture_output=True)
Path(a.output).parent.mkdir(parents=True,exist_ok=True)
Path(a.output).write_bytes(r.stdout)
jar=Path('work/minecraft-fusion/palcraft/mc/minecraft-client-26.3.jar')
Path(a.output).with_suffix('.meta.json').write_text(json.dumps({'minecraft_client_sha256':hashlib.sha256(jar.read_bytes()).hexdigest(),'minecraft_version':'26.3','source_class':source.stem,'data_only':True},indent=2))
print('exit',r.returncode,'bytes',len(r.stdout));print(r.stderr.decode('utf-8','replace')[:1500])
raise SystemExit(r.returncode)
