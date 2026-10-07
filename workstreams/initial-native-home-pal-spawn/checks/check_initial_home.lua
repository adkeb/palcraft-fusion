-- Three pure source cases. Every actor, collision and camera value is synthetic.
local here=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))..'../'
local P=dofile(here..'checks/dependencies/protocol.lua')
local J=dofile(here..'checks/dependencies/json.lua')
local New=dofile(here..'source/server/travel.lua')
local Old=dofile(here..'base/server/travel.lua')
local function equal(a,b)return J.encode(a)==J.encode(b)end
local function fixture(module,dim,reason)
 local b={mc_uuid='11111111-1111-1111-1111-111111111111',pal_uid='22222222-2222-2222-2222-222222222222',
  session_id='33333333-3333-3333-3333-333333333333',generation=1,mc_epoch='fixture-mc',world_id='fixture-world',server_session_id='fixture-SID',pc={GetAddress=function()return 1 end}}
 local position={X=10000,Y=20000,Z=1088};local messages,requests={},{};local moved,activated=0,0;local ready=false
 local c={version=1,scale=100,y_origin=64,page_blocks=512,window_size=656,radius_blocks=64,below_blocks=16,above_blocks=32,
  prepare_timeout_ms=30000,replication_timeout_ms=15000,resend_ms=1000,position_tolerance_cm=50,server_settle_ms=100,
  world_bounds={-900000,-900000,-900000,900000,900000,900000},region_half_width_cm=32768,
  home_origin={X=10000,Y=20000,Z=1000},native_overworld_window_size=32000,region_vertical_padding_cm=500,
  slots={{0,0},{0,100000}},dimensions={}}
 for i,d in ipairs({'minecraft:overworld','minecraft:the_nether','minecraft:the_end'})do
  c.dimensions[d]={min_y=-64,max_y=320,profile=d,center={X=-400000+(i-1)*250000,Y=250000,Z=120000}}
 end
 local actor={valid=function()return true end,position=function()return P.copy(position)end,
  snapshot=function()return{position=P.copy(position),rotation={Yaw=0,Pitch=0,Roll=0},half_height=88,pawn_address=2,movement_mode=1}end,
  hold=function()return{}end,release=function()end,maintain_hold=function()return true end,safety=function()return true,{}end,
  teleport=function(_,target)moved=moved+1;position=P.copy(target);return true end}
 local function proof(req)
  return{ready=ready,world_session=req.world_session,dim=req.dim,view=req.view,region_id=req.mapping.region_id,
   generation=1,revision=1,coverage_complete=true,covered_bounds=P.copy(req.required_bounds),snapshots_pending=0,
   collision_pending=0,collision_committed=true,errors={},visual_pending=0,visual_committed=true}
 end
 local view={prepare_view=function(req)requests[#requests+1]=P.copy(req);return{req=req}end,
  readiness=function(ticket)return proof(ticket.req)end,activate=function()activated=activated+1;return true end,release=function()return true end}
 local s=module.new{protocol=P,config=c,actor=actor,game_thread=function()return true end,
  resolve=function()return b end,send=function(row)messages[#messages+1]=P.copy(row);return true end,
  journal={load=function()return{}end,save=function()return true end,ack=function()return true end},view=view}
 s.now=100;s.world_session='fixture-world-session'
 local e={player=b.mc_uuid,to=dim,view=1,pos={13.5,53,7.5},yaw=0,pitch=0,reason=reason}
 assert(s:_begin({session=s.world_session,seq=1},e,b)==true)
 local tx=assert(s.pending[b.pal_uid])
 return{server=s,b=b,tx=tx,event=e,messages=messages,requests=requests,proof=proof,set_ready=function(v)ready=v end,
  counts=function()return moved,activated end,position=function()return P.copy(position)end}
end
local cases={}
for _,reason in ipairs({'join','reconnect','respawn'})do
 local f=fixture(New,'minecraft:overworld',reason);local tx=f.tx
 assert(tx.initial_native_home_from_pal_spawn==true and tx._already_arrived==true)
 assert(equal(tx.target_pawn,tx.source.snapshot.position)and equal(tx.pos,f.event.pos))
 local expected=f.server.registry:required(tx.mapping,{0,64,0})
 assert(equal(tx.required_bounds,expected)and equal(f.requests[1].required_bounds,expected))
 assert(tx.mapping.origin.X==10000 and tx.mapping.origin.Y==20000 and tx.mapping.origin.Z==1000)
end
cases[#cases+1]='initial_join_reconnect_respawn_use_auth_Pal_snapshot_and_actual_feet_coverage'
for _,v in ipairs({{'minecraft:the_nether','reconnect'},{'minecraft:the_end','respawn'},{'minecraft:overworld','teleport'}})do
 local old,new=fixture(Old,v[1],v[2]),fixture(New,v[1],v[2])
 assert(equal(new.tx.target_pawn,old.tx.target_pawn)and equal(new.tx.required_bounds,old.tx.required_bounds))
 assert(new.tx.initial_native_home_from_pal_spawn==nil)
end
cases[#cases+1]='aux_Nether_End_and_ordinary_home_MC_target_unchanged'
local f=fixture(New,'minecraft:overworld','reconnect');local s,tx=f.server,f.tx
tx.client_ready=f.proof(P.request(tx,'client'));s:_progress(tx)
assert(tx.phase=='preparing');local moved,activated=f.counts();assert(moved==0 and activated==0)
f.set_ready(true);tx.client_ready=f.proof(P.request(tx,'client'));s:_progress(tx)
assert(tx.phase=='committed');moved,activated=f.counts();assert(moved==0 and activated==1)
local camera={schema=1,ready=true,source_epoch='synthetic-camera',source_frame=2,source_generation=1,origin_generation=1,origin_frame=1,
 world_session=tx.world_session,dim=tx.dim,view=tx.view,host_scope=P.copy(tx.binding)}
local evidence=f.proof(P.request(tx,'client'));evidence.camera_commit=camera
assert(s:_client{binding=f.b,row=P.message(tx,'client_observed',{proof=evidence,position=f.position(),region_id=tx.mapping.region_id})}==true)
s.now=s.now+s.config.server_settle_ms+1;s:_progress(tx)
assert(tx.phase=='complete'and tx.final.applied==true and equal(tx.final.proof.camera_commit,camera))
assert(f.messages[#f.messages].phase=='complete'and s.stats.completed==1)
cases[#cases+1]='no_premature_ready_original_collision_commit_camera_and_complete_ACK_chain'
print(J.encode{schema=1,passed=true,tests=3,cases=cases,all_native_actor_camera_collision_data_synthetic=true,
 original_source_modules_loaded=true,actual_Game_RPC_SDK_Popen_installed_writes_Git_or_ACK_proven=false})
