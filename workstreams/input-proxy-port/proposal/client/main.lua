-- All Unreal calls stay on the game thread. Discovery and files are maintained
-- by elapsed time; locomotion/camera are sampled every game callback.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Paths=dofile(dir..'runtime/paths.lua');Paths.assert_role(dir,'client')
local J=dofile(dir..'json.lua')
local ROOT=Paths.bridge
local O={X=-308099.9282280116,Y=187800.81696803804,Z=3480.330899345611}
local origin=io.open(ROOT..'world-origin.json','rb');if origin then O=J.decode(origin:read('*a'));origin:close()end
local home_origin={X=O.X,Y=O.Y,Z=O.Z}
local client_view={}
local view_state={held=false,applied=false,mapping={origin=home_origin,scale=100,y_origin=64,dim='minecraft:overworld',native_overworld=true}}
local last_pose,capture_pose
local capture_counter,origin_generation,origin_frame=0,0,0
local source_epoch
local enabled=true;local frame=0;local tick_count=0;local terrain_origin;local queue={};local columns=J.array();local identity
local pc_cache,game_cache,world_address
local commit,collisions,session,camera_file,input_file,native_suspend,native_resume,native_paused
local native_form_on,native_form_off
local last_input={};local input_seen=0;local input_sequence
local next_player,next_game,next_identity,next_ops,next_ui,next_status,next_profile,next_json,next_input_open,next_render_flag=0,0,0,0,0,0,0,0,0,0
local render_disabled=false;local dismissed_notices={}
local stats={ticks=0,scans={controllers=0,game_states=0,widgets=0},file_opens=0,input_torn=0,input_duplicates=0,terrain_traces=0,stages={}}
local intervals,world_frames={},{};local profile_start,previous_time
local function live(x)return x and x:IsValid()end
local function discovered(x)return live(x)and not x:GetFullName():find('Default__',1,true)end
local function open(path,mode)stats.file_opens=stats.file_opens+1;return io.open(ROOT..path,mode)end
local function json(path,v)local f=assert(open(path,'wb'));f:write(J.encode(v));f:close()end
local function stage(name,start)
 local cost=(os.clock()-start)*1000;local s=stats.stages[name]or{count=0,sum_ms=0,max_ms=0}
 s.count=s.count+1;s.sum_ms=s.sum_ms+cost;s.max_ms=math.max(s.max_ms,cost);stats.stages[name]=s
end
local statics=StaticFindObject('/Script/Engine.Default__GameplayStatics')
local trace_lib=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
local function time_ms(pc)return live(pc)and statics:GetRealTimeSeconds(pc)*1000 or os.time()*1000 end
local function mc(p)return(p.X-O.X)/100,64+(p.Z-O.Z)/100,-(p.Y-O.Y)/100 end
local last_connection
local function connection(phase)
 if phase==last_connection then return end;last_connection=phase
 local f=assert(open('connection-history.ndjson','ab'));f:write(J.encode({phase=phase,unix=os.time()})..'\n');f:close()
end
local form=dofile(dir..'form.lua');_G.PalCraftForm=form
local runtime_config={}
local runtime_file=open('runtime-config.json','rb')
if runtime_file then runtime_config=J.decode(runtime_file:read('*a'));runtime_file:close()end
local feature_options=dofile(dir..'runtime/client_options.lua').new{json=J,bridge_root=ROOT,origin=O,
 config=runtime_config,scripts_dir=dir,view_bridge=client_view}
