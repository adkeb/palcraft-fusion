"""Add original block-entity models, motion clips and texture frames to v2."""
from __future__ import annotations
import argparse
import hashlib
import io
import json
import math
from pathlib import Path
from PIL import Image
from prepare_models_v2 import Converter, NORMALS, write_json


def matrix3(m):
    return [[m[row + column * 4] for column in range(3)] for row in range(3)]


def inverse(a):
    b=[[a[1][1]*a[2][2]-a[1][2]*a[2][1],a[0][2]*a[2][1]-a[0][1]*a[2][2],a[0][1]*a[1][2]-a[0][2]*a[1][1]],
       [a[1][2]*a[2][0]-a[1][0]*a[2][2],a[0][0]*a[2][2]-a[0][2]*a[2][0],a[0][2]*a[1][0]-a[0][0]*a[1][2]],
       [a[1][0]*a[2][1]-a[1][1]*a[2][0],a[0][1]*a[2][0]-a[0][0]*a[2][1],a[0][0]*a[1][1]-a[0][1]*a[1][0]]]
    det=sum(a[0][i]*b[i][0] for i in range(3))
    return [[v/det for v in row] for row in b]


def multiply(a,b):
    return [[sum(a[r][k]*b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]


def clip_for(rows,family,variant):
    poses={}
    for row in rows:
        if row['type']=='part' and row['family']==family and row['variant']==variant:
            poses.setdefault(row['part'],[]).append(row)
    result={'schema':1,'family':family,'variant':variant,'space':'minecraft_block_local',
            'input':'open_progress','input_curve':'one_minus_cube' if family=='chest' else 'linear',
            'parts':{},'keyframes':[]}
    frames={}
    for part,samples in poses.items():
        samples.sort(key=lambda value:value['input'])
        base=samples[0]['matrix'];sample=samples[1];current=sample['matrix']
        rotation=multiply(matrix3(current),inverse(matrix3(base)))
        skew=[rotation[2][1]-rotation[1][2],rotation[0][2]-rotation[2][0],rotation[1][0]-rotation[0][1]]
        length=math.sqrt(sum(v*v for v in skew))
        angle=math.atan2(length/2,(sum(rotation[i][i]for i in range(3))-1)/2)
        progress=sample['input'];curved=1-(1-progress)**3 if family=='chest'else progress
        axis=[v/length for v in skew]if length>1e-7 else[1,0,0]
        rate=angle/curved if length>1e-7 else 0
        delta=[(current[12+i]-base[12+i])/progress for i in range(3)]
        result['parts'][part]={'pivot':base[12:15],'rotation_axis':axis,'radians_per_input':rate,
                               'translation_per_input':delta,'moving':rate>1e-7 or any(abs(v)>1e-7 for v in delta)}
        for row in samples:
            frames.setdefault(row['input'],{})[part]=row['matrix']
    result['keyframes']=[{'input':value,'part_matrices':poses}for value,poses in sorted(frames.items())]
    return result


class ConverterV3(Converter):
    def __init__(self,*args,entity_models=None,**kwargs):
        super().__init__(*args,**kwargs)
        self.entity_models=Path(entity_models)if entity_models else None
        self.frames_done=set()

    def export_texture(self,name):
        info=super().export_texture(name)
        animation=info.get('animation')
        if animation and name not in self.frames_done:
            self.frames_done.add(name)
            namespace,path=name.split(':',1)
            png=self.read(f'assets/{namespace}/textures/{path}.png')
            source=Image.open(io.BytesIO(png)).convert('RGBA')
            relative=f'textures/{namespace}/{path}.frames/'
            target=self.out/relative;target.mkdir(parents=True,exist_ok=True)
            w,h,columns=animation['width'],animation['height'],animation['columns']
            scale=info['nearest_scale']
            for index in sorted({v['index']for v in animation['frames']}):
                x,y=index%columns*w,index//columns*h
                frame=source.crop((x,y,x+w,y+h)).resize((w*scale,h*scale),Image.Resampling.NEAREST)
                frame.save(target/f'{index:04d}.png')
                self.counts['animation_frame_files']+=1
            animation['frames_dir']=relative
            animation['ticks_per_second']=20
            write_json(self.out/'textures'/namespace/(path+'.json'),info)
        return info

    def faces(self,rows,texture):
        info=self.export_texture(texture)
        result=[]
        for row in rows:
            n=row['normal'];direction=max(NORMALS,key=lambda name:sum(a*b for a,b in zip(NORMALS[name],n)))
            result.append({'texture':texture,'vertices':[v[:3]for v in row['vertices']],
                           'normal':n,'uv':[v[3:]for v in row['vertices']],'direction':direction,
                           'tint':-1,'translucent':False,'alpha_mode':info['alpha_mode'],
                           'part':row['part'],'shade':True,'light_emission':0})
        return result

    def extras(self):
        if not self.entity_models:
            return
        meta=json.loads(self.entity_models.with_suffix('.meta.json').read_text())
        if meta['minecraft_client_sha256']!=hashlib.sha256(self.jar.read_bytes()).hexdigest():
            raise ValueError('Entity model extraction is from a different client jar')
        rows=[json.loads(line)for line in self.entity_models.read_text().splitlines()if line.startswith('{')]
        colors=['','black','blue','brown','cyan','gray','green','light_blue','light_gray','lime',
                'magenta','orange','pink','purple','red','white','yellow']
        for color in colors:
            block=(color+'_'if color else'')+'shulker_box'
            texture='minecraft:entity/shulker/shulker'+('_'+color if color else'')
            variants={}
            for facing in NORMALS:
                shape=[r for r in rows if r['type']=='face'and r['family']=='shulker'and r['variant']==facing and r['input']==0]
                model='minecraft:palcraft/block_entity/shulker/'+block+'/'+facing
                clip='minecraft:block_entity/shulker/'+facing
                write_json(self.out/'models/minecraft/palcraft/block_entity/shulker'/block/(facing+'.json'),
                           {'schema':3,'faces':self.faces(shape,texture),'block_entity':'shulker','animation_clip':clip})
                write_json(self.out/'animations/minecraft/block_entity/shulker'/(facing+'.json'),clip_for(rows,'shulker',facing))
                variants['facing='+facing]={'model':model}
                self.counts['block_entity_models']+=1
            write_json(self.out/'states/minecraft'/(block+'.json'),{'variants':variants})
            name='minecraft:block/'+block
            if name in self.special:self.special.remove(name)

        pot_variants={}
        for facing in ['north','south','east','west']:
            base=[r for r in rows if r['type']=='face'and r['family']=='pot_base'and r['variant']==facing]
            sides=[r for r in rows if r['type']=='face'and r['family']=='pot_sides'and r['variant']==facing]
            faces=self.faces(base,'minecraft:entity/decorated_pot/decorated_pot_base')+self.faces(sides,'minecraft:entity/decorated_pot/decorated_pot_side')
            for face in faces:
                if face['part']in['/front','/back','/left','/right']:face['decoration_slot']=face['part'][1:]
            model='minecraft:palcraft/block_entity/decorated_pot/'+facing
            write_json(self.out/'models/minecraft/palcraft/block_entity/decorated_pot'/(facing+'.json'),
                       {'schema':3,'faces':faces,'block_entity':'decorated_pot'})
            pot_variants['facing='+facing]={'model':model};self.counts['block_entity_models']+=1
        write_json(self.out/'states/minecraft/decorated_pot.json',{'variants':pot_variants})
        if'minecraft:block/decorated_pot'in self.special:self.special.remove('minecraft:block/decorated_pot')
        for path in sorted(self.paths):
            if path.startswith('assets/minecraft/textures/entity/decorated_pot/')and path.endswith('_pottery_pattern.png'):
                self.export_texture('minecraft:'+path.removeprefix('assets/minecraft/textures/').removesuffix('.png'))

        for variant in['single','left','right']:
            clip=clip_for(rows,'chest',variant)
            write_json(self.out/'animations/minecraft/block_entity/chest'/(variant+'.json'),clip)
            for model in(self.out/'models/minecraft/palcraft/block_entity/chest').glob('*/'+variant+'.json'):
                data=json.loads(model.read_text());data['animation_clip']='minecraft:block_entity/chest/'+variant;write_json(model,data)
        text=[r for r in rows if r['type']=='text']
        write_json(self.out/'text_layouts/minecraft/signs.json',{'schema':1,'space':'minecraft_block_local',
                   'input_units':'minecraft_font_pixels','layouts':text,'glyph_rendering_implemented':False})
        self.counts['sign_text_layouts']=len(text)
        self.counts['animation_clips']=9
        self.counts['block_entity_blocks']+=18

    def prepare(self):
        manifest=super().prepare()
        self.extras()
        manifest.update(self.counts)
        manifest.update({'schema':3,'special_models':sorted(self.special),'motion_data_available':True,
                         'animations_playing_in_game':False,'sign_text_rendering_implemented':False})
        write_json(self.out/'manifest.json',manifest)
        return manifest


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('jar');p.add_argument('destination');p.add_argument('--resource-pack',action='append',default=[])
    p.add_argument('--texture-min-size',type=int,default=256)
    p.add_argument('--block-entity-models');p.add_argument('--entity-models')
    a=p.parse_args()
    c=ConverterV3(a.jar,a.destination,a.resource_pack,a.texture_min_size,a.block_entity_models,entity_models=a.entity_models)
    result=c.prepare()
    print(json.dumps({k:v for k,v in result.items()if k not in['special_models','empty_models']}))
