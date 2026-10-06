#!/usr/bin/env python3
"""PalCraft stdio MCP: actual Minecraft survival input inside BridgeLab."""
import json,sys
import ai_tools
import mc_transport

def schema(p,required=()):
 return {'type':'object','properties':p,'required':list(required),'additionalProperties':False}
TOOLS=[
 {'name':'palcraft_block','description':'Read a Minecraft block, its neighbors and actual container inventory from the world server.','inputSchema':schema({k:{'type':'integer','minimum':-30000000,'maximum':30000000} for k in ('x','y','z')},['x','y','z'])},
 {'name':'palcraft_inspect','description':'Read actual Minecraft player identity, survival mode, inventory and aimed block.','inputSchema':schema({})},
 {'name':'palcraft_collisions','description':'Start, stop or inspect the BridgeLab native collision companion.','inputSchema':schema({'action':{'type':'string','enum':['start','stop','status']}},['action'])},
 {'name':'palcraft_status','description':'Read BridgeLab fusion status and both server task states.','inputSchema':schema({})},
 {'name':'palcraft_blocks','description':'Read real Minecraft solid block positions around the synchronized player.','inputSchema':schema({'radius':{'type':'integer','minimum':1,'maximum':64}})},
 {'name':'palcraft_action','description':'Perform vanilla Minecraft survival input. This never issues creative commands or grants items.','inputSchema':schema({'key':{'type':'string','enum':['attack','use','pick','drop','swap','inventory','escape']},'duration_ms':{'type':'integer','minimum':1,'maximum':5000}},['key'])},
 {'name':'palcraft_slot','description':'Select a Minecraft inventory slot (0 through 8).','inputSchema':schema({'slot':{'type':'integer','minimum':0,'maximum':8}},['slot'])},
 {'name':'palcraft_hud','description':'Show or hide the Minecraft HUD overlay.','inputSchema':schema({'hidden':{'type':'boolean'}},['hidden'])},
]
for tool in TOOLS:
 tool['inputSchema']['properties']['request_id']={'type':'string','format':'uuid','description':'Reuse this ID to inspect a pending outcome; never retry a mutation with a new ID.'}

def invoke(name,a):
 t=next((t for t in TOOLS if t['name']==name),None)
 if not t:raise ValueError('Unknown tool')
 s=t['inputSchema']
 if set(a)-set(s['properties']) or set(s['required'])-set(a):raise ValueError('Invalid arguments')
 for k,v in a.items():
  p=s['properties'][k]
  if p['type']=='integer' and (type(v)!=int or not p['minimum']<=v<=p['maximum']):raise ValueError(k+' outside range')
  if p['type']=='boolean' and type(v)!=bool:raise ValueError(k+' must be boolean')
  if 'enum' in p and v not in p['enum']:raise ValueError('Invalid '+k)
 operation_id=a.get('request_id')
 if operation_id is not None:mc_transport.request_id(operation_id)
 q={'method':name.removeprefix('palcraft_'),**{k:v for k,v in a.items()if k!='request_id'}}
 if q['method']=='blocks':q.setdefault('radius',32)
 if q['method']=='action':q.setdefault('duration_ms',200)
 return mc_transport.call(q,operation_id)

def dispatch(q):
 m=q['method'];p=q.get('params',{})
 if m=='initialize':return {'protocolVersion':p.get('protocolVersion','2025-06-18'),'capabilities':{'tools':{}},'serverInfo':{'name':'palcraft-bridgelab','version':'0.2.0'}}
 if m=='ping':return {}
 if m=='tools/list':return {'tools':TOOLS+ai_tools.answer(q)['tools']}
 if m=='tools/call':
  if p['name'].startswith('palworld_ai_'):return ai_tools.answer(q)
  try:r=invoke(p['name'],p.get('arguments',{}));return {'content':[{'type':'text','text':json.dumps(r,ensure_ascii=False)}],'isError':False}
  except Exception as e:return {'content':[{'type':'text','text':str(e)}],'isError':True}
 raise ValueError('Unknown MCP method')

if __name__=='__main__':
 for line in sys.stdin:
  q=json.loads(line)
  if 'id' not in q:continue
  try:o={'jsonrpc':'2.0','id':q['id'],'result':dispatch(q)}
  except Exception as e:o={'jsonrpc':'2.0','id':q['id'],'error':{'code':-32603,'message':str(e)}}
  print(json.dumps(o,ensure_ascii=False),flush=True)
