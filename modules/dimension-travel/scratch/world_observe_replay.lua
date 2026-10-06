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
local function row(h,session,seq)
 return{t='blocks',v=2,session=session,seq=seq,dim='minecraft:overworld',lifecycle={{op='player_view',
  player=h.binding.mc_uuid,to='minecraft:overworld',view=1,reason='join',pos={0,64,0},yaw=0,pitch=0}}}
end
check('valid_duplicate_observe_is_true_and_tick_ignores_without_new_ack',function()
 local h=harness();h.join();local before=h.server.pending[h.binding.pal_uid].tx
 local ok,why=h.server:observe_world(row(h,'world-A',1));assert(ok==true)
 h.step(200,true)
 assert(h.server.pending[h.binding.pal_uid].tx==before and #h.acks==1 and h.sa.moves==0)
end)
check('malformed_processed_old_event_false_is_player_view_before_stale_fence',function()
 local h=harness();h.join();local r=row(h,'world-A',1);r.lifecycle[1].yaw=nil
 local ok,why=h.server:observe_world(r)
 assert(ok==false and why=='player_view'and r.session==h.server.world_session and r.seq<=h.server.last_seq)
 assert(#h.acks==1 and h.sa.moves==0)
end)
check('malformed_new_sequence_and_unknown_world_remain_real_rejections',function()
 local h=harness();h.join();local r=row(h,'world-A',h.server.last_seq+1);r.lifecycle[1].yaw=nil
 local ok,why=h.server:observe_world(r);assert(ok==false and why=='player_view')
 r.session='world-new';r.lifecycle[1].yaw=0;r.lifecycle[1].pos={31000000,64,0}
 ok,why=h.server:observe_world(r);assert(ok==false and why=='mc_bounds')
 assert(h.server.world_session=='world-A'and #h.acks==1)
end)
check('valid_retired_world_observe_is_true_and_tick_ignores_without_scope_revival',function()
 local h=harness();h.join();h.intent('minecraft:overworld',{0,64,0},1,'join',nil,'world-B')
 h.step(200,true);h.step(201,true);h.step(302,true)
 assert(h.server.retired['world-A']==true and h.server.world_session=='world-B'and #h.acks==2)
 local ok=h.server:observe_world(row(h,'world-A',h.server.last_seq+100));assert(ok==true)
 h.step(400,true)
 assert(h.server.world_session=='world-B'and #h.acks==2 and h.sa.moves==0)
end)
local J=dofile('/path/to/workspace/work/minecraft-fusion/native_renderer/stable-v3/json.lua')
print(J.encode({schema=1,task='travel_world_observe_replay_classification',mode='offline_data_adapters',passed=#cases,names=cases,
 real_modules={'server/travel.lua','client/travel.lua','travel/protocol.lua'},native_engine_validated=false,
 runtime_mutations=false,core_source_changes=false,feature_patch_executed=false}))
