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
local function failed_join()
 local h=harness();h.sv.ready=false
 h.intent('minecraft:overworld');h.step(0);h.step(config.prepare_timeout_ms+1)
 local tx=h.server.pending[h.binding.pal_uid]
 assert(tx.phase=='error'and tx.error=='target_prepare_timeout')
 assert(h.client.tx.phase=='error'and not tx._ticket and h.pc.locks==0 and #h.acks==0 and h.sa.moves==0)
 return h,tx.tx
end
check('terminal_first_join_host_rebind_and_same_tuple_replay_do_not_retry',function()
 local h,old=failed_join()
 h.host_scope.session_id=id(710);h.host_scope.generation=6;h.sv.ready=true
 h.intent('minecraft:overworld',{0,64,0},1,'reconnect')
 h.step(config.prepare_timeout_ms+100)
 assert(h.server.pending[h.binding.pal_uid].phase=='error'and h.server.pending[h.binding.pal_uid].tx==old)
 assert(#h.acks==0 and h.sa.moves==0)
end)
check('public_game_thread_retry_same_tuple_rotates_nonce_and_still_waits_for_camera',function()
 local h,old=failed_join();local at=config.prepare_timeout_ms+100
 h.sv.ready=true;h.camera_ready=false;h.host_scope.session_id=id(710);h.host_scope.generation=6
 h.server.now=at;assert(h.server:retry(h.binding.mc_uuid))
 local tx=h.server.pending[h.binding.pal_uid]
 assert(tx.tx~=old and tx.world_session=='world-A'and tx.dim=='minecraft:overworld'and tx.view==1)
 h.step(at,true);h.step(at+1,true);h.step(at+102,true)
 assert(#h.acks==0 and h.client.tx.phase=='awaiting_camera_commit')
 assert(h.server.pending[h.binding.pal_uid].phase=='committed')
 h.camera_ready=true;h.step(at+103,true);h.step(at+104,true)
 assert(#h.acks==1 and h.acks[1].view==1 and h.acks[1].world_session=='world-A'and h.acks[1].tx~=old)
 assert(h.acks[1].proof.camera_commit.host_scope.generation==6 and h.sa.moves==0)
 assert(h.client.tx.phase=='complete'and h.pc.locks==0 and h.replica.locks==0)
end)
check('persisted_terminal_first_join_can_use_same_public_retry_without_world_restart',function()
 local h,old=failed_join();local at=config.prepare_timeout_ms+200
 h.make_server();h.sv.ready=true;h.server.now=at
 assert(h.server:retry(h.binding.mc_uuid))
 assert(h.server.pending[h.binding.pal_uid].tx~=old)
 h.step(at,true);h.step(at+1,true);h.step(at+102,true)
 assert(#h.acks==1 and h.acks[1].view==1 and h.server.world_session=='world-A'and h.sa.moves==0)
end)
check('public_retry_rejects_foreign_identity_and_non_game_thread',function()
 local h,old=failed_join();local ok,why=h.server:retry(id(711))
 assert(ok==false and why=='authenticated_player_unavailable')
 h.sa.thread=false;local good,err=pcall(h.server.retry,h.server,h.binding.mc_uuid)
 assert(not good and tostring(err):find('travel_requires_game_thread',1,true))
 assert(h.server.pending[h.binding.pal_uid].tx==old and #h.acks==0)
end)
local J=dofile('/path/to/workspace/work/minecraft-fusion/native_renderer/stable-v3/json.lua')
print(J.encode({schema=1,task='initial_ow_terminal_retry',mode='offline_data_adapters',passed=#cases,names=cases,
 real_modules={'server/travel.lua','client/travel.lua','travel/protocol.lua'},native_engine_validated=false,
 runtime_mutations=false,source_changes=false}))
