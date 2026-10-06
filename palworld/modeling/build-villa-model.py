"""Reconstruct the completed villa from recorded native building results.

Coordinates and rotations come from completed operations. Asset geometry is a
dimensioned proxy: this does not extract Palworld artwork or collision meshes.
"""
from pathlib import Path
import json
import math
from collections import Counter

HERE = Path(__file__).resolve().parent
LAB = HERE.parent / 'lab'
OUT = HERE.parents[2] / 'outputs' / 'villa-model'
VIZ = Path('/Users/PLAYER/.codex/visualizations/2026/10/04/00000000-0000-4000-8000-000000000003')

def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))

requests = {}
for p in LAB.glob('villa-*-plan.json'):
    for op in read(p).get('operations', []):
        if op['kind'] == 'build':
            requests[op['request']['nonce']] = op['request']
for p in HERE.glob('house-experiment-*.json'):
    j = read(p)
    requests[j['nonce']] = j['request']

alive = {}
def apply(row):
    if row['kind'] == 'dismantle':
        alive.pop(row['model_id'], None)
    elif row.get('status') == 'normal_structure_completed':
        alive[row['model']['model_id']] = row

foundation = read(HERE / 'house-experiment-00000000-0000-4000-8000-00000000002b.json')
apply(dict(kind='build', label='raised-foundation-0-0', nonce=foundation['nonce'],
           model=foundation['new_model'], recipe=foundation['recipe'], status=foundation['status']))
for p in [LAB/'villa-deck-batch-live.json', LAB/'villa-main-batch-live.json',
          HERE/'villa-batch-00000000-0000-4000-8000-00000000002f.json',
          LAB/'villa-stairs-rails-live.json', LAB/'villa-finishing-live.json']:
    for row in read(p)['results']:
        apply(row)

origin = [-308099.9282280116, 187800.81696803804, 3480.330899345611]
base_yaw = 2 * math.atan2(0.9335364086075154, 0.35848259902564583)
c, s = math.cos(base_yaw), math.sin(base_yaw)
pieces = []
for mid, row in alive.items():
    cfg = requests[row['nonce']]
    p = row['model']['position']
    dx, dy = p['X']-origin[0], p['Y']-origin[1]
    q = cfg['rotation']
    yaw = 2*math.atan2(q['Z'], q['W'])-base_yaw
    yaw = math.atan2(math.sin(yaw), math.cos(yaw))
    pieces.append(dict(id=mid, label=row['label'], build=cfg['build_id'],
                       p=[round((dx*c+dy*s)/100,4),round((-dx*s+dy*c)/100,4),
                          round((p['Z']-origin[2])/100,4)], yaw=round(yaw,8)))

faces, vertices = [], []
def box(piece, center, dims, category=None):
    a = piece['yaw']; ca, sa = math.cos(a), math.sin(a)
    ids = []
    for sx, sy, sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
                       (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:
        x, y, z = [center[i]+[sx,sy,sz][i]*dims[i]/2 for i in range(3)]
        v=[piece['p'][0]+x*ca-y*sa,piece['p'][1]+x*sa+y*ca,piece['p'][2]+z]
        ids.append(len(vertices)); vertices.append([round(t,4) for t in v])
    for idx in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]:
        faces.append(dict(v=[ids[i] for i in idx], piece=piece['id'],
                          category=category or piece['category'], z=piece['p'][2]))

for p in pieces:
    b = p['build']; label = p['label']; z = p['p'][2]
    p['level'] = 'supports' if b=='Wooden_pillar' else 'upper' if z>=3.2 else 'ground'
    p['category'] = ('support' if b=='Wooden_pillar' else 'stairs' if b=='Wooden_stair'
                     else 'railing' if b=='Wood_Fence' else 'roof' if label.startswith('top-roof')
                     or label=='entrance-canopy' else 'floor' if b in ('Wooden_roof','Wooden_foundation')
                     else 'wall')
    if b == 'Wooden_pillar':
        box(p,[0,0,1.625],[.25,.25,3.25])
    elif b == 'Wooden_foundation':
        box(p,[0,0,-.25],[4,4,.5])
        for x in [-1.8,1.8]:
            for y in [-1.8,1.8]: box(p,[x,y,-.75],[.22,.22,1.5],'support')
    elif b == 'Wooden_roof':
        box(p,[0,0,-.1],[4,4,.2])
    elif b == 'Wooden_wall':
        box(p,[0,0,1.625],[.14,4,3.25])
    elif b == 'Wood_WindowWall':
        box(p,[0,0,.5],[.14,4,1])
        box(p,[0,0,2.825],[.14,4,.85])
        for y in [-1.4,1.4]: box(p,[0,y,1.7],[.14,1.2,1.4])
        box(p,[0,0,1.7],[.18,.06,1.4])
    elif b == 'Wooden_DoorWall':
        for y in [-1.325,1.325]: box(p,[0,y,1.625],[.14,1.35,3.25])
        box(p,[0,0,2.825],[.14,1.3,.85])
    elif b == 'Wooden_stair':
        for i in range(13):
            height=.25*(i+1)
            box(p,[-2+(i+.5)*4/13,0,-3.25+height/2],[4/13,4,height])
    elif b == 'Wood_Fence':
        for y in [-1.88,0,1.88]: box(p,[0,y,.525],[.15,.15,1.05])
        for zrail in [.35,.9]: box(p,[0,0,zrail],[.12,4,.12])
    else:
        raise ValueError('Unhandled completed build '+b)

scene = dict(format=1, source='completed_native_construction_records', snapshot_saved_utc='2026-10-04T10:13:25.6497760Z',
             geometry='simplified_dimensioned_proxy', units='meters', world_origin_cm=origin,
             base_yaw_radians=base_yaw, pieces=pieces, vertices=vertices, faces=faces,
             counts=dict(Counter(p['build'] for p in pieces)), removed_models_omitted=True,
             failed_placements_omitted=True)
OUT.mkdir(parents=True,exist_ok=True); VIZ.mkdir(parents=True,exist_ok=True)
(OUT/'villa-scene.json').write_text(json.dumps(scene,ensure_ascii=False,indent=2)+'\n')
obj=['# BridgeLab villa, completed pieces; simplified asset geometry', '# Units meters, Z up']
obj.extend('v '+' '.join(str(v) for v in point) for point in vertices)
last=None
for f in faces:
    if f['piece']!=last:
        last=f['piece']; obj.append('g '+next(p['label'] for p in pieces if p['id']==last))
    obj.append('f '+' '.join(str(v+1) for v in f['v']))
(OUT/'villa.obj').write_text('\n'.join(obj)+'\n')
html=(HERE/'villa-viewer-template.html').read_text()
html=html.replace('SCENE_JSON_PLACEHOLDER',json.dumps(scene,separators=(',',':')))
(VIZ/'palworld-villa.html').write_text(html)
print(json.dumps({'pieces':len(pieces),'counts':scene['counts'],'faces':len(faces),'view':str(VIZ/'palworld-villa.html')}))
