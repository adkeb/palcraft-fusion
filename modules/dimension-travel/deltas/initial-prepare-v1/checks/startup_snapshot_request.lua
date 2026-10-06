local root,tmp=assert(arg[1]),assert(arg[2])
local J=dofile('/path/to/workspace/work/minecraft-fusion/native_renderer/stable-v3/json.lua')
local P=dofile(root..'/travel/protocol.lua');local config=dofile(root..'/travel/config.lua')
local function id(n)return('00000000-0000-0000-0000-%012d'):format(n)end
local b={mc_uuid=id(1),pal_uid=id(2),session_id=id(3),generation=1,mc_epoch=id(4),world_id='lab',server_session_id=id(5)}
local v={player=b.mc_uuid,world_session='world-10.1',dim='minecraft:overworld',view=1,waiting_ack=true}
local pos={-8.073118,63.110739,-13.45403}
local registry=P.registry(config);local m=assert(registry:acquire(v.world_session,v.dim,pos,'fixture'))
local tx={binding=b,tx='bootstrap:1',world_session=v.world_session,dim=v.dim,view=v.view}
local function prepare(binding,nonce)
 local t=P.copy(tx);t.binding=P.copy(binding);t.tx=nonce
 return P.message(t,'prepare',{mapping=m,required_bounds=assert(registry:required(m,pos)),pos=pos,yaw=0,pitch=0,target_pawn=P.to_ue(m,pos)})
end
local function append(row)local f=assert(io.open(tmp..'/travel-events.ndjson','ab'));assert(f:write(J.encode(row)..'\n'));f:close()end
local o=dofile(root..'/runtime/client_options.lua').new{json=J,origin=P.copy(config.home_origin),bridge_root=tmp,
 scripts_dir=root..'/client/',travel_dir=root..'/travel/',view_bridge={},game_thread=function()return true end,
 config={identity={world_id=b.world_id,pal_uid=b.pal_uid,mc_uuid=b.mc_uuid},travel_enabled=true,chunk_enabled=true,entities_enabled=false}}
local api={mc_binding=b,mc_view=v,bootstrap_view=function()return v end}
local c={running=true,world={session=nil},origin=P.copy(config.home_origin)}
local ctx={pc={},collisions=c};local w=o.client_world.new(ctx,api)
local foreign=prepare(b,'foreign');foreign.session_id=id(999);append(foreign);w:tick(0,ctx)
assert(o.command_bus.status().queued==0 and w.startup_rejected==1)
append(prepare(b,'bootstrap:1'));w:tick(1,ctx)
assert(o.command_bus.status().queued==1 and w.snapshot_requested_radius==64)
assert(not w:ready()and not w.initial_proof and not w.chunks)
o.command_bus.tick();local f=assert(io.open(tmp..'/command.json','rb'));local q=J.decode(f:read('*a'));f:close()
assert(q.t=='blocksync'and q.r==64 and q.world_session==v.world_session and q.view==1 and q.dim==v.dim)
append(prepare(b,'bootstrap:1'));append(prepare(b,'bootstrap:new-nonce'));w:tick(2,ctx)
assert(o.command_bus.status().queued==0) -- Repeated prepare/new nonce does not duplicate the same scope request.
assert(os.rename(tmp..'/command.json',tmp..'/consumed-command-1.json'))
api.mc_binding=P.copy(b);api.mc_binding.session_id=id(10);api.mc_binding.generation=2
append(prepare(api.mc_binding,'reconnect:1'));w:tick(3,ctx)
assert(o.command_bus.status().queued==1 and w.snapshot_requested_tuple:find(id(10),1,true))
o.command_bus.tick();f=assert(io.open(tmp..'/command.json','rb'));q=J.decode(f:read('*a'));f:close()
assert(q.t=='blocksync'and q.r==64 and q.view==1 and not w:ready())
print(J.encode({schema=1,task='authenticated_startup_snapshot_request',mode='real_factory_and_command_bus_with_data_context',passed=true,
 initial_radius=64,requests_initial_scope=1,requests_same_view_new_mc_scope=1,repeated_nonce_extra_requests=0,
 foreign_scope_requests=0,request_implies_coverage=false,engine_validated=false,runtime_operations=false,
 real_modules={'runtime/client_options.lua','runtime/records.lua','travel/protocol.lua'}}))
