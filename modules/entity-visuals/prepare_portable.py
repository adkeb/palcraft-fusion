"""Private original item models/skins and Arrow/Trident rigs; no free items."""
import argparse,hashlib,io,json,math,sys,zipfile
from pathlib import Path
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'palcraft/native'))
from prepare_models_v2 import vertices,default_uvs,element_transform,face_normal,NORMALS

ITEMS='oak_log oak_planks cobblestone stone dirt crafting_table furnace coal charcoal stick wooden_pickaxe stone_pickaxe iron_pickaxe diamond_pickaxe iron_sword arrow spectral_arrow trident iron_ingot gold_ingot diamond emerald redstone bread apple beef cooked_beef porkchop cooked_porkchop feather string bone gunpowder wheat egg ender_pearl'.split()
p=argparse.ArgumentParser(description=__doc__);p.add_argument('jar');p.add_argument('oracle');p.add_argument('destination')
a=p.parse_args();jar=Path(a.jar);oracle=Path(a.oracle);root=Path(a.destination);z=zipfile.ZipFile(jar)
meta=json.loads(oracle.with_suffix('.meta.json').read_text());assert meta['minecraft_client_sha256']==hashlib.sha256(jar.read_bytes()).hexdigest()
def resource(s):return s if':'in s else'minecraft:'+s
def write(path,value):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,separators=(',',':')))
def read(kind,name):ns,path=resource(name).split(':',1);return json.loads(z.read(f'assets/{ns}/{kind}/{path}.json'))
models={};skins={};issues=[]
def model(name):
    name=resource(name)
    if name in models:return models[name]
    data=read('models',name);parent=data.get('parent','')
    base={'builtin':parent}if parent.startswith('builtin/')else model(parent)if parent else{}
    result={**base,**data,'textures':{**base.get('textures',{}),**data.get('textures',{})},'display':{**base.get('display',{}),**data.get('display',{})}}
    models[name]=result;return result
def sprite(value,data):
    seen=set()
    if value in data.get('textures',{}):value='#'+value
    while isinstance(value,str)and value.startswith('#'):
        if value in seen:raise ValueError('texture cycle')
        seen.add(value);value=data['textures'][value[1:]]
    return resource(value['sprite']if isinstance(value,dict)else value)
