from probe import WS
from pathlib import Path
import json,time,threading
w=WS();stop=threading.Event();pose={'t':'cam','p':[.5,65.62,2.5],'pl':[.5,64,2.5],'r':[0,0,0],'g':True,'fp':True,'fov':70}
report={'steps':[],'fixture':'Continues prior test. Inventory wood was dropped by survival mining, no items granted.'}
def pump():
 while not stop.wait(.07):
  try:w.send(pose)
  except Exception:return
threading.Thread(target=pump,daemon=True).start()
def inspect(label):
 r=w.inspect();report['steps'].append({'step':label,**r});print(label,json.dumps(r),flush=True);return r
def wait(label,predicate,seconds=6):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  r=w.inspect()
  if predicate(r):report['steps'].append({'step':label,**r});print(label,json.dumps(r),flush=True);return r
  time.sleep(.15)
 raise AssertionError((label,r))
def wood(r):return sum(i['count'] for i in r.get('inventory',[]) if i['item']=='minecraft:oak_planks')
try:
 before=wait('ready_with_mined_item',lambda r:r.get('screen')=='none' and wood(r)==1 and r.get('grounded'))
 assert before['master_volume']==0
 w.send({'t':'slot','n':0});time.sleep(.2)
 w.send({'t':'key','k':'use','down':True});time.sleep(.15);w.send({'t':'key','k':'use','down':False})
 placed=wait('survival_placed_and_consumed',lambda r:wood(r)==0 and r.get('aim',{}).get('z')==4 and r['aim'].get('type')=='BLOCK')
 # Mine the other original fixture block, leaving the newly placed block to test world persistence.
 pose.update(pl=[.5,64,7.5],p=[.5,65.62,7.5],r=[180,0,0]);time.sleep(.6)
 target=inspect('second_target');assert target['aim']['z']==5
 w.send({'t':'key','k':'attack','down':True});time.sleep(3.5);w.send({'t':'key','k':'attack','down':False})
 mined=wait('survival_mined_second',lambda r:r.get('aim',{}).get('z')!=5)
 pose.update(pl=[.5,64,5.5],p=[.5,65.62,5.5]);
 picked=wait('survival_pickup',lambda r:wood(r)==1,10)
 assert picked['server']['players'][0]['inventory'][0]['count']==1
 # Stop camera input with attack pressed: it must auto-release after the host timeout.
 w.send({'t':'key','k':'attack','down':True});stop.set();time.sleep(2.5)
 detached=inspect('host_detached_releases_input');assert not detached['attack_down']
 report['passed']=True
except Exception as e:report['passed']=False;report['error']=repr(e);print('FAILED',repr(e),flush=True)
finally:
 w.send({'t':'key','k':'attack','down':False});w.send({'t':'key','k':'use','down':False});w.send({'t':'shutdown'});stop.set();w.close()
 Path('work/minecraft-fusion/background/resume-result.json').write_text(json.dumps(report,indent=2)+'\n')
