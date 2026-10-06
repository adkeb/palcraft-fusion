-- One offline composition check. Native/engine objects are fixtures, never live acceptance.
local base,tmp,features_path,pipeline_path,cold_source=assert(arg[1]),assert(arg[2]),assert(arg[3]),assert(arg[4]),assert(arg[5])
local J=dofile(base..'/../package/PalCraftClient/Scripts/json.lua')
for _,name in ipairs({'command.json','command.json.pending','travel-events.ndjson','result.json'})do os.remove(tmp..'/'..name)end
local function clone(v)return J.decode(J.encode(v))end
local function check(v,reason)assert(v,reason)end
local function write(path,row)local f=assert(io.open(path,'wb'));assert(f:write(J.encode(row)));f:close()end
local function append(path,row)local f=assert(io.open(path,'ab'));assert(f:write(J.encode(row)..'\n'));f:close()end
local results={}
for case,dimension in ipairs({'minecraft:the_nether','minecraft:the_end'})do
for _,name in ipairs({'command.json','command.json.pending','travel-events.ndjson'})do os.remove(tmp..'/'..name)end
local PAL='00000000-0000-4000-8000-000000000001'
local MC='00000002-0000-0000-0000-000000000000'
local HOST='00000003-0000-0000-0000-000000000000'
local NATIVE='00000004-0000-0000-0000-000000000000'
local O={X=-308099.9282280116,Y=187800.81696803804,Z=3480.330899345611}
local home=clone(O);local OW='minecraft:overworld';local clock=100
IsInGameThread=function()return true end
local function object(n,m)
 m=m or{};m.IsValid=function()return true end;m.GetAddress=function()return n end
 m.GetFullName=function()return'Fixture '..n end;return m
end
local movement=object(103,{MovementMode=1,CustomMovementMode=0})
local position={X=O.X+50,Y=O.Y-50,Z=O.Z+180}
local pawn=object(101,{CharacterMovement=movement,K2_GetActorLocation=function()return clone(position)end})
pawn.CapsuleComponent=object(102,{GetScaledCapsuleHalfHeight=function()return 90 end})
local pc=object(100,{Pawn=pawn,Player=object(104),GetPlayerUId=function()return{A=1,B=0,C=0,D=0}end,
 GetControlRotation=function()return{Yaw=0,Pitch=0,Roll=0}end,
 SetIgnoreMoveInput=function()end,SetIgnoreLookInput=function()end})
pc.Player.GetFullName=function()return'PalLocalPlayer /Engine/Transient.Fixture'end
local ctx={pc=pc,identity={server_session_id='pal-boot'},input={},context_alive=true}
local identity={world_id='lab-world',pal_uid=PAL,mc_uuid=MC,mc_name='Fixture'}
local host={schema=1,protocol=2,state='bound',authenticated_host=true,updated_unix=clock,
 identity=identity,server_session_id='pal-boot',session_id=HOST,generation=1,expires_at=1000}
local binding={v=2,legacy=false,world_id='lab-world',pal_uid=PAL,mc_uuid=MC,mc_name='Fixture',
 server_session_id='pal-boot',session_id=NATIVE,generation=7,expires_at=1000,mc_epoch='native-epoch'}
local accepted={player=MC,world_session='world-live',dim=dimension,view=1,waiting_ack=true}
local bootstrap={schema=1,protocol=2,authenticated_host=true,native_mc_verified=true,updated_unix=clock,
 host_scope={session_id=HOST,generation=1,pal_uid=PAL,mc_uuid=MC,world_id='lab-world',server_session_id='pal-boot'},
 native_binding=binding,world_view=accepted}
