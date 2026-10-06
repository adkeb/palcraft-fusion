"""Add common original creature rigs and private skin/layer assets to V2."""
import argparse,hashlib,io,json,shutil,zipfile
from pathlib import Path
from PIL import Image

p=argparse.ArgumentParser(description=__doc__);p.add_argument('jar');p.add_argument('v2_assets');p.add_argument('oracle');p.add_argument('destination')
a=p.parse_args();root=Path(a.destination);jar=Path(a.jar);oracle=Path(a.oracle)
source=json.loads(oracle.with_suffix('.meta.json').read_text());assert source['minecraft_client_sha256']==hashlib.sha256(jar.read_bytes()).hexdigest()
if not root.exists():shutil.copytree(a.v2_assets,root)
for f in['CONTENT.sha256','SNAPSHOT.json']:
    if(root/f).exists():(root/f).unlink()
z=zipfile.ZipFile(jar)
def skin(name):
    namespace,path=name.split(':',1);png=z.read(f'assets/{namespace}/textures/{path}.png');image=Image.open(io.BytesIO(png)).convert('RGBA')
    target=root/'skins'/namespace/(path+'.png');target.parent.mkdir(parents=True,exist_ok=True)
    scale=max(1,256//min(image.size));image.resize((image.width*scale,image.height*scale),Image.Resampling.NEAREST).save(target)
    return target.relative_to(root).as_posix(),hashlib.sha256(png).hexdigest()
samples=[];rigs=0
for line in oracle.read_text().splitlines():
    if not line.startswith('{'):continue
    row=json.loads(line)
    if row['type']=='sample':samples.append(row);continue
    if row['type']!='rig':continue
    path,digest=skin(row['texture']);row.update({'schema':3,'kind':'minecraft:'+row['kind'],'space':'minecraft_model_blocks',
      'native_actor_space':'ue_cm_feet_origin_forward_positive_x','adult_only':True,'skin_path':path,
      'skin_source_sha256':digest,'alpha_mode':'cutout','renderer_model_y_offset':1.501,
      'renderer_actor_yaw_formula':'-90 - mc_body_yaw_degrees','source':'Minecraft26.3 actual model factory'})
    if row['kind']=='minecraft:spider':row['death_flip_degrees']=180
    target=root/'rigs/minecraft'/(row['kind'].split(':')[1]+'.json');target.write_text(json.dumps(row,separators=(',',':')));rigs+=1
layers={}
for kind in['spider','enderman']:
    texture=f'minecraft:entity/{kind}/{kind}_eyes';path,digest=skin(texture)
    layers[kind]={'texture':texture,'skin_path':path,'source_sha256':digest,'render_layer':'minecraft_eyes',
                  'light_emission':15,'additive_material_required':True,'runtime_material_verified':False}
layers['sheep']={'rig_kind':'minecraft:sheep_wool','default_wool_color':'white','dyed_and_jeb_color_runtime_pending':True}
(root/'layers.json').write_text(json.dumps(layers,indent=2));(root/'common-pose-samples.json').write_text(json.dumps(samples,separators=(',',':')))
manifest=json.loads((root/'manifest.json').read_text());manifest.update({'schema':3,'common_creature_rigs':rigs,'common_pose_samples':len(samples),
    'common_creatures':['skeleton','spider','cow','sheep','chicken','enderman'],'runtime_graphics_verified':False,
    'not_implemented':['armor/held bow and items','common creature babies/climate variants except prior pigs','colored/jeb sheep wool material','eyes additive material','carried block geometry','runtime native attachment']})
(root/'manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps({'common_rigs':rigs,'samples':len(samples)}))
