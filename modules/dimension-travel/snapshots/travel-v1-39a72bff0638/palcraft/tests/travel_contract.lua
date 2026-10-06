-- Run: lua tests/travel_contract.lua <absolute palcraft source directory>
local root=assert(arg[1],'palcraft_root_required')
local P=dofile(root..'/travel/protocol.lua');local config=dofile(root..'/travel/config.lua')
local Server=dofile(root..'/server/travel.lua');local Client=dofile(root..'/client/travel.lua')
local cases={};local function check(name,f)f();cases[#cases+1]=name end
local function near(a,b)assert(math.abs(a-b)<0.00001,tostring(a)..' != '..tostring(b))end
local function id(n)return('00000000-0000-0000-0000-%012d'):format(n)end
local binding={mc_uuid=id(1),pal_uid=id(2),session_id=id(3),generation=1,mc_epoch=id(4),world_id='BridgeLabWorld',server_session_id=id(5)}
local function actor()
 local a={moves=0,thread=true}
 function a.valid(pc,b,authority)return pc and pc.valid and pc.uid==b.pal_uid, 'actor_identity' end
 function a.snapshot(pc)return{position=P.copy(pc.position),rotation={Yaw=0,Pitch=0,Roll=0},half_height=80,
  movement_mode=pc.mode,custom_movement_mode=0,pawn_address=pc.pawn_id}end
 function a.position(pc)return P.copy(pc.position)end
 function a.hold(pc,authority,restore)
  local lock={pc=pc,mode=restore and restore.movement_mode or pc.mode,authority=authority};pc.locks=pc.locks+1
  if authority then pc.mode=0 end;return lock
 end
 function a.release(lock)
  if not lock.released then lock.pc.locks=lock.pc.locks-1;if lock.authority then lock.pc.mode=lock.mode end;lock.released=true end
 end
 function a.safety(pc,mapping,target)return a.safe~=false,a.safe==false and'pal_kill_z'or{kill_z=-10000,streaming='native'}end
 function a.teleport(pc,target)
  a.moves=a.moves+1
  if a.fail=='false'then return false,'native_teleport_failed'end
  pc.position=P.copy(target)
  if a.fail=='misplace'then pc.position.X=pc.position.X+10000 end
  if a.fail=='exception'then error('crash_after_native_move')end
  return true,P.copy(pc.position)
 end
 return a
end
local function view()
 local v={tickets={},ready=true,generation=7}
 function v.prepare_view(req)
  local ticket={id=#v.tickets+1,request=P.copy(req),generation=v.generation};v.tickets[#v.tickets+1]=ticket;return ticket
 end
 function v.readiness(ticket)
  assert(ticket and not ticket.released,'live_ticket_required');local req=ticket.request
  local proof={ready=v.ready,world_session=req.world_session,dim=req.dim,view=req.view,region_id=req.mapping.region_id,
   generation=ticket.generation,coverage_complete=v.ready,covered_bounds=P.copy(req.required_bounds),
   snapshots_pending=v.ready and 0 or 1,visual_pending=0,collision_pending=0,collision_committed=v.ready,
   visual_committed=v.ready,errors={},revision=12}
  for k,x in pairs(v.override or{})do proof[k]=P.copy(x)end;return proof
 end
 function v.activate(ticket)assert(v.readiness(ticket).ready);ticket.active=true;return true end
 function v.release(ticket)assert(not ticket.released,'duplicate_ticket_release');ticket.released=true;return true end
 function v.abandon(ticket)ticket.abandoned=true;return true end
 return v
end
local function harness(saved_state)
 local h={binding=P.copy(binding),time=0,acks={},out={},seq=0,config=P.copy(config),checkpoint=P.copy(saved_state)}
 local origin=config.home_origin
 h.pc={uid=binding.pal_uid,valid=true,position={X=origin.X,Y=origin.Y,Z=origin.Z+80},mode=1,locks=0,pawn_id=100}
 function h.pc:GetAddress()return 50 end
 h.replica={uid=binding.pal_uid,valid=true,position=P.copy(h.pc.position),mode=1,locks=0,pawn_id=101}
 function h.replica:GetAddress()return 51 end
 h.sa=actor();h.ca=actor();h.sv=view();h.cv=view();h.cv.generation=9
 h.journal={load=function()return P.copy(h.checkpoint)end,
  save=function(state)
   if h.fail_save and h.fail_save(state)then error('disk_write_fault')end
   h.checkpoint=P.copy(state);return true
  end,
  ack=function(row)if h.fail_ack then return false end;h.acks[#h.acks+1]=P.copy(row);return true end}
 function h.make_server()
  h.server=Server.new{protocol=P,config=h.config,actor=h.sa,view=h.sv,journal=h.journal,game_thread=function()return h.sa.thread end,
   resolve=function(player)if h.unbound or player~=h.binding.mc_uuid then return nil end;local b=P.copy(h.binding);b.pc=h.pc;return b end,
   send=function(row)h.out[#h.out+1]=P.copy(row);return true end};return h.server
 end
 function h.make_client()
  h.client=Client.new{protocol=P,config=h.config,actor=h.ca,view=h.cv,game_thread=function()return h.ca.thread end,
   identity=function()return P.copy(h.binding)end,
   send=function(row)h.server:observe_client(row,h.binding);return true end,
   set_mapping=function(mapping)h.mapping=P.copy(mapping);return true end,
   sync_view=function(pc,yaw,pitch,input)h.sync={yaw,pitch};assert(pc==h.replica);return true end};return h.client
 end
 h.make_server();h.make_client()
 function h.intent(dim,pos,generation,reason,from,session)
  h.seq=h.seq+1;local row={t='blocks',v=2,session=session or'world-A',seq=h.seq,dim=dim,lifecycle={{op='player_view',
   player=h.binding.mc_uuid,to=dim,pos=pos or{0,64,0},view=generation or 1,reason=reason or'join',from=from,yaw=30,pitch=10}}}
  assert(h.server:observe_world(row));return row
 end
 function h.step(t,replicate)
  h.time=t;h.server:tick(t)
  local out=h.out;h.out={};for _,row in ipairs(out)do h.client:observe(row)end
  if replicate then h.replica.position=P.copy(h.pc.position)end
  return h.client:tick(h.replica,config.home_origin,t,{build=true})
 end
 function h.join()
  h.intent('minecraft:overworld');h.step(0);h.step(1,true);h.step(102,true)
  assert(#h.acks==1 and h.acks[1].phase=='complete'and not h.client:status().blocked)
 end
 return h
end
check('home_origin_exact_and_dimension_separation',function()
 local r=P.registry(config);local home=assert(r:acquire('w','minecraft:overworld',{0,64,0},'a'))
 for k,v in pairs(config.home_origin)do near(home.origin[k],v)end
 local nether=assert(r:acquire('w','minecraft:the_nether',{10,70,-10},'n'))
 local ending=assert(r:acquire('w','minecraft:the_end',{100,50,0},'e'))
 assert(nether.region_id~=ending.region_id and math.abs(nether.center.X-ending.center.X)>100000)
 local point=P.to_ue(nether,{10,70,-10});local back=P.to_mc(nether,point);near(back[1],10);near(back[2],70);near(back[3],-10)
end)
check('region_pool_capacity_no_recycle_of_other_player',function()
 local r=P.registry(config);local first
 for i=1,4 do local m=assert(r:acquire('w','minecraft:the_nether',{i*512,64,0},'p'..i));first=first or m end
 local m,why=r:acquire('w','minecraft:the_nether',{9999,64,0},'overflow');assert(not m and why=='physical_region_capacity')
 r:release(first,'p1');assert(r:acquire('w','minecraft:the_nether',{9999,64,0},'overflow'))
end)
check('overworld_beyond_256_blocks_preserves_actual_pal_origin_and_low_ground',function()
 local r=P.registry(config)
 for _,pos in ipairs({{300,64,0},{5000,80,-2000}})do
  local m=assert(r:acquire('world','minecraft:overworld',pos,'native'))
  assert(m.native_overworld and m.slot==0 and m.window_size>=32000 and not m.auxiliary_pending)
  for k,v in pairs(config.home_origin)do near(m.origin[k],v)end
  assert(r:required(m,pos))
 end
 local m=assert(r:acquire('world','minecraft:overworld',{29000000,64,0},'far'))
 assert(m.auxiliary_pending and not m.native_overworld)
end)
check('retiring_native_arena_cannot_be_recycled_even_without_player_refs',function()
 local r=P.registry(config);local blocked
 r.can_recycle=function(mapping)return mapping.region_id~=blocked end
 for i=1,4 do local m=assert(r:acquire('w','minecraft:the_nether',{i*512,64,0},'p'..i))
  if i==1 then blocked=m.region_id;r:release(m,'p1')end
 end
 local m,why=r:acquire('w','minecraft:the_nether',{9999,64,0},'overflow');assert(not m and why=='physical_region_capacity')
 blocked=nil;assert(r:acquire('w','minecraft:the_nether',{9999,64,0},'overflow'))
end)
check('far_mc_coordinate_stays_inside_physical_window',function()
 local r=P.registry(config);local m=assert(r:acquire('w','minecraft:the_end',{29000000,70,-29000000},'far'))
 local p=P.to_ue(m,{29000000,70,-29000000});assert(P.contains(m.region_bounds,p));assert(r:required(m,{29000000,70,-29000000}))
end)
check('join_requires_both_sides_real_readiness',function()
 local h=harness();h.cv.ready=false;h.intent('minecraft:overworld');h.step(0);h.step(1000,true)
 assert(#h.acks==0 and h.sa.moves==0 and h.client:status().blocked)
 h.cv.ready=true;h.step(1001);h.step(1002,true);h.step(1103,true)
 assert(#h.acks==1 and h.pc.mode==1 and h.pc.locks==0 and h.replica.locks==0)
end)
check('native_server_collision_gate_cannot_be_client_acknowledged',function()
 local h=harness();h.sv.ready=false;h.intent('minecraft:the_nether',{10,64,0});h.step(0);h.step(1,true)
 assert(#h.acks==0 and h.sa.moves==0);h.sv.ready=true;h.step(2,false);assert(h.sa.moves==1)
end)
check('vanilla_nether_landing_not_scaled_twice_and_replica_wait',function()
 local h=harness();h.join();local old=h.mapping.origin.X
 h.intent('minecraft:the_nether',{10,65,2},2,'dimension_change','minecraft:overworld');h.step(200);h.step(201,false)
 assert(h.sa.moves==1 and h.mapping.origin.X==old and #h.acks==1)
 local tx=h.server.pending[h.binding.pal_uid];local feet=P.copy(h.pc.position);feet.Z=feet.Z-80
 local pos=P.to_mc(tx.mapping,feet);near(pos[1],10);near(pos[2],65);near(pos[3],2)
 h.step(202,true);near(h.sync[1],-120);near(h.sync[2],-10);h.step(302,true)
 assert(#h.acks==2 and h.mapping.dim=='minecraft:the_nether'and not h.client:status().blocked)
end)
check('end_then_overworld_restores_original_origin_and_movement',function()
 local h=harness();h.join();h.intent('minecraft:the_end',{100,50,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,true);h.step(302,true);assert(h.mapping.dim=='minecraft:the_end')
 h.intent('minecraft:overworld',{4,64,-3},3,'dimension_change','minecraft:the_end')
 h.step(400);h.step(401,true);h.step(502,true)
 for k,v in pairs(config.home_origin)do near(h.mapping.origin[k],v)end
 assert(h.pc.mode==1 and h.pc.locks==0 and h.replica.locks==0 and #h.acks==3)
end)
check('stale_view_and_wrong_player_message_rejected',function()
 local h=harness();h.join();h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld');h.step(200)
 local tx=h.server.pending[h.binding.pal_uid];local m=P.message(tx,'client_ready',{proof=h.cv.readiness(h.cv.tickets[#h.cv.tickets])})
 m.view=1;assert(h.server:observe_client(m,h.binding));h.server:tick(201);assert(h.server.stats.rejected>=1)
 local before=h.ca.moves;local other=P.message(tx,'committed',{target_pawn=tx.target_pawn});other.player=id(999)
 h.client:observe(other);h.client:tick(h.replica,config.home_origin,202,{});assert(h.client.stats.rejected>=1 and h.ca.moves==before)
end)
check('prepared_timeout_restores_source_without_moving_or_final_ack',function()
 local h=harness();h.join();local source=P.copy(h.pc.position);h.cv.ready=false
 h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld');h.step(200);h.step(30200)
 assert(#h.acks==1 and h.sa.moves==0 and P.distance(source,h.pc.position)==0 and h.pc.locks==0 and h.pc.mode==1)
 assert(h.server.pending[h.binding.pal_uid].phase=='error')
end)
check('false_native_result_returns_specific_error',function()
 local h=harness();h.join();h.sa.fail='false';h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,true);assert(#h.acks==1 and h.server.pending[h.binding.pal_uid].error=='native_teleport_failed')
 assert(h.pc.locks==0 and h.pc.mode==1)
end)
check('native_true_with_wrong_position_is_recovery_not_success',function()
 local h=harness();h.join();h.sa.fail='misplace';h.intent('minecraft:the_end',{100,50,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,true);assert(#h.acks==1 and h.server.pending[h.binding.pal_uid].phase=='recovery_required')
 assert(h.server.pending[h.binding.pal_uid].error=='server_landing_position_mismatch')
end)
check('journal_fault_before_move_never_teleports',function()
 local h=harness();h.join();h.fail_save=function(state)
  for _,tx in pairs(state.pending)do if tx.phase=='moving'then return true end end;return false
 end
 h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld');h.step(200);h.step(201,true);h.step(202,true)
 assert(h.sa.moves==0 and #h.acks==1 and h.server._journal_fault)
end)
check('crash_after_move_replays_without_second_native_teleport',function()
 local h=harness();h.join();h.fail_save=function(state)
  for _,tx in pairs(state.pending)do if tx.phase=='committed'then return true end end;return false
 end
 h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld');h.step(200);h.step(201,false)
 assert(h.sa.moves==1 and h.checkpoint.pending[h.binding.pal_uid].phase=='moving')
 h.fail_save=nil;h.pc.locks=0;h.replica.locks=0;h.sv=view();h.cv=view();h.make_server();h.make_client()
 h.step(300,true);h.step(301,true);h.step(402,true)
 assert(h.sa.moves==1 and #h.acks==2 and h.pc.mode==1 and h.pc.locks==0)
end)
check('replication_timeout_retains_native_target_and_requires_recovery',function()
 local h=harness();h.join();h.intent('minecraft:the_end',{100,50,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,false);h.step(15202,false)
 local tx=h.server.pending[h.binding.pal_uid];assert(tx.phase=='recovery_required'and #h.acks==1 and not tx._ticket.released)
end)
check('outer_epoch_rotation_rejects_old_ready_and_preserves_new_prepare',function()
 local h=harness();h.join();h.cv.ready=false;h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld');h.step(200)
 local old=P.copy(h.binding);local tx=h.server.pending[old.pal_uid]
 local message=P.message(tx,'client_ready',{proof=h.cv.readiness(h.cv.tickets[#h.cv.tickets])})
 h.binding.session_id=id(30);h.binding.generation=2;h.binding.mc_epoch=id(40)
 assert(h.server:observe_client(message,old));h.step(201,false)
 assert(h.server.stats.rejected>=1 and h.client.tx and h.client.tx.binding.session_id==h.binding.session_id and #h.acks==1)
 h.cv.ready=true;h.step(202);h.step(203,true);h.step(304,true);assert(#h.acks==2)
end)
check('unbound_world_event_waits_for_authentication',function()
 local h=harness();h.unbound=true;h.intent('minecraft:overworld');h.step(0);assert(h.server:status().queued==1 and #h.acks==0)
 h.unbound=nil;h.step(1);h.step(2,true);h.step(103,true);assert(#h.acks==1)
end)
check('missing_collision_proof_does_not_become_empty_world_success',function()
 local h=harness();h.sv.override={coverage_complete=false,covered_bounds={0,0,0,1,1,1},snapshots_pending=0}
 h.intent('minecraft:overworld');h.step(0);h.step(1,true);assert(#h.acks==0 and h.sa.moves==0)
end)
check('native_methods_only_on_game_thread',function()
 local h=harness();h.sa.thread=false;assert(not pcall(h.server.tick,h.server,0));h.ca.thread=false
 assert(not pcall(h.client.tick,h.client,h.replica,config.home_origin,0,{}));assert(h.sa.moves==0 and h.ca.moves==0)
end)
check('retired_world_packets_cannot_restore_an_old_dimension',function()
 local h=harness();h.join();h.intent('minecraft:overworld',{0,64,0},1,'join',nil,'world-B');h.step(200);h.step(201,true);h.step(302,true)
 h.intent('minecraft:the_nether',{0,64,0},9,'dimension_change','minecraft:overworld','world-A');h.step(400)
 assert(h.server.world_session=='world-B'and h.mapping.dim=='minecraft:overworld'and h.sa.moves==0)
end)
check('multiplayer_wrong_pal_uid_never_mutates_another_character',function()
 local h=harness();h.pc.uid=id(999);h.intent('minecraft:the_nether',{0,64,0});h.step(0)
 assert(h.sa.moves==0 and h.pc.locks==0 and #h.acks==0)
end)
check('stop_releases_owned_locks_but_keeps_occupied_floor_for_recovery',function()
 local h=harness();h.join();h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,false);local tx=h.server.pending[h.binding.pal_uid]
 local ok,handoff=h.server:stop('test_reload',true)
 assert(ok and h.server.stopped and h.pc.locks==0 and h.pc.mode==1 and not tx._ticket.released and #handoff.retained_scenes>=1)
 assert(#h.acks==1 and h.server:observe_world({})==false);h.client:stop('reload',true)
 assert(h.replica.locks==0 and h.client.stopped)
end)
check('ack_sink_failure_retry_rotates_nonce_without_duplicate_native_move',function()
 local h=harness();h.join();h.fail_ack=true;h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,true);h.step(302,true);local old=h.server.pending[h.binding.pal_uid].tx
 assert(#h.acks==1 and h.sa.moves==1 and h.server.pending[h.binding.pal_uid]._fault)
 h.fail_ack=nil;h.server.now=400;assert(h.server:retry(h.binding.mc_uuid));assert(h.server.pending[h.binding.pal_uid].tx~=old)
 h.step(400,true);h.step(401,true);h.step(502,true);assert(#h.acks==2 and h.sa.moves==1 and h.pc.mode==1)
end)
check('completed_checkpoint_does_not_rewind_a_walking_player_on_reload',function()
 local h=harness();h.join();h.pc.position.X=h.pc.position.X+2000;local before=P.copy(h.pc.position)
 h.make_server();h.server:tick(400);assert(h.sa.moves==0 and P.distance(h.pc.position,before)==0 and #h.acks==1)
end)
check('failed_target_vanilla_rollback_view_reenters_actual_source',function()
 local h=harness();h.join();h.sa.fail='false';h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,true);h.sa.fail=nil
 h.intent('minecraft:overworld',{0,64,0},3,'rollback','minecraft:the_nether');h.step(400);h.step(401,true);h.step(502,true)
 assert(#h.acks==2 and h.mapping.dim=='minecraft:overworld'and h.pc.mode==1)
end)
check('two_authenticated_players_and_unbound_third_do_not_share_travel',function()
 local h=harness();h.join();h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,true);h.step(302,true);local occupied=P.copy(h.pc.position)
 local peer=P.copy(binding);peer.mc_uuid=id(10);peer.pal_uid=id(11);peer.session_id=id(12)
 peer.pc={uid=peer.pal_uid,valid=true,position={X=config.home_origin.X+200,Y=config.home_origin.Y,Z=config.home_origin.Z+80},mode=1,locks=0,pawn_id=110}
 function peer.pc:GetAddress()return 52 end
 h.server.options.resolve=function(uuid)
  if uuid==peer.mc_uuid then return peer elseif uuid==h.binding.mc_uuid then local b=P.copy(h.binding);b.pc=h.pc;return b end
 end
 local function event(seq,uuid)return{t='blocks',v=2,session='world-A',seq=seq,dim='minecraft:overworld',
  lifecycle={{op='player_view',player=uuid,to='minecraft:overworld',view=1,reason='join',pos={2,64,0},yaw=0,pitch=0}}}end
 assert(h.server:observe_world(event(3,peer.mc_uuid)));h.server:tick(400)
 local tx=h.server.pending[peer.pal_uid];assert(tx and h.pc.locks==0 and P.distance(h.pc.position,occupied)==0)
 local proof=h.sv.readiness(tx._ticket)
 assert(h.server:observe_world(event(4,id(999))))
 assert(h.server:observe_client(P.message(tx,'client_ready',{proof=proof}),peer));h.server:tick(401)
 assert(tx.phase=='committed'and h.server:status().queued==1)
 assert(h.server:observe_client(P.message(tx,'client_observed',{proof=proof,position=peer.pc.position,region_id=tx.mapping.region_id}),peer));h.server:tick(502)
 assert(#h.acks==3 and h.sa.moves==1 and peer.pc.mode==1 and peer.pc.locks==0 and P.distance(h.pc.position,occupied)==0)
end)
check('real_chunk_facade_snapshot_and_native_commit_proof_connect_to_travel',function()
 local data=dofile(root..'/chunks/tests/support.lua')
 local Facade=dofile(root..'/client/chunk_views.lua')
 local h=harness()
 local function facade()
  local adapter=data.adapter();local manager=Facade.new{geometry=data.geometry,adapter=adapter,frame_budget_ms=2,
   frame_steps=128,max_regions=4,view_player=binding.mc_uuid};local seq=0
  local wrapper={manager=manager,adapter=adapter}
  function wrapper.prepare_view(req)
   local ticket=manager:prepare_view(req);local b=req.required_bounds;local r=config.radius_blocks
   local x,z=b[1]+r,b[3]+r;local y=b[2]+config.below_blocks-1
   local snapshot='travel-snapshot-'..ticket.id
   local function row(life,ops)
    seq=seq+1;assert(manager:ingest{t='blocks',v=2,session=req.world_session,seq=seq,dim=req.dim,ops=ops or{},lifecycle=life})
   end
   row({{op='snapshot_begin',snapshot=snapshot,bounds=b,at={x//16,z//16},player=req.player}})
   local block=data.block(x,y,z,'stone');block.op='upsert';block.snapshot=snapshot
   row({}, {block});row({{op='snapshot_end',snapshot=snapshot,bounds=b,at={x//16,z//16},player=req.player}})
   return ticket
  end
  function wrapper.readiness(ticket)manager:tick(2,128);return manager:readiness(ticket)end
  function wrapper.activate(ticket)manager:activate(ticket);return true end
  function wrapper.release(ticket)return manager:release(ticket)end
  return wrapper
 end
 h.sv=facade();h.cv=facade();h.make_server();h.make_client();h.intent('minecraft:overworld')
 for i=0,20 do h.step(i*20,true);if #h.acks==1 then break end end
 assert(#h.acks==1 and h.sv.adapter.commits>0 and h.cv.adapter.commits>0)
 h.intent('minecraft:the_nether',{10,64,0},2,'dimension_change','minecraft:overworld')
 for i=21,50 do h.step(i*20,true);if #h.acks==2 then break end end
 assert(#h.acks==2 and h.sa.moves==1 and h.mapping.dim=='minecraft:the_nether')
 assert(h.acks[2].proof.collision_committed and h.acks[2].proof.visual_committed)
end)
check('authoritative_page_rebase_freezes_only_its_pawn_then_completes_new_mapping',function()
 local h=harness();h.join();h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,true);h.step(302,true);h.server.options.rebase_supported=true
 h.pc.position.X=h.pc.position.X+30000;h.replica.position=P.copy(h.pc.position)
 h.server:tick(1000);local tx=h.server.pending[h.binding.pal_uid]
 assert(tx._rebase_lock and h.pc.mode==0 and h.pc.locks==1)
 local rebase=h.out[#h.out];assert(rebase.phase=='rebase_required'and rebase.mc_pos[1]==300 and rebase.next_mc_anchor[1]==512)
 h.out={};h.intent('minecraft:the_nether',{300,64,0},3,'rebase','minecraft:the_nether')
 h.step(1100);h.step(1101,true);h.step(1202,true)
 assert(#h.acks==3 and h.mapping.mc_anchor[1]==512 and h.pc.mode==1 and h.pc.locks==0 and h.sa.moves==2)
end)
check('far_auxiliary_overworld_is_explicitly_pending_not_false_success',function()
 local h=harness();h.join();h.intent('minecraft:overworld',{29000000,64,0},2,'teleport','minecraft:overworld')
 h.step(200);assert(#h.acks==1 and h.sa.moves==0 and h.pc.locks==0)
 assert(h.server.pending[h.binding.pal_uid].error=='auxiliary_overworld_pending_validation')
end)
check('crash_record_with_legitimate_source_region_save_drift_can_recover',function()
 local h=harness();h.join();h.sa.fail='exception';h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,false);assert(#h.acks==1)
 local tx=h.checkpoint.pending[h.binding.pal_uid]
 tx.phase='moving';h.pc.position=P.copy(tx.source.snapshot.position);h.pc.position.X=h.pc.position.X+300
 h.sa.fail=nil;h.pc.locks=0;h.replica.locks=0;h.sv=view();h.cv=view();h.make_server();h.make_client()
 h.step(300,true);h.step(301,true);h.step(402,true);assert(#h.acks==2 and h.pc.mode==1)
end)
check('new_epoch_supersedes_old_move_with_actual_region_not_stale_exact_point',function()
 local h=harness();h.join();h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,false);h.pc.position.X=h.pc.position.X+300
 h.binding.session_id=id(31);h.binding.generation=2;h.binding.mc_epoch=id(41)
 h.intent('minecraft:overworld',{0,64,0},1,'join',nil,'world-B')
 h.step(300);h.step(301,true);h.step(402,true)
 assert(#h.acks==2 and h.mapping.native_overworld and h.pc.mode==1 and h.pc.locks==0)
end)
check('failed_rebase_rollback_uses_previous_origin_and_proves_source_ring',function()
 local h=harness();h.join();h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);h.step(201,true);h.step(302,true);local origin=P.copy(h.mapping.origin)
 h.pc.position.X=h.pc.position.X+25800;h.replica.position=P.copy(h.pc.position);h.sa.fail='false'
 h.intent('minecraft:the_nether',{258,64,0},3,'rebase','minecraft:the_nether');h.step(600);h.step(601,true)
 assert(#h.acks==2 and h.server.pending[h.binding.pal_uid].phase=='error');h.sa.fail=nil
 h.intent('minecraft:the_nether',{258,64,0},4,'rollback','minecraft:the_nether');h.step(700);h.step(701,true);h.step(802,true)
 assert(#h.acks==3 and h.mapping.mc_anchor[1]==0 and h.pc.mode==1 and h.pc.locks==0)
 for k,v in pairs(origin)do near(h.mapping.origin[k],v)end
 assert(h.server.pending[h.binding.pal_uid].required_bounds[4]==323)
end)
io.write('{"test":"dimension_travel_contract","passed":'..#cases..',"cases":[')
for i,name in ipairs(cases)do if i>1 then io.write(',')end;io.write('"'..name..'"')end
io.write('],"live_pal_travel_verified":false}\n')