local files={read=function(path)
 if path:match('session%-bind%-status.json$')then return clone(host)end
 if path:match('mc%-bootstrap%-status.json$')then return clone(bootstrap)end
end}
local World=dofile(base..'/server/world_compat.lua')
local companion={world=World.new{dimension=OW,auto_view=false},origin=clone(O),actors={},queue={},queue_head=1,running=true,changes=0}
ctx.collisions=companion
companion.context=function()return pc end
companion.geometry_signature=J.encode
companion.render_signature=function(g)return J.encode({id=g.id,state=g.state,properties=g.properties,boxes=g.boxes,visible=g.visible,render_kind=g.render_kind,fluid=g.fluid,tint_colors=g.tint_colors})end
companion.install_consumer=function(c)check(not companion.chunk_consumer,'Only one actual consumer');companion.chunk_consumer=c;return true end
companion.retire_legacy=function(_,keys)for _,k in ipairs(keys)do companion.actors[k]=nil end;return{ok=true}end
companion.set_view=function(dim,player)companion.world:set_view(dim,player);companion.pending_view=nil;return companion.world:status()end
companion.set_world_observer=function(o)companion.observer=o end
companion.status_json=function()return J.encode({running=true,world=companion.world:status()})end
companion.block_render_entry=function(dim,at)
 if companion.chunk_consumer then return companion.chunk_consumer.block_render_entry(dim,at)end
 return companion.actors[('%d:%d:%d'):format(table.unpack(at))]
end
local serial=200;local native_commits=0;local models={version=5,geometry_version=2,
 capabilities={opaque=true,dynamic=true,atomic_commit=true,hidden_prepare=true,atomic_pages=true}}
function models.geometry(id)
 return{{texture='minecraft:block/oak_planks',alpha_mode='opaque',shade=false,
  vertices={{0,0,0,0,1,0,0,0},{100,0,0,0,1,0,1,0},{100,0,100,0,1,0,1,1},{0,0,100,0,1,0,0,1}},
  indices={0,1,2,0,2,3},face_ranges={{first_vertex=0}}}}
end
function models.status()return{version=5,asset_root=tmp..'/assets/',geometry_version=2,capabilities=models.capabilities}end
function models.prepare(_,_,b)
 serial=serial+1;return{actor=serial,component=serial+1000,revision=b.revision,generation=b.generation,fence=b.fence,state='prepared'}
end
function models.prepare_block(c,o,e,p)
 return models.prepare(c,o,{groups=e.groups,at=e.at,revision=p.revision,generation=p.generation,fence=p.fence})
end
function models.commit_transaction(fresh,old,transaction)
 if transaction then transaction.adapter.commit(transaction.prepared,transaction.previous,transaction.expected_fence)end
 for _,h in ipairs(fresh)do h.state='active'end;for _,h in ipairs(old)do h.state='released'end
 native_commits=native_commits+1;return true
end
function models.discard(h)h.state='released'end
models.unload=models.discard
models.update_groups=function()end;models.release_model=function()return true end
models.set_material_provider=function()end
models.set_visible=function()end;models.tick_animations=function()end
models.block_event=function()end
companion.models=models
local collision={handles={}}
function collision.prepare(_,_,p)
 serial=serial+1;local h={actor=serial,revision=p.revision,generation=p.generation,fence=p.fence,state='prepared',components={}}
 collision.handles[h]=true;return h
end
function collision.preflight(fresh,old)
 for _,h in ipairs(fresh)do check(collision.handles[h]and h.state=='prepared','Real adapter transaction preflight')end
end
function collision.commit(fresh,old)
 for _,h in ipairs(old)do collision.handles[h]=nil;h.state='released'end
 for _,h in ipairs(fresh)do h.state='active'end;return fresh
end
function collision.unload(list)for _,h in ipairs(list or{})do collision.handles[h]=nil;h.state='released'end end
collision.discard=collision.unload
function collision.reset()collision.handles={}end
local water_native={commits=0}
function water_native:replace()self.commits=self.commits+1;return true end
function water_native:reset()end
function water_native:status()return{commits=self.commits}end
local water_engine={}
function water_engine:attach(p)return{actor=p.actor,movement=movement}end
function water_engine:release()end
function water_engine:pose(p)return{dim=p.dim,feet={.5,64.9,.5},radius=.3,height=1.8,shape='capsule'}end
function water_engine:apply()return{known=true}end
local state={held=false,mapping={origin=home,native_overworld=true,dim=OW,scale=100,y_origin=64}}
local camera={ready=false}
local bridge={}
function bridge.status()return clone(state)end
function bridge.initWorldView()error('Pending initial ACK must not bypass travel')end
function bridge.reset()state.held=false;return true end
function bridge.hold()state.held=true;return true end
function bridge.applyMapping(m,ws,dim,view)
 state.mapping=clone(m);state.mapping.view=view;O.X,O.Y,O.Z=m.origin.X,m.origin.Y,m.origin.Z
 check(m.world_session==ws and m.dim==dim,'Actual mapping scope');return true
