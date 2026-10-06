import json
from pathlib import Path
report=json.loads(Path('work/storage-organize/chest-inspection.json').read_text())
rows=[]
for chest in report['chests']:
 for c in chest['containers']:
  h=c['id'].replace('-','')
  rows.append({
   'container_id':c['id'],'guid':dict(zip('ABCD',[int(h[i:i+8],16) for i in range(0,32,8)])),
   'instance_id':chest['instanceId'],'instance_guid':dict(zip('ABCD',[int(chest['instanceId'].replace('-','')[i:i+8],16) for i in range(0,32,8)])),'base_id':chest['baseId'],'group_id':chest['groupId'],
   'type':chest['type'],'expected_capacity':c['slotNum'],'world':chest['world'],'map':chest['map']})
assert len(rows)==18 and len({r['container_id'] for r in rows})==18
assert all(r['type'] in ('ItemChest','ItemChest_02') for r in rows)
def lua(v):
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,bool):return 'true' if v else 'false'
 if isinstance(v,dict):return '{'+', '.join(k+' = '+lua(x) for k,x in v.items())+'}'
 if isinstance(v,list):return '{\n'+',\n'.join('    '+lua(x) for x in v)+'\n}'
 return str(v)
out=Path('work/palworld-live/bridge/PalLiveBridge/Scripts/targets.lua')
out.write_text('-- Candidate target allowlist; from an earlier saved snapshot, not live ownership proof.\n-- FGuid A/B/C/D are uint32 values. Conversion matches docs/js/gvas.js UUID raw-byte LE words.\nreturn '+lua({'candidate_unvalidated':True,'snapshot_sha256':report['sha256'],'chests':rows})+'\n')
print(out,len(rows))
