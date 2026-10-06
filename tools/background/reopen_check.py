from probe import WS
from pathlib import Path
import json,time,threading
saved=json.loads(Path('work/minecraft-fusion/background/final-cycle-result.json').read_text());assert saved['passed']
for _ in range(60):
 try:w=WS();break
 except (OSError,EOFError):time.sleep(.5)
else:raise RuntimeError('background not ready')
stop=threading.Event();pose=saved['saved_pose']
def pump():
 while not stop.wait(.08):
  try:w.send(pose)
  except Exception:return
threading.Thread(target=pump,daemon=True).start()
report={}
try:
 for _ in range(150):
  r=w.inspect()
  if r.get('screen')=='none' and r.get('host_active') and r.get('server',{}).get('players'):break
  time.sleep(.15)
 time.sleep(.3);r=w.inspect();report['reopened']=r
 assert r['uuid']=='00000000-0000-4000-8000-000000000029' and r['master_volume']==0
 assert sum(i['count'] for i in r['inventory'] if i['item']=='minecraft:oak_planks')==saved['saved_wood_count']
 assert all(r['aim'][k]==saved['placed_block'][k] for k in ['x','y','z','block'])
 assert r['server']['players'][0]['inventory']==r['inventory']
 report['passed']=True
except Exception as e:report['passed']=False;report['error']=repr(e)
finally:
 w.send({'t':'shutdown'});stop.set();w.close();Path('work/minecraft-fusion/background/reopen-result.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