end
function bridge.syncView()return true end
function bridge.commitFrame()return clone(camera)end
function bridge.release(s)
 check(s.phase=='complete'and s.active and s.world_session==accepted.world_session,'Actual final ACK required')
 state.held=false;return true
end
local cf=assert(io.open(cold_source,'rb'));local cold_code=cf:read('*a');cf:close()
local Cold=assert(load(cold_code,'@'..base..'/runtime/client_options.lua'))()
local opts=Cold.new{json=J,bridge_root=tmp,scripts_dir=base..'/client',
 config={identity=identity,entities_enabled=false,travel_enabled=true,chunk_enabled=true,fluid_physics_enabled=true,sign_text_enabled=true},
 origin=O,view_bridge=bridge,now=function()return clock end,files=files,travel_dir=base..'/travel',
 fluid_shared_dir=base..'/native',fluid_options={contact_driver=dofile(base..'/server/world_fluid.lua'),native=water_native,engine=water_engine},
 chunk_options={collision=collision,frame_steps=512,frame_budget_ms=10,seed_blocks_per_tick=16}}
opts.load=function(name)return dofile(base..'/client/'..name..'.lua')end
-- Apply only the one-line lifecycle patch to real pipeline source, using its
-- complete next-candidate dependencies. No graphical API is touched here.
local f=assert(io.open(pipeline_path,'rb'));local source=f:read('*a');f:close()
local pipeline_dir=base..'/../native_renderer/candidate-v5/'
local Pipeline=assert(load(source,'@'..pipeline_dir..'native_visual_pipeline.lua'))()
companion.visual_pipeline=Pipeline.new{models=models,json=J,bridge_root=tmp..'/',origin=O,context=companion.context,companion=companion}
f=assert(io.open(features_path,'rb'));source=f:read('*a');f:close()
local Features=assert(load(source,'@'..base..'/client/features.lua'))()
local features=Features.new(opts)
local function named(name)
 for _,row in ipairs(features:status().features)do if row.name==name then return row end end
 error('Missing real feature '..name)
end
local seq=0
local function ingest(dim,ops,life)
 seq=seq+1
 local row={t='blocks',v=2,session='world-live',seq=seq,tick=seq,dim=dim,ops=ops or{},lifecycle=life or{}}
 local ok,reason=companion.world:ingest(row);check(ok,reason)
 if companion.chunk_consumer then check(companion.chunk_consumer.on_row(row,true,reason)~=false,'Existing reader forwards once')end
 if companion.observer then companion.observer.on_row(row,true,reason)end
 return row
end
local P=dofile(base..'/travel/protocol.lua')
local config=P.copy(dofile(base..'/travel/config.lua'));config.home_origin=P.copy(home)
local mapping=assert(P.registry(config):acquire('world-live',dimension,{.5,64.9,.5},'authority-cold'))
local target=P.to_ue(mapping,{.5,64.9,.5});target.Z=target.Z+90
position=clone(target)
local bounds={0,64,0,16,80,16}
local tx={tx='cold-'..case,binding=binding,world_session='world-live',dim=dimension,view=1,mapping=mapping}
local function signal(phase,extra)return P.message(tx,phase,extra)end
local prepare=signal('prepare',{mapping=mapping,required_bounds=bounds,pos={.5,64.9,.5},target_pawn=target,yaw=0,pitch=0})
local wrong=clone(prepare);wrong.session_id='00000009-0000-0000-0000-000000000000'
append(tmp..'/travel-events.ndjson',wrong)
features:tick(0,ctx)
check(not companion.chunk_consumer and named('client_world').status.startup_rejected==1,'Cold startup rejects a mismatched actual native lease')
check(named('world').phase=='waiting'and named('travel').phase=='waiting','No invented cold scene or ACK')
append(tmp..'/travel-events.ndjson',prepare)
features:tick(50,ctx)
check(not companion.chunk_consumer,'Authoritative prepare still waits for the real reducer world')
ingest(dimension,{},{{op='snapshot_begin',snapshot='actual-cold',at={0,0},bounds=bounds,player=MC}})
ingest(dimension,{{op='upsert',at={2,64,1},id='minecraft:oak_sign',state='rotation=0',properties={rotation='0'},boxes={},solid=false,visible=true,
 fluid={kind='none',height=0,waterlogged=false},snapshot='actual-cold'}})
