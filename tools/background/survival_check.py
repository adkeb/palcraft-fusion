from probe import WS
from pathlib import Path
import json,time,threading
w=WS();stop=threading.Event();pose={'t':'cam','f':0,'p':[0.5,65.62,0.5],'r':[0,0,0],'fov':70,'fp':True,'pl':[0.5,64,0.5],'h':0,'g':True}
report={'test':'isolated_session0_survival','fixture':'Separate background-check world. Two oak target blocks and stone floor created as test fixture; no inventory items granted. All tested mining/placement uses ordinary key events.','steps':[]}
def pump():
 while not stop.wait(.08):
  try:pose['f']+=1;w.send(pose)
  except Exception:return
th=threading.Thread(target=pump,daemon=True);th.start()
def inspect(label):
 r=w.inspect();report['steps'].append({'step':label,**r});print(label,json.dumps(r),flush=True);return r
def cmd(c):w.send({'t':'cmd','c':c})
try:
 time.sleep(.7)
 cmd('fill -4 63 -4 4 63 8 minecraft:stone')
 cmd('setworldspawn 0 64 0');cmd('spawnpoint @a 0 64 0')
 cmd('setblock 0 65 3 minecraft:oak_planks');cmd('setblock 0 65 5 minecraft:oak_planks')
 time.sleep(1)
 before=inspect('before_grounded')
 assert before['creative']==False and not before['inventory'],before
 assert before['aim']['block']=='minecraft:oak_planks',before
 assert before['grounded']==True and before['host_grounded']==True,before
 pose['g']=False;time.sleep(.4);air=inspect('airborne');assert not air['grounded']
 pose['g']=True;time.sleep(.4);ground=inspect('ground_restored');assert ground['grounded']
 assert 4.9<ground['aim']['progress_per_tick']/air['aim']['progress_per_tick']<5.1
 w.send({'t':'key','k':'attack','down':True});start=time.monotonic();time.sleep(1);inspect('mining_1_second');time.sleep(2.7)
 w.send({'t':'key','k':'attack','down':False});time.sleep(.3);mined=inspect('after_mining');report['mining_hold_seconds']=round(time.monotonic()-start,3)
 assert mined['aim'].get('z')!=3 or mined['aim']['block']!='minecraft:oak_planks',mined
 pose['pl']=[.5,64,3.3];pose['p']=[.5,65.62,3.3];time.sleep(1)
 pickup=inspect('after_pickup');assert sum(i['count'] for i in pickup['inventory'] if i['item']=='minecraft:oak_planks')==1,pickup
 pose['pl']=[.5,64,2.5];pose['p']=[.5,65.62,2.5];time.sleep(.5)
 w.send({'t':'slot','n':0});w.send({'t':'key','k':'use','down':True});time.sleep(.16);w.send({'t':'key','k':'use','down':False});time.sleep(.5)
 placed=inspect('after_placement');assert not placed['inventory'] and placed['aim']['z']==4 and placed['aim']['block']=='minecraft:oak_planks',placed
 # Mine the remaining fixture block from the other side, keep its drop to test inventory persistence.
 pose['pl']=[.5,64,7.5];pose['p']=[.5,65.62,7.5];pose['r']=[180,0,0];pose['h']=180;time.sleep(.5)
 inspect('second_target');w.send({'t':'key','k':'attack','down':True});time.sleep(3.6);w.send({'t':'key','k':'attack','down':False});time.sleep(.4)
 pose['pl']=[.5,64,5.6];pose['p']=[.5,65.62,5.6];time.sleep(1)
 saved=inspect('before_save');assert sum(i['count'] for i in saved['inventory'] if i['item']=='minecraft:oak_planks')==1,saved
 report['passed']=True
except Exception as e:
 report['passed']=False;report['error']=repr(e);print('FAILED',repr(e),flush=True)
finally:
 w.send({'t':'key','k':'attack','down':False});w.send({'t':'key','k':'use','down':False});w.send({'t':'shutdown'});stop.set();w.close()
 Path('work/minecraft-fusion/background/survival-result.json').write_text(json.dumps(report,indent=2)+'\n')
