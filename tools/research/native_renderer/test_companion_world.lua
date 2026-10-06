local root=assert(arg[1]);local tmp=assert(arg[2])..'/'
local real_open,real_dofile,real_lines=io.open,dofile,io.lines
local J=real_dofile(root..'/native_renderer/stable-v3/json.lua')
local World=real_dofile(root..'/palcraft/server/world_compat.lua')
local calls,callbacks={},{};local actor=0x5000;local models={version=4}
function models.spawn(_,_,g)calls[#calls+1]={kind='model',id=g.id,boxes=#g.boxes};actor=actor+1;return actor,actor+1000 end
function models.status()return{version=4,stats={}}end
local script='D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/'
local shared='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local journal='D:/PalworldServer-LAN/BridgeLab/rpc/palcraft-events.ndjson'
local function mapped(p)
 if p==journal then return tmp..'world-events.ndjson'end
 if p==script..'models.lua'then return root..'/palcraft/client/models.lua'end
 if p:sub(1,#shared)==shared then return tmp..p:sub(#shared+1)end
 return p
end
local ctx={IsValid=function()return true end,GetFullName=function()return'PalGameStateInGame live'end,GetAddress=function()return 10 end}
local env=setmetatable({},{__index=_G});env._G=env
local io_mock=setmetatable({},{__index=io})
io_mock.open=function(p,m)return real_open(mapped(p),m)end
io_mock.lines=function()local done=false;return function()if not done then done=true;return'ProcessEvent address 0x13'end end end
env.io=io_mock
local function append(v)local f=assert(real_open(tmp..'world-events.ndjson','ab'));f:write(J.encode(v)..'\n');f:close()end
local function block(x,id,boxes,extra)
 local g={op='upsert',at={x,64,-10},id=id,state='Block{'..id..'}',boxes=boxes,solid=#boxes>0,visible=true,render_kind='block',fluid={kind='none'}}
 for k,v in pairs(extra or{})do g[k]=v end;return g
end
local function event(seq,ops,life)return{t='blocks',v=2,session='world-A',seq=seq,dim='minecraft:overworld',ops=ops or{},lifecycle=life}end
local f=assert(real_open(tmp..'world-events.ndjson','wb'));f:close()
append(event(1,{block(-5,'minecraft:oak_button',{})}))
append(event(2,{block(-4,'minecraft:oak_planks',{{0,0,0,1,1,1}})}))
append(event(3,{block(-3,'minecraft:water',{}, {solid=false,fluid={kind='water',height=1,own_height=1}})}))
append(event(4,{block(-5,'minecraft:oak_button',{}, {state='powered=true'})}))
env.dofile=function(p)
 if p==script..'json.lua'then return J end
 if p==script..'models.lua'then return models end
 if p==script..'world_compat.lua'then return World end
 error('Unexpected module '..p)
end
env.FindAllOf=function(name)if name=='GameStateBase'then return{ctx}end;return{}end
env.StaticFindObject=function(name)return{IsValid=function()return true end,GetAddress=function()return 20 end}end
env.LoadAsset=function()return{IsValid=function()return true end,GetAddress=function()return 100 end}end
env.ExecuteInGameThreadWithDelay=function(_,callback)callbacks[#callbacks+1]=callback end
env.package={loadlib=function(_,symbol)
 assert(symbol=='palcraft_spawn_box')
 return function()
  local f=assert(io_mock.open(shared..'palcraft-spawn-request.bin','rb'));local raw=f:read('*a');f:close()
  local fields={string.unpack('<c8I8I8I8I8I8dddI8I8I8',raw)}
  assert(fields[1]=='PALCMSH6');local action=fields[10]
  calls[#calls+1]={kind='collision',action=action};actor=actor+1
  f=assert(io_mock.open(shared..'palcraft-spawn-result.json','wb'));f:write(J.encode({ok=true,actor=('0x%x'):format(actor),stage='configured'}));f:close()
 end
end}
local source=assert(real_open(root..'/palcraft/server/main.lua')):read('*a')
local companion=assert(load(source,'@'..script..'palcraft-collisions.lua','t',env))()
local rows,lifecycle,ticks=0,0,0
companion.set_world_observer({on_row=function(_,accepted)assert(accepted);rows=rows+1 end,on_lifecycle=function(e,row)assert(e and row);lifecycle=lifecycle+1 end,tick=function()ticks=ticks+1 end})
local function step()assert(#callbacks>0);local next=table.remove(callbacks,1);next()end
step();assert(companion.running and not companion.error,companion.error);assert(rows==4 and ticks==1)
assert(companion.status().blocks==3 and companion.status().models==3 and companion.status().shapes==1)
assert(companion.status().pending==0 and #calls==4,'Coalescing must render only final three blocks plus one solid collider')
assert(#companion.actors['-5:64:-10'].handles==0 and companion.actors['-5:64:-10'].model)
assert(#companion.actors['-3:64:-10'].handles==0,'Fluid must not become a full cube collider')
step();assert(companion.running and not companion.error and #calls==4,'EOF must not stop world reader')
append(event(5,{},{{op='snapshot_begin',snapshot='snap',at={-1,-1},bounds={-16,0,-16,0,128,0},replace=true}}))
append(event(6,{block(-2,'minecraft:oak_button',{}, {snapshot='snap'})}))
step();assert(companion.status().blocks==3,'Partial snapshot must remain unpublished')
append(event(7,{},{{op='snapshot_end',snapshot='snap',at={-1,-1},bounds={-16,0,-16,0,128,0}}}))
step();assert(companion.running and companion.status().blocks==1 and companion.actors['-2:64:-10'])
append({t='blocks',set={-12,64,-10},clear={},geometry={}});step();assert(companion.status().blocks==1,'Legacy must not overwrite authoritative v2')
append(event(8,{},{{op='player_view',player='mc-player',to='minecraft:the_nether',view=4}}));step();assert(companion.pending_view and companion.world:status().dimension=='minecraft:overworld')
assert(lifecycle>=4 and ticks==6)
print(J.encode({ok=true,checks=16,coalesced_final_states=true,non_solid_zero_collision=true,fluid_zero_collision=true,snapshot_atomic=true,legacy_after_v2_ignored=true,eof_continues=true,single_reader_hooks=true,view_requires_host_ack=true}))
