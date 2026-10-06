"""Freeze an asset directory and record hashes for its matching Lua modules."""
import argparse
import hashlib
import json
import shutil
from datetime import datetime,timezone
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('source');p.add_argument('version');p.add_argument('--script',action='append',default=[])
p.add_argument('--verification',action='append',default=[])
a=p.parse_args();source=Path(a.source)
entries=[]
for path in sorted(source.rglob('*')):
    if path.is_file():entries.append((path.relative_to(source).as_posix(),hashlib.sha256(path.read_bytes()).hexdigest()))
content=''.join(d+'  '+name+'\n'for name,d in entries)
digest=hashlib.sha256(content.encode()).hexdigest()
base=Path('work/minecraft-fusion/model-compat')
target=base/'snapshots'/('models-'+a.version+'-'+digest[:12]);target.parent.mkdir(parents=True,exist_ok=True)
if not target.exists():shutil.copytree(source,target)
meta={'schema':3,'version':a.version,'frozen':True,'created_utc':datetime.now(timezone.utc).isoformat(),
      'asset_content_sha256':digest,'files':len(entries),'directory':str(target.resolve()),
      'minecraft_version':'26.3','scripts':{str(Path(s).resolve()):hashlib.sha256(Path(s).read_bytes()).hexdigest()for s in a.script},
      'verification':{str(Path(v).resolve()):json.loads(Path(v).read_text())for v in a.verification},
      'manifest':json.loads((source/'manifest.json').read_text())}
(target/'CONTENT.sha256').write_text(content)
(target/'SNAPSHOT.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2))
(base/('READY-'+a.version+'.json')).write_text(json.dumps(meta,ensure_ascii=False,indent=2))
print(json.dumps({'directory':meta['directory'],'asset_content_sha256':digest,'files':len(entries),'ready':str((base/('READY-'+a.version+'.json')).resolve())},indent=2))
