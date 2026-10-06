"""One directed original bootstrap fixture: deterministic MCP configs and rejection boundaries."""
import sys
sys.dont_write_bytecode=True
import argparse
import importlib.util
import json
import shutil
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--base',required=True,type=Path)
p.add_argument('--fixture',required=True,type=Path)
p.add_argument('--mod',required=True,type=Path)
a=p.parse_args()
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(a.base.resolve()))
from installer import core,standalone
spec=importlib.util.spec_from_file_location('launcher.runtime',HERE/'source/launcher/runtime.py')
runtime=importlib.util.module_from_spec(spec);sys.modules[spec.name]=runtime;spec.loader.exec_module(runtime)
spec=importlib.util.spec_from_file_location('original_mcp_health_fixture',a.fixture.resolve())
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)
case=fixture.SingleplayerBootstrapTests();case.setUp()
try:
 root=case.root;state=case.state
 state['profile']['standalone']={'backend_root':str(root.parent/'backend'),'save_account_directory':'123456789','enrollment_pending':True}
 target=core.DEV+'/minecraft-mods/existing-approved.jar'
 dst=root/target;dst.parent.mkdir(parents=True);shutil.copyfile(a.mod,dst)
 state['manifest']['files'].append({'target':target,'role':'minecraft_mod','sha256':core.digest(dst)})
 rel=core.DEV+'/mcp/ai-transport.json';extra=core.DEV+'/mcp/mc-transport.json'
 seed=b'{"schema":1,"transport":"portable-template"}\n'
 import hashlib
 state['manifest']['files'].append({'target':rel,'role':'standalone_component','sha256':hashlib.sha256(seed).hexdigest()})
 generated=standalone.generated_files(core.validate_profile(state['profile'],root),state['manifest'])
 state['files']={}
 for name in (rel,extra):
  path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(generated[name]);state['files'][name]=core.digest(path)
 core.atomic_json(root/'.palcraft/state.json',state)
 def mcp_ok():
  result=runtime.health(root,launch_mode=runtime.BOOTSTRAP_MODE)
  return {name:next(c['ok'] for c in result['checks'] if c['message']=='组件校验：'+name) for name in (rel,extra)},result
 good,result=mcp_ok();assert all(good.values()) and result['ok']
 (root/rel).write_bytes(seed)
 bad,_=mcp_ok();assert bad[rel] is False
 (root/rel).write_bytes(generated[rel])
 state['files'][rel]=hashlib.sha256(seed).hexdigest();core.atomic_json(root/'.palcraft/state.json',state)
 bad,_=mcp_ok();assert bad[rel] is False
 (root/rel).write_bytes(seed)
 bad,_=mcp_ok();assert bad[rel] is False,'matching template/edited state cannot replace this-root generator bytes'
 (root/rel).write_bytes(generated[rel]);state['files'][rel]=core.digest(root/rel);core.atomic_json(root/'.palcraft/state.json',state)
 (root/extra).write_bytes(b'changed generated extra')
 bad,_=mcp_ok();assert bad[extra] is False
 (root/extra).write_bytes(generated[extra])
 host=next(e for e in state['manifest']['files'] if e['role']=='client_host')
 (root/host['target']).write_bytes(b'changed binary')
 state['files'][host['target']]=core.digest(root/host['target']);core.atomic_json(root/'.palcraft/state.json',state)
 _,binary=mcp_ok()
 assert next(c['ok'] for c in binary['checks'] if c['message']=='组件校验：'+host['target']) is False
 report={'schema':1,'passed':True,'existing_temporary_bootstrap_fixture_reused':True,
  'original_generator_bytes_and_managed_hash_match_accepted':True,'seed_template_file_rejected':True,
  'changed_managed_hash_rejected':True,'seed_plus_changed_managed_record_rejected':True,
  'changed_generated_extra_without_manifest_entry_rejected':True,
  'non_configuration_binary_remains_exact_manifest_guard_even_if_managed_hash_changed':True,
  'allowlist_only_ai_and_mc_transport_JSON':True,'actual_game_GUI_RPCS_or_full_Bundle_matrix':False}
 (HERE/'check-receipt.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
finally:case.tearDown()
