-- One offline composition check. Native/engine objects are fixtures, never live acceptance.
local base,tmp,features_path,pipeline_path=assert(arg[1]),assert(arg[2]),assert(arg[3]),assert(arg[4])
local J=dofile(base..'/../package/PalCraftClient/Scripts/json.lua')
for _,name in ipairs({'command.json','command.json.pending','travel-events.ndjson','result.json'})do os.remove(tmp..'/'..name)end
local function clone(v)return J.decode(J.encode(v))end
local function check(v,reason)assert(v,reason)end
local function write(path,row)local f=assert(io.open(path,'wb'));assert(f:write(J.encode(row)));f:close()end
local function append(path,row)local f=assert(io.open(path,'ab'));assert(f:write(J.encode(row)..'\n'));f:close()end
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
local accepted={player=MC,world_session='world-live',dim=OW,view=1,waiting_ack=true}
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
local opts=dofile(base..'/runtime/client_options.lua').new{json=J,bridge_root=tmp,scripts_dir=base..'/client',
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
features:tick(0,ctx)
check(named('client_world').phase=='running'and named('world').phase=='waiting','Actual factory waits for a committed world receipt')
check(not companion.chunk_consumer,'No scene inferred from flags or empty native queues')
local seq=0
local function ingest(dim,ops,life)
 seq=seq+1
 local row={t='blocks',v=2,session='world-live',seq=seq,tick=seq,dim=dim,ops=ops or{},lifecycle=life or{}}
 local ok,reason=companion.world:ingest(row);check(ok,reason)
 if companion.chunk_consumer then check(companion.chunk_consumer.on_row(row,true,reason)~=false,'Existing reader forwards once')end
 if companion.observer then companion.observer.on_row(row,true,reason)end
 return row
end
local bounds={0,64,0,16,80,16}
ingest(OW,{},{{op='snapshot_begin',snapshot='actual-receipt',at={0,0},bounds=bounds,player=MC}})
ingest(OW,{{op='upsert',at={2,64,1},id='minecraft:oak_sign',state='rotation=0',properties={rotation='0'},boxes={},solid=false,visible=true,
 fluid={kind='none',height=0,waterlogged=false},snapshot='actual-receipt'}})
ingest(OW,{},{{op='snapshot_end',snapshot='actual-receipt',at={0,0},bounds=bounds}})
features:tick(50,ctx)
check(companion.chunk_consumer,'Trusted waiting_ack=true installs the actual native composition')
check(named('world').phase=='waiting','World not ready before its actual chunk commit')
for n=1,30 do
 companion.chunk_consumer.tick()
 features:tick(50+n*50,ctx)
 if named('world').phase=='running'and named('travel').phase=='running'and named('fluid_physics').phase=='running'then break end
end
local world=named('world')
check(world.phase=='running','Initial committed scene opens world: '..J.encode(features:status()))
check(accepted.waiting_ack==true,'Initial chunk commit has not fabricated a final ACK')
check(native_commits>0,'Actual chunk transaction callback ran')
local client_world=named('client_world')
check(client_world.status.chunks.acceptance.collision_verified==false and client_world.status.chunks.acceptance.visual_verified==false,'QA remains false')
check(named('travel').phase=='running'and named('travel').status.phase=='idle','Real Travel.new is constructed without an external travel_view')
check(named('fluid_physics').phase=='running'and water_native.commits>0,'Real fluid core tick reached its native adapter: '..J.encode(named('fluid_physics')))
check(named('sign_text').phase=='waiting','A config flag alone does not establish the receiver facility')
host.sign_text_receiver={version=1,installed=true}
check(opts.sign.images_ready(features.binding)==true,'Real receiver facility is ready before any bind or PNG')
check(not opts.sign.view_provider(),'Sign waits while native view ACK is pending')
local P=dofile(base..'/travel/protocol.lua')
local mapping=clone(opts.travel.initial_mapping)
local tx={tx='actual-join',binding=binding,world_session='world-live',dim=OW,view=1,mapping=mapping}
local function signal(phase,extra)return P.message(tx,phase,extra)end
append(tmp..'/travel-events.ndjson',signal('prepare',{mapping=mapping,required_bounds=bounds,pos={.5,65.8,.5},
 target_pawn=position,yaw=0,pitch=0}))
for n=1,20 do
 companion.chunk_consumer.tick();features:tick(2000+n*50,ctx)
 if named('travel').status.phase=='prepared'then break end
end
check(named('travel').status.phase=='prepared','Local proxy mirror feeds the real prepare transaction: '..J.encode(named('travel')))
opts.command_bus.reset();os.remove(tmp..'/command.json')
append(tmp..'/travel-events.ndjson',signal('committed',{target_pawn=position}))
features:tick(3100,ctx)
check(named('travel').status.phase=='awaiting_camera_commit'and state.held,'No early observed ACK before a real target camera receipt')
camera={schema=1,ready=true,source_epoch='capture-epoch',source_frame=2,source_generation=1,origin_generation=1,origin_frame=1,
 world_session='world-live',dim=OW,view=1,host_scope={session_id=HOST,generation=1,mc_uuid=MC,pal_uid=PAL,world_id='lab-world',server_session_id='pal-boot'}}
features:tick(3150,ctx);features:tick(3200,ctx)
f=assert(io.open(tmp..'/command.json','rb'));local command=J.decode(f:read('*a'));f:close()
check(command.t=='travel_observed'and command.session_id==NATIVE and command.session_generation==7,'Existing command sender preserves real native lease and phase')
append(tmp..'/travel-events.ndjson',signal('complete',{applied=true,mapping=mapping}))
accepted.waiting_ack=false
features:tick(3250,ctx);features:tick(3500,ctx)
check(named('travel').status.phase=='complete'and not state.held,'Only real protocol complete releases the native hold')
check(named('sign_text').phase=='running','Real sign consumer constructs from receiver/committed scene')
local view=assert(opts.sign.view_provider())
check(view.origin.Z==home.Z and view.fence.view==1 and view.fence.mapping==mapping.region_id,'Initial sign scene uses actual home mapping and accepted tuple')
local g,committed=opts.sign.block_at(OW,{2,64,1})
check(g.id=='minecraft:oak_sign'and committed,'Sign body comes from actual chunk committed entry')
companion.visual_pipeline.tick(.25,4)
check(opts.command_bus.status().queued>0,'First sign bind is requested without requiring PNG readiness')
bootstrap.world_view.view=2
check(not opts.sign.view_provider(),'New accepted tuple cannot reuse an old active native scene')
bootstrap.world_view.view=1
check(features:reset('offline_done',{context_alive=true})==true,'One lifecycle stops all constructed workers')
check(companion.chunk_consumer==nil,'Factory retires only its own installed consumer')
write(tmp..'/result.json',{schema=1,passed=true,checks=1,scope='one client factory integration scenario',
 actual_modules={'client_options','features','compose','bootstrap','travel','fluid_physics','fluid_physics_core','world_compat','chunks','companion_chunk_bridge','chunk_views','chunk_scheduler','native_visual_pipeline','sign_consumer'},
 initial_waiting_ack=true,native_and_engine_boundary='offline fixtures',in_game_verified=false,production_touched=false,
 new_world_reader=false,new_timer=false,new_socket=false,old_195_or_33_checks_rerun=false})
print('PASS: one client factory integration scenario; native/engine fixtures; no live acceptance.')
