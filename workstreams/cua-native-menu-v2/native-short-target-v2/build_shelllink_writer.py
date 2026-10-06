#!/usr/bin/env python3
"""One small Windows CLI build on Mac, nice19, no runtime execution/deployment."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import argparse

here=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--zig',required=True,type=Path,help='Path to the installed Zig 0.15.2 executable')
parser.add_argument('--out',type=Path,default=here/'PalCraftShellLink-v2.exe')
parser.add_argument('--source',type=Path,default=here/'shelllink_writer.cpp')
args=parser.parse_args()
zig=args.zig.absolute();output=args.out.absolute();source=args.source.absolute()
assert not output.exists(),'Do not overwrite compiled artifacts'
output.parent.mkdir(parents=True,exist_ok=True)
os.nice(19)
command=[str(zig),'c++','-target','x86_64-windows-gnu','-std=c++17','-Os',
         '-fno-exceptions','-fno-rtti','-fno-lto','-municode','-Wall','-Wextra',
         str(source),'-o',str(output),'-lole32','-luuid']
with output.with_suffix('.build.log').open('w') as log:
    subprocess.run(command,check=True,stdout=log,stderr=log,cwd=source.parent)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report={'schema':1,'artifact':str(output),'sha256':sha(output),'bytes':output.stat().st_size,
        'source_sha256':sha(source),'target':'x86_64-windows-gnu',
        'command':command,'priority_nice':19,'concurrent_compilers':1,
        'deployed':False,'executed_under_wine':False,'target_executed':False,
        'protocol':'PCSLNK01: five u32-length-prefixed UTF-16LE fields',
        'api':'GetShortPathNameW ASCII alias if needed; original/alias/readback file identities must agree; IShellLinkW/IPersistFile Save/Load and exact original Args/Workdir/Description; no Resolve/target start'}
output.with_suffix('.build.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
