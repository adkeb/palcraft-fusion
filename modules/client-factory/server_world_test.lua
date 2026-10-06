-- One narrow offline facade scenario: real Models empty-list transaction +
-- actual chunk/reducer modules; only the native compound backend is a fixture.
local base,tmp,facade_source=assert(arg[1]),assert(arg[2]),assert(arg[3])
local J=dofile(base..'/../package/PalCraftClient/Scripts/json.lua')
local function check(v,m)assert(v,m)end
local function clone(v)return J.decode(J.encode(v))end
IsInGameThread=function()return true end
FindAllOf=function(name)check(name=='Actor','Empty visual transaction only queries actor inventory');return{}end
StaticFindObject=function()error('No reflected renderer functions should be accessed')end
package.loadlib=function()error('No client Model DLL or live native library may load in this check')end
local World=dofile(base..'/server/world_compat.lua')
local context={GetAddress=function()return 0x11000 end,IsValid=function()return true end}
local origin={X=-308099.9282280116,Y=187800.81696803804,Z=3480.330899345611}
local c={world=World.new{dimension='minecraft:overworld',auto_view=false},running=true,actors={},origin=origin,changes=0}
local installs=0
c.context=function()return context end
c.geometry_signature=J.encode
c.render_signature=function(g)return J.encode({id=g.id,state=g.state,boxes=g.boxes,visible=g.visible,fluid=g.fluid})end
c.install_consumer=function(binding)check(not c.chunk_consumer,'Single authoritative consumer');c.chunk_consumer=binding;installs=installs+1;return true end
c.retire_legacy=function()return{ok=true}end
local collider={live={},commits=0,preflights=0,boxes={}}
local serial=0x20000
function collider.prepare(_,o,p)
 serial=serial+8;local h={actor=serial,components={},revision=p.revision,generation=p.generation,fence=p.fence,state='prepared'}
 for i,b in ipairs(p.boxes)do h.components[i]=serial+i*8;collider.boxes[#collider.boxes+1]=clone(b.cm)end
 collider.live[h]=true;return h
end
function collider.preflight(fresh,old)
 for _,h in ipairs(fresh)do check(collider.live[h]and h.state=='prepared','Actual compound transaction preflight')end
 for _,h in ipairs(old)do check(collider.live[h],'Actual old compound lifetime')end
 collider.preflights=collider.preflights+1
end
function collider.commit(fresh,old)
 for _,h in ipairs(old)do collider.live[h]=nil;h.state='released'end
 for _,h in ipairs(fresh)do h.state='active'end
 collider.commits=collider.commits+1;return fresh
end
function collider.unload(handles)for _,h in ipairs(handles or{})do collider.live[h]=nil;h.state='released'end end
collider.discard=collider.unload
function collider.reset()collider.live={};collider.resets=(collider.resets or 0)+1 end
local ff=assert(io.open(facade_source,'rb'));local code=ff:read('*a');ff:close()
local module=assert(load(code,'@'..base..'/runtime/server_views.lua'))()
local view=module.new{json=J,models_path=tmp..'/Scripts/models.lua',root=tmp..'/rpc',origin=origin,companion=function()return c end,
 chunk_dir=base..'/client',collision=collider,collision_dll='unused-fixture.dll',frame_steps=512,frame_budget_ms=10}
check(installs==0 and view.status().phase=='waiting_for_authoritative_prepare','Facade construction is inert')
local seq=0;local session='authority-world'
local function row(dim,ops,life)
 seq=seq+1;local r={t='blocks',v=2,session=session,seq=seq,tick=seq,dim=dim,ops=ops or{},lifecycle=life or{}}
 local ok,why=c.world:ingest(r);check(ok,why)
 if c.chunk_consumer then check(c.chunk_consumer.on_row(r,true,why)~=false,'One existing reducer forwards accepted rows')end
end
local P=dofile(base..'/travel/protocol.lua')
local config=P.copy(dofile(base..'/travel/config.lua'));config.home_origin=P.copy(origin)
local registry=P.registry(config)
local bounds={0,64,0,8,72,8}
local players={'00000002-0000-0000-0000-000000000000','00000006-0000-0000-0000-000000000000'}
local dims={'minecraft:overworld','minecraft:the_nether','minecraft:the_end'}
local function snapshot(dim,player,n)
 local id='receipt-'..n
 row(dim,{},{{op='snapshot_begin',snapshot=id,at={0,0},bounds=bounds,player=player}})
 row(dim,{
  {op='upsert',id='minecraft:stone',at={1,64,1},state='',boxes={{0,0,0,1,1,1}},solid=true,visible=true,fluid={kind='none'},snapshot=id},
  {op='upsert',id='minecraft:oak_slab',at={2,64,1},state='type=bottom,waterlogged=true',boxes={{0,0,0,1,.5,1}},
   solid=true,visible=true,fluid={kind='water',height=8/9,waterlogged=true,flow={0,0,0}},snapshot=id},
  {op='upsert',id='minecraft:lava',at={3,64,1},state='',boxes={},solid=false,visible=true,
   fluid={kind='lava',height=8/9,waterlogged=false},snapshot=id}})
 row(dim,{},{{op='snapshot_end',snapshot=id,at={0,0},bounds=bounds,player=player}})
end
local tickets={}
for i,dim in ipairs(dims)do
 local player=players[i==2 and 2 or 1];snapshot(dim,player,i)
 local mapping=assert(registry:acquire('authority-world',dim,{.5,65,.5},'fixture-'..i))
 local req={world_session='authority-world',dim=dim,view=i,player=player,mode='server',session_generation=7,mapping=mapping,required_bounds=bounds}
 local t=view.prepare_view(req);tickets[#tickets+1]=t
 check(view.readiness(t).ready==false,'Prepare never invents collision readiness')
 for n=1,30 do c.chunk_consumer.tick();if view.readiness(t).ready then break end end
 local proof=view.readiness(t)
 check(proof.ready and proof.collision_committed,'Actual compound resources/receipt make region ready: '..J.encode(proof))
 check(proof.accepted==false and proof.acceptance.collision_verified==false,'Native QA stays false')
 check(view.activate(t)==true,'Actual collision-only target activation')
 check(c.world.dimension=='minecraft:overworld','Server activation never changes every player global dimension')
 for _,previous in ipairs(tickets)do check(view.readiness(previous).ready,'Other region/ticket remains committed')end
end
-- A later request from player two must participate in snapshot lifecycle,
-- rather than inheriting a permanent filter for player one's initial view.
row(dims[2],{},{{op='snapshot_begin',snapshot='player-two-update',at={0,0},bounds=bounds,player=players[2],replace=false}})
check(not view.readiness(tickets[2]).ready,'Second player pending snapshot really blocks readiness')
row(dims[2],{},{{op='snapshot_end',snapshot='player-two-update',at={0,0},bounds=bounds,player=players[2],replace=false}})
for n=1,10 do c.chunk_consumer.tick()end
check(view.readiness(tickets[2]).ready,'Second player accepted completion releases only its pending snapshot')
check(installs==1 and collider.commits>=3,'All dimensions share one real installed consumer')
check(view.status().views.regions==3 and view.status().collision_only,'Three retained physical regions')
check(c.world:get(dims[2],2,64,1).fluid.kind=='water'and c.world:get(dims[2],3,64,1).fluid.kind=='lava','Fluid authority data stays intact')
local half=false
for _,b in ipairs(collider.boxes)do if math.abs(b[6]-b[3]-50)<.001 then half=true end end
check(half,'Exact waterlogged solid slab remains a 50cm compound collider')
local t=tickets[1]
check(view.retain_scene{player=players[1],pal_uid='fixture',mapping=t.mapping,ticket=t,occupied=true},'Occupied real scene handoff')
check(#view.recovery_scenes==1,'Travel.new can consume its exact opaque retained ticket')
check(view.release(t)==true,'Actual source ticket release')
for n=1,20 do c.chunk_consumer.tick();if view.can_recycle(t.region_id,{world_session='authority-world'})then break end end
check(view.can_recycle(t.region_id,{world_session='authority-world'}),'Real retirement releases only one arena')
check(view.readiness(tickets[2]).ready and view.readiness(tickets[3]).ready,'Source retirement preserves both targets')
check(#view.recovery_scenes==0,'Retired source removed from retained scene handoff')
local old=c
c={world=World.new{dimension='minecraft:overworld',auto_view=false},running=true,actors={},origin=origin,changes=0}
for _,name in ipairs({'context','geometry_signature','render_signature'})do c[name]=old[name]end
c.install_consumer=function(binding)check(not c.chunk_consumer,'Only new companion owns its consumer');c.chunk_consumer=binding;installs=installs+1;return true end
c.retire_legacy=old.retire_legacy
seq=0;session='new-authority-world';snapshot(dims[1],players[1],4)
local mapping=assert(registry:acquire(session,dims[1],{.5,65,.5},'replacement-fixture'))
local req={world_session=session,dim=dims[1],view=1,player=players[1],mode='server',session_generation=8,mapping=mapping,required_bounds=bounds}
check(not pcall(view.prepare_view,req),'A changed getter cannot tear out an occupied old scene')
check(view.readiness(tickets[2]).ready and next(collider.live),'Old committed floor survives a premature replacement')
-- The companion owner explicitly abandons the dead context through its actual
-- consumer callback; the facade must neither repeat it nor keep the old instance.
old.chunk_consumer.stop(false);old.chunk_consumer=nil;old.running=false
local fresh=view.prepare_view(req)
for n=1,30 do c.chunk_consumer.tick();if view.readiness(fresh).ready then break end end
check(view.readiness(fresh).ready and fresh.world_session==session and installs==2,'A genuinely retired old companion is replaced by a fresh authoritative scene')
check(#view.recovery_scenes==0,'Dead old tickets cannot enter a new backend handoff')
check(view.abandon(fresh),'Dead context bookkeeping cleanup without renderer DLL')
check(c.chunk_consumer==nil and collider.resets==2,'Each dead consumer resets its own bookkeeping exactly once')
local result={schema=1,passed=true,checks=1,scope='one authoritative server view facade composition',
 actual_models_empty_transaction=true,actual_chunk_modules=true,native_compound_boundary='offline fixture',
 dimensions=dims,players=2,consumer_installs=installs,companion_replacement='requires_actual_old_stop',world_reader_added=false,timer_added=false,socket_added=false,
 in_game_verified=false,production_touched=false,old_195_or_33_checks_rerun=false}
local f=assert(io.open(tmp..'/server-world-result.json','wb'));f:write(J.encode(result));f:close()
print('PASS: one server facade scenario; actual empty Models transactions, compound boundary fixture.')
