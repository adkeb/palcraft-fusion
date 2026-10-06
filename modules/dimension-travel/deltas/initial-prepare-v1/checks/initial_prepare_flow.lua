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
 h.host_scope={session_id=id(700),generation=5,mc_uuid=binding.mc_uuid,pal_uid=binding.pal_uid,
  world_id=binding.world_id,server_session_id=binding.server_session_id}
 function h.camera_frame(tx)
  return{schema=1,ready=h.camera_ready~=false,source_epoch=id(701),source_frame=100,source_generation=19,
   origin_generation=2,origin_frame=99,world_session=tx.world_session,dim=tx.dim,view=tx.view,host_scope=P.copy(h.host_scope)}
 end
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
   commit_frame=function()return h.camera_frame(h.client.tx)end,host_scope=function()return P.copy(h.host_scope)end,
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
local function progress(h,t,ready)
 for _,v in ipairs({h.sv,h.cv})do
  v.ready=ready;v.override={revision=1+t//10000,snapshots_pending=ready and 0 or math.max(1,8-t//20000)}
 end
end
check('slow_initial_world_progress_completes_without_operator_retry_or_duplicate_move',function()
 local h=harness();h.pc.position.X=h.pc.position.X+500;h.replica.position=P.copy(h.pc.position);h.camera_ready=false
 progress(h,0,false);h.intent('minecraft:overworld');h.step(0);local nonce=h.server.pending[h.binding.pal_uid].tx
 for t=10000,90000,10000 do progress(h,t,false);h.step(t);assert(h.server.pending[h.binding.pal_uid].phase=='preparing'and #h.acks==0 and h.sa.moves==0)end
 progress(h,94000,true);h.step(94000);h.step(94001,true);h.step(94101,true)
 assert(h.server.pending[h.binding.pal_uid].tx==nonce and h.sa.moves==1 and #h.acks==0 and h.client.tx.phase=='awaiting_camera_commit')
 h.camera_ready=true;h.step(94102,true);h.step(94103,true)
 assert(#h.acks==1 and h.sa.moves==1 and h.client.tx.phase=='complete'and h.pc.locks==0)
 assert(h.server.pending[h.binding.pal_uid].initial_prepare_extensions==3)
 -- Same MC world and view, a newly authenticated outer MC scope is bootstrap too.
 h.binding.session_id=id(800);h.binding.generation=2;h.make_client();progress(h,100000,false)
 h.intent('minecraft:overworld',{0,64,0},1,'reconnect','minecraft:overworld');h.step(100000)
 for t=110000,140000,10000 do progress(h,t,false);h.step(t);assert(h.server.pending[h.binding.pal_uid].phase=='preparing')end
 progress(h,145000,true);h.step(145000);h.step(145001,true);h.step(145102,true)
 assert(#h.acks==2 and h.acks[2].session_id==h.binding.session_id and h.acks[2].view==1 and h.sa.moves==1)
end)
check('stalled_or_wrong_scope_native_evidence_cannot_renew_initial_budget',function()
 for _,bad_scope in ipairs({false,true})do
  local h=harness();h.sv.ready=false;h.cv.ready=false
  h.sv.override={revision=0,snapshots_pending=0,collision_pending=0,visual_pending=0}
  if bad_scope then h.sv.override.world_session='wrong-world';h.sv.override.revision=99 end
  h.intent('minecraft:overworld');h.step(0);h.step(30001)
  assert(h.server.pending[h.binding.pal_uid].phase=='error'and h.server.pending[h.binding.pal_uid].error=='target_prepare_timeout')
  assert(#h.acks==0 and h.sa.moves==0)
 end
end)
check('continuing_actual_progress_has_a_finite_180_second_ceiling',function()
 local h=harness();progress(h,0,false);h.intent('minecraft:overworld');h.step(0)
 for t=10000,170000,10000 do progress(h,t,false);h.step(t);assert(h.server.pending[h.binding.pal_uid].phase=='preparing')end
 progress(h,180000,false);h.step(180000)
 assert(h.server.pending[h.binding.pal_uid].phase=='error'and #h.acks==0 and h.sa.moves==0 and h.pc.locks==0)
end)
check('ordinary_dimension_change_keeps_30_second_prepare_timeout',function()
 local h=harness();h.join();progress(h,200,false);h.intent('minecraft:the_nether',{0,64,0},2,'dimension_change','minecraft:overworld')
 h.step(200);progress(h,10200,false);h.step(10200);progress(h,20200,false);h.step(20200);progress(h,30201,false);h.step(30201)
 assert(h.server.pending[h.binding.pal_uid].phase=='error'and not h.server.pending[h.binding.pal_uid].initial_prepare_limit and #h.acks==1)
end)
check('committed_replication_and_camera_still_have_15_second_timeout',function()
 local h=harness();h.camera_ready=false;h.intent('minecraft:overworld');h.step(0);h.step(1,true);h.step(15002,true)
 assert(h.server.pending[h.binding.pal_uid].phase=='recovery_required'and #h.acks==0)
end)
local J=dofile('/path/to/workspace/work/minecraft-fusion/native_renderer/stable-v3/json.lua')
print(J.encode({schema=1,task='initial_prepare_lease',passed=#cases,names=cases,mode='offline_data_adapters',engine_validated=false,runtime_operations=false}))
