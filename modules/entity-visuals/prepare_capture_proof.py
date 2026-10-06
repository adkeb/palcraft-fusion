"""Private CPU capture proof assets. Live capture uses the existing resource packs."""
import argparse,hashlib,json,zipfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('jar');p.add_argument('captures');p.add_argument('destination')
a=p.parse_args();root=Path(a.destination);jar=Path(a.jar);captures=Path(a.captures)
source=json.loads(captures.with_suffix('.meta.json').read_text());assert source['minecraft_client_sha256']==hashlib.sha256(jar.read_bytes()).hexdigest()
z=zipfile.ZipFile(jar);frames=[];textures={}
for line in captures.read_text().splitlines():
    if not line.startswith('{'):continue
    frame=json.loads(line)
    for batch in frame['batches']:
        for texture in batch['textures'].values():
            if texture in textures:continue
            namespace,path=texture.split(':',1)
            content=z.read(f'assets/{namespace}/{path}')
            target=root/'resources'/namespace/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
            textures[texture]={'path':target.relative_to(root).as_posix(),'source_sha256':hashlib.sha256(content).hexdigest()}
    frames.append(frame)
root.mkdir(parents=True,exist_ok=True)
(root/'frames.json').write_text(json.dumps(frames,separators=(',',':')))
(root/'textures.json').write_text(json.dumps(textures,indent=2))
(root/'manifest.json').write_text(json.dumps({'schema':1,'source':source,'actual_renderers':[f['renderer']for f in frames],
    'source_kind_whitelist':False,'model_vertex_stream_capture':True,'renderer_submit_verified':True,
    'runtime_graphics_verified':False,'texture_files':len(textures),'private_resources':True,
    'limitations':['item/block-model submit paths not yet captured','text/shadow/leash/flame paths reported separately',
                   'dynamic/atlas CPU texture export needs texture owner','native color/eyes/translucency material binding remains pending']},indent=2))
print(json.dumps({'actual_renderers':len(frames),'vertices':sum(f['vertices']for f in frames),'textures':len(textures)}))
