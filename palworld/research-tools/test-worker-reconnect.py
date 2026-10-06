#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path
p=Path(__file__).with_name('verify-worker-reconnect.py')
spec=importlib.util.spec_from_file_location('verify_worker_reconnect',p); m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
snap=json.loads(Path('work/palworld-live/lab/oldbase-workers-client-online.json').read_text())
saved=json.loads(Path('work/palworld-live/lab/client-acceptance-worker-save-verification.json').read_text())
for b in snap['bases']:
 for w in b['workers']:
  if w.get('individual_id',{}).get('instance_id')==m.INDIVIDUAL:
   target=w
snap['observed_utc']='2026-10-04T10:00:00Z'
target['task']={'known':True,'assigned':True,'fixed':True,'work_id':m.WORK,'working':False,'working_state_enum':3}
checkpoint='2026-10-04T09:59:00Z'
def run(s=snap,sv=saved,after=checkpoint):return m.verify(s,sv,after)
r=run();assert r['ok'] and r['restart_retention_evidence'] and not r['live_model_binding_verified'] and not r['production_work_observed']
for kind in ['raw','jsonrpc','mcptext','structured']:
 wrapper={'raw':snap,'jsonrpc':{'result':snap},'mcptext':{'result':{'content':[{'type':'text','text':json.dumps(snap)}]}},'structured':{'structuredContent':snap}}[kind]
 assert m.verify(wrapper,saved,checkpoint)['ok']
assert not run(after='2026-10-04T10:01:00Z')['ok']
assert not m.verify(snap,saved,checkpoint,'bad-instance')['ok']
for key,value in [('actor_loaded',False),('ownership_verified_live',False),('base_id',m.ZERO)]:
 s=copy.deepcopy(snap);t=next(w for b in s['bases'] for w in b['workers'] if w.get('individual_id',{}).get('instance_id')==m.INDIVIDUAL);t[key]=value
 assert not run(s)['ok'],key
for change in [{'known':False},{'assigned':False},{'fixed':False},{'work_id':m.ZERO}]:
 s=copy.deepcopy(snap);t=next(w for b in s['bases'] for w in b['workers'] if w.get('individual_id',{}).get('instance_id')==m.INDIVIDUAL);t['task'].update(change)
 assert not run(s)['ok'],change
s=copy.deepcopy(saved);s['workers'][0]['work']['model_id']=m.ZERO;assert not run(sv=s)['ok']
s=copy.deepcopy(snap);s['bases'][0]['workers'].append(copy.deepcopy(target));assert not run(s)['ok']
assert not m.verify({'isError':True},saved,checkpoint)['ok']
print('PASS reconnect parser: valid binding/wrappers, stale/foreign instance, unloaded/unknown, ownership, wrong task/model, duplicate and tool-error guards; fixtures are synthetic, not a live acceptance claim.')
