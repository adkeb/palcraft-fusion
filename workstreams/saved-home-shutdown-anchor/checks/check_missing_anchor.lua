-- Three bounded synthetic cases of the exact loaded main functions; no Game, Saved, ACK, or runtime closure apply.
local work,dir=assert(arg[1]),assert(arg[2]);local J=dofile(work..'/../palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function part(s,a,b)local i=assert(s:find(a,1,true));local k=assert(s:find(b,i+1,true));return s:sub(i,k-1)end
local source=read(dir..'/source/client/main.lua');local original=read(dir..'/base/client/main.lua')
local marker='local function saved_home_cleanup_ready(';local after='function client_control.normal_saved_shutdown'
assert(source:sub(1,assert(source:find(marker,1,true))-1)==original:sub(1,assert(original:find(marker,1,true))-1))
assert(source:sub(assert(source:find(after,1,true)))==original:sub(assert(original:find(after,1,true))))
local code=part(source,'local function control_context(','function client_control.start(')
local original_code=part(original,'local function control_context(','function client_control.start(')
local cases={};local function test(name,f)f();cases[#cases+1]=name end
local function clone(v)return J.decode(J.encode(v))end
local function fixture(use_original)
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
 setmetatable(env,{__index=_G});env.predicate=assert(load((use_original and original_code or code)..'\nreturn saved_home_cleanup_ready','@exact-main-stop-functions','t',env))()
 local request={kind='normal_saved_world_shutdown_v1',action='return_title',token=scope.token,normal_save_id=witness.normal_save_id}
 return{calls=calls,env=env,proof=proof,request=request,files=files,witness=witness,sf=sf,view=view,travel=travel,map=map,
  old=old,target=target,dead=function()alive=false end}
end


local function shutdown(f)
 return f.env.client_control.normal_saved_shutdown(f.sf,f.proof,f.view,f.request,false)
end
local expected='suspend,server.stop:true,original-owned-lock-release,release2,release1,view.reset:true,form.stop,companion.stop:true,client.stop:true'
test('missing_and_partial_home_anchor_validate_real_dual_view_fixture_tickets_then_original_cleanup',function()
 for _,mode in ipairs({'missing','partial','pending_only','recovery_only'})do
  local f=fixture();f.env.view_state.mapping=nil
  if mode=='partial'then local p=clone(f.map);p.world_session=nil;p.view=nil;f.env.view_state.mapping=p
  elseif mode=='pending_only'then f.travel.players={};f.view.recovery_scenes={{ticket=f.old,mapping=f.map,pal_uid=f.proof.host_uid}}
  elseif mode=='recovery_only'then f.travel.players={};f.travel.pending={};f.view.recovery_scenes={{ticket=f.old,mapping=f.map,pal_uid=f.proof.host_uid},{ticket=f.target,mapping=f.map,pal_uid=f.proof.host_uid}}end
  local before=f.env.view_state.mapping;assert(f.env.predicate(f.sf,f.proof,f.view)==true)
  assert(f.env.view_state.mapping==before,'Only local source anchor may change')
  local result=shutdown(f);assert(result.stop_ok==true and result.context_alive==true and f.view.leases==0)
  assert(table.concat(f.calls,',')==expected,'Original cleanup ordering changed')
 end
end)
local function corrupt(f,kind)
 if kind=='foreign_uid'then f.travel.pending.foreign=f.travel.pending[f.proof.host_uid]
 elseif kind=='epoch_conflict'then
  local realm={};for k,v in pairs(f.proof)do realm[k]=v end;realm.process_epoch='different-process';f.target.realm=realm
 elseif kind=='origin_conflict'then local m=clone(f.map);m.origin.X=m.origin.X+1;f.travel.pending[f.proof.host_uid].mapping=m
 elseif kind=='lease_conflict'then f.view.leases=3
 elseif kind=='world_conflict'then local m=clone(f.map);m.world_session='foreign-MC-world';f.travel.pending[f.proof.host_uid].mapping=m
 elseif kind=='explicit_nonhome'then f.env.view_state.mapping={native_overworld=false,dim='minecraft:overworld'}
 elseif kind=='explicit_partial_foreign_origin'then local m=clone(f.map);m.world_session=nil;m.origin.X=m.origin.X+1;f.env.view_state.mapping=m
 elseif kind=='explicit_foreign_source'then local m=clone(f.map);m.world_session='foreign-MC-world';f.env.view_state.mapping=m
 elseif kind=='no_ticket'then f.travel.players={};f.travel.pending={};f.view.leases=0
 else error('unknown fixture')end
end
test('foreign_epoch_origin_world_lease_and_explicit_nonhome_conflicts_refused_no_empty_anchor_success',function()
 for _,kind in ipairs({'foreign_uid','epoch_conflict','origin_conflict','lease_conflict','world_conflict','explicit_nonhome','explicit_partial_foreign_origin','explicit_foreign_source','no_ticket'})do
  local f=fixture();f.env.view_state.mapping=nil;corrupt(f,kind)
  assert(f.env.predicate(f.sf,f.proof,f.view)==false,kind)
  assert(not pcall(shutdown,f)and#f.calls==0,'No cleanup allowed on rejected '..kind)
 end
end)
test('complete_original_source_path_preserves_predicate_and_normal_cleanup_behavior',function()
 for _,kind in ipairs({'valid','foreign_uid','epoch_conflict','origin_conflict','lease_conflict','world_conflict','explicit_nonhome','explicit_foreign_source'})do
  local old,new=fixture(true),fixture()
  if kind~='valid'then corrupt(old,kind);corrupt(new,kind)end
  local a=old.env.predicate(old.sf,old.proof,old.view);local b=new.env.predicate(new.sf,new.proof,new.view)
  assert(a==b,'Original complete source predicate changed: '..kind)
  if a then
   assert(shutdown(old).stop_ok==true and shutdown(new).stop_ok==true)
   assert(table.concat(old.calls,',')==table.concat(new.calls,','),'Original cleanup order changed')
  end
 end
end)
print(J.encode{ok=true,tests=3,cases=cases,synthetic_only=true,exact_original_and_new_main_predicate_and_shutdown_functions=true,
 original_saved_scope_operator_guard_and_stop_body_byte_equal=true,existing_stop_callbacks_are_scoped_fixture_adapters=true,
 original_fake_file_witness_fixture_only=true,actual_Game_Save_ACK_native_release_or_closure_apply=false})
