-- BridgeLab persistent control endpoint: serial game-thread file queue, no async Lua.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local SP=rawget(_G,'PalCraftStandaloneBootstrap')
local function root_path(p)return assert(p):gsub('\\','/'):gsub('/?$','/')end
if SP then
 assert(SP.local_realm and SP.client_worker and root_path(SP.scripts_dir)==root_path(dir),'Selected standalone scripts/provider required')
else
 assert(dir:gsub('\\','/'):lower():find('d:/palworldserver-lan/bridgelab/',1,true))
end
local ROOT=SP and root_path(SP.rpc_root)or'D:/PalworldServer-LAN/BridgeLab/rpc/' 
local J=dofile(dir..'json.lua');local R=dofile(dir..'readers.lua');local active;local palcraft
local function exists(p)local f=io.open(p,'rb');if f then f:close();return true end end
local function read(p)local f=assert(io.open(p,'rb'));local x=J.decode(f:read('*a'));f:close();return x end
local function write(p,v)local f=assert(io.open(p..'.tmp','wb'));f:write(J.encode(v));f:close();os.remove(p);assert(os.rename(p..'.tmp',p))end
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function objects(c)local a={};for _,o in ipairs(FindAllOf(c)or{})do if live(o)then a[#a+1]=o end end;return a end
local function gid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
package.path=dir..'?.lua;'..package.path;package.loaded.json=J;package.loaded.readers=R
local storage_runtime,storage_targets,instance_id
local function storage_read(base_id,ids)
 local found=dofile(dir..'discovery.lua').discover();assert(found.ok,'Chest discovery failed');storage_targets=found.targets
 local selected={snapshot_sha256=storage_targets.snapshot_sha256,chests={}};local wanted
 if ids then wanted={};for _,id in ipairs(ids)do wanted[id]=true end end
 for _,v in ipairs(storage_targets.chests)do if v.base_id==base_id and(not wanted or wanted[v.container_id])then selected.chests[#selected.chests+1]=v end end
 if #selected.chests==0 then return {ok=true,includes_items=true,chests=J.array(),errors=J.array()}end
 return R.chests(selected,{include_items=true,require_snapshot_ownership=true})
end
local function storage_api()
 if not storage_runtime then
  local function new_id()return R.guid_to_string(StaticFindObject('/Script/Engine.Default__KismetGuidLibrary'):NewGuid())end
  instance_id=new_id()
  storage_runtime=dofile(dir..'storage-runtime-fast.lua').new({root=ROOT,json=J,readers=dofile(dir..'storage-readers-fast.lua'),schedule=ExecuteInGameThreadWithDelay,targets=dofile(dir..'targets.lua'),organize=dofile(dir..'organize.lua'),merge=dofile(dir..'merge.lua'),utc=function()return os.date('!%Y-%m-%dT%H:%M:%SZ')end,new_uuid=new_id,instance_id=function()return instance_id end,read_storage=storage_read,get_targets=function()return storage_targets end})
 end
 return storage_runtime
end
local exchange
local function exchange_api()if not exchange then exchange=dofile(dir..'palcraft-exchange.lua')end;return exchange end
local SHARED=SP and root_path(SP.bridge_root)or'D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local standalone
if SP then
 standalone=dofile(dir..'runtime/standalone_world.lua').new{local_realm=SP.local_realm,client_worker=SP.client_worker,game_thread=SP.game_thread}
 SP.world=standalone
end
local early_boot_observer
-- Copy the actual loader while it still owns the save object, before the dispatcher delay.
do
 local cfg=exists(SHARED..'runtime-config.json')and read(SHARED..'runtime-config.json')or{}
 if not SP and cfg.profile=='lab-next9-test'and(cfg.boot_observer_enabled~=false or cfg.exchange_enabled==true)
  and cfg.bootstrap_sampling_hold~=true then
  early_boot_observer=dofile(dir..'exchange_bootstrap.lua').new{json=J,readers=R,
   root=assert(cfg.exchange_root),rpc_root=ROOT,process_dll=dir..'PalCraftEscrowBoot-v1.dll'}
  early_boot_observer.start_early()
 elseif SP and SP.start_early_boot then
  -- Supplied by the standalone save/escrow owner; no dedicated-save getter is faked.
  early_boot_observer=SP.start_early_boot(cfg,J,R)
 end
end
local features,next_runtime_status,next_control_tick,previous_runtime_ms
local clock_context,clock_lib
local function runtime_time_ms()
 if standalone then
  local proof=SP.local_realm:current();clock_context=proof and proof.game_state or nil
 end
 if not standalone and not live(clock_context)then
  clock_context=nil
  for _,g in ipairs(objects('PalGameStateInGame'))do
   if g:HasAuthority()then assert(not clock_context,'Ambiguous authority clock');clock_context=g end
  end
 end
 clock_lib=clock_lib or StaticFindObject('/Script/Engine.Default__GameplayStatics')
 return live(clock_context)and clock_lib:GetRealTimeSeconds(clock_context)*1000 or os.time()*1000
end
local function feature_api()
 if not features then
  local cfg=exists(SHARED..'runtime-config.json')and read(SHARED..'runtime-config.json')or{}
  local origin=exists(SHARED..'world-origin.json')and read(SHARED..'world-origin.json')or nil
  local options
  if cfg.profile=='lab-next9-test'or SP then
   if not SP and cfg.chunk_enabled==true and not palcraft then palcraft=dofile(dir..'palcraft-server.lua')end
   options=dofile(dir..'runtime/server_options.lua').new{json=J,readers=R,bridge_root=SHARED,origin=origin,
    config=cfg,scripts_dir=dir,rpc_root=ROOT,companion=standalone and standalone.companion or function()return palcraft end,
    local_realm=SP and SP.local_realm,standalone_world=standalone,standalone_observer=early_boot_observer}
  else
   options={json=J,readers=R,bridge_root=SHARED,origin=origin,companion=function()return palcraft end,
    exchange_factory=exchange_api,entities_enabled=cfg.entities_enabled~=false,exchange_enabled=false,travel_enabled=false,fluid_enabled=false}
  end
  if early_boot_observer and options.bootstrap then options.bootstrap.early_observer=early_boot_observer end
  features=dofile(dir..'features.lua').new(options)
  _G.PalCraftServerFeatures=features
 end
 return features
end
local function dispatch(req)
 local p=req.params or {};local method=req.method
 if standalone then standalone.authorize_ai(p,method~='status'and method~='bases'and method~='catalog'and method~='storage')end
 local handled,result=feature_api():dispatch(method,p,req);if handled then return result end
 if method=='status'then return {online_controllers=#objects('PalPlayerController'),offline_building=true,modes={'survival','creative'},adapter='saved_owner_server_spawn',active_operation=active,observed_unix=os.time()}
 elseif method=='palcraft_start'then
  if standalone then local c=standalone.companion();return c and J.decode(c.status_json())or{running=false,reason='actual_standalone_client_world_pending'}end
  if palcraft and not palcraft.running then palcraft.stop();palcraft=nil end
  if not palcraft then palcraft=dofile(dir..'palcraft-server.lua')end;return J.decode(palcraft.status_json())
 elseif method=='palcraft_status'then return palcraft and J.decode(palcraft.status_json())or{running=false,blocks=0}
 elseif method=='palcraft_stop'then
  assert(not standalone,'Standalone physical consumer is owned by the client world lifecycle')
  if not palcraft then return{running=false,blocks=0}end
  palcraft.stop();return J.decode(palcraft.status_json())
 elseif method=='palcraft_identity'then
  if standalone then local s=standalone.status();return{server_session_id=s.server_session_id,world_directory=s.world_id}end
  local a=objects('PalGameStateInGame')[1];assert(a,'No game state')
  local function str(v)return type(v)=='string'and v or v:ToString()end
  return {server_session_id=str(a.ServerSessionId),world_directory=str(a:GetWorldSaveDirectoryName())}
 elseif method=='palcraft_boot_probe'then
  return dofile(ROOT..'runtime-boot-probe.lua')
 elseif method=='bases'then return R.bases()
 elseif method=='storage'then return storage_read(p.base_id,p.container_ids)
 elseif method=='storage_plan'then return storage_api().plan(p)
 elseif method=='storage_apply'then return storage_api().apply(p,req.id)
 elseif method=='storage_operation'then return storage_api().get(p)
 elseif method=='storage_cancel'then return storage_api().cancel(p)
 elseif method=='catalog'then
  local mgr=objects('PalMapObjectManager')[1];local account
  for _,a in ipairs(objects('PalPlayerAccount'))do if live(a.IndividualHandle)and gid(a.IndividualHandle:GetIndividualID().PlayerUId)==p.player_uid then account=a end end
  assert(live(account),'Saved account unavailable');local out={builds=J.array()};local map=mgr:GetBuildOperator().DataMap
  map.BuildObjectDataIdMap:ForEach(function(k,v)
   local name=k:get():ToString()
   if not p.filter or name:lower():find(p.filter:lower(),1,true)then
    local r=map:GetById(FName(name));local materials=J.array()
    for i=1,4 do if r['Material'..i..'_Count']>0 then materials[#materials+1]={item=r['Material'..i..'_Id']:ToString(),count=r['Material'..i..'_Count']}end end
    out.builds[#out.builds+1]={id=name,unlocked=account.TechnologyData:IsUnlockBuildObject(FName(name)),work=r.RequiredBuildWorkAmount,materials=materials}
   end
  end)
  return out
 elseif method=='operation'then
  local path=ROOT..'offline-build-'..p.id..'.json'
  if exists(path)then return read(path)end;return {status='pending_or_unknown',id=p.id}
 elseif method=='models'then
  local out={models=J.array()};local mgr=objects('PalMapObjectManager')[1]
  for _,id in ipairs(p.ids or{})do
   local m=mgr:FindModel(R.guid_from_string(id))
   if live(m)then local t=m.InitialTransformCache;local pos=t.Translation;out.models[#out.models+1]={id=id,build_id=m.BuildObjectId:ToString(),player_uid=gid(m.BuildPlayerUId),guild_id=gid(m.GroupIdBelongTo),base_id=gid(m.BaseCampIdBelongTo),state=live(m.BuildProcess)and m.BuildProcess.State or nil,position={X=pos.X,Y=pos.Y,Z=pos.Z},rotation={X=t.Rotation.X,Y=t.Rotation.Y,Z=t.Rotation.Z,W=t.Rotation.W},scale={X=t.Scale3D.X,Y=t.Scale3D.Y,Z=t.Scale3D.Z}}end
  end
  return out
 elseif method=='finish'then
  assert(p.mode=='creative','Instant completion is a creative-mode operation')
  local mgr=objects('PalMapObjectManager')[1];local out={objects=J.array()}
  for _,id in ipairs(p.ids or{})do
   local m=mgr:FindModel(R.guid_from_string(id));assert(live(m),'Object unavailable')
   assert(gid(m.BuildPlayerUId)==p.player_uid and gid(m.GroupIdBelongTo)==p.guild_id,'Object ownership mismatch')
   local process=m.BuildProcess
   if live(process)and process.State~=1 then
    local w=process.BuildWork;assert(live(w),'Construction work unavailable')
    w.CurrentWorkAmount=w.RequiredWorkAmount;process:OnFinishWorkInServer(w)
   end
   out.objects[#out.objects+1]={id=id,state=live(process)and process.State or nil}
  end
  return out
 elseif method=='transform'then
  assert(p.mode=='creative','Transform editing is a creative-mode operation')
  local mgr=objects('PalMapObjectManager')[1];local m=mgr:FindModel(R.guid_from_string(p.id))
  assert(live(m),'Object unavailable')
  assert(gid(m.BuildPlayerUId)==p.player_uid and gid(m.GroupIdBelongTo)==p.guild_id,'Object ownership mismatch')
  local actor
  for _,a in ipairs(objects('PalMapObject'))do local am=a:GetModel();if live(am)and gid(am.InstanceId)==p.id then actor=a;break end end
  assert(live(actor),'Actor is not currently loaded')
  local t=m.InitialTransformCache
  for _,k in ipairs({'X','Y','Z'})do t.Translation[k]=p.position[k];t.Scale3D[k]=p.scale[k]end
  if p.quaternion then for _,k in ipairs({'X','Y','Z','W'})do t.Rotation[k]=p.quaternion[k]end end
  local root=actor.RootComponent;assert(live(root),'Actor root unavailable');local mobility=root.Mobility
  root:SetMobility(2)
  local hit={};local moved=actor:K2_SetActorTransform(t,false,hit,true)
  root:SetMobility(mobility)
  actor:SetReplicateMovement(true)
  actor:ForceNetUpdate()
  local actual=actor:GetTransform()
  return {id=p.id,moved=moved,root_mobility=mobility,position={X=actual.Translation.X,Y=actual.Translation.Y,Z=actual.Translation.Z},scale={X=actual.Scale3D.X,Y=actual.Scale3D.Y,Z=actual.Scale3D.Z}}
 elseif method=='dismantle'then
  local mgr=objects('PalMapObjectManager')[1];local removed=J.array()
  local tr
  for _,x in ipairs(objects('PalNetworkTransmitter'))do if x:HasAuthority()and live(x:GetOwner())and x:GetOwner():GetFullName():find('BP_PalGameStateInGame',1,true)then tr=x end end
  assert(live(tr),'Global transmitter unavailable')
  for _,id in ipairs(p.ids or{})do
   local m=mgr:FindModel(R.guid_from_string(id));assert(live(m),'Object unavailable')
   assert(gid(m.BuildPlayerUId)==p.player_uid and gid(m.GroupIdBelongTo)==p.guild_id,'Object ownership mismatch')
   local actor
   for _,a in ipairs(objects('PalMapObject'))do local am=a:GetModel();if live(am)and gid(am.InstanceId)==id then actor=a;break end end
   assert(live(actor),'Actor is not currently loaded')
   actor:DisposeSelf_ServerInternal();removed[#removed+1]={id=id,registered_after=live(mgr:FindModel(R.guid_from_string(id)))}
  end
  return {objects=removed}
 elseif method=='build'then
  if active then local ap=ROOT..'offline-build-'..active..'.json';if exists(ap)then local a=read(ap);if a.finished_unix or a.status=='failed'then active=nil end end end
  assert(not active,'A building operation is still active')
  p.nonce=req.id;p.execute=true;p.expires_unix=os.time()+300
  write(ROOT..'offline-build-arm.json',p);active=req.id
  dofile(dir..'offline-build-main.lua')
  return {accepted=true,operation_id=req.id}
 elseif method=='geometry'then
  write(ROOT..'actual-geometry-model-ids.json',p.ids or{})
  os.remove(ROOT..'actual-geometry.json');dofile(dir..'read-actual-geometry-main.lua')
  return {accepted=true,path='actual-geometry.json'}
 elseif method=='materials'then
  write(ROOT..'material-components.json',p.components or{})
  os.remove(ROOT..'actual-materials.json');dofile(dir..'read-materials-main.lua')
  return {accepted=true,path='actual-materials.json'}
 elseif method=='terrain'then
  local mgr=objects('PalMapObjectManager')[1];local lib=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');local ignore=objects('PalMapObject');local out={points=J.array()};local color={R=0,G=0,B=0,A=1}
  for _,pos in ipairs(p.points or{})do
   local hit={};local yes=lib:LineTraceSingle(mgr,{X=pos.X,Y=pos.Y,Z=11000},{X=pos.X,Y=pos.Y,Z=-20000},0,false,ignore,0,hit,true,color,color,0);local h=hit.OutHit or hit
   local row={x=pos.local_x,y=pos.local_y,hit=yes};if h.ImpactPoint then row.impact={X=h.ImpactPoint.X,Y=h.ImpactPoint.Y,Z=h.ImpactPoint.Z};row.normal={X=h.ImpactNormal.X,Y=h.ImpactNormal.Y,Z=h.ImpactNormal.Z}end;out.points[#out.points+1]=row
  end
  return out
 else error('Unknown method '..tostring(method))end
end
local tick
tick=function(external_ms)
 local ms=external_ms or runtime_time_ms()
 if previous_runtime_ms and ms<previous_runtime_ms then next_control_tick=nil;next_runtime_status=nil end
 previous_runtime_ms=ms
 if not next_control_tick or ms>=next_control_tick then
  next_control_tick=ms+500
  local file=ROOT..'agent-request.json'
  if exists(file)then
   local ok,req=pcall(read,file)
   if ok and type(req.id)=='string'and req.id:match('^[%x%-]+$')then
    local out=ROOT..'agent-result-'..req.id..'.json'
    if not exists(out)then
     local good,result=pcall(dispatch,req)
     write(out,{id=req.id,ok=good,result=good and result or nil,error=not good and tostring(result)or nil})
    end
   end
  end
  if storage_runtime then storage_runtime.tick()end
 end
 feature_api():tick(ms)
 if not next_runtime_status or ms>=next_runtime_status then
  next_runtime_status=ms+1000;write(ROOT..'palcraft-features-status.json',feature_api():status())
 end
 if not(SP and SP.external_tick)then return ExecuteInGameThreadWithDelay(250,tick)end
end
if SP and SP.external_tick then return{tick=tick}end
return ExecuteInGameThreadWithDelay(30000,tick)
