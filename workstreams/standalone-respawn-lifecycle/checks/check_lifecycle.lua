-- Source-only object/IO contracts. No SDK, installed queue, save, or native proof is created.
local root=assert(arg[1]);local source=assert(arg[2]);local J=dofile(assert(arg[3]))
local function module(path,env)return assert(loadfile(path,'t',env))()end
local function suffix(path,s)return path:sub(-#s)==s end
local cases=J.array();local function test(name,f)f();cases[#cases+1]={name=name,passed=true}end

local function boot(which,reason)
 local state={valid=false,reason=reason,dispatcher_ticks=0,service_ticks=0,service_constructions=0,status={}}
 local p={pc={},game_state={},mode='standalone',world_id='ContractWorld',host_uid='11111111-1111-1111-1111-111111111111',
  server_session_id='standalone:contract',process_epoch='contract-process'}
 local realm={current=function()return state.valid and p or nil,state.reason end,
  validate=function(_,proof,pc)return state.valid and proof==p and pc==p.pc end}
 local env=setmetatable({}, {__index=_G});env._G=env;env.IsInGameThread=function()return true end
 local scope={world_directory='ContractWorld',pal_uid=p.host_uid,rpc_root_windows='/contract/rpc/',exchange_root_windows='/contract/exchange/',
  durable_dll_windows='/contract/durable.dll',credit_dll_windows='/contract/credit.dll'}
 env.os=setmetatable({remove=function()return true end,rename=function(a,b)
  state.status[b]=state.status[a];state.status[a]=nil;return true end}, {__index=os})
 env.io={open=function(path,mode)
  if mode=='rb'then return{read=function()return J.encode(scope)end,close=function()return true end}end
  local body='';return{write=function(_,s)body=body..s;return true end,close=function()
   state.status[path]=J.decode(body);return true end}
 end}
 local IO={root=function(p)return p:gsub('/?$','/')end,new=function()return{read=function()return nil end,write=function()return true end}end}
 local Compose=module(root..'/client/runtime/compose.lua',env)
 env.dofile=function(path)
  if suffix(path,'standalone_permissions.lua')then return{new=function()return{authorize=function()error('not invoked by fixture')end}end}end
  if suffix(path,'local_realm.lua')then return{new=function()return realm end}end
  if suffix(path,'readers.lua')then return{}end
  if suffix(path,'standalone_service.lua')then return{new=function()
   state.service_constructions=state.service_constructions+1
   local s={ready=false};function s.tick()state.service_ticks=state.service_ticks+1;s.ready=true end;return s
  end}end
  if suffix(path,'escrow_setup.lua')then return{new=function()return{}end}end
  if suffix(path,'compose.lua')then return Compose end
  if suffix(path,'io.lua')then return IO end
  if suffix(path,'session.lua')then return{registry=function()error('no guest enrollment in this source fixture')end}end
  if suffix(path,'main.lua')then
   local sp=assert(env.PalCraftStandaloneBootstrap)
   local observer=sp.start_early_boot({},J,{})
   state.features=module(root..'/server/features.lua',env).new{runtime_dir='/contract/runtime/',json=J,readers={},
    bridge_root='/contract/bridge/',auth_root='/contract/auth/',origin={X=0,Y=0,Z=0},local_realm=realm,
    game_thread=env.IsInGameThread,entities_enabled=false,fluid_enabled=false,travel_enabled=false,exchange_enabled=false,
    bootstrap_enabled=true,bootstrap={early_observer=observer},companion=function()return nil end,
    load=function(name)
     assert(name=='session-auth');return{new=function()return{tick=function()
      -- The last presence sample may still be valid when the current realm gate fails.
      return{authority=true,world_id=p.world_id,server_session_id=p.server_session_id}
     end}end}
    end}
   return{tick=function(ms)state.dispatcher_ticks=state.dispatcher_ticks+1;return state.features:tick(ms)end}
  end
  error('Unexpected source dependency '..path)
 end
 state.api=module(which..'/client/runtime/standalone_bootstrap.lua',env).new{json=J,paths={
  bridge='/contract/bridge/',journal='/contract/rpc/',join=function(s)return s end},
  client_features=function()return nil end,client_control={}}
 return state
end

test('uninitialized_levels_or_temporary_saved_host_gate_resume_original_observer',function()
 for _,reason in ipairs({'Initialized MainWorld levels required','Owned saved native host missing'})do
  local old=boot(root,reason);old.api:tick(0);old.valid=true;old.api:tick(1000)
  assert(old.features.composition.features.exchange_bootstrap.phase=='error'and old.service_ticks==0)
  local new=boot(source,reason);new.api:tick(0)
  assert(new.dispatcher_ticks==0 and new.service_ticks==0)
  local status=assert(new.status['/contract/bridge/standalone-runtime-status.json'])
  assert(status.authority==false and status.dispatcher_ok==false and status.dispatcher_error==reason)
  new.valid=true;new.api:tick(1000)
  assert(new.features.composition.features.exchange_bootstrap.phase=='running'and new.service_ticks==1)
  assert(new.service_constructions==1,'The original observer/service is retained, not reconstructed')
  status=new.status['/contract/bridge/standalone-runtime-status.json']
  assert(status.authority==true and status.dispatcher_ok==true)
 end
end)

test('serious_permission_failure_never_reuses_prior_verified_gate_or_reports_ready',function()
 local s=boot(source,'Runtime observation belongs to another actual process')
 s.valid=true;s.api:tick(0);assert(s.service_ticks==1)
 s.valid=false;s.api:tick(1000)
 assert(s.service_ticks==1 and s.dispatcher_ticks==1)
 local status=s.status['/contract/bridge/standalone-runtime-status.json']
 assert(status.authority==false and status.dispatcher_ok==false and status.game_ready==false)
 assert(status.dispatcher_error=='Runtime observation belongs to another actual process')
end)

test('successful_original_client_stop_abandons_old_lease_but_live_or_failed_stop_does_not',function()
 local proof={mode='standalone',server_session_id='standalone:contract',world_id='ContractWorld',host_uid='11111111-1111-1111-1111-111111111111',pc={}}
 local valid=true;local releases,cleanups=0,0;local stop_ok=true;local current
 local realm={current=function()return valid and proof or nil end,validate=function()return valid end,same_world=function()return valid end}
 local env=setmetatable({}, {__index=_G});env.IsInGameThread=function()return true end
 env.dofile=function(path)
  if suffix(path,'io.lua')then return{new=function()return{read=function()return nil end}end}end
  if suffix(path,'session.lua')then return{}end
  if suffix(path,'records.lua')then return{commands=function()return{}end}end
  error('Unexpected source dependency '..path)
 end
 local factory=module(root..'/client/runtime/client_options.lua',env).new{json=J,config={identity={},chunk_enabled=true,entities_enabled=false},
  bridge_root='/contract/bridge/',scripts_dir='/contract/scripts/',origin={X=0,Y=0,Z=0},view_bridge={},game_thread=env.IsInGameThread}
 local request={mode='server',player='22222222-2222-2222-2222-222222222222',session_id='contract-session',mc_epoch='contract-epoch',
  session_generation=1,world_session='contract-world',dim='minecraft:overworld',view=3,mapping={region_id='contract-region'}}
 local function owner()
  local companion={running=true,world={session=request.world_session},context=function()return{}end}
  local binding={pal_uid=proof.host_uid,world_id=proof.world_id,server_session_id=proof.server_session_id,mc_uuid=request.player,
   session_id=request.session_id,generation=1,mc_epoch=request.mc_epoch}
  local w=factory.client_world.new({pc=proof.pc,collisions=companion},{mc_binding=binding});w.started=true
  local token={};companion.chunk_consumer=token
  w.chunks={bridge={installed=true,binding=token},view={
   prepare_view=function(r)return{world_session=r.world_session,dim=r.dim,view=r.view,region_id=r.mapping.region_id,generation=1}end,
   release=function()releases=releases+1;return true end},stop=function()cleanups=cleanups+1;return stop_ok end}
  current=w;return w
 end
 local options={local_realm=realm,client_worker=function()return current end,game_thread=env.IsInGameThread}
 local old=module(root..'/server/runtime/standalone_views.lua',env).new(options)
 local w=owner();local t=old.prepare_view(request);assert(w:stop('contract',{})==true)
 local ok,why=pcall(old.release,t);assert(not ok and tostring(why):find('Dead shared world requires abandon',1,true))
 assert(releases==0)
 local new=module(source..'/server/runtime/standalone_views.lua',env).new(options)
 w=owner();t=new.prepare_view(request);assert(w:stop('contract',{})==true)
 assert(new.release(t)==true and t.abandoned==true and releases==0)
 assert(new.status().owned_server_leases==0)
 w=owner();t=new.prepare_view(request);stop_ok=false
 assert(pcall(w.stop,w,'contract',{})==false and w.stopped~=true)
 valid=false;assert(pcall(new.release,t)==false and not t.abandoned and releases==0)
 valid=true;assert(new.release(t)==true and t.released==true and releases==1)
 assert(cleanups==3)
end)

print(J.encode{ok=true,cases=cases,targeted_cases=#cases,existing_source_modules_loaded=true,
 fixture_only=true,actual_save_or_ACK_or_recovery_proven=false,installed_files_game_RPC_or_queue_changed=false})
