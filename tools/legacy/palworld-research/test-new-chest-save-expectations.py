import copy,importlib.util,json
from pathlib import Path
p=Path(__file__).with_name('make-new-chest-save-expectations.py');s=importlib.util.spec_from_file_location('new_chest_expectations',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
baseline=json.loads(Path('work/palworld-live/lab/oldbase-after-manual-demolition.json').read_text())
observed=json.loads(Path('work/palworld-live/lab/manual-new-chests.json').read_text())
# Synthetic new identity reuses only the shape of an actual verified observation.
new='00000000-0000-4000-8000-000000000010';observed[0]['model_instance_id_live']=new
r=m.make(observed,baseline,new);assert len(r['chests'])==14 and r['chests'][-1]['model_id']==new and 'save_verified' not in r
for kind in ['old_manual','baseline_model','missing','duplicate','not_verified','foreign_guild','old_container','wrong_type','wrong_capacity']:
 o=copy.deepcopy(observed);target=new
 if kind=='old_manual':target=m.OLD_MANUAL
 elif kind=='baseline_model':target=baseline['chests'][0]['model_instance_id_live']
 elif kind=='missing':o=[]
 elif kind=='duplicate':o.append(copy.deepcopy(o[0]))
 elif kind=='not_verified':o[0]['ownership_verified_live']=False
 elif kind=='foreign_guild':o[0]['group_id_live']=m.ZERO
 elif kind=='old_container':
  for key in ['id','actual_id','container_id_from_module_live']:o[0][key]=baseline['chests'][0]['container_id_from_module_live']
 elif kind=='wrong_type':o[0]['type_live']='ItemChest_02'
 elif kind=='wrong_capacity':o[0]['capacity']=24
 try:m.make(o,baseline,target)
 except (AssertionError,ValueError):pass
 else:raise AssertionError(kind+' unexpectedly accepted')
print('PASS expectations generator uses actual verified new model/container, refuses old/manual/ambiguous/mismatched rows; synthetic positive fixture does not claim a build.')
