"""Creative cliff manor, built from real 4m wooden building modules."""
from pathlib import Path
import json,math

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
old=json.loads((ROOT/'outputs/villa-model/villa-scene.json').read_text())
terrain=json.loads((HERE/'manor-terrain.json').read_text())
P=old['world_origin_cm'];yaw=old['base_yaw_radians'];c,s=math.cos(yaw),math.sin(yaw)
UID='22222222-0000-0000-0000-000000000000';GUILD='00000000-0000-4000-8000-00000000001b';BASE='00000000-0000-4000-8000-000000000031'
ops=[]
def build(label,kind,x,y,z=0,angle=0):
    ops.append({'kind':'build','label':label,'params':{'mode':'creative','player_uid':UID,'guild_id':GUILD,'base_id':BASE,'build_id':kind,
       'position':{'X':P[0]+x*c-y*s,'Y':P[1]+x*s+y*c,'Z':P[2]+z},'rotation':{'Pitch':0,'Yaw':math.degrees(yaw)+angle,'Roll':0}}})

kept=[p for p in old['pieces'] if p['category'] in ('support','floor') and (p['p'][2]<.1)]
kept_ids={p['id'] for p in kept}
remove=[p for p in old['pieces'] if p['id'] not in kept_ids]
remove.sort(key=lambda p:p['p'][2],reverse=True)
ops.append({'kind':'dismantle','label':'clear-old-misassembled-house','params':{'ids':[p['id'] for p in remove]+['00000000-0000-4000-8000-000000000032','00000000-0000-4000-8000-000000000033'],'player_uid':UID,'guild_id':GUILD}})

# New perimeter support columns, rooted in measured terrain; top is deck level.
ground={(p['x'],p['y']):p['impact']['Z'] for p in terrain['points'] if p.get('hit')}
for x,y in [(600,-200),(600,600),(600,1000),(-1000,1000),(-600,1000),(-200,1000),(200,1000)]:
    n=math.ceil((P[2]-ground[(x,y)])/325)
    for i in range(n):build(f'column-{x}-{y}-{i}','Wooden_pillar',x,y,-n*325+i*325)

# Expand the existing 12x8m deck into a 16x12m platform.
for x,y in [(400,0),(400,400),(400,800),(-800,800),(-400,800),(0,800)]:
    build(f'deck-{x}-{y}','Wooden_roof',x,y)

# Lower floor: panoramic windows, landward central entry.
for y in [0,400,800]:
    build(f'lower-entry-{y}','Wooden_DoorWall' if y==400 else 'Wood_WindowWall',600,y,0,180)
    build(f'lower-ocean-{y}','Wood_WindowWall',-1000,y)
for x in [-800,-400,0,400]:
    build(f'lower-south-{x}','Wood_WindowWall',x,-200,0,90)
    build(f'lower-north-{x}','Wood_WindowWall',x,1000,0,-90)

# Upper floor: 12x12m rooms, 4m ocean-side balcony and a real stair opening.
for x in [-800,-400,0,400]:
    for y in [0,400,800]:
        if (x,y)!=(0,800):build(f'upper-floor-{x}-{y}','Wooden_roof',x,y,325)
build('internal-stair-correct-origin','Wooden_stair',0,800,0,0)
for y in [0,400,800]:
    build(f'upper-front-{y}','Wood_WindowWall',600,y,325,180)
    build(f'upper-balcony-{y}','Wooden_DoorWall' if y==400 else 'Wood_WindowWall',-600,y,325)
for x in [-400,0,400]:
    build(f'upper-south-{x}','Wood_WindowWall',x,-200,325,90)
    build(f'upper-north-{x}','Wood_WindowWall',x,1000,325,-90)

# Raised central roof strip with pitched flanks. Sloped mesh rises toward -X.
for y in [0,400,800]:
    build(f'roof-ocean-slope-{y}','Wood_SlantedRoof',-400,y,650,180)
    build(f'roof-land-slope-{y}','Wood_SlantedRoof',400,y,650,0)
    build(f'roof-ridge-{y}','Wooden_roof',0,y,975)
for y,angle in [(-200,90),(1000,-90)]:
    build(f'gable-ocean-{y}','Wood_TriangleWall',-400,y,650,angle)
    build(f'gable-land-{y}','Wood_TriangleWall',400,y,650,angle+180)
    build(f'gable-centre-{y}','Wood_WindowWall',0,y,650,angle)

# Four-window belvedere under a small pyramid roof.
for label,x,y,angle in [('west',-200,400,0),('east',200,400,180),('south',0,200,90),('north',0,600,-90)]:
    build('belvedere-'+label,'Wood_WindowWall',x,y,975,angle)
build('belvedere-pyramid-roof','Wooden_PyramidRoof',0,400,1300)

# Balcony: fence mesh runs along local X, unlike the wall mesh.
for y in [0,400,800]:build(f'balcony-ocean-rail-{y}','Wood_Fence',-1000,y,325,90)
for y in [-200,1000]:build(f'balcony-end-rail-{y}','Wood_Fence',-800,y,325,0)

# Entrance stairs: correct lower origin and high end facing the door.
build('entry-stair-correct-origin','Wooden_stair',800,400,-325,0)
build('entry-canopy','Wooden_roof',800,400,325)
for y in [200,600]:
    build(f'porch-post-lower-{y}','Wooden_pillar',1000,y,-325)
    build(f'porch-post-upper-{y}','Wooden_pillar',1000,y,0)

# Functional upper suite and an illuminated entrance.
build('suite-bed-left','PlayerBed_02',-400,0,325,0)
build('suite-bed-right','PlayerBed_02',400,0,325,180)
build('suite-desk','SF_Desk',0,0,325,90)
build('suite-chair','SF_Chair',0,120,325,90)
build('entrance-lantern-left','Shrine_Lantern',500,150,0,0)
build('entrance-lantern-right','Shrine_Lantern',500,650,0,0)
build('ocean-lantern-south','Shrine_Lantern',-850,50,325,0)
build('ocean-lantern-north','Shrine_Lantern',-850,750,325,0)

plan={'name':'cliff-observation-manor','mode':'creative','base_id':BASE,'player_uid':UID,'guild_id':GUILD,
      'origin_cm':P,'yaw_radians':yaw,'retained_model_ids':sorted(kept_ids)+['00000000-0000-4000-8000-000000000015'],
      'operations':ops,'description':'16x12m platform, two panoramic floors, ocean balcony, pitched roof and four-window belvedere; original terrain support retained.'}
(HERE/'manor-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'operations':len(ops),'builds':sum(o['kind']=='build' for o in ops),'retained':len(plan['retained_model_ids'])}))
