-- Targeted checks of the actual candidate functions. No engine, RPC or timer.
local root=assert(arg[1]);local checks=0
local function check(ok,why)assert(ok,why);checks=checks+1 end
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local main=read(root..'/source/client/main.lua')
local controls=assert(main:match('(local function control_context%(proof%).-)local function player%(now%)'))
local loop=assert(main:match(" connection%('in_bridgelab'%)\n(.-) stage%('discovery',started%);started=os.clock%(%)"))
local function owner()
 local calls={};local pc={};local proof={pc=pc,host_uid='host',world_id='world',server_session_id='sid'}
 local env=setmetatable({},{__index=_G});local valid=true
 local function record(s)calls[#calls+1]=s end
 env.client_control={};env.operator_paused=false;env.control_stop_ok=nil
 env.view_thread=function()record('thread')end
 env.standalone={realm={validate=function(_,p,c)return valid and p==proof and c==pc end,
  same_world=function(_,context,p)return context==pc and p==proof end}}
 env.runtime_config={identity={pal_uid='host',world_id='world'}}
 env.identity={server_session_id='sid'};env.session='sid';env.view_state={held=false,mapping={native_overworld=true,world_session='mcworld',dim='minecraft:overworld',view=1}}
 local companion={running=true}
 companion.context_alive=function()return true end;companion.context=function()return pc end
 companion.status_json=function()return{running=companion.running,blocks=17,ready=false}end
 companion.stop=function(alive)record('companion_stop:'..tostring(alive));companion.running=false end
 env.collisions=companion;env.J={decode=function(s)return s end}
 env.native_suspend=function()record('suspend')end
 env.client_view={reset=function(_,alive)record('view_reset:'..tostring(alive));return true end}
 env.form={stop=function()record('form_stop')end}
 env.features={running=true,status=function(self)return{running=self.running,ready=false}end,
  stop=function(self,_,ctx)record('client_stop:'..tostring(ctx.context_alive));self.running=false;return true end,
  start=function(self)record('client_start');self.running=true;return true end}
 env.camera_file=nil;env.dir='unused/';env.now=0;env.next_ui=1;env.next_status=1;env.started=0
 env.stage=function()end;env.profile=function()end
 env._G={PalCraftCollisionCompanion=companion}
 local server={running=true,composition={features={travel={phase='disabled'}}},stop=function(self,_,ctx)record('server_stop');self.running=false;self.stop_context=ctx;return true end,
  dispatch=function(self,method)record(method);self.running=true;return true,{running=true}end}
 assert(load(controls,'actual_client_controls','t',env))()
 return env,server,proof,calls,companion,function(v)valid=v end
end
local env,server,proof,calls,c,validate=owner()
local s=env.client_control.status(nil,proof)
check(s.running and s.blocks==17 and s.ready==false,'Status must read the actual companion')
env.client_control.stop(server,proof)
local physical={};for _,v in ipairs(calls)do if v~='thread'then physical[#physical+1]=v end end
check(table.concat(physical,',')=='suspend,server_stop,view_reset:true,form_stop,companion_stop:true,client_stop:true','Existing cleanup order changed')
check(env.operator_paused and env.collisions==nil and not c.running and env._G.PalCraftCollisionCompanion==nil,'Stop must retire the real owner and pause')
check(env.client_control.status(nil,proof).running==false and env.control_stop_ok==true,'Stop status must follow completed cleanup')
local factories=0;env.dofile=function()factories=factories+1;return c end
assert(load(loop,'actual_paused_loop','t',env))()
check(factories==0 and env.collisions==nil,'Paused original loop recreated the companion')
s=env.client_control.start(server,proof)
check(not env.operator_paused and env.features.running and server.running and not s.running and s.client_features.ready==false,'Restart may not claim native readiness')
assert(load(loop,'actual_resumed_loop','t',env))()
check(factories==1 and env.collisions==c,'Only the original loop may recreate the companion')
env,server,proof,calls,c,validate=owner();validate(false)
check(not pcall(env.client_control.stop,server,proof)and c.running and not env.operator_paused,'Invalid actual realm must not mutate')
env,server,proof,calls,c=owner();env.view_state.held=true
check(env.client_control.stop(server,proof).stop_ok==false and c.running and not env.operator_paused,'Held travel must preserve physical scenes')
env,server,proof,calls,c=owner();env.view_state.mapping.native_overworld=false
check(env.client_control.stop(server,proof).stop_ok==false and c.running and not env.operator_paused,'Auxiliary occupied scene must be preserved')
env,server,proof,calls,c=owner();server.stop=function()return false end
check(not pcall(env.client_control.stop,server,proof)and env.operator_paused and c.running and env.control_stop_ok==false,'Failed server cleanup must not retire client scenes')
check(not pcall(env.client_control.start,server,proof)and env.operator_paused,'Failed cleanup must not silently restart')
for _,phase in ipairs({'preparing','moving','committed','finalizing','recovery_required'})do
 env,server,proof,calls,c=owner()
 server.composition.features.travel={phase='running',instance={pending={host={phase=phase}},players={}}}
 check(env.client_control.stop(server,proof).stop_ok==false and not env.operator_paused and c.running,'Unfinished server travel must retain its floor:'..phase)
end
env,server,proof,calls,c=owner();server.composition.features.travel=nil
check(env.client_control.stop(server,proof).stop_ok==false and not env.operator_paused,'Missing authoritative travel state is pending')
env,server,proof,calls,c=owner();server.composition.features.travel={phase='waiting'}
check(env.client_control.stop(server,proof).stop_ok==false and not env.operator_paused,'Unstarted authoritative travel may not claim no scenes')
env,server,proof,calls,c=owner()
local mapping={native_overworld=true,dim='minecraft:overworld',world_session='mcworld',region_id='home'}
local ticket={realm=proof,world_session='mcworld',dim='minecraft:overworld',view=1,region_id='home'};local leases=1;local releases,abandons=0,0
local view={recovery_scenes={},status=function()return{owned_server_leases=leases}end}
view.release=function(t)
 check(t==ticket,'Release must use the actual owned server ticket');releases=releases+1;leases=0
 table.remove(view.recovery_scenes);calls[#calls+1]='server_ticket_release';return true
end
view.abandon=function()abandons=abandons+1;return true end
server.composition.features.travel={phase='running',instance={pending={host={phase='complete',_ticket=ticket,mapping=mapping}},players={host={_ticket=ticket,mapping=mapping}}}}
local original_stop=server.stop
server.stop=function(self,reason,ctx)
 local good=original_stop(self,reason,ctx)
 view.recovery_scenes[1]={ticket=ticket,mapping=mapping,pal_uid='host',occupied=true};return good
end
check(env.client_control.stop(server,proof,view).stop_ok and releases==1 and abandons==0 and leases==0,'Native-home stop must explicitly release the owned server reference once')
local positions={};for i,v in ipairs(calls)do positions[v]=i end
check(positions.server_stop<positions.server_ticket_release and positions.server_ticket_release<positions['companion_stop:true'],'Owned server release must precede physical teardown')
check(env.client_control.stop(server,proof,view).stop_ok and releases==1,'Completed operator stop must be idempotent')
env,server,proof,calls,c=owner()
local unknown={recovery_scenes={},status=function()return{owned_server_leases=1}end}
check(env.client_control.stop(server,proof,unknown).stop_ok==false and not env.operator_paused and c.running,'Untracked borrowed references must not be discarded')
env,server,proof,calls,c=owner();env.view_state.held=true;env.view_state.mapping.native_overworld=false
c.context_alive=function()return false end
leases=1;abandons=0
local dead={recovery_scenes={{ticket={},mapping={native_overworld=false}}},status=function()return{owned_server_leases=leases}end,
 release=function()error('Dead context may not release a live native ticket')end}
dead.abandon=function()abandons=abandons+1;leases=0;table.remove(dead.recovery_scenes);return true end
check(env.client_control.stop(server,proof,dead).stop_ok and abandons==1 and server.stop_context.context_alive==false,'Dead context must abandon without the live-floor guard or live release')

-- Exercise the real feature composition restart, with only an inert cleanup probe.
local Features=dofile(root..'/source/client/features.lua')
local shared=assert(arg[2]);local json={decode=function(v)return v end}
local features=Features.new{json=json,bridge_root='unused',runtime_dir=shared..'/palcraft/runtime/',
 game_thread=function()return true end,entities_enabled=false,files={read=function()return nil end}}
local starts,stops=0,0
features.composition:register('cleanup_probe',{factory=function()starts=starts+1;return{}end,
 stop=function()stops=stops+1 end})
features.composition:tick(1,{context_alive=true})
check(features:stop('operator_stop',{context_alive=true})and stops==1 and features.composition.stopped,'Real stop must call the composition cleanup')
check(features:start('operator_start',{context_alive=true})and not features.composition.stopped and features.running and not features:status().ready,'Real restart must remain pending normal host readiness')
features.composition:tick(2,{context_alive=true})
check(starts==2 and stops==1,'Real restart must reuse the existing composition')
features:start('operator_start',{context_alive=true})
check(starts==2 and stops==1,'Start must preserve an already running composition')
local ServerFeatures=dofile(root..'/source/server/features.lua')
local server_features=ServerFeatures.new{json=json,readers={},bridge_root='unused',runtime_dir=shared..'/palcraft/runtime/',
 game_thread=function()return true end,entities_enabled=false,files={read=function()return nil end},
 load=function(name)assert(name=='session-auth');return{new=function()return{tick=function()return{authority=false}end}end}end}
local stopped_context
server_features.composition:register('context_probe',{factory=function()return{}end,stop=function(_,_,ctx)stopped_context=ctx end})
server_features.composition:tick(1,server_features)
local dead_context={context_alive=false}
check(server_features:stop('operator_stop',dead_context)and stopped_context==dead_context,'Actual server cleanup must receive the observed context lifetime')

local World=dofile(root..'/source/runtime/standalone_world.lua')
local realm_proof={mode='standalone',pc={}};local realm_valid=true;local routed={}
local world=World.new{local_realm={current=function()return realm_proof end,
 validate=function()return realm_valid end},client_worker=function()end,
 client_control={start=function(f,p)routed.start={f,p};return'normal_start'end,
 stop=function(f,p)routed.stop={f,p};return'normal_stop'end,
 status=function(f,p)routed.status={f,p};return'real_status'end}}
check(world.start(server)=='normal_start'and world.stop(server)=='normal_stop'and world.control_status()=='real_status'
 and routed.start[1]==server and routed.start[2]==realm_proof,'World must route controls to the existing owner')
realm_valid=false
check(not pcall(world.start,server),'World control must revalidate the real realm')

local bridge=read(root..'/source/server/bridge-main.lua')
local first=assert(bridge:find(" elseif method=='palcraft_start'then",1,true))
local last=assert(bridge:find(" elseif method=='palcraft_identity'then",first,true))
local routes=bridge:sub(first,last-1):gsub('^ elseif',' if')
local routed_env=setmetatable({standalone={start=function(f)return{operation='start',owner=f}end,
 stop=function(f)return{operation='stop',owner=f}end,control_status=function()return{running=true,blocks=23}end},
 feature_api=function()return server end,J={decode=function(v)return v end}},{__index=_G})
local dispatch=assert(load('return function(method)\n'..routes..'\n end\nend','actual_bridge_control_routes','t',routed_env))()
check(dispatch('palcraft_start').owner==server and dispatch('palcraft_stop').owner==server,'Bridge must use the existing Standalone lifecycle')
check(dispatch('palcraft_status').running and dispatch('palcraft_status').blocks==23,'Bridge status must not read the dedicated singleton')
routed_env.standalone=nil
check(dispatch('palcraft_status').running==false and dispatch('palcraft_stop').running==false,'Unselected dedicated branches must be preserved')
print('PASS '..checks..' targeted control lifecycle checks; no engine/RPC/timer')
