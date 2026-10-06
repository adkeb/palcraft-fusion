"""Read installed MC class signatures/bytecode without starting its client."""
import argparse
import base64
import re
import subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("output")
p.add_argument("classes", nargs="+")
p.add_argument("--bytecode", action="store_true")
a = p.parse_args()
assert all(re.fullmatch(r"[A-Za-z0-9_.$]+", name) for name in a.classes)
classes = " ".join("'" + name + "'" for name in a.classes)
script = r"""
$ProgressPreference='SilentlyContinue'
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass='BelowNormal'
$env:JAVA_TOOL_OPTIONS='-XX:ActiveProcessorCount=1 -Xms16m -Xmx256m'
$javap='C:\Users\PLAYER\AppData\Roaming\.minecraft\runtime\java-runtime-epsilon\windows-x64\java-runtime-epsilon\bin\javap.exe'
$jar='D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache\caches\fabric-loom\26.3\minecraft-client.jar'
""" + "& $javap -p " + ("-c " if a.bytecode else "") + "-classpath $jar " + classes
result = subprocess.run(["ssh", "-o", "BatchMode=yes", "5090", "powershell -NoProfile -NonInteractive -EncodedCommand " + base64.b64encode(script.encode("utf-16le")).decode()], capture_output=True)
Path(a.output).parent.mkdir(parents=True, exist_ok=True)
Path(a.output).write_bytes(result.stdout)
print("exit", result.returncode, "bytes", len(result.stdout))
if result.stderr:
    print(result.stderr.decode("utf-8", "replace")[:500])
raise SystemExit(result.returncode)
