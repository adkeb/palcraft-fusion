#!/usr/bin/env python3
"""Use one installed player's existing game-thread operation mailbox."""
import argparse,json,time,os
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('source',type=Path)
p.add_argument('--root',required=True,type=Path)
p.add_argument('--timeout',type=float,default=15)
a=p.parse_args()
root=a.root.resolve();bridge=root/'PalCraft-Dev/bridge'
assert (root/'.palcraft/state.json').is_file(), 'Owned installed root required'
assert bridge.is_dir(), 'Existing player bridge required'
target=bridge/'client-op.lua'
assert not target.exists(), 'Existing client operation is still pending'
result=bridge/'client-op-result.json';old=result.stat().st_mtime_ns if result.exists() else 0
pending=bridge/'client-op.pending';pending.write_text(a.source.read_text(),encoding='utf-8');os.replace(pending,target)
deadline=time.monotonic()+a.timeout
while time.monotonic()<deadline:
 if result.exists() and result.stat().st_mtime_ns!=old:
  try:receipt=json.loads(result.read_text())
  except json.JSONDecodeError:time.sleep(.1);continue
  print(json.dumps(receipt,ensure_ascii=False));break
 time.sleep(.1)
else:raise TimeoutError('Installed player did not execute the existing operation mailbox within the requested timeout')
