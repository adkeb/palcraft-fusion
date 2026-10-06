-- Exercise the actual facade, not an engine or ticket/ACK implementation.
local Views=dofile(assert(arg[1])..'/source/runtime/standalone_views.lua')
local proof={mode='standalone',world_id='world',host_uid='host',server_session_id='standalone:life',pc={},game_state={}}
local worker;local generation=9;local calls=0
local realm={current=function()return proof end,
 validate=function(_,p,pc)return p==proof and(not pc or pc==proof.pc)end,
 same_world=function(_,ctx,p)return p==proof and ctx==proof.game_state end}
local request={mode='server',world_session='mcworld',dim='minecraft:overworld',view=1,
 player='mc',session_id='native-MC-lease',session_generation=1,mc_epoch='MC-epoch',
 mapping={region_id='home'},required_bounds={0,0,0,16,16,16}}
local api=Views.new{local_realm=realm,client_worker=function()return worker end,game_thread=function()return true end}
local checks=0;local function check(v,why)assert(v,why);checks=checks+1 end
local ticket=api.prepare_view(request)
check(ticket.generation==nil and ticket.native==nil and calls==0,'Pending wrapper must not invent a renderer generation')
local binding={};local view={prepare_view=function(r)
 calls=calls+1
 return{world_session=r.world_session,dim=r.dim,view=r.view,region_id=r.mapping.region_id,generation=generation}
end,readiness=function(t)return{world_session=t.world_session,dim=t.dim,view=t.view,region_id=t.region_id,
 renderer_generation=t.generation,ready=false,coverage_complete=false,collision_committed=false}end}
worker={ctx={pc=proof.pc},companion={running=true,world={session='mcworld'},chunk_consumer=binding,
 context=function()return proof.game_state end},features={mc_binding={pal_uid='host',world_id='world',server_session_id=proof.server_session_id,
 mc_uuid='mc',session_id=request.session_id,generation=1,mc_epoch=request.mc_epoch}},chunks={view=view,bridge={installed=true,binding=binding}},host_generation=609}
local readiness=api.readiness(ticket)
check(ticket.generation==9 and ticket.generation==ticket.native.generation,'Wrapper must copy the actual native ticket generation')
check(ticket.session_generation==1 and ticket.generation~=1 and ticket.generation~=worker.host_generation,'Renderer/MC/HOST generations must stay distinct')
check(readiness.ready==false and readiness.renderer_generation==9,'Copying generation may not change native readiness')
api.readiness(ticket)
check(calls==1,'The existing native ticket must be reused')
for _,bad in ipairs({0,-1,1.5,'9'})do
 generation=bad;check(not pcall(api.prepare_view,request),'Invalid native generation was accepted')
end
generation=nil;check(not pcall(api.prepare_view,request),'Missing native generation was fabricated')
print('PASS '..checks..' native view generation checks; mocked facade only, no game/RPC/ACK')
