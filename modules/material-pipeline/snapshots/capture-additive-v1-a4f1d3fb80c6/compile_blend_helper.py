"""One isolated API compile, no game launch or shared build cache writes."""
import ctypes
import json
import pathlib
import re
import subprocess

ctypes.windll.kernel32.SetPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(), 0x4000)
root = pathlib.Path('D:/PalworldServer-LAN/PalCraft-Dev/workstreams/material_pipeline/capture-additive-delta')
classpath_source = pathlib.Path('D:/PalworldServer-LAN/PalCraft-Dev/workstreams/integration/tint-prepare-10-1-52ee271b7560/mc/build/palcraft-launch-metadata/runRegisteredGuest.json')
classpath = ';'.join(entry.replace('\\','/') for entry in json.loads(classpath_source.read_text())['classpath'])
(root / 'classes').mkdir(exist_ok=True)
argfile = root / 'javac.args'
argfile.write_text('--release\n25\n-proc:none\n-classpath\n"' + classpath + '"\n-d\n"' +
    (root / 'classes').as_posix() + '"\n"' + (root / 'CaptureBlendMetadata.java').as_posix() + '"\n')
compiler = 'C:/Users/PLAYER/AppData/Roaming/.minecraft/runtime/java-runtime-epsilon/windows-x64/java-runtime-epsilon/bin/javac.exe'
result = subprocess.run([compiler, '@' + str(argfile)], capture_output=True, text=True, errors='replace')
output = root / 'classes/dev/rehan/passthrough/client/visual/CaptureBlendMetadata.class'
report = dict(compile_exit_code=result.returncode, stderr=result.stderr,
    class_bytes=output.stat().st_size if output.exists() else 0, single_helper_only=True, game_calls=0,
    classpath_source=str(classpath_source), priority='BelowNormal')
print(json.dumps(report))
raise SystemExit(result.returncode)
