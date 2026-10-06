"""Import the complete private cow/sheep/chicken age/climate batch into V3."""
import argparse,hashlib,io,json,shutil,zipfile
from pathlib import Path
from PIL import Image
p=argparse.ArgumentParser(description=__doc__);p.add_argument('jar');p.add_argument('v3_assets');p.add_argument('oracle');p.add_argument('destination')
a=p.parse_args();jar=Path(a.jar);oracle=Path(a.oracle);root=Path(a.destination)
source=json.loads(oracle.with_suffix('.meta.json').read_text());assert source['minecraft_client_sha256']==hashlib.sha256(jar.read_bytes()).hexdigest()
if not root.exists():shutil.copytree(a.v3_assets,root)
for f in['CONTENT.sha256','SNAPSHOT.json']:
    if(root/f).exists():(root/f).unlink()
z=zipfile.ZipFile(jar);samples=[];rigs=0
for line in oracle.read_text().splitlines():
    if not line.startswith('{'):continue
    row=json.loads(line)
    if row['type']=='sample':samples.append(row);continue
    if row['type']!='rig':continue
    ns,path=row['texture'].split(':',1);png=z.read(f'assets/{ns}/textures/{path}.png');im=Image.open(io.BytesIO(png)).convert('RGBA');scale=max(1,256//min(im.size))
    target=root/'skins'/ns/(path+'.png');target.parent.mkdir(parents=True,exist_ok=True);im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST).save(target)
    row.update({'schema':4,'kind':'minecraft:'+row['kind'],'space':'minecraft_model_blocks','native_actor_space':'ue_cm_feet_origin_forward_positive_x',
      'adult_only':False,'skin_path':target.relative_to(root).as_posix(),'skin_source_sha256':hashlib.sha256(png).hexdigest(),
      'alpha_mode':'cutout','renderer_model_y_offset':1.501,'renderer_actor_yaw_formula':'-90 - mc_body_yaw_degrees',
      'baby_geometry_already_small':True,'head_tracks_look':not(row['kind']=='minecraft:chicken'and row['baby'])})
    file=root/'variants/minecraft'/(row['rig_key']+'.json');file.parent.mkdir(parents=True,exist_ok=True);file.write_text(json.dumps(row,separators=(',',':')));rigs+=1
(root/'animal-pose-samples.json').write_text(json.dumps(samples,separators=(',',':')))
manifest=json.loads((root/'manifest.json').read_text());manifest.update({'schema':4,'new_animal_rigs':rigs,'new_animal_pose_samples':len(samples),
 'cow_chicken_climate_age_data_available':True,'sheep_age_and_fur_data_available':True,'runtime_graphics_verified':False,
 'not_implemented':['armor/held bow and items','colored/Jeb sheep wool material','eyes additive material','carried block geometry','runtime native attachment']})
(root/'manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps({'animal_rigs':rigs,'samples':len(samples)}))
