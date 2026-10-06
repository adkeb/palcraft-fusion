#!/usr/bin/env python3
# coding: utf-8
"""Generate a local evidence snapshot; never contact/deploy to any server."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check-only',action='store_true',help='Validate and summarize without writing the snapshot')
parser.add_argument('--v4-report',help='Optional actual v4 runtime JSON path relative to work/palworld-live; success requires explicit reviewed state and evidence checks')
parser.add_argument('--v4-save-report',help='Optional actual v4 post-save verification JSON; success requires matching runtime and saved identity chains')
args=parser.parse_args()
refs={
 'current_state':'lab/current-client-acceptance-state.json',
 'production_operations':'lab/production-operation-verification.json',
 'production_save':'lab/production-save-integrity.json',
 'worker_once':'lab/worker-assign-once-live.json',
 'worker_save':'lab/client-acceptance-worker-save-verification.json',
 'build_manifest':'research/normal-rebuild-execute-manifest.json',
 'crash_saved_state':'lab/rebuild-crash-20261004/last-save-state-analysis.json',
 'readonly_v3':'lab/full-observer-readonly-v3-live.json',
}
state=json.loads((ROOT/refs['current_state']).read_text())
build_verified=state.get('ai_build_result')=='limited_lab_verified' and state.get('build_save_verified') is True
if build_verified:
 args.v4_report=args.v4_report or 'lab/'+state['build_runtime_report']
 args.v4_save_report=args.v4_save_report or 'lab/'+state['build_save_report']
if state.get('house_server_save_verified') is True:
 refs['house_runtime']='lab/house-acceptance-evidence.json'
 refs['house_saved']='lab/house-save-verification.json'
if state.get('worker_restart_runtime_verified') is True:
 refs['worker_restart']='lab/worker-after-recovery-verification.json'
if (ROOT/'lab/full-observer-readonly-v3-online-live.json').exists():
 refs['readonly_v3_online']='lab/full-observer-readonly-v3-online-live.json'
for key,name in [('build_v4_runtime',args.v4_report),('build_v4_saved',args.v4_save_report)]:
 if name:
  full=(ROOT/name).resolve()
  assert full.is_relative_to(ROOT) and full.suffix=='.json','Optional v4 evidence must be a local project JSON file'
  refs[key]=full.relative_to(ROOT).as_posix()
evidence=[];data={}
for key,name in refs.items():
 raw=(ROOT/name).read_bytes();data[key]=json.loads(raw)
 evidence.append({'id':key,'path':'work/palworld-live/'+name,'sha256':hashlib.sha256(raw).hexdigest()})
assert data['production_operations']['ok'] and data['production_save']['valid_save']
assert data['worker_once']['ok'] and data['worker_once']['native_call_attempted']
assert data['worker_save']['workers'][0]['fixedWorkSaved']
assert data['build_manifest']['native_execute_runtime_verified'] is False
v3=data['readonly_v3'];assert v3['lab_only'] and v3['read_only'] and v3['gameplay_mutation_calls']==0 and v3['construction_attempts']==0
assert v3['status']=='complete_partial_client_unavailable' and len(v3['samples'])==3 and v3['errors']==[]
assert v3['full_chain_verified'] is False and v3['complete_construction_proven'] is False
worker_restart=data['current_state'].get('worker_restart_runtime_verified',False)
if worker_restart:
 wr=data['worker_restart']
 assert wr['ok'] and wr['lab_only'] and wr['read_only'] and wr['restart_retention_evidence']
 assert wr['runtime_fixed_association'] and wr['saved_work_model_binding'] and wr['fresh_after_checkpoint']
 assert wr['expected_work_id']=='00000000-0000-4000-8000-000000000020' and wr['expected_model_id']=='00000000-0000-4000-8000-000000000012'
 assert wr['live_model_binding_verified'] is False and wr['live_reverse_work_binding_verified'] is False
 assert wr['native_assignment_called'] is False and wr['actor_force_load_called'] is False
if 'readonly_v3_online' in data:
 online=data['readonly_v3_online']
 assert online['lab_only'] and online['read_only'] and online['full_chain_verified'] and online['client_present']
 assert len(online['samples'])==3 and online['errors']==[] and online['gameplay_mutation_calls']==0 and online['construction_attempts']==0
 assert online['complete_construction_proven'] is False
for key in ('build_v4_runtime','build_v4_saved'):
 if key in data:
  assert data[key].get('lab_only') is True,'V4 evidence must be Lab-only'
  # File existence alone does not establish completed construction.
if build_verified:
 runtime,saved=data['build_v4_runtime'],data['build_v4_saved']
 assert runtime['nonce']==state['build_nonce']=='00000000-0000-4000-8000-00000000001f'
 assert runtime['native_call_attempts']==1 and runtime['native_call_returned'] and runtime['structure_completion_verified']
 assert runtime['immediate_material_delta']['exact_recipe_cost'] and runtime['immediate_material_delta']['deltas']=={'Wood':-15,'Stone':-5}
 assert runtime['recipe_debit_observed']['elapsed_seconds']==0 and runtime['errors']==[]
 candidate=runtime['new_model'];detail=candidate['detail']
 assert candidate['ok'] and candidate['completed_verified'] and detail['build_process']['completed']
 assert candidate['model_id']==state['build_model_id']=='00000000-0000-4000-8000-00000000000c'
 assert detail['container']['id']==state['build_container_id'] and detail['container']['capacity']==10
 progress=[o['candidate']['early_process']['work'] for o in runtime['observations'] if o.get('candidate',{}).get('early_process',{}).get('work')]
 assert progress and progress[0]['current']==0 and any(0<w['current']<1000 for w in progress)
 assert all(w['required']==1000 and w['owner_model_id']==state['build_model_id'] and w['base_id']==state['base_id'] for w in progress)
 assert len({w['id'] for w in progress})==1 and len({w['owner_concrete_id'] for w in progress})==1
 assert saved['ok'] and saved['errors']==[] and len(saved['chests'])==14 and all(c['ok'] for c in saved['chests'])
 new_saved=[c for c in saved['chests'] if c['model']['id']==state['build_model_id']]
 assert len(new_saved)==1 and new_saved[0]['container_id']==state['build_container_id'] and new_saved[0]['model']['completed']
 assert saved['input']['sha256']==state['save_sha256'] and saved['workers'][0]['fixedWorkSaved']
 assert state['build_client_visible_and_openable'] is True and state['build_restart_verified'] is False
 assert state['build_generic_api_enabled'] is False
 if state['build_far_distance_tested']:
  assert data['house_saved']['ok'] and len(data['house_runtime']['pieces'])==6
  assert all(p['status']=='normal_structure_completed' and p['immediate_cost']=={'Wood':-2} for p in data['house_runtime']['pieces'])

snapshot={
 'schema_version':1,'source':'local_evidence_snapshot','generated_utc':dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00','Z'),
 'is_live':False,'current_live_availability_checked':False,
 'summary':'本地验收证据快照，不是实时服务器状态。正式服箱子整理已有验证；派工仅完成一次测试服执行及保存核验；自动建造不可用。报告不会开启任何游戏能力。',
 'features':[
 {'id':'storage','environment':'production','state':'production_verified','recorded_public_write_enabled':True,
  'summary':'普通箱同基地合并与分类已在正式服验证；当次操作遵守实时能力和计划校验，当前服务健康需另查。',
  'verified_steps':['5次正式整理操作、291步骤含60次合并均有intent/commit与实际回读核对。','相关交易物品数量与动态身份守恒；在线保存可解析且动态引用可解析。'],
  'unverified_steps':['本报告未查询当前服务器在线、延迟或能力心跳。','不声称玩家继续游玩后的全世界物品完全不变。'],
  'evidence_ids':['production_operations','production_save']},
 {'id':'workers','environment':'BridgeLab','state':'limited_lab_verified','recorded_public_write_enabled':False,
  'summary':'佐伊固定到旧基地工作台的单次测试已执行，3秒/10秒双向关联和在线保存均通过；公开派工写接口仍关闭。',
  'verified_steps':['真实在线玩家权限7、健康空闲帕鲁、目标无人及原生适配检查后，仅调用一次正常固定分工。','角色与工作台双向关联通过，保存中有唯一相符的fixed分配记录。'],
  'unverified_steps':['测试服后来因建造实验崩溃后已重开；尚未有重载后的实时关联验证证据。','工作台空队列时Working=false，仅证明固定关联，不宣称已产出。','批量指派、取消/替换岗位及通用公开apply尚未验证。'],
  'evidence_ids':['current_state','worker_once','worker_save']},
 {'id':'build','environment':'BridgeLab','state':'unavailable_after_crash','recorded_public_write_enabled':False,
  'summary':'一次正常扣料建造请求后测试服发生崩溃，完整建成未验证；当前建造不可用，离线服务端建造仍在研究。',
  'verified_steps':['此前崩溃试验只提交一次；即时账本观察到扣除15木材和5石头，该次不重试。','清洁测试服已恢复，未手工改存档或补料；最后保存比请求早约19秒，保存里无该次扣料和新箱。','只读v3三次观察完成，无错误、无建造调用、无游戏修改；因无客户端是partial，不是建造验收。'],
  'unverified_steps':['自动建造完整成功、复制给客户端、完成施工和持久化均未验证。','早于请求的存档不能证明崩溃前从未短暂创建过新模型。','无真实客户端时的正常离线建造路径仍为研究，不能宣传支持。'],
  'evidence_ids':['current_state','build_manifest','crash_saved_state','readonly_v3']}
 ],'evidence':evidence}
if worker_restart:
 worker=snapshot['features'][1]
 worker['summary']='佐伊单次固定派工、在线保存及重启后角色侧固定关联均已在Lab核验；公开派工写接口仍关闭。'
 worker['verified_steps'].append('重启后的新鲜读取仍为assigned=true、fixed=true及同一WorkID，角色/基地归属一致。')
 worker['unverified_steps'][0]='重启后此次workers.list未返回目标模型实时反查或工作台反向membership；不能说完整双向链已重新验过。'
 worker['evidence_ids'].append('worker_restart')
 snapshot['summary']='本地验收证据快照，不是实时服务器状态。正式服整理已验证；Lab派工已执行、保存且重启后角色固定关联保留；自动建造仍不可用。'
if 'readonly_v3_online' in data:
 build=snapshot['features'][2]
 build['verified_steps'].append('玩家随后在线时只读v3又完成三次全只读链观察、errors=[]；没有发起建造或修改游戏，因此不是自动建造成功。')
 build['evidence_ids'].append('readonly_v3_online')
for key in ('build_v4_runtime','build_v4_saved'):
 if key in data:
  snapshot['features'][2]['evidence_ids'].append(key)
  if not build_verified:
   snapshot['features'][2]['unverified_steps'].append('已附加实际v4证据供审阅；此生成器不会仅凭文件存在自动宣告建成或开启写能力。')
if build_verified:
 build=snapshot['features'][2]
 build['state']='limited_lab_verified'
 build['summary']='Lab单次正常木箱建造成功：准确扣料、原生施工完成、用户确认可见可打开，保存已核验；通用建造写接口仍关闭。'
 build['verified_steps']=[
  '新操作只调用一次正常建造；同一游戏线程即时账本准确扣除15木材和5石头，其他已覆盖槽位当时不变。',
  '同一原生BuildWork需求1000，读取进度0、66.602、429.944、990.505，随后State1 Completed；未调用FinishWork。',
  '新箱模型、基地、公会、建造玩家和10格容器归属一致；用户明确确认看得到并能打开。',
  '在线保存中已核验新箱及原13箱的身份/容器链，佐伊固定分工仍在；新箱保存时含Wood17、CopperOre13、Fiber3。',
  '独立纯游戏线程只读诊断3轮通过后，本次建造使用无异步Lua业务回调的串行调度；没有改动JSON掩盖错误。']
 build['unverified_steps']=[
  '此次新箱尚未重启后再验证；保存成功不等于重载验收。',
  '通用、多建筑、失败补偿、远距离及离线建造尚未完成验收；公开建造写接口保持关闭。',
  '此前失败操作与凭据仍保留；串行调度实测成功不证明全部UE4SS共享VM问题已经根治。',
  '此快照未实时查询服务器健康，未将建造部署到正式服。']
 snapshot['summary']='本地验收证据快照，不是实时服务器状态。正式服整理已验证；Lab固定派工及单次正常木箱建造、客户端确认和保存核验通过；通用建造写接口仍关闭。'
 snapshot['features'][1]['verified_steps'].append('本次木箱完成后的新保存再次确认同一佐伊固定分工仍在。')
 snapshot['features'][1]['evidence_ids'].append('build_v4_saved')
if state.get('house_server_save_verified'):
 build=snapshot['features'][2]
 build['summary']='测试服已造出可用木箱和一间6部件小木屋；房屋远程建造、正常扣料及存档连接关系通过，正式服建造尚未部署。'
 build['verified_steps'].append('玩家位于基地外、距施工点约56至74米时完成地基、实墙、两面窗墙、门、屋顶；合计消耗12木材，6件均完成并保存。')
 build['verified_steps'].append('从自家基地箱子原生转移32木材到玩家背包，供远程正常扣料；地基、墙、屋顶的存档Connector相互引用。')
 build['unverified_steps']=[x for x in build['unverified_steps'] if '远距' not in x]
 if state.get('house_client_walkthrough_verified'):
  build['verified_steps'].append('用户确认小木屋外观、进门和站在地板上均正常。')
 build['unverified_steps'].append('全员离线建造尚未实现；本次没有重启测试服验证重载。')
 build['evidence_ids']+=['house_runtime','house_saved']
 snapshot['summary']='正式服箱子整理已验证；测试服已完成固定派工、正常木箱和远程小木屋建造，均有保存证据。'
if args.check_only:
 print(json.dumps({'validated':True,'written':False,'worker_restart_recorded':worker_restart,'limited_lab_build_verified':build_verified,'build_public_write_enabled':snapshot['features'][2]['recorded_public_write_enabled'],'evidence_ids':[e['id'] for e in evidence]},indent=2))
else:
 path=ROOT/'mcp/acceptance-status.json';path.write_text(json.dumps(snapshot,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(path)
