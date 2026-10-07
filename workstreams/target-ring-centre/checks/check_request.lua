-- One target-request case; all files and command writes remain inside this fixture directory.
local delta=assert(arg[1]);local work=assert(arg[2]);local J=dofile(delta..'/checks/deps/json.lua')
local P=dofile(delta..'/checks/deps/protocol.lua')
local real_dofile=dofile
local env=setmetatable({},{__index=_G})
env.dofile=function(path)
 local name=path:match('([^/]+)$')
 if name=='io.lua'or name=='session.lua'or name=='records.lua'or name=='protocol.lua'then
  return real_dofile(delta..'/checks/deps/'..name)
 end
 error('unexpected fixture module: '..path)
end
local function id(n)return('00000000-0000-0000-0000-%012d'):format(n)end
local b={mc_uuid=id(1),pal_uid=id(2),session_id=id(3),generation=1,mc_epoch='fixture-epoch',world_id='fixture-world',server_session_id='fixture-pal-session'}
local v={player=b.mc_uuid,world_session='fixture-MC-world',dim='minecraft:overworld',view=1,waiting_ack=true}
local origin={X=0,Y=0,Z=0}
local mapping={region_id='fixture/native',world_session=v.world_session,dim=v.dim,native_overworld=true,
 origin=origin,center=origin,mc_anchor={0,64,0},scale=100,y_origin=64,region_bounds={-900000,-900000,-30000,900000,900000,30000}}
local bounds={-66,46,-70,63,94,59}
local row=P.message({tx='fixture:38',binding=b,world_session=v.world_session,dim=v.dim,view=v.view},'prepare',
 {mapping=mapping,required_bounds=bounds,pos={13.5,53,7.5},target_pawn={X=-150,Y=550,Z=-50}})
local options=assert(loadfile(delta..'/source/client/runtime/client_options.lua','t',env))().new{
 json=J,origin=origin,bridge_root=work,scripts_dir=delta..'/checks/deps',travel_dir=delta..'/checks/deps',
 view_bridge={},game_thread=function()return true end,files={read=function()return nil end},
 config={identity={world_id=b.world_id,pal_uid=b.pal_uid,mc_uuid=b.mc_uuid},travel_enabled=true,chunk_enabled=true,entities_enabled=false}}
local worker=options.client_world.new({collisions={running=true}}, {mc_binding=b,mc_view=v})
assert(worker:request_target_snapshot(row,b,v)==true)
assert(worker.snapshot_requested_radius==64 and options.command_bus.status().queued==1)
options.command_bus.tick()
local f=assert(io.open(work..'/command.json','rb'));local q=J.decode(f:read('*a'));f:close()
assert(q.t=='blocksync'and q.r==64 and q.tx==row.tx and q.world_session==v.world_session and q.dim==v.dim and q.view==v.view)
for i=1,6 do assert(q.required_bounds[i]==bounds[i])end
assert(q.required_bounds~=bounds and row.pos[1]==13.5 and row.pos[3]==7.5 and not worker.started and not worker.chunks)
print(J.encode({name='root_numbers_request_uses_bounds_center_and_preserves_tx_pos_full_ring',passed=true,
 old_wrong_radius=79,requested_radius=64,bounds=bounds,center={-2,-6},request_implies_readiness=false,fixture_only=true}))