local features=dofile(dir..'features.lua').new(feature_options)
_G.PalCraftClientFeatures=features
local blocked_input={build=false,focus=false,stale=true}
local function host_allowed(pc)
 local bound,expected=features.binding,runtime_config.identity
 if not bound or not expected then return false,'authenticated_host_unavailable' end
 for _,key in ipairs({'pal_uid','mc_uuid','mc_name','world_id'})do
  if bound[key]~=expected[key]then return false,'host_identity_mismatch:'..key end
 end
 if bound.server_session_id~=(identity and identity.server_session_id)then return false,'host_pal_boot_mismatch' end
 if type(bound.expires_at)~='number'or bound.expires_at<=os.time()then return false,'host_binding_expired' end
 if not live(pc.Player)or not pc.Player:GetFullName():match('^PalLocalPlayer ')then return false,'local_player_unavailable' end
 local g=pc:GetPlayerUId()
 local uid=('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)
 if uid~=bound.pal_uid then return false,'local_pal_uid_mismatch' end
 return true,'authenticated_local_host'
end
local VIEW_FLAG=FName('PalCraftWorldTransition')
local function view_thread()assert(type(IsInGameThread)=='function'and IsInGameThread(),'World view hook requires game thread')end
local function epoch()
 if not source_epoch then
  view_thread();local g=StaticFindObject('/Script/Engine.Default__KismetGuidLibrary'):NewGuid()
  source_epoch=('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)
 end
 return source_epoch
end
local function stamp_pose(pose)
 capture_counter=capture_counter+1;local m=view_state.mapping
 pose.scope={source_epoch=epoch(),source_frame=capture_counter,capture_frame=capture_counter,
  origin_generation=origin_generation,origin_frame=origin_frame,world_session=m.world_session,dim=m.dim,view=m.view}
 return pose
end
local function invalidate_watermark()
 view_state.watermark=nil;view_state.target_pose_ready=false;os.remove(ROOT..'origin-commit-watermark.json')
end
local function clear_terrain()
 terrain_origin=nil;queue={};columns=J.array();os.remove(ROOT..'ground.json')
end
function client_view.hold(pc)
 view_thread();assert(live(pc)and live(pc.Pawn),'World view requires possessed player')
 if view_state.held then assert(view_state.pc:GetAddress()==pc:GetAddress(),'World view possession changed');return true end
 local snapshot=last_pose or capture_pose(pc,last_input)
 view_state.frozen=J.decode(J.encode(snapshot));view_state.pc=pc
 view_state.held=true;view_state.applied=false
 invalidate_watermark()
 pc:SetDisableInputFlag(VIEW_FLAG,true);view_state.input_flag=true
 if native_suspend then native_suspend();native_paused=true end
 clear_terrain();return true
end
function client_view.applyMapping(mapping,world_session,dim,view)
 view_thread();assert(view_state.held,'World view must be held before mapping commit')
 assert(type(mapping)=='table'and mapping.world_session==world_session and mapping.dim==dim,'World mapping identity mismatch')
 assert(type(world_session)=='string'and#world_session>0 and math.type(view)=='integer'and view>=1,'World mapping view invalid')
 assert(dim=='minecraft:overworld'or dim=='minecraft:the_nether'or dim=='minecraft:the_end','World mapping dimension unsupported')
 assert(mapping.scale==100 and mapping.y_origin==64,'World mapping scale mismatch')
 local next_mapping=J.decode(J.encode(mapping));local next_origin=assert(next_mapping.origin,'World mapping origin missing')
 for _,k in ipairs({'X','Y','Z'})do assert(type(next_origin[k])=='number'and next_origin[k]==next_origin[k]and math.abs(next_origin[k])<math.huge,'Nonfinite world mapping origin')end
 if dim=='minecraft:overworld'then
  assert(next_mapping.native_overworld==true,'Auxiliary Overworld not accepted')
  for _,k in ipairs({'X','Y','Z'})do assert(math.abs(next_origin[k]-home_origin[k])<.001,'Native Overworld must preserve home origin')end
 end
 next_mapping.view=view
 -- mapping.origin already absorbs mc_anchor. Mutate the shared O table in one
 -- game-thread assignment so Features/fluid consumers keep the same reference.
 O.X,O.Y,O.Z=next_origin.X,next_origin.Y,next_origin.Z
 origin_generation=origin_generation+1;origin_frame=capture_counter;invalidate_watermark()
 view_state.mapping=next_mapping;view_state.applied=true;clear_terrain();return true
end
function client_view.initWorldView(world_session,dim,view,native_context)
 view_thread();assert(not view_state.held and dim=='minecraft:overworld'and view_state.mapping.native_overworld==true,'Initial scope requires native Overworld')
 assert(type(world_session)=='string'and#world_session>0 and math.type(view)=='integer'and view>=1,'Initial trusted world tuple invalid')
 local m=view_state.mapping
 local previous=view_state.native_context;local next_context
 if native_context then
  assert(native_context.v==2 and native_context.legacy==false and type(native_context.mc_epoch)=='string'and#native_context.mc_epoch>0,'Trusted native MC epoch missing')
  assert(type(native_context.session_id)=='string'and#native_context.session_id==36 and math.tointeger(native_context.generation)and native_context.generation>=1,'Trusted native MC lease invalid')
  local host=assert(features.binding,'Authenticated local host required for home reinit')
  for _,key in ipairs({'pal_uid','mc_uuid','world_id','server_session_id'})do assert(native_context[key]==host[key],'Native MC home identity mismatch:'..key)end
  assert(type(native_context.expires_at)=='number'and native_context.expires_at>os.time(),'Trusted native MC lease expired')
  next_context={mc_epoch=native_context.mc_epoch,session_id=native_context.session_id,generation=native_context.generation}
 end
 local changed=next_context and previous and(next_context.mc_epoch~=previous.mc_epoch or next_context.session_id~=previous.session_id or next_context.generation~=previous.generation)
 if m.world_session==world_session and m.view==view and not changed then
  if next_context then view_state.native_context=next_context end
  -- A native feature stop may clear its watermark after initialize_home already
  -- adopted the same fresh backend tuple. Re-arm publication, never old poses.
  view_state.target_pose_ready=true;return true
 end
 if m.world_session then
  assert(next_context and previous and(changed or m.world_session~=world_session),'World tuple changes require physical mapping transition')
  -- Only a confirmed native home can reinitialize after a backend/lease restart.
  -- Keep O fixed and retire old pose/tuple before producing a new capture.
  for _,key in ipairs({'X','Y','Z'})do assert(math.abs(O[key]-home_origin[key])<.001,'Non-home origin needs physical recovery')end
  m.world_session=nil;m.view=nil;last_pose=nil
  view_state.last_home_reinit='trusted_native_mc_epoch_or_session_changed'
 end
 m.world_session,m.dim,m.view=world_session,dim,view
 view_state.native_context=next_context or previous
 origin_generation=origin_generation+1;origin_frame=capture_counter;invalidate_watermark()
 view_state.target_pose_ready=true;return true
end
function client_view.syncView(pc,pal_yaw,pal_pitch,input)
 view_thread();form.sync_view(pc,pal_yaw,pal_pitch,input)
 if view_state.held and view_state.applied then
  -- Replication has arrived. Freeze the committed target pose while the final
  -- ACK travels back; a Java gate may open before Pal's complete row is read.
  -- Do not use CameraManager here: it can still contain the source frame.
  local pawn=pc.Pawn;local feet=pawn:K2_GetActorLocation()
  feet={X=feet.X,Y=feet.Y,Z=feet.Z-pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()}
  local at={X=feet.X,Y=feet.Y,Z=feet.Z+(input and input.sneak and 147 or 162)}
  local x,y,z=mc(at);local px,py,pz=mc(feet)
  local pose_input={};for k,v in pairs(last_input)do pose_input[k]=v end
  for k,v in pairs(input or{})do pose_input[k]=v end
  local pose=capture_pose(pc,pose_input)
  pose.x,pose.y,pose.z,pose.px,pose.py,pose.pz=x,y,z,px,py,pz
  pose.yaw,pose.pitch,pose.roll=-90-form.yaw,-form.pitch,0
  view_state.frozen=pose
  view_state.target_pose_ready=true
 end
 return true
end
function client_view.release(status)
 view_thread();local m=view_state.mapping
 assert(view_state.held and view_state.applied and status and status.phase=='complete'and status.active==true,'World view final ACK missing')
 assert(status.world_session==m.world_session and status.dim==m.dim and status.view==m.view,'World view final ACK mismatch')
 if view_state.input_flag and live(view_state.pc)then view_state.pc:SetDisableInputFlag(VIEW_FLAG,false)end
 view_state.held=false;view_state.input_flag=false;view_state.pc=nil;view_state.frozen=nil
 return true
end
function client_view.reset(reason,context_alive)
 view_thread()
 if context_alive~=false and view_state.input_flag and live(view_state.pc)then view_state.pc:SetDisableInputFlag(VIEW_FLAG,false)end
 view_state.held=false;view_state.applied=false;view_state.input_flag=false;view_state.pc=nil;view_state.frozen=nil
 invalidate_watermark()
 last_pose=nil;view_state.last_reset=reason;clear_terrain();return true
end
function client_view.status()
 return{held=view_state.held,mapping_applied=view_state.applied,mapping=J.decode(J.encode(view_state.mapping)),
  source_epoch=source_epoch,origin_generation=origin_generation,origin_frame=origin_frame,capture_frame=capture_counter,
  watermark=view_state.watermark and J.decode(J.encode(view_state.watermark)),last_reset=view_state.last_reset,
  native_context=view_state.native_context,last_home_reinit=view_state.last_home_reinit}
end
function client_view.commitFrame()
 return view_state.watermark and J.decode(J.encode(view_state.watermark))or{ready=false,source_epoch=source_epoch,origin_generation=origin_generation,origin_frame=origin_frame}
end
_G.PalCraftClientView=client_view
_G.PalCraftOperator=nil
if runtime_config.operator_enabled==true then
 _G.PalCraftOperator=dofile(dir..'operator.lua').new{
  thread=view_thread,input=function()return last_input end,form_status=form.status,
  request=function(mode)
   local fn=mode and native_form_on or native_form_off
   assert(fn,'Operator renderer is not loaded');fn()
  end,
  gate=function()
   assert(not render_disabled and native_paused==false,'Native host actions are suspended')
   assert(not view_state.held,'World view is held')
   assert(live(pc_cache)and live(pc_cache.Pawn),'Possessed local player unavailable')
   local allowed,reason=host_allowed(pc_cache);assert(allowed,reason)
  end}
end
capture_pose=function(pc,input)
 local camera=pc.PlayerCameraManager;local at,rot
 if form.active then at=form.camera:K2_GetActorLocation();rot={Yaw=form.yaw,Pitch=form.pitch,Roll=0}
 else at=camera:GetCameraLocation();rot=camera:GetCameraRotation()end
 local pawn=pc.Pawn;local feet=pawn:K2_GetActorLocation();feet={X=feet.X,Y=feet.Y,Z=feet.Z-pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()}
 local x,y,z=mc(at);local px,py,pz=mc(feet)
 local width,height=input.viewport_width or 0,input.viewport_height or 0
 local aspect=width>0 and height>0 and width/height or 16/9
 local horizontal=form.active and 90 or camera:GetFOVAngle()
 return stamp_pose{x=x,y=y,z=z,px=px,py=py,pz=pz,yaw=-90-rot.Yaw,pitch=-rot.Pitch,roll=-rot.Roll,
  fov=2*math.atan(math.tan(horizontal*math.pi/360)/aspect)*180/math.pi,grounded=pawn.CharacterMovement:IsMovingOnGround(),width=width,height=height}
end
local feature_reset_error
local function reset_features(reason,context_alive)
 local ok,result=pcall(features.reset,features,reason,{context_alive=context_alive==true})
 feature_reset_error=not ok and tostring(result)or(result==false and'feature_reset_incomplete'or nil)
end
_G.PalCraftReloadCollisions=function()
 local alive=collisions and collisions.context_alive and collisions.context_alive()==true
 -- Retire the companion's legacy/body visuals BEFORE a shared Models reset.
 -- A live unknown lifetime must still fail here; never destroy an unowned Actor.
 client_view.reset('collision_replay',alive)
 if collisions then collisions.stop(alive)end
 reset_features('collision_replay',alive)
 collisions=nil;session=nil;_G.PalCraftCollisionCompanion=nil
 return 'collision_and_model_replay_queued'
end
local function publish(bytes)
 if not camera_file then camera_file=assert(open('camera-live.bin','wb'));camera_file:setvbuf('no')end
 assert(camera_file:seek('set',0));assert(camera_file:write(bytes));assert(camera_file:flush())
 if commit then commit()end
end
local function record_watermark(pose,input,publish_frame)
 local scope=pose.scope;local binding=features.binding
 if not view_state.target_pose_ready or not binding or not scope.world_session or not scope.view or scope.capture_frame<=scope.origin_frame then return end
 local generation=input.generation
 if type(generation)~='number'or generation<1 then return end
 local old=view_state.watermark
 if old and old.source_epoch==scope.source_epoch and old.source_generation==generation and old.origin_generation==scope.origin_generation
  and old.host_scope.session_id==binding.session_id and old.host_scope.generation==binding.generation then return end
 local watermark={schema=1,ready=true,source_epoch=scope.source_epoch,source_frame=scope.capture_frame,capture_frame=scope.capture_frame,
  source_generation=generation,origin_generation=scope.origin_generation,origin_frame=scope.origin_frame,
  world_session=scope.world_session,dim=scope.dim,view=scope.view,first_publish_frame=publish_frame,updated_unix=os.time(),
  host_scope={session_id=binding.session_id,generation=binding.generation,world_id=binding.world_id,pal_uid=binding.pal_uid,
   mc_uuid=binding.mc_uuid,server_session_id=binding.server_session_id},meaning='producer_capture_published_not_network_delivery_or_final_ack'}
 local name='origin-commit-watermark.json';local f=assert(open(name..'.tmp','wb'));f:write(J.encode(watermark));f:close()
 os.remove(ROOT..name);assert(os.rename(ROOT..name..'.tmp',ROOT..name))
 view_state.watermark=watermark
end
local function reset(reason)
 local alive=collisions and collisions.context_alive and collisions.context_alive()==true
 client_view.reset(reason,alive)
 form.stop(reason)
 if collisions then collisions.stop(alive)end
 reset_features(reason,alive)
 collisions=nil;session=nil;_G.PalCraftCollisionCompanion=nil
 terrain_origin=nil;queue={};columns=J.array();game_cache=nil;world_address=nil;next_game=0
 if camera_file then
  publish(string.pack('<c8I4I4dddddddffffff','PALCRFT1',2,0,os.time(),0,0,0,0,0,0,0,0,0,60,.1,1000000))
 end
end
local function player(now)
 if live(pc_cache)and live(pc_cache.PlayerCameraManager)and live(pc_cache.Pawn)then return pc_cache end
 if pc_cache then reset('controller_or_pawn_lost');pc_cache=nil;next_player=0 end
 if now<next_player then return end;next_player=now+500;stats.scans.controllers=stats.scans.controllers+1
 for _,p in ipairs(FindAllOf('PalPlayerController')or{})do
  if discovered(p)and live(p.PlayerCameraManager)and live(p.Pawn)then pc_cache=p;return p end
 end
end
local function str(v)return type(v)=='string'and v or v:ToString()end
local function matched(pc,now)
 if not identity or not identity.server_session_id or #identity.server_session_id==0 then return false end
 local world=pc:GetWorld();local address=world:GetAddress()
 if world_address~=address then reset('world_changed');world_address=address end
 if live(game_cache)then return str(game_cache.ServerSessionId)==identity.server_session_id end
 if now<next_game then return false end;next_game=now+500
 stats.scans.game_states=stats.scans.game_states+1
 for _,g in ipairs(FindAllOf('PalGameStateInGame')or{})do
  if discovered(g)and g:GetWorld():GetAddress()==address then game_cache=g;return str(g.ServerSessionId)==identity.server_session_id end
 end
 return false
end
local function read_input(now)
 if not input_file and now>=next_input_open then
  next_input_open=now+500;input_file=open('input-live.bin','rb');if input_file then input_file:setvbuf('no')end
 end
 if input_file then
  input_file:seek('set',0);local raw=input_file:read(80)
  if raw and #raw==80 then
   local magic,seq,tick,unix,mx,my,flags,forward,strafe,generation,width,height,ending=string.unpack('<c8I8I8di8i8I4i4i4I4I4I4I8',raw)
   if magic=='PALINP15'and seq==ending and seq%2==0 then
    if input_sequence~=seq then
     input_sequence=seq;input_seen=now
     last_input={menu=flags&1~=0,build=flags&2~=0,focus=flags&4~=0,jump=flags&8~=0,sneak=flags&16~=0,sprint=flags&32~=0,unix=unix,mouse_x=mx,mouse_y=my,forward=forward,strafe=strafe,generation=generation,viewport_width=width,viewport_height=height,tick_ms=tick,sequence=seq}
    else stats.input_duplicates=stats.input_duplicates+1 end
   else stats.input_torn=stats.input_torn+1 end
  else stats.input_torn=stats.input_torn+1 end
  last_input.stale=now-input_seen>300
 elseif now>=next_json then
  next_json=now+100
  local f=open('input-state.json','rb')
  if f then local bytes=f:read('*a');f:close();local ok,v=pcall(J.decode,bytes);if ok and type(v)=='table'then last_input=v;input_seen=now end end
 end
 return last_input
end
local function widgets()
 stats.scans.widgets=stats.scans.widgets+1
 local all=FindAllOf('UserWidget')or{}
 for _,w in ipairs(all)do
  if discovered(w)then
   local id=w:GetAddress();local n=w:GetFullName()
   if not dismissed_notices[id]and n:find('/Engine/Transient',1,true)and(n:match('^WBP_ModCautionDialog_ExternalCrash_C ')or n:match('^WBP_ModCautionDialog_C '))then
    dismissed_notices[id]=w
    w['BndEvt__WBP_ModDisclaimerDialog_WBP_CommonButton_K2Node_ComponentBoundEvent_1_OnClicked__DelegateSignature'](w)
    json('mod-notice-status.json',{dismissed=n})
   end
  end
 end
 for id,w in pairs(dismissed_notices)do if not live(w)then dismissed_notices[id]=nil end end
 form.observe_widgets(all)
end
local function summary(values)
 if #values==0 then return{samples=0}end
 table.sort(values);local sum=0;for _,v in ipairs(values)do sum=sum+v end
 return{samples=#values,mean_ms=sum/#values,p50_ms=values[math.max(1,math.ceil(#values*.5))],p95_ms=values[math.ceil(#values*.95)],p99_ms=values[math.ceil(#values*.99)],max_ms=values[#values]}
end
local function profile(now)
 if not profile_start then profile_start=now end
 if now<next_profile then return end;next_profile=now+1000
 local stages={};for n,v in pairs(stats.stages)do stages[n]={samples=v.count,mean_ms=v.sum_ms/v.count,max_ms=v.max_ms}end
 json('client-performance.json',{version=15,unix=os.time(),clock='os.clock (runtime CRT)',elapsed_ms=now-profile_start,total_ticks=stats.ticks,callback_interval=summary(intervals),world_frame=summary(world_frames),stages=stages,scans=stats.scans,file_opens=stats.file_opens,input_transport=input_file and'binary_persistent'or'json_legacy',input_unchanged_ms=math.max(0,now-input_seen),input_torn=stats.input_torn,input_duplicates=stats.input_duplicates,terrain_traces=stats.terrain_traces,terrain_pending=#queue,form=form.status()})
 stats.stages={};intervals={};world_frames={};profile_start=now
end
local function run()
 tick_count=tick_count+1;stats.ticks=stats.ticks+1
 local now=time_ms(pc_cache)
 local started=os.clock()
 local pc=player(now)
 if pc then now=time_ms(pc)end
 if previous_time and now<previous_time then next_game=0;next_identity=0;next_ops=0;next_ui=0;next_status=0;next_profile=0;next_json=0;next_input_open=0;next_render_flag=0;input_seen=now;profile_start=now end
 if previous_time and now>previous_time and live(pc)then intervals[#intervals+1]=now-previous_time end;previous_time=now
 if now>=next_ops then
  next_ops=now+1000;local f=open('client-op.lua','rb')
  if f then
   local source=f:read('*a');f:close();os.remove(ROOT..'client-op.lua')
   local ok,result=pcall(function()return assert(load(source,'PalCraft operation','t',_ENV))()end)
   json('client-op-result.json',{ok=ok,result=ok and result or tostring(result),unix=os.time()})
  end
 end
 if not pc then
  connection('no_possessed_character')
  if now>=next_ui then next_ui=now+1000;widgets()end
  if now>=next_status then next_status=now+1000;json('client-status.json',{status='waiting_for_lab_player',unix=os.time(),version=15})end
  stage('discovery',started);profile(now);return
 end
 if now>=next_identity then
  next_identity=now+1000;local f=open('lab-identity.json','rb')
  if f then local bytes=f:read('*a');f:close();local ok,v=pcall(J.decode,bytes);if ok then identity=v end end
 end
 if not matched(pc,now)then
  if last_connection~='other_session'then reset('other_session')end
  connection('other_session');stage('discovery',started);profile(now);return
 end
 connection('in_bridgelab')
 if not collisions or session~=identity.server_session_id then
  if collisions then
   local alive=collisions.context_alive and collisions.context_alive()==true
   collisions.stop(alive);reset_features('server_session_changed',alive)
  end
  collisions=dofile(dir..'palcraft-collisions.lua');_G.PalCraftCollisionCompanion=collisions;session=identity.server_session_id
 end
 stage('discovery',started);started=os.clock()
 if now>=next_render_flag then
  next_render_flag=now+1000;local f=open('render-disabled.flag','rb');render_disabled=f~=nil;if f then f:close()end
 end
 if not render_disabled and not commit then
  local dll=Paths.join('PalCraft-Client/Pal/Binaries/Win64/PalCraftRender-v16-portable-operator.dll')
  native_suspend=assert(package.loadlib(dll,'palcraft_suspend_actions'));native_suspend();native_paused=true
  native_resume=assert(package.loadlib(dll,'palcraft_resume_actions'))
  if runtime_config.operator_enabled==true then
   native_form_on=assert(package.loadlib(dll,'palcraft_form_on'))
   native_form_off=assert(package.loadlib(dll,'palcraft_form_off'))
  end
  commit=assert(package.loadlib(dll,'palcraft_commit_camera'));print('[PalCraft] Native camera/input v15 loaded\n')
 end
 local input=read_input(now);stage('input',started);started=os.clock()
 features:tick(now,{pc=pc,identity=identity,collisions=collisions,input=input})
 local allowed,gate_reason=host_allowed(pc)
 if allowed then features:initialize_home(pc)end
 local actions_allowed=allowed and not view_state.held
 if native_suspend and native_paused~=not actions_allowed then
  if actions_allowed then native_resume()else native_suspend()end;native_paused=not actions_allowed
 end
 stage('features',started);started=os.clock()
 local before=form.active
 if not view_state.held then form.tick(pc,allowed and input or blocked_input,now)end
 if form.active~=before or now>=next_ui then next_ui=now+5000;widgets()end
 stage('form',started);started=os.clock()
 -- The newly updated camera actor is the render target. Reading the camera
 -- manager here can still return last frame's view and misalign MC interaction.
 local pose=view_state.held and view_state.frozen or capture_pose(pc,input)
 if not view_state.held then last_pose=pose end
 local x,y,z,px,py,pz=pose.x,pose.y,pose.z,pose.px,pose.py,pose.pz
 local yaw,pitch,roll,fov=pose.yaw,pose.pitch,pose.roll,pose.fov
 local width,height,grounded=pose.width,pose.height,pose.grounded
 -- DLL/WS remain alive for authentication bootstrap. Only an authenticated
 -- binding for this possessed local Pal character may drive the guest camera.
 local flags=allowed and enabled and not render_disabled and(1+(grounded and 2 or 0))or 0
 local metadata=J.encode(pose.scope);assert(#metadata<=4096,'Camera capture scope too large')
 publish(string.pack('<c8I4I4dddddddffffff','PALCRFT1',2,flags|4,os.time(),x,y,z,px,py,pz,yaw,pitch,roll,fov,.1,1000000)
  ..string.pack('<I8I8I4',input.tick_ms or 0,frame+1,#metadata)..metadata)
 frame=frame+1
 if flags&1~=0 then record_watermark(pose,input,frame)end
 local delta=statics:GetWorldDeltaSeconds(pc)*1000;if delta>0 then world_frames[#world_frames+1]=delta end
 if now>=next_status then
  next_status=now+1000;json('client-status.json',{status='camera_published',unix=os.time(),version=15,frame=frame,camera={x,y,z},feet={px,py,pz},rotation={yaw,pitch,roll},vertical_fov=fov,viewport={width,height},enabled=enabled,grounded=grounded,form=form.status(),features=features:status(),host_input_gate={strict=true,allowed=allowed,actions_allowed=actions_allowed,reason=gate_reason},world_view=client_view.status(),feature_reset_error=feature_reset_error})
 end
 stage('camera',started);started=os.clock()
 if not allowed or view_state.held or view_state.mapping.native_overworld~=true then profile(now);return end
 local pawn=pc.Pawn;local feet=pawn:K2_GetActorLocation();feet.Z=feet.Z-pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
 local bx,bz=math.floor(px),math.floor(pz)
 -- Finish nearby sampling before re-centering. Rebuilding the queue every four
 -- metres used to starve ground publication during continuous walking.
 local distant=terrain_origin and(math.abs(bx-terrain_origin.x)>32 or math.abs(bz-terrain_origin.z)>32)
 if not terrain_origin or distant or(#queue==0 and(math.abs(bx-terrain_origin.x)>4 or math.abs(bz-terrain_origin.z)>4))then
  terrain_origin={x=bx,z=bz};queue={};columns=J.array()
  for xx=bx-16,bx+16,2 do for zz=bz-16,bz+16,2 do queue[#queue+1]={x=xx,z=zz}end end
  table.sort(queue,function(a,b)return(a.x-bx)^2+(a.z-bz)^2>(b.x-bx)^2+(b.z-bz)^2 end)
 end
 if #queue>0 then
  local color={R=0,G=0,B=0,A=1}
  for _=1,math.min(4,#queue)do
   local p=table.remove(queue);local wx=O.X+(p.x+.5)*100;local wy=O.Y-(p.z+.5)*100;local hit={}
   local yes=trace_lib:LineTraceSingle(pawn,{X=wx,Y=wy,Z=feet.Z+250},{X=wx,Y=wy,Z=feet.Z-3000},0,false,{pawn},0,hit,true,color,color,0)
   stats.terrain_traces=stats.terrain_traces+1;local h=hit.OutHit or hit
   if yes and h.ImpactPoint then
    local top=math.floor(64+(h.ImpactPoint.Z-O.Z)/100)-1
    for dx=0,1 do for dz=0,1 do columns[#columns+1]=p.x+dx;columns[#columns+1]=p.z+dz;columns[#columns+1]=top-2;columns[#columns+1]=top end end
   end
   if(os.clock()-started)*1000>=1 then break end
  end
  -- solid() only adds barriers into air, so incremental disjoint batches preserve
  -- the paid/player-built world while making nearby ground available promptly.
  if #columns>0 and(#queue==0 or now-(terrain_origin.published or 0)>=250)then
   json('ground.json',{t='ground',c=columns});columns=J.array();terrain_origin.published=now
  end
 end
 stage('terrain',started);profile(now)
end
local tick
tick=function()
 local start=os.clock();local ok,e=pcall(run);stage('total',start)
 if not ok then
  pcall(reset,'client_error')
  pcall(json,'client-status.json',{status='error',error=tostring(e),frame=frame,unix=os.time(),version=15})
 end
 ExecuteInGameThreadWithDelay(1,tick)
end
ExecuteInGameThreadWithDelay(3000,tick)
print('[PalCraft] Camera/input v15 task scheduled\n')
