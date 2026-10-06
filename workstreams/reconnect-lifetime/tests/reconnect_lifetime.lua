-- One old UWorld -> Title -> new UWorld lifecycle. Reuses the existing Model
-- adapter/companion test boundary: real Lua modules, simulated UObjects/native IO.
local root,delta,tmp=assert(arg[1]),assert(arg[2]),assert(arg[3])..'/'
local raw_open,raw_lines,raw_rename,raw_remove=io.open,io.lines,os.rename,os.remove
local J=dofile(root..'/native_renderer/stable-v3/json.lua')
local script='D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/'
local server_script='D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'
local journal_root='D:/PalworldServer-LAN/BridgeLab/rpc/'
local bridge='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local journal='D:/PalworldServer-LAN/BridgeLab/rpc/palcraft-events.ndjson'
local checks=0;local function check(v,s)checks=checks+1;assert(v,s)end
local serial=0x8000;local objects,actors,components={},{},{}
local function object(name,address)
 serial=serial+1;local o={valid=true,name=name,address=address or serial}
 function o:IsValid()return self.valid end
 function o:GetAddress()return self.address end
 function o:GetFullName()return self.name end
 objects[o.address]=o;return o
end
local old_world,title_world,new_world=object('World old',1000),object('World Title',2000),object('World new',3000)
local old_context,title_context,new_context=object('PalGameStateInGame old',10),object('GameStateBase Title',20),object('PalGameStateInGame new',30)
old_context.world=old_world;title_context.world=title_world;new_context.world=new_world
for _,o in ipairs({old_context,title_context,new_context})do function o:GetWorld()return self.world end end
local current_context=old_context;local version=5;local adapter
local function path(p)
 if p==journal then return tmp..'events.ndjson'end
 if p:sub(1,#journal_root)==journal_root then return tmp..'server-journal/'..p:sub(#journal_root+1)end
 if p==script..'models.lua'then return delta..'/proposals/models/models_v'..version..'.lua'end
 if p:sub(1,#bridge)==bridge then return tmp..p:sub(#bridge+1)end
 return p
end
local function read(p)local f=assert(raw_open(path(p),'rb'));local s=f:read('*a');f:close();return s end
local function write(p,v)local f=assert(raw_open(path(p),'wb'));f:write(type(v)=='string'and v or J.encode(v));f:close()end
local env=setmetatable({},{__index=_G});env._G=env
env.io=setmetatable({open=function(p,m)return raw_open(path(p),m)end,lines=function(p,...)
 if p:find('UE4SS.log',1,true)then local done=false;return function()if not done then done=true;return'ProcessEvent address 0x13'end end end
 return raw_lines(path(p),...)
end},{__index=io})
env.os=setmetatable({rename=function(a,b)return raw_rename(path(a),path(b))end,remove=function(p)return raw_remove(path(p))end},{__index=os})
env.IsInGameThread=function()return true end;env.FName=function(v)return v end
local callbacks={};env.ExecuteInGameThreadWithDelay=function(_,fn)callbacks[#callbacks+1]=fn end
env.FindAllOf=function(name)
 if name=='GameStateBase'then return current_context and current_context:IsValid()and{current_context}or{}end
 if name=='Actor'then return actors end
 if name=='ProceduralMeshComponent'then return components end
 return{}
end
local functions={}
env.StaticFindObject=function(name)
 functions[name]=functions[name]or object(name);return functions[name]
end
env.LoadAsset=function(name)return object(name)end
local native_records={[5]={},[6]={}};local actions,destroyed,order={},{},{};local owned_boxes={};local server_box_destroyed=0
local native_serial={[5]=0,[6]=0}
env.package={loadlib=function(library,symbol)
 if symbol=='palcraft_spawn_box'then return function()
  local fields={string.unpack('<c8I8I8I8I8I8dddI8I8I8',read(journal_root..'palcraft-spawn-request.bin'))}
  check(fields[1]=='PALCMSH6'and fields[2]==new_context.address,'Actual shared server companion collision wire/context')
  local action,actor=fields[10],fields[11]
  if action==1 then
   check(owned_boxes[actor]==new_context.address,'Server destroys only its own live collision Actor')
   owned_boxes[actor]=nil;destroyed[actor]=true;server_box_destroyed=server_box_destroyed+1
  else
   check(action==0,'Server fixture creates one original collision Actor')
   actor=object('TriggerBox fixture owned').address;owned_boxes[actor]=new_context.address
  end
  write(journal_root..'palcraft-spawn-result.json',{ok=true,actor=actor,stage='configured'})
 end end
 local abi=assert(tonumber(library:match('PalCraftModel%-v([56])%.dll')),'Only the actual Model5/6 lifetime DLL interfaces')
 if symbol=='palcraft_create_model'then return function()
  local h={string.unpack('<c8'..string.rep('I8',18)..'dddI4I4',read(bridge..'model-request.bin'))}
  check(h[1]==(abi==5 and'PALCPRC4'or'PALCPRC6'),'Actual versioned Model create wire')
  local a=object('Owned procedural Actor');a.owner=objects[h[2]];a.hidden=(h[24]&1)~=0
  function a:GetOwner()return self.owner end
  function a:SetActorHiddenInGame(v)self.hidden=v end
  function a:K2_SetActorLocation(p)self.position=p end
  function a:K2_SetActorRotation(r)self.rotation=r end
  local c=object('Owned procedural mesh');c.owner=a;function c:GetOwner()return self.owner end
  actors[#actors+1]=a;components[#components+1]=c;native_serial[abi]=native_serial[abi]+1
  native_records[abi][a.address]={context=h[2],component=c.address,id=native_serial[abi]}
  write(bridge..'model-result.json',{ok=true,actor=a.address,component=c.address,native_id=native_serial[abi],stage='created'})
 end end
 if symbol=='palcraft_update_model'then return function()error('This directed lifetime case never updates geometry')end end
 if symbol=='palcraft_release_model'then return function()
  local w={string.unpack('<c8I8I8I8I8I8I8I4I4',read(bridge..'model-release-request.bin'))}
  check(w[1]=='PALCREL1','Actual native lifetime release wire')
  local action=w[8];actions[#actions+1]={abi=abi,context=w[2],actor=w[3],action=action};order[#order+1]='native:'..action
  if action==2 then
   for a,r in pairs(native_records[abi])do if r.context==w[2]then native_records[abi][a]=nil end end
   write(bridge..'model-result.json',{ok=true,stage='abandoned'});return
  end
  local r=native_records[abi][w[3]]
  check(r and r.context==w[2]and r.component==w[4]and r.id==w[5],'Only an exact owned native lifetime may release')
  if action==1 then
   check(objects[w[3]].owner:IsValid()and objects[w[3]].owner.world:IsValid(),'Destroy is confined to its still-live bound world')
   destroyed[w[3]]=true;objects[w[3]].valid=false;objects[w[4]].valid=false
  end
  native_records[abi][w[3]]=nil;write(bridge..'model-result.json',{ok=true,stage=action==1 and'destroyed'or'released'})
 end end
 error('Unknown native lifetime operation '..symbol)
end}
local source_hash_inputs={}
local function module(source,logical)
 local f=assert(raw_open(source,'rb'));local raw=f:read('*a');f:close();source_hash_inputs[#source_hash_inputs+1]=source
 return assert(load(raw,'@'..logical,'t',env))()
end
env.dofile=function(p)
 if p==script..'json.lua'or p==server_script..'json.lua'then return J end
 if p==script..'models.lua'then
  if not adapter then adapter=module(delta..'/proposals/models/models_v'..version..'.lua',p)end
  return adapter
 end
 if p==script..'world_compat.lua'or p==server_script..'world_compat.lua'then return module(root..'/palcraft/server/world_compat.lua',p)end
 if p==script..'model_geometry_v2.lua'then return module(root..'/native_renderer/stable-v3/model_geometry_v2.lua',p)end
 if p==script..'runtime/paths.lua'then return module(root..'/native_renderer/capture-increment/runtime/paths.lua',p)end
 error('Unexpected actual dependency '..p)
end
write(journal,'');write(bridge..'world-origin.json',{X=0,Y=0,Z=0})
local groups={{texture='minecraft:block/oak_planks',alpha_mode='opaque',tint=-1,
 vertices={{0,0,0,0,0,1,0,0},{100,0,0,0,0,1,1,0},{100,100,0,0,0,1,1,1},{0,100,0,0,0,1,0,1}},indices={0,2,1,0,3,2}}}
local origin={X=0,Y=0,Z=0}
local material=object('Lifetime fixture material')
local function companion()
 local c=module(delta..'/proposals/client/palcraft-collisions.lua',script..'palcraft-collisions.lua')
 local timer=table.remove(callbacks);timer();check(c.running and not c.error,tostring(c.error))
 c.models.set_material_provider(function()return material end)
 return c
end
local function legacy(c)
 local a,b=c.models.spawn_groups(current_context,origin,groups,{5,64,-14})
 c.actors['5:64:-14']={model=a,model_component=b,at={5,64,-14},handles={},id='minecraft:oak_planks',dim='minecraft:overworld',visible=true}
 return a
end
local function prepared(models,ctx,generation)
 return models.prepare(ctx,origin,{groups=groups,at={6,64,-14},revision=1,generation=generation,
  fence={world_session='fixture-scope',dim='minecraft:overworld',view=1,mapping='actual-world-origin'}})
end
-- Execute the actual ReloadCollisions source block, retaining its closure order.
local function reload(c,reset_generation)
 local f=assert(raw_open(delta..'/proposals/client/main.lua','rb'));local s=f:read('*a');f:close()
 local first=assert(s:find('local feature_reset_error',1,true));local last=assert(s:find('local function publish',first,true))
 local real=s:sub(first,last-1)
 local reset_calls=0;local reload_env=setmetatable({_G={}}, {__index=env})
 reload_env.fixture_companion=c;reload_env.fixture_view={reset=function(_,alive)order[#order+1]='view:'..tostring(alive);return true end}
 reload_env.fixture_features={reset=function(_,_,ctx)
  reset_calls=reset_calls+1;order[#order+1]='features:'..tostring(ctx.context_alive)
  c.models.reset(reset_generation,ctx.context_alive);return true
 end}
 local prelude='local collisions=fixture_companion;local features=fixture_features;local client_view=fixture_view;local session="fixture";'
 assert(load(prelude..real,'@'..script..'main.lua','t',reload_env))()
 return reload_env._G.PalCraftReloadCollisions,function()return reset_calls end
end
local c=companion();local raw=legacy(c);local Models5=c.models
check(c.context_alive()==true and Models5.version==5,'Actual old-world Model5 companion owns its live context')
local transaction=prepared(Models5,old_context,1)
Models5.reset(2,true)
check(destroyed[transaction.actor]and not destroyed[raw],'Live adapter reset releases only its transaction handles')
check(pcall(Models5.set_visible,raw,true),'Legacy lifetime remains owned after live Models reset')
-- An alive foreign Actor must fail BEFORE feature reset; it is never destroyed.
local owned_entries=c.actors;c.actors={['unknown:alive']={model=0xdeadc0de,at={5,64,-14},handles={}}}
local live_reload,reset_calls=reload(c,3);local okay,err=pcall(live_reload)
check(not okay and tostring(err):find('Native model lifetime is not owned by this renderer',1,true),'Unknown live lifetime remains an actionable error')
check(reset_calls()==0 and not destroyed[0xdeadc0de],'Failed live cleanup cannot erase ownership or destroy an unknown Actor')
c.actors=owned_entries;c.running=true
live_reload=reload(c,3);check(live_reload()=='collision_and_model_replay_queued','Normal live reload completes')
check(destroyed[raw]and not next(c.actors),'Known live legacy model retires normally before shared reset')
local native_destroy,feature_reset
for index,value in ipairs(order)do if value=='native:1'then native_destroy=index elseif value=='features:true'then feature_reset=index end end
check(native_destroy and feature_reset and native_destroy<feature_reset,'Actual reload source retires companion before feature-owned Models reset')
-- Reload an old-world companion, retain both raw and transaction bookkeeping,
-- then enter Title in the same process. No old UObject remains valid.
c=companion();raw=legacy(c);transaction=prepared(Models5,old_context,3)
c.queue={{'set',5,64,-14}};c.queued={old=true};c.pending='partial old-world journal record';c.queue_head=1
c.items={old={actor=object('Dead-world drop')}}
local drop=c.items.old.actor;function drop:K2_DestroyActor()error('Dead-world cleanup must never destroy a drop')end
old_context.valid=false;old_world.valid=false;current_context=title_context
check(c.context_alive()==false,'Actual bound GameState/UWorld rejects Title context')
local dead_reload=reload(c,4);check(dead_reload()=='collision_and_model_replay_queued','Old-world ReloadCollisions uses the normal dead-world branch')
check(not destroyed[raw]and not destroyed[transaction.actor],'Dead-world abandon never calls DestroyActor')
check(not next(native_records[5]),'Actual Model5 abandon action removes native context records')
check(not next(c.actors)and not next(c.items)and not next(c.queue)and not next(c.queued)and c.pending==''and c.queue_head==1,'Dead-world companion clears legacy/drop/queue/partial bookkeeping')
check(c.abandoned and not c.running and not c.context_alive(),'Old companion cannot resume on new-world callbacks')
check(not pcall(Models5.unload,transaction),'Old transaction handle no longer belongs to the abandoned adapter')
-- The same Model5 instance can prepare the new world: abandon also cleared
-- world_context and handles. Then a fresh Model6 companion performs a real join.
current_context=new_context
local reuse=prepared(Models5,new_context,4);check(reuse.world==new_context.address,'Dead-world adapter abandons its old world_context')
Models5.unload(reuse)
version=6;adapter=nil;c=companion();local Models6=c.models;local fresh=legacy(c)
check(Models6.version==6 and c.context_alive()and native_records[6][fresh].context==new_context.address,'Fresh Model6 binds only the real new UWorld context')
check(not next(native_records[5]),'Model5 records do not cross into the new Model6 adapter')
local raw6=prepared(Models6,new_context,1);Models6.reset(2,true)
check(destroyed[raw6.actor]and pcall(Models6.set_visible,fresh,true),'Model6 preserves raw ownership on the same live reset contract')
local new_reload=reload(c,3);check(new_reload()=='collision_and_model_replay_queued','New-world live cleanup remains normal')
check(destroyed[fresh]and not next(native_records[6]),'Fresh Model6 cleanup destroys only its own live record')
-- This companion source is also shipped to BridgeLab. Its normal server stop
-- must retain the original live retirement path even without client bindings.
write(journal,J.encode({t='blocks',v=2,session='fixture-server',seq=1,dim='minecraft:overworld',ops={{op='upsert',at={5,64,-14},
 id='minecraft:oak_planks',state='Block{minecraft:oak_planks}',boxes={{0,0,0,1,1,1}},solid=true,visible=true,render_kind='block',fluid={kind='none'}}}})..'\n')
local server=module(delta..'/proposals/client/palcraft-collisions.lua',server_script..'palcraft-server.lua')
table.remove(callbacks)();check(server.running and not server.error,tostring(server.error))
check(server.models==nil and server.status().side=='server'and server.status().shapes==1,'Actual shared server reducer creates its owned collision Actor')
server.stop()
check(server_box_destroyed==1 and not next(owned_boxes)and not next(server.actors),'Server normal stop retires its actual owned collision Actor')
print(J.encode({status='passed',checks=checks,fixture='one old UWorld -> Title -> new UWorld lifecycle',actual_sources=source_hash_inputs,
 actual_reload_block=true,models5_and6_actual_lua=true,live_unknown_actor_error_preserved=true,dead_world_native_action=2,
 unknown_actors_destroyed=0,old_bookkeeping_cleared=true,new_adapter_context_clean=true,shared_server_live_stop_preserved=true,
 engine_boundary='simulated UObjects and existing native entrypoints',GUI_calls=0,RPC_calls=0,services_started=0,Java_builds=0,old_matrices_repeated=false}))
