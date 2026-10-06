from probe import WS
from pathlib import Path
import json,time,threading
for _ in range(60):
 try:w=WS();break
 except (OSError,EOFError):time.sleep(.5)
else:raise RuntimeError('background not ready')
stop=threading.Event();pose={'t':'cam','p':[.5,65.62,1.5],'pl':[.5,64,1.5],'r':[0,0,0],'g':True,'fp':True,'fov':70}
report={'steps':[],'fixture':'Existing separate QA world. This run issues no commands, grants no items, and uses survival input only.'}
def pump():
 while not stop.wait(.07):
  try:w.send(pose)
  except Exception:return
threading.Thread(target=pump,daemon=True).start()
def wood(r):return sum(i['count'] for i in r.get('inventory',[]) if i['item']=='minecraft:oak_planks')
def wait(label,ok,seconds=15):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  r=w.inspect()
  if ok(r):report['steps'].append({'step':label,**r});print(label,json.dumps(r),flush=True);return r
  time.sleep(.15)
 raise AssertionError((label,r))
def inspect(label):return wait(label,lambda r:True)
try:
 before=wait('ready',lambda r:r.get('screen')=='none' and r.get('host_active') and r.get('aim',{}).get('z')==4 and r.get('server',{}).get('players'))
 n=wood(before);assert n==1 and before['master_volume']==0 and not before['creative'],before
 pose['g']=False;air=wait('airborne',lambda r:r.get('grounded')==False and r.get('host_grounded')==False)
 pose['g']=True;ground=wait('grounded',lambda r:r.get('grounded') and r.get('host_grounded'))
 assert 4.9<ground['aim']['progress_per_tick']/air['aim']['progress_per_tick']<5.1
 w.send({'t':'key','k':'attack','down':True});start=time.monotonic()
 mined=wait('mined',lambda r:r.get('aim',{}).get('type')=='MISS',7)
 w.send({'t':'key','k':'attack','down':False});report['mining_seconds']=round(time.monotonic()-start,3)
 dropped=wait('drop_created',lambda r:bool(r.get('server',{}).get('dropped_items')))
 item=dropped['server']['dropped_items'][0];origin=pose['pl'][:]
 for i in range(1,21):
  f=i/20;x=origin[0]+(item['x']-origin[0])*f;z=origin[2]+(item['z']-origin[2])*f
  pose.update(pl=[x,64,z],p=[x,65.62,z]);time.sleep(.1)
 picked=wait('picked_up',lambda r:wood(r)==n+1,8)
 assert sum(x['count'] for x in picked['server']['players'][0]['inventory'])==n+1
 pose.update(pl=[.5,64,1.5],p=[.5,65.62,1.5],r=[0,60,0]);time.sleep(.5)
 floor=inspect('aim_floor');assert floor['aim']['block']=='minecraft:stone'
 w.send({'t':'slot','n':0});w.send({'t':'key','k':'use','down':True});time.sleep(.12);w.send({'t':'key','k':'use','down':False})
 placed=wait('placed_one_consumed',lambda r:wood(r)==n and r.get('aim',{}).get('block')=='minecraft:oak_planks')
 report['saved_pose']=pose.copy();report['saved_wood_count']=n;report['placed_block']=placed['aim']
 w.send({'t':'key','k':'attack','down':True});stop.set();time.sleep(2.5)
 idle=inspect('detached_released_and_stationary');assert not idle['attack_down'] and not idle['host_active'] and idle['screen']=='none'
 assert abs(idle['y']-64)<.2 and idle['server']['players'][0]['health']>0
 report['passed']=True
except Exception as e:report['passed']=False;report['error']=repr(e);print('FAILED',repr(e),flush=True)
finally:
 w.send({'t':'key','k':'attack','down':False});w.send({'t':'key','k':'use','down':False});w.send({'t':'shutdown'});stop.set();w.close()
 Path('work/minecraft-fusion/background/final-cycle-result.json').write_text(json.dumps(report,indent=2)+'\n')
