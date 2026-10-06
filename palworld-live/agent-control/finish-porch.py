from pathlib import Path
import json,time
from client import call
D=Path(__file__).parent
p=json.loads((D/'manor-current-world-plan.json').read_text());r=json.loads((D/'manor-current-world-plan-run.json').read_text());terrain=json.loads((D/'porch-terrain.json').read_text())['points'];temp=json.loads((D/'porch-pillar-temp-receipt.json').read_text())
for index in [70,71]:
    op=p['operations'][index]
    if index==70:receipt=temp['receipt']
    else:receipt=call('build',temp['params'])
    while True:
        result=call('operation',{'id':receipt['operation_id']})
        if result.get('status')=='completed':break
        if result.get('status') in ['failed','spawn_not_observed']:raise RuntimeError(result)
        time.sleep(.3)
    params={k:op['params'][k] for k in ['mode','player_uid','guild_id','position']};params['position']=params['position'].copy();ground=terrain[index-70]['impact']['Z'];params['position']['Z']=ground;params['scale']={'X':1,'Y':1,'Z':(p['operations'][69]['params']['position']['Z']-36-ground)/325.1440124511719};params['id']=result['model']['id']
    transformed=call('transform',params);m=call('models',{'ids':[params['id']]})['models'][0]
    if index<len(r['rows']):r.setdefault('superseded_attempts',[]).append(r['rows'][index])
    row={'index':index,'label':op['label'],'id':receipt['operation_id'],'status':'completed','result':dict(result,model=m),'creative_transform':transformed}
    if index<len(r['rows']):r['rows'][index]=row
    else:r['rows'].append(row)
    op['params']['position']=params['position'];op['params']['scale']=params['scale']
    (D/'manor-current-world-plan.json').write_text(json.dumps(p,indent=2));(D/'manor-current-world-plan-run.json').write_text(json.dumps(r,indent=2));print(index,op['label'],m['id'],flush=True)
