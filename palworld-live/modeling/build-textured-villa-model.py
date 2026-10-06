"""Attach actual game materials, native UVs and native normals to the real scene."""
from pathlib import Path
import json,math,base64,struct,io,shutil,runpy,gzip
from PIL import Image

HERE=Path(__file__).resolve().parent
OUT=HERE.parents[2]/'outputs/villa-model-real'
VIZ=Path('/Users/PLAYER/.codex/visualizations/2026/10/04/00000000-0000-4000-8000-000000000003')
runpy.run_path(str(HERE/'build-real-villa-model.py'))
scene=json.loads((OUT/'villa-real-scene.json').read_text())
geometry=json.loads((HERE/'real-mesh-material-geometry.json').read_text())
runtime=json.loads((HERE/'actual-materials-live.json').read_text())
live=json.loads((HERE/'actual-geometry-live.json').read_text())
index=json.loads((HERE/'game-textures/texture-index.json').read_text())
source=runtime['materials']

def flat(name):
    row=source[name];out=flat(row['parent']) if row.get('parent') else {'textures':{},'scalars':{},'vectors':{}}
    for k in ['textures','scalars','vectors']:out[k].update(row[k])
    return out

def asset_material(name):
    while not name.startswith('MaterialInstanceConstant '):
        name=source[name]['parent']
    return name.split('/')[-1].split('.')[0]

materials={};texture_paths={}
material_for_component={}
for comp in runtime['components']:
    slots=[]
    for name in comp['materials']:
        m=flat(name);mid=asset_material(name)
        textures={k:v.split(' ',1)[1] for k,v in m['textures'].items()}
        materials[mid]=dict(asset=name,scalars=m['scalars'],vectors=m['vectors'],
            base=textures.get('Base Texture'),normal=textures.get('Normal Map'),
            surface=textures.get('MetallicRoughnessOcclusionSpecularTexture'),
            emissive=textures.get('Emissive Texture'))
        for role in ['base','normal','surface','emissive']:
            path=materials[mid][role]
            if path:texture_paths[path]=role
        slots.append(mid)
    material_for_component[comp['component']]=slots

components_by_key={(v['model_id'],v['mesh'].split('/')[-1].split('.')[0]):v for v in live['components'] if v.get('model_id')}
for comp in scene['components']:
    native=components_by_key[(comp['model_id'],comp['mesh'])]
    comp['materials']=material_for_component[native['component']]
    comp['material']=comp['materials'][0]
for name,m in scene['meshes'].items():
    lod=next(v for v in geometry[m['asset']]['lods'] if v['level']==0)
    assert len(lod['uv'])==len(m['v'])==len(lod['normals'])
    m['uv']=[[round(float(u),6) for u in p] for p in lod['uv']]
    m['normals']=base64.b64encode(b''.join(struct.pack('<I',n) for n in lod['normals'])).decode()
    m['sections']=lod['sections']

texture_out=OUT/'textures';texture_out.mkdir(exist_ok=True)
for path,item in index.items():
    if 'error' in item:raise RuntimeError(item['error'])
    destination=texture_out/item['file']
    if not destination.exists():
        # Lossless PNG recompression only; preserves every decoded pixel.
        with Image.open(HERE/'game-textures'/item['file']) as im:im.save(destination,optimize=True)

def previews(base_quality=83,base_size=384):
    textures={}
    for path,role in texture_paths.items():
        item=index[path]
        with Image.open(HERE/'game-textures'/item['preview']) as im:
            im.thumbnail((base_size,base_size) if role=='base' else (128,128),Image.Resampling.LANCZOS)
            im=im.convert('RGB');f=io.BytesIO();im.save(f,format='WEBP',quality=base_quality if role=='base' else 87,method=5)
            textures[path]={'src':'data:image/webp;base64,'+base64.b64encode(f.getvalue()).decode(),
                            'width':im.width,'height':im.height,'file':'textures/'+item['file'],'role':role}
    return textures

scene.update(format=3,materials=materials,textures=previews(),material_textures_included=True,
    material_source='live component material inheritance and native client PAK texture resources',
    normal_source='native packed vertex normals and normal-map texture',preview_lighting='neutral preview approximation of game material shading')
