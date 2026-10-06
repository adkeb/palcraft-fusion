"""Read live geometry/materials through the persistent agent, then export the model.

Does not replace the running server Mod entry or require an online player.
New assets are extracted on the Windows host from its installed game.
"""
from pathlib import Path
import argparse,base64,json,subprocess,time,sys,zipfile
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(HERE.parent/'agent-control'))
from client import call
parser=argparse.ArgumentParser();parser.add_argument('--ids-file',type=Path);parser.add_argument('--read-only',action='store_true');args=parser.parse_args()
ids=json.loads(args.ids_file.read_text()) if args.ids_file else [p['id'] for p in json.loads((ROOT/'outputs/villa-model-real/villa-real-scene.json').read_text())['pieces']]
def remote(script):
    encoded=base64.b64encode(script.encode('utf-16le')).decode()
    return subprocess.run(['ssh','-o','BatchMode=yes','5090','powershell -NoProfile -NonInteractive -EncodedCommand '+encoded],check=True,capture_output=True,text=True).stdout
def receive(name,local):
    for _ in range(30):
        ready=remote("$ProgressPreference='SilentlyContinue';Test-Path 'D:\\PalworldServer-LAN\\BridgeLab\\rpc\\"+name+"'").strip()
        if ready=='True':break
        time.sleep(.5)
    else:raise RuntimeError('Snapshot not ready: '+name)
    subprocess.run(['scp','-q','5090:D:/PalworldServer-LAN/BridgeLab/rpc/'+name,str(local)],check=True)
call('geometry',{'ids':ids});receive('actual-geometry.json',HERE/'actual-geometry-live.json')
live=json.loads((HERE/'actual-geometry-live.json').read_text())
if live.get('error') or live['errors']:raise RuntimeError(json.dumps({'error':live.get('error'),'errors':live['errors']}))
owned={m['id'] for m in live['models']};components=[c for c in live['components'] if c.get('model_id') in owned]
call('materials',{'components':components});receive('actual-materials.json',HERE/'actual-materials-live.json')
mats=json.loads((HERE/'actual-materials-live.json').read_text())
if mats['errors']:raise RuntimeError(json.dumps(mats['errors']))
if args.read_only:
    print(json.dumps({'models':len(owned),'components':len(components),'requested_ids':len(ids)}));raise SystemExit()
needed=sorted({c['mesh'].split(' ',1)[1] for c in components})
need_tex=sorted({v.split(' ',1)[1] for m in mats['materials'].values() for v in m['textures'].values()})
cache={}
for file in ['real-mesh-material-geometry.json','all-wood-mesh-geometry.json']:
    if (HERE/file).exists():cache.update(json.loads((HERE/file).read_text()))
texture_index=json.loads((HERE/'game-textures/texture-index.json').read_text())
missing=set(needed)-set(cache);missing_tex=set(need_tex)-set(texture_index)
if missing or missing_tex:
    (HERE/'real-mesh-assets.json').write_text(json.dumps(needed));(HERE/'real-texture-assets.json').write_text(json.dumps(need_tex))
    subprocess.run(['scp','-q',str(HERE/'real-mesh-assets.json'),str(HERE/'real-texture-assets.json'),'5090:D:/PalworldServer-LAN/BridgeLab/view/'],check=True)
    remote(r'''
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$r='D:\PalworldServer-LAN\BridgeLab\view'
$map=Get-ChildItem 'D:\PalworldServer-LAN\BridgeLab\Pal\Binaries\Win64\ue4ss' -Filter '*.usmap'|Select-Object -First 1 -ExpandProperty FullName
& "$r\mesh-exporter-materials\MeshExporter.exe" 'D:\steam\steamapps\common\Palworld\Pal\Content\Paks' $map "$r\real-mesh-assets.json" "$r\real-mesh-material-geometry.json" '-' "$r\real-texture-assets.json"
if($LASTEXITCODE -ne 0){throw 'Asset exporter failed'}
Compress-Archive "$r\game-textures\*" "$r\game-textures.zip" -Force
''')
    subprocess.run(['scp','-q','5090:D:/PalworldServer-LAN/BridgeLab/view/real-mesh-material-geometry.json','5090:D:/PalworldServer-LAN/BridgeLab/view/game-textures.zip',str(HERE)+'/'],check=True)
    with zipfile.ZipFile(HERE/'game-textures.zip')as z:z.extractall(HERE/'game-textures')
    cache.update(json.loads((HERE/'real-mesh-material-geometry.json').read_text()))
cache={k:cache[k] for k in needed}
(HERE/'real-mesh-material-geometry.json').write_text(json.dumps(cache,separators=(',',':')))
(HERE/'real-mesh-geometry.json').write_text(json.dumps(cache,separators=(',',':')))
bundled=Path('/Users/PLAYER/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3')
subprocess.run([str(bundled) if bundled.exists() else sys.executable,str(HERE/'build-textured-villa-model.py')],check=True)
