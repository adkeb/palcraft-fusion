"""Import private climate/baby rigs beside a frozen V1 creature dataset."""
import argparse
import hashlib
import io
import json
import shutil
import zipfile
from pathlib import Path
from PIL import Image

p=argparse.ArgumentParser(description=__doc__);p.add_argument('jar');p.add_argument('v1_assets');p.add_argument('oracle');p.add_argument('destination')
a=p.parse_args();jar=Path(a.jar);oracle=Path(a.oracle);root=Path(a.destination)
source=json.loads(oracle.with_suffix('.meta.json').read_text());assert source['minecraft_client_sha256']==hashlib.sha256(jar.read_bytes()).hexdigest()
if not root.exists():shutil.copytree(a.v1_assets,root)
for file in['CONTENT.sha256','SNAPSHOT.json']:
    if(root/file).exists():(root/file).unlink()
archive=zipfile.ZipFile(jar);samples=[];rigs=0
for line in oracle.read_text().splitlines():
    if not line.startswith('{'):continue
    row=json.loads(line)
    if row['type']=='sample':samples.append(row);continue
    if row['type']!='rig':continue
    namespace,texture=row['texture'].split(':',1);png=archive.read(f'assets/{namespace}/textures/{texture}.png')
    image=Image.open(io.BytesIO(png)).convert('RGBA');scale=max(1,256//min(image.size))
    target=root/'skins'/namespace/(texture+'.png');target.parent.mkdir(parents=True,exist_ok=True)
    image.resize((image.width*scale,image.height*scale),Image.Resampling.NEAREST).save(target)
    row.update({'schema':2,'kind':'minecraft:'+row['kind'],'space':'minecraft_model_blocks',
      'native_actor_space':'ue_cm_feet_origin_forward_positive_x','adult_only':False,'skin_path':target.relative_to(root).as_posix(),
      'skin_source_sha256':hashlib.sha256(png).hexdigest(),'alpha_mode':'cutout','renderer_model_y_offset':1.501,
      'renderer_actor_yaw_formula':'-90 - mc_body_yaw_degrees','baby_geometry_already_small':True})
    path=root/'variants/minecraft'/(row['rig_key']+'.json');path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(row,separators=(',',':')))
    rigs+=1
(root/'variant-pose-samples.json').write_text(json.dumps(samples,separators=(',',':')))
manifest=json.loads((root/'manifest.json').read_text());manifest.update({'schema':2,'variant_rigs':rigs,'variant_samples':len(samples),
 'source_variants':source,'baby_climate_data_available':True,'runtime_graphics_verified':False,
 'not_implemented':['armor and held-item layers','charged creeper aura','runtime native attachment']})
(root/'manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps({'variant_rigs':rigs,'samples':len(samples)}))
