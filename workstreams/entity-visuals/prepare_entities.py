"""Prepare private MC creature rigs/skins from an installed client, not a bundle."""
import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path
from PIL import Image

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('jar');p.add_argument('oracle');p.add_argument('destination')
a=p.parse_args();jar=Path(a.jar);oracle=Path(a.oracle);root=Path(a.destination)
metadata=json.loads(oracle.with_suffix('.meta.json').read_text())
assert metadata['minecraft_client_sha256']==hashlib.sha256(jar.read_bytes()).hexdigest()
archive=zipfile.ZipFile(jar);samples=[];counts={'rigs':0,'skins':0,'parts':0,'quads':0}
for line in oracle.read_text().splitlines():
    if not line.startswith('{'):continue
    row=json.loads(line)
    if row['type']=='sample':samples.append(row);continue
    if row['type']!='rig':continue
    namespace,texture=row['texture'].split(':',1)
    png=archive.read(f'assets/{namespace}/textures/{texture}.png')
    image=Image.open(io.BytesIO(png)).convert('RGBA')
    target=root/'skins'/namespace/(texture+'.png');target.parent.mkdir(parents=True,exist_ok=True)
    scale=max(1,256//min(image.size));image.resize((image.width*scale,image.height*scale),Image.Resampling.NEAREST).save(target)
    row.update({'schema':1,'kind':'minecraft:'+row['kind'],'space':'minecraft_model_blocks',
                'native_actor_space':'ue_cm_feet_origin_forward_positive_x','adult_only':True,
                'skin_path':target.relative_to(root).as_posix(),'skin_source_sha256':hashlib.sha256(png).hexdigest(),
                'alpha_mode':'cutout','renderer_model_y_offset':1.501,
                'renderer_actor_yaw_formula':'-90 - mc_body_yaw_degrees',
                'animations':{'walk':'actual_model_setupAnim','attack':'zombie_arms_or_creeper_fuse',
                              'hurt':'LivingEntityRenderer.hasRedOverlay','death':'LivingEntityRenderer.deathTime_roll'}})
    path=root/'rigs/minecraft'/(row['kind'].split(':')[1]+'.json');path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(row,separators=(',',':')))
    counts['rigs']+=1;counts['skins']+=1;counts['parts']+=len(row['parts']);counts['quads']+=sum(len(part['faces'])for part in row['parts'])
root.mkdir(parents=True,exist_ok=True)
(root/'vanilla-pose-samples.json').write_text(json.dumps(samples,separators=(',',':')))
(root/'manifest.json').write_text(json.dumps({'schema':1,**counts,'samples':len(samples),'source':metadata,
    'runtime_graphics_verified':False,'not_publicly_redistributable_assets':True,
    'not_implemented':['baby and climate model variants','armor and held-item layers','charged creeper aura','runtime native attachment']},indent=2))
print(json.dumps(counts))
