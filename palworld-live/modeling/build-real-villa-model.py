"""Combine actual render mesh LOD0 with actual live component transforms."""
from pathlib import Path
import json,math,hashlib,datetime,gzip,base64

HERE=Path(__file__).resolve().parent
OUT=HERE.parents[2]/'outputs'/'villa-model-real'
VIZ=Path('/Users/PLAYER/.codex/visualizations/2026/10/04/00000000-0000-4000-8000-000000000003')
live=json.loads((HERE/'actual-geometry-live.json').read_text())
assets=json.loads((HERE/'real-mesh-geometry.json').read_text())
old=json.loads((HERE.parents[2]/'outputs/villa-model/villa-scene.json').read_text())
labels={p['id']:p['label'] for p in old['pieces']}
for file in (HERE.parent/'agent-control').glob('*-run.json'):
 for row in json.loads(file.read_text()).get('rows',[]):
  model=row.get('result',{}).get('model')
  if model and model.get('id'):labels[model['id']]=row['label']
origin=old['world_origin_cm'];angle=old['base_yaw_radians'];c,s=math.cos(angle),math.sin(angle)

def qmul(a,b):
 x,y,z,w=a;X,Y,Z,W=b
 return [w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z]
def vec(v):return [v[k] for k in ['X','Y','Z']]
def transform(t):
 dx,dy,dz=[t['Translation'][k]-origin[i] for i,k in enumerate(['X','Y','Z'])]
 q=[t['Rotation'][k] for k in ['X','Y','Z','W']]
 return dict(p=[round((dx*c+dy*s)/100,6),round((-dx*s+dy*c)/100,6),round(dz/100,6)],
             q=[round(v,10) for v in qmul([0,0,-math.sin(angle/2),math.cos(angle/2)],q)],s=vec(t['Scale3D']))
def rotate(v,q):
 x,y,z,w=q;X,Y,Z=v;tx=2*(y*Z-z*Y);ty=2*(z*X-x*Z);tz=2*(x*Y-y*X)
 return [X+w*tx+y*tz-z*ty,Y+w*ty+z*tx-x*tz,Z+w*tz+x*ty-y*tx]

meshes={}
models={v['id']:v for v in live['models']}
used_assets={comp['mesh'].split(' ',1)[1] for comp in live['components'] if comp.get('model_id') in models}
for path,j in assets.items():
 if path not in used_assets:continue
 if 'error' in j:raise RuntimeError(j['error'])
 lod=next(v for v in j['lods'] if v['level']==0)
 meshes[path.split('/')[-1].split('.')[0]]=dict(asset=path,lod=0,
    v=[[round(n/100,5) for n in v] for v in lod['vertices']],i=lod['indices'])
pieces=[dict(id=k,label=labels.get(k,v['build_id']+'-'+k[:8]),build=v['build_id'],**transform(v['transform'])) for k,v in models.items()]
components=[]
for comp in live['components']:
 mid=comp.get('model_id')
 if mid not in models:continue
 name=comp['mesh'].split('/')[-1].split('.')[0];label=labels.get(mid,models[mid]['build_id']+'-'+mid[:8])
 kind=('support' if name=='SM_Pillar_Wood' else 'stairs' if name=='SM_Stair_Wood'
       else 'railing' if name=='SM_Fence_Wood' else 'roof' if any(k in label for k in ['top-roof','canopy','roof-','gable','belvedere-pyramid'])
       else 'floor' if name in ('SM_Roof_Wood','SM_Floor_Wood') else 'wall' if 'Wall' in models[mid]['build_id'] or 'wall' in models[mid]['build_id'] else 'decor')
 components.append(dict(model_id=mid,mesh=name,category=kind,label=label,**transform(comp['transform'])))
assert {c['model_id'] for c in components}==set(models)
scene=dict(format=2,source='actual_game_render_mesh_and_live_components',observed_unix=live['observed_unix'],
 units='meters',world_origin_cm=origin,base_yaw_radians=angle,pieces=pieces,components=components,
 meshes=meshes,material_textures_included=False,terrain_included=False)
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'villa-real-scene.json').write_text(json.dumps(scene,separators=(',',':'))+'\n')
obj=['# Actual Palworld render LOD0, live component transforms, meters, Z up'];offset=0;triangles=0
for comp in components:
 m=meshes[comp['mesh']];obj.append('g '+comp['label']+'_'+comp['mesh'])
 for v in m['v']:
  pos=rotate([v[i]*comp['s'][i] for i in range(3)],comp['q']);pos=[pos[i]+comp['p'][i] for i in range(3)]
  obj.append('v '+' '.join(f'{x:.5f}' for x in pos))
 for i in range(0,len(m['i']),3):obj.append('f '+' '.join(str(offset+n+1) for n in [m['i'][i],m['i'][i+2],m['i'][i+1]]));triangles+=1
 offset+=len(m['v'])
(OUT/'villa-real.obj').write_text('\n'.join(obj)+'\n')
html=(HERE/'real-villa-viewer-template.html').read_text().replace('SCENE_JSON_PLACEHOLDER',json.dumps({'encoding':'gzip-base64','data':base64.b64encode(gzip.compress(json.dumps(scene,separators=(',',':')).encode(),compresslevel=9)).decode()},separators=(',',':')))
assert len(html.encode())<1000000
(VIZ/'palworld-villa-real.html').write_text(html)
(OUT/'README.txt').write_text('真实建筑几何模型\n\n'+str(len(meshes))+'种游戏原始渲染网格，使用LOD0顶点和三角面；'+str(len(pieces))+'件建筑的'+str(len(components))+'个当前网格组件。\n坐标、旋转、缩放从测试服现有实例读取，门板独立读取，未使用请求坐标代替实际组件变换。\n单位米，Z向上。OBJ可导入3D软件，JSON保留组件与游戏实例ID用于后续精确调整。\n未带入游戏材质贴图或地形；游戏当前时刻的组件快照。\n')
print(json.dumps({'models':len(pieces),'components':len(components),'meshes':len(meshes),'triangles':triangles,'html_bytes':len(html.encode()),'path':str(VIZ/'palworld-villa-real.html')}))
