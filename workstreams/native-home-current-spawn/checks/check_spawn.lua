-- Three pure source cases. Every actor, collision and camera value is synthetic.
local here=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))..'../'
local P=dofile(here..'checks/dependencies/protocol.lua')
local J=dofile(here..'checks/dependencies/json.lua')
local New=dofile(here..'source/server/travel.lua')
local Client=dofile(here..'checks/dependencies/client_travel.lua')
local function equal(a,b)return J.encode(a)==J.encode(b)end
local function fixture(module,dim,reason,established,previous_dim)
 local b={mc_uuid='11111111-1111-1111-1111-111111111111',pal_uid='22222222-2222-2222-2222-222222222222',
  session_id='33333333-3333-3333-3333-333333333333',generation=1,mc_epoch='fixture-mc',world_id='fixture-world',server_session_id='fixture-SID',pc={GetAddress=function()return 1 end}}
 local position={X=10000,Y=20000,Z=1088};local messages,requests={},{};local moved,activated=0,0;local ready=false;local holds={};local current_mode=1;local releases,acks=0,0;local durable
 local c={version=1,scale=100,y_origin=64,page_blocks=512,window_size=656,radius_blocks=64,below_blocks=16,above_blocks=32,
  prepare_timeout_ms=30000,replication_timeout_ms=15000,resend_ms=1000,position_tolerance_cm=50,server_settle_ms=100,
  world_bounds={-900000,-900000,-900000,900000,900000,900000},region_half_width_cm=32768,
  home_origin={X=10000,Y=20000,Z=1000},native_overworld_window_size=32000,region_vertical_padding_cm=500,
  slots={{0,0},{0,100000}},dimensions={}}
 for i,d in ipairs({'minecraft:overworld','minecraft:the_nether','minecraft:the_end'})do
  c.dimensions[d]={min_y=-64,max_y=320,profile=d,center={X=-400000+(i-1)*250000,Y=250000,Z=120000}}
 end
 local actor={valid=function()return true end,position=function()return P.copy(position)end,
  snapshot=function()return{position=P.copy(position),rotation={Yaw=0,Pitch=0,Roll=0},half_height=88,pawn_address=2,movement_mode=current_mode}end,
  hold=function(_,authority,restore)holds[#holds+1]={source_restore=restore~=nil,captured_mode=restore and restore.movement_mode or current_mode};return{}end,release=function()releases=releases+1;current_mode=2 end,maintain_hold=function()return true end,safety=function()return true,{}end,
  teleport=function(_,target)moved=moved+1;position=P.copy(target);return true end}
 local function proof(req)
  return{ready=ready,world_session=req.world_session,dim=req.dim,view=req.view,region_id=req.mapping.region_id,
   generation=1,revision=1,coverage_complete=true,covered_bounds=P.copy(req.required_bounds),snapshots_pending=0,
   collision_pending=0,collision_committed=true,errors={},visual_pending=0,visual_committed=true}
 end
 local view={prepare_view=function(req)
   local saved=assert(durable.pending[b.pal_uid]);assert(saved.tx==req.tx and equal(saved.required_bounds,req.required_bounds)and equal(saved.target_pawn,position))
   requests[#requests+1]=P.copy(req);return{req=req,generation=1}end,
  readiness=function(ticket)return proof(ticket.req)end,activate=function()activated=activated+1;return true end,release=function()return true end}
 local s=module.new{protocol=P,config=c,actor=actor,game_thread=function()return true end,
  resolve=function()return b end,send=function(row)messages[#messages+1]=P.copy(row);return true end,
  journal={load=function()return{}end,save=function(row)durable=P.copy(row);return true end,ack=function()acks=acks+1;return true end},view=view}
 s.now=100;s.world_session='fixture-world-session'
 if established then
  local source_dim=previous_dim or dim
  local map=assert(s.registry:acquire(s.world_session,source_dim,{0,64,0},'active:'..b.pal_uid))
  s.players[b.pal_uid]={binding=P.identity(b),mapping=map,dim=source_dim,world_session=s.world_session,view=1,pos={0,64,0}}
 end
 local e={op='player_view',player=b.mc_uuid,to=dim,from=established and(previous_dim or dim)or nil,
  view=established and 2 or 1,pos={13.5,53,7.5},yaw=0,pitch=0,reason=reason}
 assert(P.event({t='blocks',v=2,session=s.world_session,seq=1,dim=dim},e))
 assert(s:_begin({session=s.world_session,seq=1},e,b)==true)
 local tx=assert(s.pending[b.pal_uid])
 return{server=s,b=b,tx=tx,event=e,messages=messages,requests=requests,proof=proof,set_ready=function(v)ready=v end,
  counts=function()return moved,activated,releases,acks end,actor=actor,view=view,holds=holds,durable=function()return P.copy(durable)end,position=function()return P.copy(position)end,set_position=function(v)position=P.copy(v)end}
end

local cases={}
local selected=arg[1]
local function test(name,fn)if not selected or selected==name then fn();cases[#cases+1]=name end end

test('same_pawn_late_spawn_reprepares_new_tx_durably_without_old_teleport_ACK_or_cap_extension',function()
 local f=fixture(New,'minecraft:overworld','respawn',true);local s,tx=f.server,f.tx
 local oldid,cap,bounds=tx.tx,tx.initial_prepare_limit,P.copy(tx.required_bounds)
 f.set_ready(true);tx.client_ready=f.proof(P.request(tx,'client'))
 local at=f.position();at.X=at.X+800;at.Y=at.Y+500;f.set_position(at)
 s.now=cap-5;s:_progress(tx)
 assert(tx.phase=='preparing'and tx.tx~=oldid and equal(tx.target_pawn,at))
 assert(tx.client_ready==nil and tx.server_ready==nil and tx.initial_prepare_limit==cap and tx.deadline<=cap)
 assert(not P.covers(bounds,tx.required_bounds)and #f.requests==2)
 local moved,_,released,acks=f.counts();assert(moved==0 and released>0 and acks==0)
 local last=f.messages[#f.messages];assert(last.phase=='prepare'and last.tx==tx.tx and equal(last.target_pawn,at))
 assert(f.durable().pending[f.b.pal_uid].tx==tx.tx)
 assert(#f.holds==2 and f.holds[2].source_restore==false and f.holds[2].captured_mode==2)
 assert(tx.source.snapshot.movement_mode==1) -- Old source is retained as evidence, not reused to restore the new hold.
end)

test('stable_current_spawn_with_actual_both_coverage_runs_original_commit_camera_ACK_chain',function()
 local f=fixture(New,'minecraft:overworld','respawn',true);local s,tx=f.server,f.tx
 f.set_ready(true);tx.client_ready=f.proof(P.request(tx,'client'));s:_progress(tx)
 assert(tx.phase=='committed'and equal(tx.server_position,f.position()))
 local frame={schema=1,ready=true,source_epoch='synthetic-camera',source_frame=2,source_generation=1,origin_generation=1,origin_frame=1,
  world_session=tx.world_session,dim=tx.dim,view=tx.view,host_scope=P.copy(tx.binding)}
 local proof=f.proof(P.request(tx,'client'));proof.camera_commit=frame
 assert(s:_client{binding=f.b,row=P.message(tx,'client_observed',{proof=proof,position=f.position(),region_id=tx.mapping.region_id})}==true)
 s.now=s.now+s.config.server_settle_ms+1;s:_progress(tx)
 local moved,_,_,acks=f.counts();assert(tx.phase=='complete'and tx.final.applied==true and moved==0 and acks==1)
 assert(equal(tx.final.proof.camera_commit,frame)and s.config.position_tolerance_cm==50)
end)

test('small_current_spawn_drift_is_durable_and_accepted_by_unchanged_client50cm_contract',function()
 local f=fixture(New,'minecraft:overworld','respawn',true);local s,tx=f.server,f.tx
 local oldid=tx.tx
 local client=Client.new{protocol=P,config=s.config,actor=f.actor,game_thread=function()return true end,
  identity=function()return f.b end,send=function()return true end,view={prepare_view=function(req)return{req=req,generation=1}end},
  set_mapping=function()return true end,sync_view=function()return true end,commit_frame=function()return nil end,host_scope=function()return nil end}
 client.now=s.now
 assert(client:_prepare(P.message(tx,'prepare',{mapping=tx.mapping,required_bounds=tx.required_bounds,pos=tx.pos,yaw=tx.yaw,pitch=tx.pitch,target_pawn=tx.target_pawn}),f.b,f.b.pc)==true)
 local at=f.position();at.X=at.X+20;f.set_position(at)
 f.set_ready(true);tx.client_ready=f.proof(P.request(tx,'client'));s:_progress(tx)
 assert(tx.phase=='committed'and tx.tx==oldid and equal(tx.target_pawn,at))
 local row=f.messages[#f.messages];assert(row.phase=='committed')
 assert(client:_handle(row,f.b,f.b.pc)==true and equal(client.tx.target_pawn,at))
 assert(equal(f.durable().pending[f.b.pal_uid].target_pawn,at));local moved=f.counts();assert(moved==0)
end)

print(J.encode{schema=1,passed=true,tests=#cases,native_home_rehold_captures_current_receiver_mode_not_source_snapshot=true,cases=cases,all_identity_native_actor_location_collision_camera_journal_data_synthetic=true,
 original_server_client_protocol_methods_loaded=true,actual_Game_RPC_teleport_Save_signature_or_ACK_proven=false,
 automatic_reprepare_does_not_extend_original_initial_limit=true,native750_50cm_client_ACK_and_auxiliary_paths_not_changed=true})
