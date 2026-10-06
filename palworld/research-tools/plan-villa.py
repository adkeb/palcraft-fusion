from pathlib import Path
import json,uuid,math,time
R=Path(__file__).resolve().parents[1]/'lab'
h=json.loads((R/'house-acceptance-evidence.json').read_text());f=h['pieces'][0];p=f['position'];q=f['rotation'];yaw=2*math.atan2(q['Z'],q['W']);c=math.cos(yaw);s=math.sin(yaw);z0=p['Z']+150
ops=[]
for label in ['roof','door','window-left','window-right','wall-1','foundation-supplied']:
 row=next(r for r in h['pieces'] if r['part']==label);ops.append(dict(kind='dismantle',label='old-'+label,id=row['model_id']))
def add(label,kind,x,y,z,turn=0):
 ops.append(dict(kind='build',label=label,request=dict(nonce=str(uuid.uuid4()),base_id='00000000-0000-4000-8000-000000000031',build_id=kind,position=dict(X=p['X']+x*c-y*s,Y=p['Y']+x*s+y*c,Z=z0+z),rotation=dict(X=0,Y=0,Z=math.sin((yaw+turn)/2),W=math.cos((yaw+turn)/2)),archives=[],execute=True,auto_supply_wood=True)))
for x in [0,-400,-800]:
 for y in [0,400]:add(f'raised-foundation-{x}-{y}','Wooden_foundation',x,y,0)
for y in [0,400]:
 add(f'ground-front-{y}','Wooden_DoorWall' if y==0 else 'Wood_WindowWall',-1000,y,0,0)
 add(f'ground-back-{y}','Wood_WindowWall',200,y,0,math.pi)
for x in [0,-400,-800]:
 add(f'ground-side-south-{x}','Wood_WindowWall' if x!=-400 else 'Wooden_wall',x,-200,0,math.pi/2)
 add(f'ground-side-north-{x}','Wood_WindowWall' if x!=-400 else 'Wooden_wall',x,600,0,-math.pi/2)
for x in [0,-400,-800]:
 for y in [0,400]:
  if (x,y)!=(-800,400):add(f'upper-floor-{x}-{y}','Wooden_roof',x,y,325,math.pi)
add('internal-stair','Wooden_stair',-800,400,0,0)
for y in [0,400]:
 add(f'upper-front-door-{y}','Wooden_DoorWall',-600,y,325,0)
 add(f'upper-back-window-{y}','Wood_WindowWall',200,y,325,math.pi)
for x in [0,-400]:
 add(f'upper-side-south-{x}','Wood_WindowWall',x,-200,325,math.pi/2)
 add(f'upper-side-north-{x}','Wood_WindowWall',x,600,325,-math.pi/2)
for x in [0,-400]:
 for y in [0,400]:add(f'top-roof-{x}-{y}','Wooden_roof',x,y,650,math.pi)
add('entry-stair','Wooden_stair',-1200,0,-325,0)
add('balcony-front-railing','Wood_Fence',-1000,0,325,0)
add('balcony-side-railing','Wood_Fence',-800,-200,325,math.pi/2)
add('stair-edge-railing','Wood_Fence',-1000,400,325,0)
plan=dict(nonce=str(uuid.uuid4()),lab_only=True,description='Raised 1.5m, 12x8m ground floor, 8x8m upper floor, balcony and stairs',operations=ops)
(R/'villa-batch-plan.json').write_text(json.dumps(plan,indent=2)+'\n');print(json.dumps({'nonce':plan['nonce'],'operations':len(ops),'builds':sum(o['kind']=='build' for o in ops)}))
