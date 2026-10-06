-- BridgeLab custom survival builder. No connected PlayerController is required.
-- Uses the public server spawn entry plus real technology/guild/material checks.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local SP=rawget(_G,'PalCraftStandaloneBootstrap')
if SP then assert(SP.world,'Standalone world authority adapter required')
else assert(dir:gsub('\\','/'):lower():find('d:/palworldserver-lan/bridgelab/',1,true))end
local ROOT=SP and assert(SP.rpc_root):gsub('\\','/'):gsub('/?$','/')or'D:/PalworldServer-LAN/BridgeLab/rpc/' 
local J,R,cfg,report,mgr,started,before={},nil,nil,nil,nil,nil,nil
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function gid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
local function vec(v)return {X=v.X,Y=v.Y,Z=v.Z}end
local function write()
 local p=ROOT..'offline-build-'..cfg.nonce..'.json';local f=assert(io.open(p..'.tmp','wb'));f:write(J.encode(report));f:close();os.remove(p);assert(os.rename(p..'.tmp',p))
end
local function exists(p)local f=io.open(p,'rb');if f then f:close();return true end end
local function all(c)local a={};for _,o in ipairs(FindAllOf(c)or{})do if live(o)then a[#a+1]=o end end;return a end
local function one(c)local a=all(c);assert(#a==1,'Expected one '..c);return a[1]end
local function text(v)return type(v)=='string'and v or v:ToString()end
local function snapshot()
 local rows={}
 for _,m in ipairs(all('PalMapObjectModel'))do
  local t=m.InitialTransformCache;local p=t.Translation
  if math.abs(p.X-cfg.position.X)<1200 and math.abs(p.Y-cfg.position.Y)<1200 then
   local id=gid(m.InstanceId);if live(mgr:FindModel(R.guid_from_string(id)))then rows[id]=m end
  end
 end
 return rows
end
local function run()
 J=dofile(dir..'json.lua');R=dofile(dir..'readers.lua')
 local f=assert(io.open(ROOT..'offline-build-arm.json','rb'));cfg=J.decode(f:read('*a'));f:close()
 if exists(ROOT..'offline-build-'..cfg.nonce..'.json')then return false end
 if SP then SP.world.authorize_ai(cfg,true)end
  cfg.mode=cfg.mode or 'survival';assert(cfg.mode=='survival'or cfg.mode=='creative','Unknown building mode');assert(not cfg.scale,'Create a standard building, then use the creative transform tool for custom scale')
 report={nonce=cfg.nonce,lab_only=true,adapter='custom_server_builder',mode=cfg.mode,status='preparing',started_unix=os.time(),native_build_calls=0,materials=J.array(),observations=J.array()};write()
 assert(cfg.execute==true and cfg.expires_unix>os.time(),'Request expired or not armed')
 mgr=one('PalMapObjectManager');local items=one('PalItemContainerManager')
 local uid=R.guid_from_string(cfg.player_uid);local account
 for _,a in ipairs(all('PalPlayerAccount'))do if live(a.IndividualHandle)and gid(a.IndividualHandle:GetIndividualID().PlayerUId)==cfg.player_uid then account=a end end
 assert(live(account),'Saved player account unavailable')
 local tech=account.TechnologyData
 assert(live(tech)and tech:IsUnlockBuildObject(FName(cfg.build_id))and not tech:IsDeniedBuildObject(FName(cfg.build_id)),'Technology locked')
 local utility=StaticFindObject('/Script/Pal.Default__PalUtility');local guild=utility:GetGuildByPlayerUId(items,uid)
 assert(live(guild)and R.guid_to_string(guild:GetId())==cfg.guild_id and guild:HasGuildPermission(uid,4),'Guild construction permission unavailable')
 local bo={};assert(one('PalBaseCampManager'):TryGetModel(R.guid_from_string(cfg.base_id),bo),'Base unavailable')
 assert(live(bo.OutModel)and R.guid_to_string(bo.OutModel:GetGroupIdBelongTo())==cfg.guild_id,'Base guild mismatch')
 report.online_controllers=#all('PalPlayerController');report.account=account:GetFullName();report.guild_id=cfg.guild_id;report.tech_unlocked=true
 local recipe=mgr:GetBuildOperator().DataMap:GetById(FName(cfg.build_id))
 assert(text(recipe.MapObjectId)==cfg.build_id,'Recipe mismatch')
 report.recipe={build_id=cfg.build_id,work=recipe.RequiredBuildWorkAmount,materials=J.array()}
 before=snapshot()
 -- Initial offline run uses a real registered floor as its support reference.
 if cfg.support_model_id then
  local support=mgr:FindModel(R.guid_from_string(cfg.support_model_id));assert(live(support),'Support disappeared')
  assert(gid(support.GroupIdBelongTo)==cfg.guild_id and gid(support.BaseCampIdBelongTo)==cfg.base_id,'Support ownership mismatch')
  report.support_model_id=cfg.support_model_id
 end
 for id,m in pairs(before)do
  local p=m.InitialTransformCache.Translation
  assert(not(text(m.BuildObjectId)==cfg.build_id and math.sqrt((p.X-cfg.position.X)^2+(p.Y-cfg.position.Y)^2+(p.Z-cfg.position.Z)^2)<5),'Matching object already occupies the point')
 end
 local selected={};local boxes={chests={}}
 if cfg.mode=='survival'then
  local targets={chests={}}
  package.path=dir..'?.lua;'..package.path;package.loaded.json=J;package.loaded.readers=R
  local discovered=dofile(dir..'discovery.lua').discover({group_id=cfg.guild_id});assert(discovered.ok,'Chest discovery failed')
  for _,v in ipairs(discovered.targets.chests)do if v.base_id==cfg.base_id and v.group_id==cfg.guild_id then targets.chests[#targets.chests+1]=v end end
  boxes=R.chests(targets,{include_items=true,verify_ownership=true});assert(boxes.ok and boxes.verified_live,'Base storage unavailable')
 end
 for n=1,4 do
  local amount=recipe['Material'..n..'_Count']
  if amount>0 then
   local item=text(recipe['Material'..n..'_Id']);local remain=amount;report.recipe.materials[#report.recipe.materials+1]={item=item,count=amount}
   if cfg.mode=='survival'then for _,box in ipairs(boxes.chests)do for _,s in ipairs(box.slots)do
    if remain>0 and s.item==item and s.count>0 then
     local take=math.min(s.count,remain);local slot=items:GetContainer({ID=R.guid_from_string(box.id)}):Get(s.index)
     assert(live(slot)and slot:GetStackCount()==s.count,'Material stack changed');selected[#selected+1]={slot=slot,count=take,item=item}
     report.materials[#report.materials+1]={container_id=box.id,slot=s.index,item=item,cost=take,before=s.count};remain=remain-take
    end
   end end
   assert(remain==0,'Insufficient '..item)end
  end
 end
 local transmitter
 for _,tr in ipairs(all('PalNetworkTransmitter'))do if tr:HasAuthority()and live(tr:GetOwner())and tr:GetOwner():GetFullName():find('BP_PalGameStateInGame',1,true)then transmitter=tr end end
 if #selected>0 then assert(live(transmitter),'Server item transmitter unavailable')end
 report.status=cfg.mode=='survival'and'material_debit_started'or'creative_no_material_debit';write()
 for i,v in ipairs(selected)do
  transmitter:GetItem():RequestDispose_ToServer(StaticFindObject('/Script/Engine.Default__KismetGuidLibrary'):NewGuid(),{SlotId=v.slot:GetSlotId(),Num=v.count})
  report.materials[i].after=v.slot:GetStackCount()
  assert(report.materials[i].after==report.materials[i].before-v.count,'Material debit did not occur')
 end
 report.status='native_spawn_started';report.native_build_calls=1;write()
 started=os.time()
 report.spawn_return=mgr:RequestSpawnMapObjectByPlayer_Server(FName(cfg.build_id),cfg.position,cfg.rotation,uid)
 report.status='observing';write();return true
end
local tick
tick=function()
 local ok,again=pcall(function()
  if not cfg then return run()end
  if not started then return false end
  local elapsed=os.time()-started
  for id,m in pairs(snapshot())do
   if not before[id]and text(m.BuildObjectId)==cfg.build_id then
    local p=m.InitialTransformCache.Translation
    if math.sqrt((p.X-cfg.position.X)^2+(p.Y-cfg.position.Y)^2+(p.Z-cfg.position.Z)^2)<5 then
     local process=m.BuildProcess;report.model={id=id,player_uid=gid(m.BuildPlayerUId),guild_id=gid(m.GroupIdBelongTo),base_id=gid(m.BaseCampIdBelongTo),position=vec(p),scale=vec(m.InitialTransformCache.Scale3D),state=live(process)and process.State or nil}
     if live(process)and live(process.BuildWork)then local w=process.BuildWork;report.model.work={required=w.RequiredWorkAmount,current=w.CurrentWorkAmount}end
     if cfg.mode=='creative'and live(process)and process.State~=1 and live(process.BuildWork)then
      local w=process.BuildWork;w.CurrentWorkAmount=w.RequiredWorkAmount;process:OnFinishWorkInServer(w);report.creative_instant_completion=true;report.model.state=process.State
     end
     if live(process)and process.State==1 then report.status='completed';report.finished_unix=os.time();write();return false end
    end
   end
  end
  if report.last_observation_second~=elapsed then report.last_observation_second=elapsed;report.observations[#report.observations+1]={elapsed=elapsed,model=report.model};write()end
  if elapsed>(report.recipe.work==0 and 15 or 120)then report.status=report.model and 'registered_work_pending' or 'spawn_not_observed';report.finished_unix=os.time();write();return false end
  return true
 end)
 if not ok then if report then report.status='failed';report.error=tostring(again);write()end;print('[OfflineBuild] '..tostring(again)..'\n');return end
 if again then return ExecuteInGameThreadWithDelay(50,tick)end
end
return ExecuteInGameThreadWithDelay(50,tick)