template=(HERE/'real-villa-material-viewer-template.html').read_text()
def inline():
    payload={'encoding':'gzip-base64','data':base64.b64encode(gzip.compress(json.dumps(scene,separators=(',',':')).encode(),compresslevel=9)).decode()}
    return template.replace('SCENE_JSON_PLACEHOLDER',json.dumps(payload,separators=(',',':')))
html=inline()
if len(html.encode())>=1000000:
    scene['textures']=previews(78,256);html=inline()
assert len(html.encode())<1000000,len(html.encode())
(OUT/'villa-textured-scene.json').write_text(json.dumps(scene,separators=(',',':'))+'\n')
(VIZ/'palworld-villa-textured.html').write_text(html)

def rotate(v,q):
    x,y,z,w=q;X,Y,Z=v;tx=2*(y*Z-z*Y);ty=2*(z*X-x*Z);tz=2*(x*Y-y*X)
    return [X+w*tx+y*tz-z*ty,Y+w*ty+z*tx-x*tz,Z+w*tz+x*ty-y*tx]

obj=['# Actual game LOD0, native UV0/normals, material sections, actual component transforms','mtllib villa-textured.mtl'];offset=0
for comp in scene['components']:
    m=scene['meshes'][comp['mesh']];obj.append('g '+comp['label']+'_'+comp['mesh'])
    for v in m['v']:
        pos=rotate([v[i]*comp['s'][i] for i in range(3)],comp['q']);pos=[pos[i]+comp['p'][i] for i in range(3)]
        obj.append('v '+' '.join(f'{x:.5f}' for x in pos))
    for u,v in m['uv']:obj.append(f'vt {u:.6f} {1-v:.6f}')
    raw=base64.b64decode(m['normals'])
    for i in range(len(m['v'])):
        n=rotate([(raw[i*4+k]/127.5-1)/comp['s'][k] for k in range(3)],comp['q']);length=math.sqrt(sum(x*x for x in n)) or 1
        obj.append('vn '+' '.join(f'{x/length:.6f}' for x in n))
    for section in m['sections']:
        obj.append('usemtl '+comp['materials'][section['material']])
        for i in range(section['first'],section['first']+section['count'],3):obj.append('f '+' '.join(f'{offset+n+1}/{offset+n+1}/{offset+n+1}' for n in [m['i'][i],m['i'][i+2],m['i'][i+1]]))
    offset+=len(m['v'])
(OUT/'villa-textured.obj').write_text('\n'.join(obj)+'\n')
mtl=[]
for key,m in materials.items():
    mtl.extend(['newmtl '+key,'Kd 1 1 1','Ka 0.2 0.2 0.2','Ks 0.04 0.04 0.04','Ns 16','illum 2'])
    for role,label in [('base','map_Kd'),('normal','norm'),('emissive','map_Ke')]:
        if m[role]:mtl.append(label+' textures/'+index[m[role]]['file'])
    mtl.append('')
(OUT/'villa-textured.mtl').write_text('\n'.join(mtl))
(OUT/'actual-materials.json').write_text(json.dumps(runtime,ensure_ascii=False,indent=2)+'\n')
(OUT/'texture-index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n')
(OUT/'README.txt').write_text(f'真实建筑网格与原始材质\n\n游戏原始LOD0、UV0、顶点法线，以及{len(scene["pieces"])}件建筑的{len(scene["components"])}个实际组件变换。\n材质绑定与参数从当前组件读取；{len(texture_paths)}张原始贴图参与预览，原分辨率PNG保存在textures目录。\n预览贴图仅缩小和压缩，几何使用完整LOD0。\n\nvilla-textured.obj 与 villa-textured.mtl 及 textures/ 应保存在一起，可导入3D软件。\nvilla-textured-scene.json 保留原始资源路径、当前材质参数、UV、法线与游戏实例ID，方便后续调整。\n材质预览使用近似中性光照，没有移植游戏的完整着色器、天气、动态灯光、阴影或地形。\n')
print(json.dumps({'materials':len(materials),'original_textures':len(index),'preview_textures':len(scene['textures']),
    'html_bytes':len(html.encode()),'path':str(VIZ/'palworld-villa-textured.html')}))
