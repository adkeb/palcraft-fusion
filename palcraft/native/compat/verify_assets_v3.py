"""Check only the new v3 asset/frame/reference contracts, without a game launch."""
import io
import json
import zipfile
from pathlib import Path
from PIL import Image

root=Path('work/minecraft-fusion/model-compat/v3/assets')
jar=zipfile.ZipFile('work/minecraft-fusion/palcraft/mc/minecraft-client-26.3.jar')
references=0
for path in(root/'states').rglob('*.json'):
    state=json.loads(path.read_text())
    specs=list(state.get('variants',{}).values())+[p['apply']for p in state.get('multipart',[])]
    for spec in specs:
        for entry in spec if isinstance(spec,list)else[spec]:
            name=entry['model']if':'in entry['model']else'minecraft:'+entry['model']
            namespace,path=name.split(':',1)
            assert(root/'models'/namespace/(path+'.json')).is_file(),name
            references+=1
frames=0
for path in(root/'textures').rglob('*.json'):
    meta=json.loads(path.read_text());animation=meta.get('animation')
    if not animation:
        continue
    relative=path.relative_to(root/'textures').with_suffix('.png').as_posix()
    namespace,texture=relative.split('/',1)
    source=Image.open(io.BytesIO(jar.read('assets/'+namespace+'/textures/'+texture))).convert('RGBA')
    w,h,columns=animation['width'],animation['height'],animation['columns']
    for index in{v['index']for v in animation['frames']}:
        x,y=index%columns*w,index//columns*h
        actual=Image.open(root/animation['frames_dir']/f'{index:04d}.png').convert('RGBA')
        expected=source.crop((x,y,x+w,y+h)).resize(meta['import_size'],Image.Resampling.NEAREST)
        assert actual.tobytes()==expected.tobytes(),str(path)
        frames+=1
manifest=json.loads((root/'manifest.json').read_text())
assert not manifest['issues']
result={'status':'passed','blockstate_model_references':references,'exact_animation_frame_files':frames,
        'remaining_special_models':manifest['special_models'],'not_a_runtime_graphics_claim':True}
(root.parent/'asset-verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
