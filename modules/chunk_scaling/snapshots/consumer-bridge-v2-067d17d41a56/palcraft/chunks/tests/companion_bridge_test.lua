-- Small migration boundary check using the actual companion, reducer, geometry,
-- scheduler, view facade and bridge. Only native engine objects are simulated.
local T=dofile('/path/to/workspace/work/minecraft-fusion/palcraft/chunks/tests/support.lua')
local root=T.root;local tmp=root..'chunk_scaling/companion-bridge-test/';local J=T.J
local checks=0;local function check(v,s)checks=checks+1;assert(v,s)end
local calls,callbacks={},{};local serial=0x50000;local model_live={};local models={capabilities={opaque=true,dynamic=true,animation=true}}
function models.spawn(_,_,g)serial=serial+1;model_live[serial]='legacy';calls[#calls+1]='legacy_spawn';return serial,serial+1000 end
function models.status()return{version=5,generation=1,stats={}}end
function models.release_model(actor)check(model_live[actor]~=nil,'Only release known model');model_live[actor]=nil;return true end
function models.block_event(e)calls[#calls+1]='block_event'end
function models.prepare(_,_,p)serial=serial+1;local h={actor=serial,component=serial+1000,revision=p.revision,generation=p.generation,fence=p.fence,state='prepared'};model_live[serial]=h;return h end
function models.prepare_block(ctx,origin,e,p)local h=models.prepare(ctx,origin,{revision=p.revision,generation=p.generation,fence=p.fence});calls[#calls+1]='dynamic_prepare';return h end
function models.commit_transaction(new,old,collision)
 for _,h in ipairs(new)do check(h.state=='prepared','All replacement models initially hidden')end
 if collision then collision.adapter.preflight(collision.prepared,collision.previous);collision.adapter.commit(collision.prepared,collision.previous)end
 for _,h in ipairs(new)do h.state='active'end;for _,h in ipairs(old)do models.release_model(h.actor);h.state='released'end
 calls[#calls+1]='chunk_commit';return true
end
function models.discard(h)models.release_model(h.actor)end
models.unload=models.discard;function models.reset()end
local script='D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/'
local shared='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local journal='D:/PalworldServer-LAN/BridgeLab/rpc/palcraft-events.ndjson'
local function mapped(p)
 if p==journal then return tmp..'world-events.ndjson'end
 if p==script..'models.lua'then return root..'palcraft/client/models.lua'end
 if p:sub(1,#shared)==shared then return tmp..p:sub(#shared+1)end
 return p
end
local ctx={IsValid=function()return true end,GetFullName=function()return'PalGameStateInGame'end,GetAddress=function()return 10 end}
local env=setmetatable({},{__index=_G});env._G=env
env.io=setmetatable({open=function(p,m)return io.open(mapped(p),m)end,lines=function()local done=false;return function()if not done then done=true;return'ProcessEvent address 0x13'end end end},{__index=io})
env.dofile=function(p)
 if p==script..'json.lua'then return J end
 if p==script..'models.lua'then return models end
 if p==script..'world_compat.lua'then return dofile(root..'palcraft/server/world_compat.lua')end
 error('Unexpected companion dependency '..p)
end
env.FindAllOf=function(n)return n=='GameStateBase'and{ctx}or{}end
env.StaticFindObject=function()return{IsValid=function()return true end,GetAddress=function()return 20 end}end
env.LoadAsset=function()return{IsValid=function()return true end,GetAddress=function()return 100 end}end
env.ExecuteInGameThreadWithDelay=function(_,fn)callbacks[#callbacks+1]=fn end
env.package={loadlib=function(_,symbol)
 check(symbol=='palcraft_spawn_box','Only legacy collision DLL is simulated')
 return function()
  local f=assert(env.io.open(shared..'palcraft-spawn-request.bin','rb'));local bytes=f:read('*a');f:close()
  local fields={string.unpack('<c8I8I8I8I8I8dddI8I8I8',bytes)};local action=fields[10]
  calls[#calls+1]=action==1 and'legacy_destroy'or'legacy_collision_spawn';serial=serial+1
  f=assert(env.io.open(shared..'palcraft-spawn-result.json','wb'));f:write(J.encode({ok=true,actor=string.format('0x%x',serial),stage='configured'}));f:close()
 end
end}
local f=assert(io.open(tmp..'world-events.ndjson','wb'));f:close()
local seq=0;local function append(ops,life)
 seq=seq+1;local row={t='blocks',v=2,session='world-A',seq=seq,dim='minecraft:overworld',ops=ops or{},lifecycle=life or{}}
 local file=assert(io.open(tmp..'world-events.ndjson','ab'));file:write(J.encode(row)..'\n');file:close();return row
end
local b=T.block(0,64,0);b.op='upsert';b.solid=true;b.visible=true;b.render_kind='block';b.fluid={kind='none'}
local bounds={0,64,0,16,80,16}
append({},{{op='snapshot_begin',snapshot='initial',at={0,0},bounds=bounds,replace=true}})
local sb=T.G.clone(b);sb.snapshot='initial';local b1=T.G.clone(sb);b1.at={1,64,0};local b2=T.G.clone(sb);b2.at={2,64,0};append({sb,b1,b2})
append({},{{op='snapshot_end',snapshot='initial',at={0,0},bounds=bounds}})
f=assert(io.open(root..'palcraft/server/main.lua','rb'));local source=f:read('*a');f:close()
local companion=assert(load(source,'@'..script..'palcraft-collisions.lua','t',env))()
local observers=0;companion.set_world_observer({on_row=function()observers=observers+1 end})
local function step()check(#callbacks>0,'Only existing companion timer drives work');table.remove(callbacks,1)();check(companion.running and not companion.error,tostring(companion.error))end
step();local legacy=assert(companion.actors['0:64:0']);local legacy_model=legacy.model
check(#legacy.handles==1 and model_live[legacy_model]=='legacy','Existing world is populated before install')
local collision={};local collider_live={}
function collision.prepare(_,_,p)serial=serial+1;local h={actor=serial,revision=p.revision,generation=p.generation};collider_live[serial]=h;return h end
function collision.preflight()end
function collision.commit(new,old)for _,h in ipairs(new)do h.active=true end;for _,h in ipairs(old)do collider_live[h.actor]=nil end end
function collision.unload(list)for _,h in ipairs(list or{})do collider_live[h.actor]=nil end end
collision.discard=collision.unload;function collision.reset()end
local adapter=dofile(root..'palcraft/client/chunk_adapter.lua').new{models=models,collision=collision,visual_verified=true,collision_verified=true}
local views=dofile(root..'palcraft/client/chunk_views.lua').new{geometry=T.geometry,adapter=adapter,context=function()return ctx end,session='world-A'}
local Bridge=dofile(root..'palcraft/client/companion_chunk_bridge.lua')
local bridge=Bridge.new{companion=companion,views=views,geometry=T.geometry,models=models,json=J,collision=collision,frame_steps=4,seed_blocks_per_tick=1}
local req={world_session='world-A',dim='minecraft:overworld',view=1,required_bounds=bounds,
 mapping={region_id='home',world_session='world-A',dim='minecraft:overworld',origin=T.G.clone(companion.origin),mc_anchor={0,64,0},window_size=656,page_size=512}}
local ticket=bridge:prepare_view(req);bridge:install()
check(companion.chunk_consumer==bridge.binding and companion.actors['0:64:0']==legacy,'Install hooks actually select consumer without clearing old actors')
step();check(bridge.stats.commits==0 and companion.actors['1:64:0']and companion.actors['2:64:0'],'Partial reducer bootstrap cannot commit and retire unseeded old blocks')
step();check(bridge.stats.commits==0,'Full authoritative bootstrap must finish before native preparation starts')
local original=companion.retire_legacy;local fail=true
companion.retire_legacy=function(...)
 if fail then return{ok=false,remaining={'0:64:0'},errors={'Injected old cleanup rejection'}}end
 return original(...)
end
local count=0;while bridge.stats.commits==0 do count=count+1;check(count<100,'Bounded migration completes');step();if bridge.stats.commits==0 then check(model_live[legacy_model]~=nil,'Legacy remains solid/visible throughout hidden preparation')end end
check(model_live[legacy_model]~=nil and not bridge:readiness(ticket).ready,'Postcommit cleanup failure retains both old handles and committed replacement')
check(not bridge:can_recycle('home'),'Outstanding old native resources prevent physical slot recycle')
local committed_models=0;for _,h in pairs(model_live)do if type(h)=='table'and h.state=='active'then committed_models=committed_models+1 end end
check(committed_models==1,'A failed old cleanup does not discard the committed new model')
fail=false;step();check(not companion.actors['0:64:0']and not model_live[legacy_model]and bridge:readiness(ticket).ready,'Old section retired only after replacement commit and successful retry')
bridge:activate(ticket)
local previous_spawns=0;for _,c in ipairs(calls)do if c=='legacy_spawn'then previous_spawns=previous_spawns+1 end end
local changed=T.G.clone(b);changed.id='minecraft:stone';append({changed});step()
local later_spawns=0;for _,c in ipairs(calls)do if c=='legacy_spawn'then later_spawns=later_spawns+1 end end
check(later_spawns==previous_spawns and companion.world:get('minecraft:overworld',0,64,0).id=='minecraft:stone','Same accepted journal updates chunk path instead of recreating legacy world')
check(observers==seq,'Existing world observer receives each row exactly once')
for _=1,30 do step();if bridge:readiness(ticket).ready then break end end
local prior_commits=bridge.stats.commits
local bookkeeping=T.G.clone(changed);bookkeeping.block_entity={container={count=2}};append({bookkeeping});step()
bookkeeping.block_entity.container.count=3;append({bookkeeping});step()
check(bridge.stats.commits==prior_commits and ticket.region.scheduler:get('minecraft:overworld',0,64,0).block_entity.container.count==3,'Static block entity bookkeeping stays current without native actor churn')
-- The bridge's dynamic overlay uses the real per-block native contract and scene
-- identity; it does not insert shared chunk models into legacy actor storage.
local dynamic_geometry={geometry=function(id,state,x,y,z)
 local groups=T.G.clone(T.geometry.geometry('minecraft:oak_planks','',x,y,z));for _,g in ipairs(groups)do g.part='/lid'end;return groups
end}
views.options.geometry=dynamic_geometry;bridge.geometry=dynamic_geometry;bridge.class_cache={}
ticket.region.scheduler.options.geometry=dynamic_geometry;ticket.region.scheduler.geometry=dynamic_geometry
local dyn=T.G.clone(changed);dyn.state='lidtest=true';dyn.block_entity={kind='chest'};append({dyn})
for _=1,50 do step();if bridge:readiness(ticket).ready and bridge:block_render_entry('minecraft:overworld',{0,64,0})then break end end
local entry=bridge:block_render_entry('minecraft:overworld',{0,64,0})
check(entry and entry.model_status=='rendered'and models.status().version==5,'Dynamic native overlay remains available to sign/model getters')
check(companion.block_render_entry('minecraft:overworld',{0,64,0})==entry and not companion.actors['0:64:0'],'Actual companion getter routes overlay without shared legacy proxy')
local result={status='passed',checks=checks,power_mode='night_low_power',actual_modules={'server/main.lua','server/world_compat.lua','chunk_geometry.lua','chunk_scheduler.lua','chunk_views.lua','companion_chunk_bridge.lua'},engine_boundary='simulated native model/collision',graphics=false,world_reset_during_install=false,new_reader=false,new_timer=false}
T.write('companion-bridge-tests.json',result);print(J.encode(result))