def texture(name):
    name=resource(name)
    if name in skins:return skins[name]
    ns,path=name.split(':',1);png=z.read(f'assets/{ns}/textures/{path}.png');image=Image.open(io.BytesIO(png)).convert('RGBA')
    scale=max(1,256//min(image.size));target=root/'textures'/ns/(path+'.png');target.parent.mkdir(parents=True,exist_ok=True)
    image.resize((image.width*scale,image.height*scale),Image.Resampling.NEAREST).save(target)
    skins[name]={'path':target.relative_to(root).as_posix(),'source_sha256':hashlib.sha256(png).hexdigest(),'size':list(image.size)}
    return skins[name]
def edges(image):
    w,h=image.size;mask=image.getchannel('A');result=[]
    for y in range(h):
        for x in range(w):
            if mask.getpixel((x,y))==0:continue
            for name,dx,dy in [('UP',0,-1),('DOWN',0,1),('LEFT',-1,0),('RIGHT',1,0)]:
                nx,ny=x+dx,y+dy
                if not(0<=nx<w and 0<=ny<h)or mask.getpixel((nx,ny))==0:result.append({'direction':name,'x':x,'y':y})
    return result
def generated(data):
    faces=[];pixel_edges={}
    for key in sorted(k for k in data['textures']if k.startswith('layer')):
        tex=sprite('#'+key,data);ns,path=tex.split(':',1);image=Image.open(io.BytesIO(z.read(f'assets/{ns}/textures/{path}.png'))).convert('RGBA');w,h=image.size
        texture(tex);E=edges(image);pixel_edges[tex]=E
        for direction,points,uv in[
          ('south',[[0,1,.53125],[0,0,.53125],[1,0,.53125],[1,1,.53125]],[[0,0],[0,1],[1,1],[1,0]]),
          ('north',[[1,1,.46875],[1,0,.46875],[0,0,.46875],[0,1,.46875]],[[1,0],[1,1],[0,1],[0,0]])]:
            faces.append({'texture':tex,'vertices':points,'normal':NORMALS[direction],'uv':uv})
        for edge in E:
            x,y=edge['x'],edge['y'];X=x/w;xx=(x+1)/w;Y=1-(y+1)/h;yy=1-y/h;name=edge['direction']
            if name=='UP':a,b,direction=[X,yy,.46875],[xx,yy,.53125],'up'
            elif name=='DOWN':a,b,direction=[X,Y,.46875],[xx,Y,.53125],'down'
            elif name=='LEFT':a,b,direction=[X,yy,.46875],[X,Y,.53125],'east'
            else:a,b,direction=[xx,yy,.46875],[xx,Y,.53125],'west'
            # Actual bakeSideFaces uses inverted Y bounds for X sides and
            # shrinks each source-pixel UV rectangle by 0.1 texel on every edge.
            points=vertices(a,b)[direction];normal=face_normal(points,NORMALS[direction])
            u,U=(x+.1)/w,(x+.9)/w
            v,V=((y+.1)/h,(y+.9)/h)if name in['UP','DOWN']else((y+.9)/h,(y+.1)/h)
            faces.append({'texture':tex,'vertices':points,'normal':normal,'uv':[[u,v],[u,V],[U,V],[U,v]],'source_pixel':edge})
    return faces,pixel_edges
def cuboid(data):
    result=[]
    for e in data.get('elements',[]):
        P=vertices(e['from'],e['to']);D=default_uvs(e['from'],e['to'])
        for direction,face in e['faces'].items():
            tex=sprite(face['texture'],data);texture(tex);points=[element_transform(v,e.get('rotation'))for v in P[direction]]
            u,v,U,V=face.get('uv',D[direction]);uv=[[u/16,v/16],[u/16,V/16],[U/16,V/16],[U/16,v/16]];shift=face.get('rotation',0)//90%4;uv=uv[shift:]+uv[:shift]
            result.append({'texture':tex,'vertices':[[v/16 for v in p]for p in points],'normal':face_normal(points,NORMALS[direction]),'uv':uv})
    return result
def ground_model(spec):
    type_=spec['type'].removeprefix('minecraft:')
    if type_=='model':return spec['model']
    if type_=='select'and spec.get('property')=='minecraft:display_context':
        for case in spec.get('cases',[]):
            when=case['when'];when=[when]if isinstance(when,str)else when
            if'ground'in when:return ground_model(case['model'])
        return ground_model(spec['fallback'])
    raise ValueError('dynamic/special item model requires actual component resolver')
edge_output={};supported=[]
for item in ITEMS:
    try:
        selected=ground_model(read('items','minecraft:'+item)['model']);data=model(selected)
        if data.get('builtin')=='builtin/generated':faces,E=generated(data);edge_output.update(E);shape='generated_sprite'
        else:faces=cuboid(data);shape='cuboid'
        if not faces:raise ValueError('no model faces')
        result={'schema':1,'item':'minecraft:'+item,'model':selected,'faces':faces,'ground':data.get('display',{}).get('ground',{'rotation':[0,0,0],'translation':[0,0,0],'scale':[1,1,1]}),
          'shape':shape,'alpha_mode':'cutout','space':'mc_model_blocks_0_to_1','source':'actual client item definition/parent model/sprite mask'}
        write(root/'items/minecraft'/(item+'.json'),result);supported.append('minecraft:'+item)
    except(KeyError,ValueError)as exc:issues.append({'item':'minecraft:'+item,'reason':str(exc)})
rows=[json.loads(l)for l in oracle.read_text().splitlines()if l.startswith('{')]
texture('minecraft:entity/projectiles/arrow_spectral')
for row in rows:
    if row['type']=='rig':
        info=texture(row['texture']);row.update({'schema':1,'texture_path':info['path'],'space':'minecraft_projectile_model_blocks'})
        write(root/'projectiles/minecraft'/(row['kind']+'.json'),row)
write(root/'projectile-pose-samples.json',[r for r in rows if r['type']=='projectile_pose'])
write(root/'item-edge-reference.json',[r for r in rows if r['type']=='item_edges'])
write(root/'item-edges-produced.json',edge_output);write(root/'textures.json',skins)
write(root/'manifest.json',{'schema':1,'source':meta,'supported_items':supported,'unsupported':issues,'projectiles':['minecraft:arrow','minecraft:spectral_arrow','minecraft:trident'],
 'item_components_dynamic_pending':True,'legacy_drop_time_fields_pending':True,'runtime_graphics_verified':False,'not_publicly_redistributable_assets':True})
print(json.dumps({'items':len(supported),'issues':issues,'projectile_rigs':2}))
