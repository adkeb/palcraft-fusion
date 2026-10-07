-- Three bounded synthetic real-function cases; no actual game, Saved, ACK or Popen.
local work,dir=assert(arg[1]),assert(arg[2]);local J=dofile(work..'/../palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function part(s,a,b)local i=assert(s:find(a,1,true));local k=assert(s:find(b,i+1,true));return s:sub(i,k-1)end
local source=read(dir..'/source/client/main.lua');local original=read(dir..'/base/client/main.lua')
assert(part(source,'local function physical_stop_ready(','function client_control.stop(')==part(original,'local function physical_stop_ready(','function client_control.stop('))
assert(part(source,'function client_control.stop(','local function saved_shutdown_scope(')==part(original,'function client_control.stop(','function client_control.start('))
local code=part(source,'local function control_context(','function client_control.start(')
local cases={};local function test(name,f)f();cases[#cases+1]=name end
local function fixture()
 local alive=true;local calls={};local function mark(s)calls[#calls+1]=s end
 local world={IsValid=function()return alive end};local gs={IsValid=function()return alive end}
 local pc={};local epoch='synthetic-process:1'
 local proof={mode='standalone',world=world,game_state=gs,pc=pc,world_address=11,world_id='fixture-world',host_uid='fixture-uid',server_session_id='fixture-SID',process_epoch=epoch,
  save_manager={IsWorldAutoSaving=function()return false end}}
 local realm={current=function()return alive and proof or nil end,validate=function(_,p,c)return alive and p==proof and c==pc end,same_world=function(_,c,p)return alive and c==gs and p==proof end}
 local scope={token=string.rep('a',32),native_scope={world_id=proof.world_id,pal_uid=proof.host_uid,server_session_id=proof.server_session_id,process_epoch=epoch,pid=1,process_created_filetime='2'}}
 local witness={native_scope=scope.native_scope,normal_save_completed=true,after_submission=true,stable=true,normal_save_id='fixture-original-save'}
 local files={['current.json']={token=scope.token},[scope.token..'/scope.json']=scope,[scope.token..'/normal-save-file-witness.json']=witness}
 local origin={X=1,Y=2,Z=3};local map={native_overworld=true,dim='minecraft:overworld',world_session='fixture-MC-world',region_id='owned-home',origin=origin}
 local function ticket(view)return{world_session=map.world_session,dim=map.dim,view=view,region_id=map.region_id,realm=proof}end
 local old,target=ticket(1),ticket(2)
 local travel={pending={[proof.host_uid]={phase='recovery_required',_needs_recover=true,_ticket=target,_lock={},mapping=map,world_session=map.world_session,dim=map.dim,view=2}},
  players={[proof.host_uid]={_ticket=old,mapping=map,world_session=map.world_session,dim=map.dim,view=1}}}
 local view={recovery_scenes={},leases=2,status=function()return{owned_server_leases=2}end}
 function view.status()return{owned_server_leases=view.leases}end
 function view.release(t)assert(alive,'Live release only');mark('release'..t.view);view.leases=view.leases-1;table.remove(view.recovery_scenes);return true end
 function view.abandon(t)assert(not alive,'Actual dead world required');mark('abandon'..t.view);view.leases=view.leases-1;table.remove(view.recovery_scenes);return true end
 local sf={composition={features={travel={phase='running',instance=travel}}}}
 function sf:stop(reason,ctx)
  mark('server.stop:'..tostring(ctx.context_alive));assert(reason=='normal_saved_shutdown')
  if ctx.context_alive then mark('original-owned-lock-release')end
  view.recovery_scenes={{ticket=old,mapping=map,pal_uid=proof.host_uid},{ticket=target,mapping=map,pal_uid=proof.host_uid}}
  return true
 end
 local c={context_alive=function()return alive end,context=function()return gs end,status_json=function()return'{}'end}
 function c.stop(context_alive)mark('companion.stop:'..tostring(context_alive));if not context_alive then mark('original.abandon')end end
 local cf={status=function()return{}end,stop=function(_,reason,ctx)mark('client.stop:'..tostring(ctx.context_alive));return true end}
 local env={client_control={},standalone={realm=realm},runtime_config={identity={world_id=proof.world_id,pal_uid=proof.host_uid}},identity={},collisions=c,features=cf,
  Paths={join=function(p)return p end},J=J,view_state={held=true,mapping=map},home_origin=origin,
  view_thread=function()return true end,native_suspend=function()mark('suspend')end,
  client_view={reset=function(_,live)mark('view.reset:'..tostring(live))end},form={stop=function()assert(alive,'No dead form SDK');mark('form.stop')end}}
 env.io={open=function(path)
  local name=path:match('journal%-lifecycle/(.+)$');local value=files[name];assert(value,'Fixture input missing')
  return{read=function()return J.encode(value)end,close=function()end}
 end}
 setmetatable(env,{__index=_G});assert(load(code,'@exact-main-stop-functions','t',env))()
 local permissions={process=function()return{read_only=true},epoch end}
 local facadeenv=setmetatable({_G={PalCraftStandalonePermissions=permissions},FindAllOf=function()return{{IsValid=function()return true end,Player={IsValid=function()return true end,GetFullName=function()return'PalLocalPlayer Fixture'end},GetFullName=function()return'BP_PalPlayerController_Title_C Fixture'end}}end},{__index=_G})
 local facade=assert(loadfile(dir..'/source/server/runtime/standalone_world.lua','t',facadeenv))().new{local_realm=realm,client_worker=function()end,client_control=env.client_control,game_thread=function()return true end}
 assert(facade.native_context()==gs);facade.view=view
 local request={kind='normal_saved_world_shutdown_v1',action='return_title',token=scope.token,normal_save_id=witness.normal_save_id}
 return{calls=calls,env=env,proof=proof,request=request,files=files,witness=witness,sf=sf,view=view,travel=travel,facade=facade,map=map,
  dead=function()alive=false end}
end

test('real_normal_saved_entry_tears_down_owned_recovery_source_and_target_views_original_operator_refuses',function()
 local f=fixture();local old=f.env.client_control.stop(f.sf,f.proof,f.view)
 assert(old.stop_ok==false and#f.calls==0)
 local result=f.facade.normal_saved_shutdown(f.sf,f.request)
 assert(result.stop_ok==true and result.context_alive==true and f.view.leases==0)
 assert(table.concat(f.calls,',')=='suspend,server.stop:true,original-owned-lock-release,release2,release1,view.reset:true,form.stop,companion.stop:true,client.stop:true')
end)

test('false_Save_wrong_saved_scope_auxiliary_or_foreign_lease_refused_before_any_cleanup',function()
 for _,kind in ipairs({'save_false','scope_foreign','auxiliary','foreign_lease','unknown_lease'})do
  local f=fixture()
  if kind=='save_false'then f.witness.normal_save_completed=false
  elseif kind=='scope_foreign'then f.files[f.request.token..'/scope.json']={token=f.request.token,native_scope={world_id='another-world'}}
  elseif kind=='auxiliary'then f.map.native_overworld=false
  elseif kind=='foreign_lease'then f.travel.pending.foreign=f.travel.pending[f.proof.host_uid]
  else f.view.leases=3 end
  assert(not pcall(f.facade.normal_saved_shutdown,f.sf,f.request)and#f.calls==0)
 end
end)

test('fresh_Title_and_known_dead_original_world_use_abandon_without_old_world_UObject_calls',function()
 local f=fixture();f.dead();local result=f.facade.normal_saved_shutdown(f.sf,f.request)
 assert(result.stop_ok==true and result.context_alive==false and f.view.leases==0)
 assert(table.concat(f.calls,',')=='suspend,server.stop:false,abandon2,abandon1,view.reset:false,companion.stop:false,original.abandon,client.stop:false')
end)
print(J.encode{ok=true,tests=3,cases=cases,synthetic_only=true,exact_new_main_and_facade_functions=true,
 original_operator_guard_and_function_byte_equal=true,existing_stop_callbacks_are_scoped_fixture_adapters=true,
 actual_Game_Save_ACK_or_native_release=false})
