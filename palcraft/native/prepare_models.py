"""Prepare installed Minecraft assets for the native Palworld renderer.

Run against the player's own client jar. The distributable contains this converter,
not Minecraft's assets. Models retain their actual faces, UVs and blockstates.
"""
import argparse,json,math,zipfile
from pathlib import Path
from functools import lru_cache

NORMALS={'down':(0,-1,0),'up':(0,1,0),'north':(0,0,-1),'south':(0,0,1),'west':(-1,0,0),'east':(1,0,0)}
def resource(name):return name if ':' in name else 'minecraft:'+name
def rotate(v,axis,degrees,origin=(0,0,0),rescale=False):
 a=math.radians(degrees);c,s=math.cos(a),math.sin(a);i='xyz'.index(axis);j,k=(i+1)%3,(i+2)%3
 p=[v[n]-origin[n] for n in range(3)];q=p.copy();q[j]=c*p[j]-s*p[k];q[k]=s*p[j]+c*p[k]
 if rescale:q[j]/=c;q[k]/=c
 return [q[n]+origin[n] for n in range(3)]
def vertices(a,b):
 x,y,z=a;X,Y,Z=b
 return {'down':[(x,y,Z),(x,y,z),(X,y,z),(X,y,Z)],'up':[(x,Y,z),(x,Y,Z),(X,Y,Z),(X,Y,z)],
 'north':[(X,Y,z),(X,y,z),(x,y,z),(x,Y,z)],'south':[(x,Y,Z),(x,y,Z),(X,y,Z),(X,Y,Z)],
 'west':[(x,Y,z),(x,y,z),(x,y,Z),(x,Y,Z)],'east':[(X,Y,Z),(X,y,Z),(X,y,z),(X,Y,z)]}
def defaults(a,b):
 x,y,z=a;X,Y,Z=b
 return {'down':[x,16-Z,X,16-z],'up':[x,z,X,Z],'north':[16-X,16-Y,16-x,16-y],
 'south':[x,16-Y,X,16-y],'west':[z,16-Y,Z,16-y],'east':[16-Z,16-Y,16-z,16-y]}
def prepare(jar,destination):
 z=zipfile.ZipFile(jar);out=Path(destination);out.mkdir(parents=True,exist_ok=True)
 @lru_cache(None)
 def model(name):
  namespace,path=resource(name).split(':',1)
  try:own=json.loads(z.read(f'assets/{namespace}/models/{path}.json'))
  except KeyError:return {'textures':{},'elements':[],'builtin':name}
  parent=model(own['parent']) if 'parent' in own else {}
  return {**parent,**own,'textures':{**parent.get('textures',{}),**own.get('textures',{})}}
 counts={'models':0,'blockstates':0,'textures':0,'builtin_models':[]}
 for path in z.namelist():
  if path.startswith('assets/minecraft/blockstates/')and path.endswith('.json'):
   target=out/'states/minecraft'/Path(path).name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(path));counts['blockstates']+=1
  if not(path.startswith('assets/minecraft/models/block/')and path.endswith('.json')):continue
  name=path.removeprefix('assets/minecraft/models/').removesuffix('.json');data=model('minecraft:'+name);faces=[]
  for element in data.get('elements',[]):
   points=vertices(element['from'],element['to']);default=defaults(element['from'],element['to'])
   for direction,face in element['faces'].items():
    texture=face['texture'];seen=set()
    while isinstance(texture,str)and texture.startswith('#')and texture not in seen:seen.add(texture);texture=data['textures'].get(texture[1:],'minecraft:block/stone')
    translucent=isinstance(texture,dict)and texture.get('force_translucent',False)
    if isinstance(texture,dict):texture=texture['sprite']
    texture=resource(texture);namespace,texture_path=texture.split(':',1)
    target=out/'textures'/namespace/(texture_path+'.png')
    if not target.exists():
     try:content=z.read(f'assets/{namespace}/textures/{texture_path}.png')
     except KeyError:continue
     target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content);counts['textures']+=1
    positions=points[direction];normal=NORMALS[direction]
    if 'rotation' in element:
     r=element['rotation'];rotations=[(r['axis'],r['angle'])]if'axis'in r else[(axis,r.get(axis,0))for axis in 'xyz']
     for axis,angle in rotations:
      positions=[rotate(v,axis,angle,r['origin'],r.get('rescale',False))for v in positions];normal=rotate(normal,axis,angle)
    u,v,U,V=face.get('uv',default[direction]);uv=[(u,v),(u,V),(U,V),(U,v)];shift=face.get('rotation',0)//90;uv=uv[shift:]+uv[:shift]
    faces.append({'texture':texture,'vertices':[[c/16 for c in p]for p in positions],'normal':normal,'uv':[[c/16 for c in p]for p in uv],'direction':direction,'tint':face.get('tintindex',-1),'translucent':translucent})
  target=out/'models/minecraft'/(name+'.json');target.parent.mkdir(parents=True,exist_ok=True)
  target.write_text(json.dumps({'faces':faces},separators=(',',':')));counts['models']+=1
  if not faces and data.get('builtin'):counts['builtin_models'].append(name)
 (out/'manifest.json').write_text(json.dumps(counts,indent=2));print(json.dumps(counts)[:1500])
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('jar');p.add_argument('destination');a=p.parse_args();prepare(a.jar,a.destination)
