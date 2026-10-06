from probe import WS
from pathlib import Path
import json,time,threading
for _ in range(45):
 try:w=WS();break
 except (OSError,EOFError):time.sleep(.5)
else:raise RuntimeError('background not ready')
stop=threading.Event();pose={'t':'cam','p':[.5,65.62,5.5],'pl':[.5,64,5.5],'r':[180,0,0],'g':True,'fp':True,'fov':70}
report={'steps':[]}
def pump():
 while not stop.wait(.07):
  try:w.send(pose)
  except Exception:return
threading.Thread(target=pump,daemon=True).start()
def inspect(label):
 r=w.inspect();report['steps'].append({'step':label,**r});print(label,json.dumps(r),flush=True);return r
def count(r):return sum(i['count'] for i in r.get('inventory',[]) if i['item']=='minecraft:oak_planks')
try:
 for _ in range(100):
  r=w.inspect()
  if r.get('screen')=='none' and r.get('server',{}).get('players'):break
  time.sleep(.2)
 time.sleep(.3);first=inspect('reloaded_world')
 assert first.get('aim',{}).get('block')=='minecraft:oak_planks' and first['aim']['z']==4,first
 items=first.get('server',{}).get('dropped_items',[])
 if items:
  item=items[0];start=pose['pl'][:]
  for i in range(1,21):
   f=i/20;x=start[0]+(item['x']-start[0])*f;z=start[2]+(item['z']-start[2])*f
   pose['pl']=[x,64,z];pose['p']=[x,65.62,z];time.sleep(.1)
 time.sleep(1);picked=inspect('walk_over_drop');assert count(picked)==1,picked
 # Restart has preserved both the survival-placed block and the actual dropped item.
 report['passed']=True
except Exception as e:report['passed']=False;report['error']=repr(e);print('FAILED',repr(e),flush=True)
finally:
 w.send({'t':'shutdown'});stop.set();w.close();Path('work/minecraft-fusion/background/persistence-result.json').write_text(json.dumps(report,indent=2)+'\n')
