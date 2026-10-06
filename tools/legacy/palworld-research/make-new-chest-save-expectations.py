#!/usr/bin/env python3
"""Create offline save-verification expectations from actual, verified Lab chest observations.
Does not perform game calls, save reads/writes, deployment, or claim construction success.
"""
import argparse
import copy
import hashlib
import json
import uuid
from pathlib import Path

BASE='00000000-0000-4000-8000-000000000031'
GUILD='00000000-0000-4000-8000-00000000001b'
PLAYER='22222222-0000-0000-0000-000000000000'
OLD_MANUAL='00000000-0000-4000-8000-000000000030'
ZERO='00000000-0000-0000-0000-000000000000'
WORKER={'individual_id':'00000000-0000-4000-8000-00000000002e','player_uid':ZERO,
 'base_id':BASE,'guild_id':GUILD,'model_id':'00000000-0000-4000-8000-000000000012',
 'work_id':'00000000-0000-4000-8000-000000000020'}

def guid(value):
    assert isinstance(value,str) and str(uuid.UUID(value))==value and value!=ZERO, 'Nonzero canonical GUID required'
    return value

def rows(value):
    for _ in range(5):
        if isinstance(value,list):return value
        assert isinstance(value,dict),'Chest report must be an object or array'
        assert value.get('isError') is not True and not value.get('error'),'Tool error is not a chest observation'
        if 'chests' in value:
            assert value.get('ok') is True and value.get('reader_verified') is True,'Successful verified reader report required'
            assert value.get('base_id')==BASE,'Report scope differs'
            return value['chests']
        if isinstance(value.get('result'),dict):value=value['result']
        elif isinstance(value.get('structuredContent'),dict):value=value['structuredContent']
        elif isinstance(value.get('content'),list):
            content=[x.get('text') for x in value['content'] if x.get('type')=='text'];assert len(content)==1
            value=json.loads(content[0])
        else:raise AssertionError('No observed chests in response')
    raise AssertionError('Too many wrappers')

def make(observed,baseline,new_model):
    guid(new_model);assert new_model!=OLD_MANUAL,'Old manually-built chest cannot be the new build result'
    old=rows(baseline)
    assert len(old)==13,'Expected the known thirteen-chest old-base baseline'
    oldmodels={guid(c['model_instance_id_live']) for c in old};oldcontainers={guid(c['container_id_from_module_live']) for c in old}
    assert len(oldmodels)==len(oldcontainers)==13,'Baseline identities must be unique'
    assert new_model not in oldmodels,'Selected model already existed in baseline'
    matched=[c for c in rows(observed) if c.get('model_instance_id_live')==new_model]
    assert len(matched)==1,'Actual new model must have exactly one observed chest row'
    c=matched[0]
    assert c.get('ok') is True and c.get('verified_live') is True and c.get('ownership_verified_live') is True,'Live ownership not verified'
    assert c.get('base_id_live')==BASE and c.get('group_id_live')==GUILD,'Observed ownership differs'
    assert c.get('type_live')=='ItemChest' and c.get('is_guild_chest_live') is False,'Expected ordinary wooden chest'
    assert c.get('capacity')==10,'Observed capacity differs'
    container=guid(c['container_id_from_module_live']);concrete=guid(c['concrete_instance_id_live'])
    assert c.get('actual_id')==container and c.get('id')==container,'Container identity differs between module and row'
    assert container not in oldcontainers,'New model reuses a baseline container'
    originals=[]
    for c in old:
        assert c.get('ok') is True and c.get('ownership_verified_live') is True and c.get('verified_live') is True,'Baseline ownership not verified'
        assert c.get('base_id_live')==BASE and c.get('group_id_live')==GUILD,'Baseline ownership differs'
        assert c.get('type_live') in ('ItemChest','ItemChest_02') and c.get('is_guild_chest_live') is False,'Unexpected baseline chest type'
        assert c.get('capacity') in (10,24),'Unexpected baseline capacity'
        originals.append({'model_id':guid(c['model_instance_id_live']),'concrete_id':guid(c['concrete_instance_id_live']),
          'container_id':guid(c['container_id_from_module_live']),'base_id':BASE,'guild_id':GUILD,
          'type':c['type_live'],'capacity':c['capacity']})
    new_chest={'model_id':new_model,'concrete_id':concrete,'container_id':container,
       'base_id':BASE,'guild_id':GUILD,'build_player_uid':PLAYER,'type':'ItemChest','capacity':10}
    # Verify original 13 identity/capacity chains as well as the actual new box.
    # Contents may naturally change; this does not assert inventory invariance.
    return {'lab_only':True,'chests':originals+[new_chest],'workers':[copy.deepcopy(WORKER)]}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--chests-report',required=True);p.add_argument('--new-model-id',required=True)
    p.add_argument('--baseline',default='work/palworld-live/lab/oldbase-after-manual-demolition.json')
    p.add_argument('--output',required=True);a=p.parse_args()
    inputs=[Path(a.chests_report),Path(a.baseline)];out=Path(a.output)
    assert out.suffix=='.json' and all(out.resolve()!=f.resolve() for f in inputs),'Output must be a new JSON artifact'
    payloads=[f.read_bytes() for f in inputs];assert all(len(b)<=8*1024*1024 for b in payloads),'Input too large'
    result=make(json.loads(payloads[0]),json.loads(payloads[1]),a.new_model_id)
    with out.open('x',encoding='utf-8') as f:json.dump(result,f,indent=2);f.write('\n')
    print(json.dumps({'expectations_created':True,'save_verified':False,'source_sha256':{str(f):hashlib.sha256(b).hexdigest() for f,b in zip(inputs,payloads)},'output':str(out)},indent=2))

if __name__=='__main__':main()
