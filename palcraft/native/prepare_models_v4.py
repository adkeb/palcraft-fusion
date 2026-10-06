"""Extend V3 with original banner, skull and inactive conduit geometry."""
import argparse
import hashlib
import io
import json
from pathlib import Path
from PIL import Image
from prepare_models_v2 import write_json
from prepare_models_v3 import ConverterV3


class ConverterV4(ConverterV3):
    def __init__(self,*args,decor_models=None,**kwargs):
        super().__init__(*args,**kwargs)
        self.decor_models=Path(decor_models)if decor_models else None
        self.generated={}

    def export_texture(self,name):
        return self.generated[name]if name in self.generated else super().export_texture(name)

    def banner_texture(self,color,rgba):
        name='minecraft:palcraft/entity/banner/'+color
        if name in self.generated:return name
        path='assets/minecraft/textures/entity/banner/base.png'
        png=self.read(path);source=Image.open(io.BytesIO(png)).convert('RGBA')
        values=bytearray(source.tobytes());rgb=[(rgba>>16)&255,(rgba>>8)&255,rgba&255]
        for i in range(0,len(values),4):
            for channel in range(3):values[i+channel]=round(values[i+channel]*rgb[channel]/255)
        frame=Image.frombytes('RGBA',source.size,bytes(values))
        scale=max(1,(self.texture_min_size+min(frame.size)-1)//min(frame.size))
        enlarged=frame.resize((frame.width*scale,frame.height*scale),Image.Resampling.NEAREST)
        target=self.out/'textures/minecraft/palcraft/entity/banner'/(color+'.png');target.parent.mkdir(parents=True,exist_ok=True);enlarged.save(target)
        info={'source_sprite':'minecraft:entity/banner/base','source_sha256':hashlib.sha256(png).hexdigest(),
              'source_size':list(source.size),'frame_size':list(frame.size),'import_size':list(enlarged.size),
              'nearest_scale':scale,'alpha_mode':'cutout','vanilla_dye_rgba':rgba&0xffffffff,
              'baked_diffuse_tint':True,'in_game_final_lighting_verified':False}
        write_json(target.with_suffix('.json'),info);self.generated[name]=info
        self.counts['textures']+=1;self.counts['texture_cutout']+=1
        return name

    def decor(self):
        if not self.decor_models:return
        meta=json.loads(self.decor_models.with_suffix('.meta.json').read_text())
        if meta['minecraft_client_sha256']!=hashlib.sha256(self.jar.read_bytes()).hexdigest():raise ValueError('Decor extraction client mismatch')
        rows=[json.loads(l)for l in self.decor_models.read_text().splitlines()if l.startswith('{')]
        faces={}
        for row in rows:
            if row['type']=='face':faces.setdefault((row['family'],row['variant']),[]).append(row)
        def save(block,variant,geometry,kind,extra=None):
            model='minecraft:palcraft/block_entity/'+kind+'/'+block+'/'+variant
            data={'schema':4,'faces':geometry,'block_entity':kind,**(extra or{})}
            write_json(self.out/'models/minecraft/palcraft/block_entity'/kind/block/(variant+'.json'),data)
            self.counts['block_entity_models']+=1
            return{'model':model}
        for dye in[r for r in rows if r['type']=='dye']:
            color=dye['name'];cloth=self.banner_texture(color,dye['rgb'])
            for wall in[False,True]:
                block=color+('_wall_banner'if wall else'_banner');variants={}
                labels=['wall_'+f for f in['north','south','east','west']]if wall else['free_'+str(i)for i in range(16)]
                for variant in labels:
                    geometry=self.faces(faces['banner_body',variant],'minecraft:entity/banner/banner_base')+self.faces(faces['banner_flag',variant],cloth)
                    key='facing='+variant[5:]if wall else'rotation='+variant[5:]
                    variants[key]=save(block,variant,geometry,'banner',{'vanilla_dye_rgba':dye['rgb']&0xffffffff,
                         'pattern_layers_implemented':False,'wave_animation_implemented':False})
                write_json(self.out/'states/minecraft'/(block+'.json'),{'variants':variants})
        if'minecraft:block/banner'in self.special:self.special.remove('minecraft:block/banner')
        player=[r['id']for r in rows if r['type']=='texture'and r['name']=='player'][0]
        player=player.replace('minecraft:textures/','minecraft:').removesuffix('.png')
        textures={'skeleton':'minecraft:entity/skeleton/skeleton','wither_skeleton':'minecraft:entity/skeleton/wither_skeleton',
                  'zombie':'minecraft:entity/zombie/zombie','creeper':'minecraft:entity/creeper/creeper',
                  'dragon':'minecraft:entity/enderdragon/dragon','piglin':'minecraft:entity/piglin/piglin','player':player}
        for type_,texture in textures.items():
            base=type_+('_skull'if type_ in['skeleton','wither_skeleton']else'_head')
            for wall in[False,True]:
                block=base.replace('_skull','_wall_skull').replace('_head','_wall_head')if wall else base
                variants={};labels=['wall_'+f for f in['north','south','east','west']]if wall else['free_'+str(i)for i in range(16)]
                for variant in labels:
                    geometry=self.faces(faces['skull_'+type_,variant],texture)
                    for face in geometry:
                        face['alpha_mode']='cutout'
                        face['render_type']='minecraft_entity_cutout_zoffset'
                    key='facing='+variant[5:]if wall else'rotation='+variant[5:]
                    variants[key]=save(block,variant,geometry,'skull',{'type':type_,'player_skin_is_default':type_=='player',
                        'powered_animation_implemented':False})
                write_json(self.out/'states/minecraft'/(block+'.json'),{'variants':variants})
        if'minecraft:block/skull'in self.special:self.special.remove('minecraft:block/skull')
        geometry=self.faces(faces['conduit','inactive'],'minecraft:entity/conduit/base')
        for face in geometry:face['alpha_mode']='opaque'
        spec=save('conduit','inactive',geometry,'conduit',{'inactive_static_only':True,'active_effects_implemented':False})
        write_json(self.out/'states/minecraft/conduit.json',{'variants':{'':spec}})
        if'minecraft:block/conduit'in self.special:self.special.remove('minecraft:block/conduit')
        # Fluid surfaces use these original sprites rather than a cuboid model.
        for sprite in['water_flow','water_overlay','lava_flow']:
            self.export_texture('minecraft:block/'+sprite)
        self.counts['block_entity_blocks']+=47

    def prepare(self):
        manifest=super().prepare();self.decor();manifest.update(self.counts)
        manifest.update({'schema':4,'special_models':sorted(self.special),'decorations_static_data_available':True,
                         'decorations_in_game_graphics_verified':False})
        write_json(self.out/'manifest.json',manifest);return manifest


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('jar');p.add_argument('destination')
    p.add_argument('--resource-pack',action='append',default=[]);p.add_argument('--texture-min-size',type=int,default=256)
    p.add_argument('--block-entity-models');p.add_argument('--entity-models');p.add_argument('--decor-models')
    a=p.parse_args();c=ConverterV4(a.jar,a.destination,a.resource_pack,a.texture_min_size,a.block_entity_models,
                                entity_models=a.entity_models,decor_models=a.decor_models)
    d=c.prepare();print(json.dumps({k:v for k,v in d.items()if k not in['special_models','empty_models']}))
