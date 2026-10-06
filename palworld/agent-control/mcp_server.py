"""MCP stdio tools for the persistent autonomous BridgeLab agent."""
import json,sys
from client import call

UUID={'type':'string','pattern':'^[0-9a-f-]{36}$'}
def obj(properties,required=()):return {'type':'object','properties':properties,'required':list(required),'additionalProperties':False}
VECTOR=obj({k:{'type':'number'} for k in ['X','Y','Z']},['X','Y','Z'])
ROTATION=obj({k:{'type':'number'} for k in ['Pitch','Yaw','Roll']},['Pitch','Yaw','Roll'])
QUATERNION=obj({k:{'type':'number'} for k in ['X','Y','Z','W']},['X','Y','Z','W'])
TOOLS={
 'palworld_ai_status':('status','Read the live autonomous agent status; production is never targeted.',obj({}),True),
 'palworld_ai_bases':('bases','List current bases, names, levels, positions and registered building counts.',obj({}),True),
 'palworld_ai_storage':('storage','Discover and read ordinary storage chests in a base, including newly built chests.',obj({'base_id':UUID,'container_ids':{'type':'array','items':UUID}},['base_id']),True),
 'palworld_ai_storage_plan':('storage_plan','Plan merging identical ordinary stacks and organizing storage by category.',obj({'base_id':UUID,'container_ids':{'type':'array','items':UUID},'policy':{'type':'string','enum':['category','item_type']}},['base_id']),True),
 'palworld_ai_storage_apply':('storage_apply','Apply a current storage plan live without restarting the server. Uses native item transfers and durable operation journals.',obj({'request_id':UUID,'plan_id':UUID,'expected_revision':UUID,'idempotency_key':UUID},['plan_id','expected_revision','idempotency_key']),False),
 'palworld_ai_storage_operation':('storage_operation','Read a storage operation by the request_id returned from storage apply.',obj({'request_id':UUID},['request_id']),True),
 'palworld_ai_catalog':('catalog','List actual building technology and recipes for a saved account; no online character needed.',obj({'player_uid':UUID,'filter':{'type':'string'}},['player_uid']),True),
 'palworld_ai_build':('build','Build using a saved account and guild. Survival consumes actual base materials; creative consumes no materials and completes construction immediately. Returns an operation ID; survival retains normal Pal construction work.',obj({'request_id':UUID,'mode':{'type':'string','enum':['survival','creative']},'player_uid':UUID,'guild_id':UUID,'base_id':UUID,'build_id':{'type':'string'},'position':VECTOR,'rotation':ROTATION,'support_model_id':UUID},['mode','player_uid','guild_id','base_id','build_id','position','rotation']),False),
 'palworld_ai_operation':('operation','Inspect the same construction operation ID after a timeout; never create a new ID to retry an unknown mutation.',obj({'id':UUID},['id']),True),
 'palworld_ai_models':('models','Read current registered building identities, ownership, placement and completion.',obj({'ids':{'type':'array','items':UUID}},['ids']),True),
 'palworld_ai_dismantle':('dismantle','Remove specified buildings owned by the selected saved player and guild in BridgeLab.',obj({'ids':{'type':'array','items':UUID},'player_uid':UUID,'guild_id':UUID},['ids','player_uid','guild_id']),False),
 'palworld_ai_geometry':('geometry','Capture actual live mesh-component transforms and original mesh asset references for external modeling.',obj({'ids':{'type':'array','items':UUID}},['ids']),True),
 'palworld_ai_finish':('finish','Complete existing owned construction in creative mode without consuming materials.',obj({'request_id':UUID,'mode':{'type':'string','enum':['creative']},'ids':{'type':'array','items':UUID},'player_uid':UUID,'guild_id':UUID},['mode','ids','player_uid','guild_id']),False),
 'palworld_ai_transform':('transform','Move and scale an existing owned building in creative mode. Edits its live actor and saved transform; survival construction uses standard transforms.',obj({'request_id':UUID,'mode':{'type':'string','enum':['creative']},'id':UUID,'player_uid':UUID,'guild_id':UUID,'position':VECTOR,'scale':VECTOR,'quaternion':QUATERNION},['mode','id','player_uid','guild_id','position','scale']),False),
 'palworld_ai_terrain':('terrain','Read terrain height beneath selected world coordinates.',obj({'points':{'type':'array','items':obj({'X':{'type':'number'},'Y':{'type':'number'},'local_x':{'type':'number'},'local_y':{'type':'number'}},['X','Y'])}},['points']),True)
}
def answer(req):
 method=req.get('method');params=req.get('params',{})
 if method=='initialize':return {'protocolVersion':params.get('protocolVersion','2025-06-18'),'capabilities':{'tools':{}},'serverInfo':{'name':'Palworld-Autonomous-BridgeLab','version':'0.3'}}
 if method=='tools/list':return {'tools':[{'name':name,'description':t[1],'inputSchema':t[2],'annotations':{'readOnlyHint':t[3],'destructiveHint':not t[3]}} for name,t in TOOLS.items()]}
 if method=='tools/call':
  name=params['name'];spec=TOOLS[name]
  try:
   arguments=dict(params.get('arguments',{}));request_id=arguments.pop('request_id',None) if spec[0]!='storage_operation' else None;result=call(spec[0],arguments,request_id);return {'content':[{'type':'text','text':json.dumps(result,ensure_ascii=False)}],'structuredContent':result}
  except Exception as e:return {'content':[{'type':'text','text':str(e)}],'isError':True}
 if method=='ping':return {}
 raise ValueError('Unsupported MCP method '+str(method))
for line in sys.stdin:
 try:
  req=json.loads(line)
  if 'id' not in req:continue
  try:result={'jsonrpc':'2.0','id':req['id'],'result':answer(req)}
  except Exception as e:result={'jsonrpc':'2.0','id':req['id'],'error':{'code':-32603,'message':str(e)}}
  print(json.dumps(result,ensure_ascii=False),flush=True)
 except ValueError:pass
