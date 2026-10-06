"""Install the actual hook into an integration-owned *next* staging MC tree.

No game launch/build/restart is performed here. Existing frozen candidates stay
untouched; integration runs its one required combined compile after this patch.
"""
import argparse,json,shutil
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('mc_staging_root');a=p.parse_args()
root=Path(a.mc_staging_root).resolve();base=Path(__file__).resolve().parent
def edit(path,old,new):
    text=path.read_text()
    if new in text:return
    if text.count(old)!=1:raise ValueError('Hook anchor changed: '+str(path))
    path.write_text(text.replace(old,new,1))
client=root/'src/client/java/dev/rehan/passthrough/client'
client.mkdir(parents=True,exist_ok=True)
for source,target in[
    ('java/EntityCaptureExporter.java',client/'EntityCaptureExporter.java'),
    ('java/VanillaEntityCapture.java',client/'visual/VanillaEntityCapture.java'),
    ('java/EntityCaptureRenderMixin.java',client/'mixin/EntityCaptureRenderMixin.java'),
    ('java/EntityCaptureResourceMixin.java',client/'mixin/EntityCaptureResourceMixin.java')]:
    target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(base/source,target)
edit(client/'PassthroughClient.java','ClientBridge.initialize();','ClientBridge.initialize();\n        EntityCaptureExporter.initialize();')
edit(client/'HostLink.java','SignTextExporter.setTransport(null);','SignTextExporter.setTransport(null);\n        EntityCaptureExporter.unbind();')
needle='case "sign_text_view" -> execute(conn, lease, () -> {'
case='case "entity_visual_view" -> execute(conn, lease, () -> EntityCaptureExporter.bind(m, row -> respond(conn, lease, row)));\n                '+needle
edit(client/'HostLink.java',needle,case)
policy=root/'src/main/java/dev/rehan/passthrough/session/SessionPolicy.java'
edit(policy,'"sign_text_view"','"sign_text_view", "entity_visual_view"')
mixins=root/'src/client/resources/passthrough.client.mixins.json';data=json.loads(mixins.read_text())
if'EntityCaptureRenderMixin'not in data['client']:data['client'].append('EntityCaptureRenderMixin')
if'EntityCaptureResourceMixin'not in data['client']:data['client'].append('EntityCaptureResourceMixin')
mixins.write_text(json.dumps(data,indent=2)+'\n')
print(json.dumps({'actual_render_tail_hook':True,'authenticated_HostLink_world_read_bound':True,'staging_root':str(root),'build_performed':False,'runtime_changed':False}))
