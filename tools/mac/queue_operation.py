#!/usr/bin/env python3
from pathlib import Path
import sys,json,time
root=Path(__file__).resolve().parent/'drive_d/PalworldServer-LAN/PalCraft-Dev/bridge'
source=Path(sys.argv[1]).read_text()
result=root/'client-op-result.json'
old=result.stat().st_mtime_ns if result.exists() else 0
pending=root/'client-op.pending';pending.write_text(source);pending.replace(root/'client-op.lua')
for _ in range(100):
 if result.exists() and result.stat().st_mtime_ns!=old:
  try:r=json.loads(result.read_text())
  except json.JSONDecodeError:time.sleep(.1);continue
  print(json.dumps(r,ensure_ascii=False));break
 time.sleep(.1)
else:raise TimeoutError('Mac client did not execute operation within10seconds')