ingest(dimension,{},{{op='snapshot_end',snapshot='actual-cold',at={0,0},bounds=bounds}})
features:tick(100,ctx)
check(companion.chunk_consumer,'The trusted cold target prepares real chunks')
check(companion.chunk_consumer.bridge.views.active_view==nil,'Initial target preparation does not claim the native view is applied')
for n=1,30 do
 companion.chunk_consumer.tick();features:tick(100+n*50,ctx)
 if named('travel').phase=='running'and named('travel').status.phase=='prepared'then break end
end
local travel=named('travel')
check(travel.phase=='running'and travel.status.phase=='prepared','Cold dimension opens actual travel: '..J.encode(travel))
check(state.held and not state.mapping.world_session and O.Z==home.Z,'Cold target has not stamped origin/camera prematurely')
check(named('client_world').status.initial_from_prepare,'Cold scene provenance is the authoritative prepare')
check(not opts.sign.view_provider(),'Sign waits for applied native view')
check(#opts.fluid.resolve_participants(ctx)==0,'Fluid cannot predict against a not-yet-applied cold mapping')
check(features:initialize_home(pc)==false,'Nether/End startup never forces an Overworld initializer')
host.sign_text_receiver={version=1,installed=true}
opts.command_bus.reset();os.remove(tmp..'/command.json')
append(tmp..'/travel-events.ndjson',signal('committed',{target_pawn=target}))
features:tick(2100,ctx)
check(named('travel').status.phase=='awaiting_camera_commit'and state.held,'Cold replication requires the target camera receipt')
check(state.mapping.dim==dimension and O.Z==mapping.origin.Z and O.Z~=home.Z,'Authoritative target origin is physically applied without a home detour')
check(not opts.sign.view_provider()and #opts.fluid.resolve_participants(ctx)==0,'Sign/fluid stay closed while final camera ACK is pending')
camera={schema=1,ready=true,source_epoch='cold-capture-'..case,source_frame=2,source_generation=1,origin_generation=1,origin_frame=1,
 world_session='world-live',dim=dimension,view=1,host_scope={session_id=HOST,generation=1,mc_uuid=MC,pal_uid=PAL,world_id='lab-world',server_session_id='pal-boot'}}
features:tick(2150,ctx);features:tick(2200,ctx)
local f=assert(io.open(tmp..'/command.json','rb'));local observed=J.decode(f:read('*a'));f:close()
check(observed.t=='travel_observed'and observed.dim==dimension and observed.session_id==NATIVE,'Actual cold camera observation preserves native binding')
append(tmp..'/travel-events.ndjson',signal('complete',{applied=true,mapping=mapping}))
accepted.waiting_ack=false
features:tick(2250,ctx);features:tick(2500,ctx)
check(named('travel').status.phase=='complete'and not state.held,'Only real cold travel complete releases input')
local scene=assert(opts.sign.view_provider())
check(scene.fence.dim==dimension and scene.origin.Z==mapping.origin.Z,'Sign uses the actual applied cold region')
local _,committed=opts.sign.block_at(dimension,{2,64,1});check(committed,'Cold sign body comes from its actual committed static page')
check(#opts.fluid.resolve_participants(ctx)==1,'Fluid opens only after the applied cold view')
check(named('client_world').status.chunks.acceptance.collision_verified==false,'Cold source check cannot manufacture native QA')
check(features:reset('cold_fixture_done',{context_alive=true})==true,'One existing lifecycle stops the cold region')
check(companion.chunk_consumer==nil,'Cold region cleanup detaches its owned consumer')
results[#results+1]={dimension=dimension,passed=true,forced_overworld=false,raw_abi_changed=false}
end
local f=assert(io.open(tmp..'/cold-result.json','wb'));f:write(J.encode({schema=1,passed=true,checks=1,scenarios=results,
 actual_factory_and_protocol_modules=true,native_and_engine_boundary='offline fixtures',in_game_verified=false,
 reader_added=false,timer_added=false,socket_added=false,active_9_2_modified=false,old_195_or_33_checks_rerun=false}));f:close()
print('PASS: one cold reconnect composition scenario, Nether + End; native boundary fixtures.')
