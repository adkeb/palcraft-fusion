local ROOT=assert(arg[1]);local Views=dofile(ROOT..'/source/runtime/standalone_views.lua')
local checks=0;local function check(x,m)checks=checks+1;assert(x,m)end
local function request()return{mode='server',player='mc',world_session='mcworld',dim='minecraft:overworld',view=2,
 session_id='session',session_generation=3,mc_epoch='epoch',mapping={region_id='home',origin={X=1,Y=2,Z=3},mc_anchor={0,0,0}},required_bounds={0,0,0,16,64,16}}end
local p={mode='standalone',server_session_id='standalone:real-life',world_id='world',host_uid='host',pc={},game_state={}}
local actual=p;local worker;local ready=false;local native_prepares,releases,activations,stops=0,0,0,0
local realm={current=function()return actual end,validate=function(_,proof,pc)return actual and proof.server_session_id==actual.server_session_id and(not pc or pc==actual.pc)end,
 same_world=function(_,object,proof)return actual and proof.server_session_id==actual.server_session_id and object==actual.game_state end}
local api=Views.new{local_realm=realm,client_worker=function()return worker end,game_thread=function()return true end}
actual=nil;check(not pcall(api.prepare_view,request()),'Title cannot prepare a standalone scene');actual=p
local q=request();local t=api.prepare_view(q);check(native_prepares==0,'No consumer/actor allocated before real worker')
local proof=api.readiness(t);check(proof.ready==false and proof.collision_committed==false,'Pending lease never declares collision commit')
local view={prepare_view=function(r)native_prepares=native_prepares+1;check(r.mode=='client','Use existing client physical mode');check(r.mapping.region_id=='home'and r.world_session=='mcworld','Original mapping/epoch retained');return{world_session=r.world_session,dim=r.dim,view=r.view,region_id=r.mapping.region_id,request=r}end,
 readiness=function(n)return{ready=ready,coverage_complete=ready,collision_committed=ready,world_session=n.world_session,dim=n.dim,view=n.view,region_id=n.region_id}end,
 activate=function()activations=activations+1;return true end,release=function()releases=releases+1;return true end,
 retirement_status=function(id)return{region_id=id,can_recycle=false,state='active'}end}
local binding={};local companion={running=true,world={session='mcworld'},chunk_consumer=binding,context=function()return p.game_state end,set_view=function(dim,player)check(dim=='minecraft:overworld'and player=='mc','Native cutover changes original reducer view')end}
worker={ctx={pc=p.pc},companion=companion,features={mc_binding={pal_uid='host',world_id='world',server_session_id=p.server_session_id,
 mc_uuid='mc',session_id='session',generation=3,mc_epoch='epoch'}},chunks={view=view,bridge={installed=true,binding=binding}}}
proof=api.readiness(t);check(native_prepares==1 and proof.ready==false,'Real pending native ticket is not replaced with fake readiness')
check(q.mode=='server','Caller request is never mutated');check(not pcall(api.activate,t),'Uncommitted native view cannot activate')
ready=true;check(api.readiness(t).ready==true,'Actual native readiness can pass');check(api.activate(t)and activations==1,'Actual native activation used')
check(api.can_recycle('home')==false,'Occupied actual scene not recyclable')
check(api.release(t)and releases==1 and stops==0 and companion.running,'Server releases only its owned native reference')
worker.features.mc_binding.generation=4;local t2=api.prepare_view(request());check(api.readiness(t2).ready==false and native_prepares==1,'Wrong authenticated tuple cannot prepare another scene')
worker.features.mc_binding.generation=3;local t3=api.prepare_view(request());check(native_prepares==2,'Reuse same view facade, not second physical factory')
actual={mode='standalone',server_session_id='new-life',world_id='world',host_uid='host',pc=p.pc,game_state={}}
check(api.readiness(t3).ready==false,'Real realm change invalidates old proof');check(api.abandon(t3)and releases==1 and stops==0,'Dead realm facade uses no native or UObject cleanup')
print('PASS standalone views '..checks..' checks; mocked facade only, no game/RPC/DLL')
