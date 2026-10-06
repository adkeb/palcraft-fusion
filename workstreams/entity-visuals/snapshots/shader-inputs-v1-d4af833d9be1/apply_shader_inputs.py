"""Apply the original shader-input source increment to an independent next MC
tree. Current/frozen 10.1 is never selected or changed by this script."""
import argparse, hashlib, json, shutil
from pathlib import Path

arg=argparse.ArgumentParser(description=__doc__);arg.add_argument('mc_staging_root');args=arg.parse_args()
base=Path(__file__).resolve().parent;root=Path(args.mc_staging_root).resolve()
client=root/'src/client/java/dev/rehan/passthrough/client'
baseline={
 'visual/VanillaEntityCapture.java':'6cd6d4cefd4ba043db28446c05febe25d383f862527c3eac08345ac30f945fe2',
 'EntityCaptureExporter.java':'b3d7a5e784ee12aa0eaf0897f81762f925568a710f12b468ec3560679e3d617c',
 'signtext/SignTextExporter.java':'7f54b90d9b15e5f18792eebf432ce8e42541e133bd280308c54417f1e64047d4'}
sources={
 'VanillaEntityCapture.java':'visual/VanillaEntityCapture.java',
 'EntityCaptureExporter.java':'EntityCaptureExporter.java',
 'EntityShaderInputCapture.java':'EntityShaderInputCapture.java',
 'SignTextExporter.java':'signtext/SignTextExporter.java',
 'EntityOverlayTextureAccessor.java':'mixin/EntityOverlayTextureAccessor.java',
 'EntityLightingInputMixin.java':'mixin/EntityLightingInputMixin.java',
 'EntityDynamicInputMixin.java':'mixin/EntityDynamicInputMixin.java',
 'EntityRenderTypeInputMixin.java':'mixin/EntityRenderTypeInputMixin.java',
 'CaptureBlendMetadata.java':'visual/CaptureBlendMetadata.java'}
for name,target in sources.items():
 source=base/'java'/name;assert source.is_file(),source
 destination=client/target
 if target in baseline:
  actual=hashlib.sha256(destination.read_bytes()).hexdigest()
  ours=hashlib.sha256(source.read_bytes()).hexdigest()
  allowed={baseline[target],ours}
  if target.startswith('visual/'):
   # Material owner's single independent metadata hunk can precede this.
   original=destination.read_text()
   call='        batch.put("capture_blend",CaptureBlendMetadata.read(type.pipeline()));\n'
   if original.count(call)==1 and hashlib.sha256(original.replace(call,'',1).encode()).hexdigest()==baseline[target]:allowed.add(actual)
  assert actual in allowed,'Changed shader-input baseline: '+str(destination)
for name,target in sources.items():
 destination=client/target;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(base/'java'/name,destination)
mixins=root/'src/client/resources/passthrough.client.mixins.json';config=json.loads(mixins.read_text())
for name in ['EntityOverlayTextureAccessor','EntityLightingInputMixin','EntityDynamicInputMixin','EntityRenderTypeInputMixin']:
 if name not in config['client']:config['client'].append(name)
mixins.write_text(json.dumps(config,indent=2)+'\n')
print(json.dumps({'source_staging_root':str(root),'original_UV1_UV2':True,'original_shader_inputs_registered':True,'new_service':False,'new_reader':False,'build_performed':False,'runtime_changed':False}))
