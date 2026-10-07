-- Three narrow synthetic cases. No actual ACK, teleport, game process or Saved.
local work,dir=assert(arg[1]),assert(arg[2])
local J=dofile(work..'/../palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local Session=dofile(dir..'/base/client/runtime/session.lua')
local Bootstrap=dofile(dir..'/base/client/runtime/bootstrap.lua')
local function read(path)local f=assert(io.open(path,'rb'));local v=f:read('*a');f:close();return v end
local function extract(s,a,b)local i=assert(s:find(a,1,true));local k=assert(s:find(b,i+1,true));return s:sub(i,k-1)end
local viewsource=read(dir..'/base/client/main.lua')
local apply=extract(viewsource,'function client_view.applyMapping(','function client_view.initWorldView(')
local init=extract(viewsource,'function client_view.initWorldView(','function client_view.syncView(')
local hold=extract(viewsource,'function client_view.hold(','function client_view.applyMapping(')
local release=extract(viewsource,'function client_view.release(','function client_view.reset(')
local status=extract(viewsource,'function client_view.status()','function client_view.commitFrame()')
local function copy(v)return J.decode(J.encode(v))end
local function scenario(source)
 local now=os.time();local host={session_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',generation=9,
  pal_uid='11111111-1111-1111-1111-111111111111',mc_uuid='22222222-2222-2222-2222-222222222222',
  mc_name='Fixture',world_id='ContractWorld',server_session_id='contract-pal-boot'}
 local native={v=2,legacy=false,session_id='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',generation=1,mc_epoch='fixture-MC-epoch',expires_at=now+60}
 for _,k in ipairs({'pal_uid','mc_uuid','mc_name','world_id','server_session_id'})do native[k]=host[k]end
 local target={player=host.mc_uuid,world_session='fixture-mc-world',dim='minecraft:overworld',view=2,waiting_ack=true}
 local q={schema=1,protocol=2,authenticated_host=true,native_mc_verified=true,updated_unix=now,
  host_scope=copy(host),native_binding=native,world_view=target}
 local api={binding=host};local oldContext={mc_epoch=native.mc_epoch,session_id=native.session_id,generation=native.generation}
 local state={held=false,mapping={world_session=target.world_session,dim=target.dim,view=1,native_overworld=true},native_context=oldContext}
 local origin={X=0,Y=0,Z=6400};local bridge={};local pc={Pawn={IsValid=function()return true end},IsValid=function()return true end,GetAddress=function()return 10 end}
 function pc:SetDisableInputFlag(_,value)self.disabled=value end
 local env={client_view=bridge,view_state=state,features=api,J=J,O=copy(origin),home_origin=copy(origin),
  live=function(o)return o and o:IsValid()end,view_thread=function()return true end,
  capture_pose=function()return{fixture_only=true}end,last_input={},clear_terrain=function()end,
  capture_counter=5,origin_generation=1,origin_frame=0,VIEW_FLAG='fixture-owned-flag'}
 function env.invalidate_watermark()state.target_pose_ready=false end
 setmetatable(env,{__index=_G});assert(load(hold..apply..init..release..status,'@original-main-view-hooks','t',env))()
 local bootstrap=Bootstrap.new{session=Session,read=function()return q end,now=function()return now end,path='/fixture/bootstrap-status.json'}
 local featureenv={api=api,bootstrap=bootstrap,o={view_bridge=bridge,player_uid=function()return host.pal_uid end}}
 setmetatable(featureenv,{__index=_G})
 local feature_source=read(source)
 local code=extract(feature_source,' function api:bootstrap_view()',' function api:initialize_home(pc)')..extract(feature_source,' function api:initialize_home(pc)',' function api:status()')
 assert(load(code,'@exact-feature-home-init','t',featureenv))()
 return api,bridge,state,target,native,q,pc,env
end
local baseline=dir..'/base/client/features.lua';local candidate=dir..'/source/client/features.lua'
local cases=J.array();local function test(name,f)f();cases[#cases+1]={name=name,passed=true}end

test('same_native_view_advance_defers_home_init_instead_of_repeating_original_141_assert',function()
 local a,b,s= scenario(baseline);local ok,why=pcall(a.initialize_home,a,{})
 assert(not ok and tostring(why):find('World tuple changes require physical mapping transition',1,true),tostring(why))
 a,b,s=scenario(candidate)
 for _=1,3 do local good,reason=a:initialize_home({});assert(good==false and reason=='physical_mapping_transition_pending')end
 assert(s.mapping.view==1 and a.initialized_native_world==nil and not s.target_pose_ready)
end)

test('original_physical_hold_apply_complete_release_then_same_tuple_home_rearm',function()
 local a,b,s,v,n,q,pc,env=scenario(candidate)
 assert(a:initialize_home(pc)==false);assert(b.hold(pc)==true)
 local mapping={world_session=v.world_session,dim=v.dim,native_overworld=true,scale=100,y_origin=64,origin=copy(env.home_origin)}
 assert(b.applyMapping(mapping,v.world_session,v.dim,v.view)==true)
 local generation=env.origin_generation
 local good,reason=a:initialize_home(pc);assert(good==false and reason=='physical_mapping_transition_pending')
 assert(s.held==true and s.mapping.view==2 and a.initialized_native_world==nil)
 -- Synthetic caller supplies complete here; no actual ACK is being fabricated/published.
 assert(b.release{phase='complete',active=true,world_session=v.world_session,dim=v.dim,view=v.view}==true)
 assert(a:initialize_home(pc)==true and a.initialized_native_world==v.world_session)
 assert(s.target_pose_ready==true and s.held==false and pc.disabled==false and env.origin_generation==generation)
end)

test('first_cold_home_and_true_fresh_backend_reinit_preserved_bad_HOST_binding_rejected',function()
 local a,b,s,v,n,q,pc=scenario(candidate);s.mapping.world_session=nil;s.mapping.view=nil;s.native_context=nil
 assert(a:initialize_home(pc)==true and s.mapping.view==2)
 a,b,s,v,n,q,pc=scenario(candidate);n.mc_epoch='new-valid-fixture-epoch'
 assert(a:initialize_home(pc)==true and s.mapping.view==2)
 a,b,s,v,n,q,pc=scenario(candidate);q.host_scope.session_id='cccccccc-cccc-cccc-cccc-cccccccccccc'
 local good,reason=a:initialize_home(pc);assert(good==false and reason:find('bootstrap_HOST_generation_mismatch',1,true))
 assert(s.mapping.view==1 and a.initialized_native_world==nil)
end)
print(J.encode{ok=true,targeted_cases=#cases,cases=cases,synthetic_only=true,
 exact_original_bootstrap_binding_validation=true,exact_original_main_view_hold_apply_init_release=true,
 actual_prepare_ACK_or_native_teleport_executed=false,actual_respawn_or_gameplay_accepted=false})
