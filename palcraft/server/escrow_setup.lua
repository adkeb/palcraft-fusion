-- One paid ordinary ItemChest through the real player's normal public RPC.
-- Source-only successor: explicit local singleplayer authority or unchanged network checks.
-- No progress writes, actor spawning, grants or service calls.
local source=debug.getinfo(1,'S').source:lower():gsub('\\','/')
local dir=assert(source:match('^@(.*[/])'))
local M={runtime_verified=false}
local ZERO='00000000-0000-0000-0000-000000000000'
local function valid(o)return o and o:IsValid()end
local function live(o)return valid(o)and not o:GetFullName():find('Default__',1,true)end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function vec(v)assert(v and finite(v.X)and finite(v.Y)and finite(v.Z),'Actual FVector unavailable');return{x=v.X,y=v.Y,z=v.Z}end
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
function M.new(o)
 local standalone=o.authority_mode=='standalone'
 assert(o.authority_mode==nil or o.authority_mode=='network'or standalone,'Unknown paid-setup authority mode')
 if standalone then
  assert(type(o.scripts_dir)=='string','Runtime-selected private test Scripts directory required')
  local selected=o.scripts_dir:gsub('\\','/'):lower():gsub('/+$','')..'/'
  assert(dir==selected,'Standalone helper is outside runtime-selected private test Scripts directory')
  assert(type(o.world_directory)=='string'and #o.world_directory==32 and o.world_directory:match('^%x+$'),'Actual loaded test-world directory required')
 else
  assert(source:find('@d:/palworldserver-lan/bridgelab/',1,true)==1,'BridgeLab setup only')
 end
 local Authority=standalone and dofile(dir..'standalone_authority.lua')or nil
 local bound_world
 local J,R=assert(o.json),assert(o.readers);local root=assert(o.root):gsub('\\','/'):gsub('/+$','')..'/'
 local Store=dofile(dir..'exchange_store.lua')
 local store=Store.new{root=root,json=J,containers={},commit=Store.native_commit(root,assert(o.durable_dll))}
 local function guid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
 local function one(class)
  local found;for _,v in ipairs(FindAllOf(class)or{})do if live(v)then assert(not found,'Ambiguous '..class);found=v end end
  return assert(found,class..' unavailable')
 end
 local function freshid()local lib=StaticFindObject('/Script/Engine.Default__KismetGuidLibrary');assert(valid(lib));return guid(lib:NewGuid())end
 local function context(uid)
  assert(IsInGameThread(),'Game thread required');local pc
  for _,v in ipairs(FindAllOf('PalPlayerController')or{})do if live(v)and v:HasAuthority()and guid(v:GetPlayerUId())==uid then assert(not pc,'Ambiguous real player');pc=v end end
  local authority
  if standalone then
   authority=Authority.read(pc,o.world_directory)
   if bound_world then
    assert(authority.world_directory==bound_world.world_directory and authority.game_state_object==bound_world.game_state_object and authority.server_session_id==bound_world.server_session_id,'Loaded local world instance changed; recreate the helper')
   else bound_world=authority end
  else assert(pc and live(pc.NetConnection),'Selected real player is not connected')end
  local state=pc:GetPalPlayerState();assert(live(state))
  local guild=state.GuildBelongTo;assert(live(guild)and guild:HasGuildPermission(pc:GetPlayerUId(),4),'Real guild BuildConstruct permission required')
  local pawn=pc:GetDefaultPlayerCharacter();assert(live(pawn),'Living player character unavailable')
  local transmitter=pc.Transmitter;assert(live(transmitter)and transmitter:GetOwner():GetFullName()==pc:GetFullName(),'Player-owned transmitter mismatch')
  local component=transmitter:GetPlayer();assert(live(component)and component:GetOwner():GetFullName()==transmitter:GetFullName(),'Player-owned RPC component mismatch')
  local inventory=state:GetInventoryData();local tech=state:GetTechnologyData();assert(live(inventory)and live(tech))
  local bases=R.bases();assert(bases.ok,'Actual all-base census unavailable');local group=guid(guild:GetId());local pos=vec(pawn:K2_GetActorLocation())
  local source_base,nearest=ZERO,math.huge
  for _,b in ipairs(bases.bases or{})do
   assert(b.ok and b.position and finite(b.range),'Unreadable base range')
   if b.group_id==group and b.available and distance(pos,b.position)<nearest then source_base=b.id;nearest=distance(pos,b.position)end
  end
  local data=one('PalMapObjectManager'):GetBuildOperator().DataMap:GetById(FName('ItemChest'))
  assert(data.bIsInstallOnlyInDoor==false and data.bIsInstallOnlyHubAround==false,'Native recipe actually restricts this placement')
  local recipe={};for i=1,4 do local n=data['Material'..i..'_Count'];if n>0 then recipe[data['Material'..i..'_Id']:ToString()]=n end end
  assert(recipe.Wood==15 and recipe.Stone==5,'Actual normal ItemChest recipe differs')
  for k in pairs(recipe)do assert(k=='Wood'or k=='Stone','Unexpected native recipe material')end
  if standalone then assert(data.RequiredBuildWorkAmount==1000,'Actual normal ItemChest work requirement differs')end
  local snapshot={player_uid=uid,guild_id=group,source_base_id=source_base,position=pos,bases=bases.bases,
   wood=inventory:CountItemNum64(FName('Wood')),stone=inventory:CountItemNum64(FName('Stone')),
   technology_unlocked=tech:IsUnlockBuildObject(FName('ItemChest'))==true and tech:IsDeniedBuildObject(FName('ItemChest'))==false,
   recipe=recipe,recipe_work=data.RequiredBuildWorkAmount,observed_unix=os.time()}
  snapshot.authority=authority
  return snapshot,{pc=pc,pawn=pawn,component=component,transmitter=transmitter}
 end
 local function check_saved_scope(op)
  if standalone then
   local a=assert(op.before and op.before.authority,'Setup belongs to an earlier authority scope; retain its WAL')
   assert(a.mode=='standalone'and a.world_directory==o.world_directory:upper(),'Setup belongs to another actual world; retain its WAL')
   context(op.before.player_uid)
  end
 end
 local function outside(p,bases)
  for _,b in ipairs(bases)do if distance(p,b.position)<=b.range+1000 then return false end end;return true
 end
 local function world_totals()
  local manager=one('PalItemContainerManager');local totals={Wood=0,Stone=0}
  for _,box in ipairs(FindAllOf('PalItemContainer')or{})do if live(box)then
   local canonical=manager:GetContainer(box:GetId())
   if live(canonical)and canonical:GetFullName()==box:GetFullName()then
    for i=0,box:Num()-1 do local slot=box:Get(i);local n=slot:GetStackCount()
     if n>0 then local item=slot:GetItemId().StaticId:ToString();if totals[item]then totals[item]=totals[item]+n end end
    end
   end
  end end
  return totals
 end
 local function boxes(group)
  local manager,item=one('PalMapObjectManager'),one('PalItemContainerManager');local rows=J.array()
  for _,model in ipairs(FindAllOf('PalMapObjectModel')or{})do if live(model)and model.BuildObjectId:ToString()=='ItemChest'and guid(model.GroupIdBelongTo)==group then
   local id=guid(model.InstanceId);local registered=manager:FindModel(R.guid_from_string(id))
   if live(registered)and registered:GetFullName()==model:GetFullName()then
    local cm=model:GetConcreteModel(false)
    if live(cm)then
     assert(guid(cm:GetModelInstanceId())==id);local module=cm:GetItemContainerModule()
     local cid=live(module)and guid(module:GetContainerId().ID)or nil;local box=cid and item:GetContainer({ID=R.guid_from_string(cid)})
     if live(box)then assert(module:GetContainer():GetFullName()==box:GetFullName(),'Canonical real container mismatch')end
     local row={model_id=id,concrete_id=guid(cm:GetInstanceId()),container_id=cid,type='ItemChest',guild_id=group,
      base_id=guid(cm:GetBaseCampIdBelongTo()),build_player_uid=guid(model.BuildPlayerUId),position=vec(cm:GetTransform().Translation),
      capacity=live(box)and box:Num()or nil,hp=model:GetHP().CurrentValue,completed=live(model.BuildProcess)and model.BuildProcess:IsCompleted()or false,empty=live(box)==true,container_pending=not live(box)}
     if live(box)then for i=0,box:Num()-1 do if box:Get(i):GetStackCount()>0 then row.empty=false end end end
     rows[#rows+1]=row
    end
   end
  end end
  return rows
 end
 local function ground(c,x,y)
  local library=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');assert(valid(library),'Actual collision library unavailable')
  local color={R=0,G=0,B=0,A=0};local hit={}
  local start={X=x,Y=y,Z=c.pawn:K2_GetActorLocation().Z+600};local finish={X=x,Y=y,Z=start.Z-3600}
  local ok=library:LineTraceSingle(c.pawn,start,finish,0,true,{c.pawn},0,hit,true,color,color,0)
  if not ok or not hit.bBlockingHit or hit.bStartPenetrating then return nil,'no_ground_hit' end
  local p=vec(hit.ImpactPoint);local n=vec(hit.ImpactNormal);if n.z<0.95 then return nil,'native_hit_slope' end
  return p
 end
 local function site(c,snapshot)
  local library=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');local errors=J.array();local color={R=0,G=0,B=0,A=0}
  -- Search nearby actual world ground. No inside-base/foundation rule is copied.
  -- The public native build validator retains its own distance/placement rules.
  for _,radius in ipairs({300,600,1000,1500,2500,3500,4500,6000})do for i=0,7 do
   local angle=i*math.pi/4;local x,y=snapshot.position.x+radius*math.cos(angle),snapshot.position.y+radius*math.sin(angle)
   if outside({x=x,y=y},snapshot.bases)then
    local success,p,reason=pcall(ground,c,x,y)
    if not success then return nil,{code='world_trace_adapter_error',error=tostring(p)}end
    if p then
     local flat=true;local samples=J.array();local highest=p.z
     for _,offset in ipairs({{-100,-100},{100,-100},{-100,100},{100,100}})do
      local a,q,why=pcall(ground,c,x+offset[1],y+offset[2]);if not a then return nil,{code='world_trace_adapter_error',error=tostring(q)}end
      if not q or math.abs(q.z-p.z)>10 then flat=false;break end;highest=math.max(highest,q.z);samples[#samples+1]=q
     end
     if flat then
      local hit={};local center={X=x,Y=y,Z=highest+122}
      local a,blocked=pcall(function()return library:BoxTraceSingle(c.pawn,center,{X=x,Y=y,Z=center.Z+1},{X=120,Y=120,Z=120},{Pitch=0,Yaw=0,Roll=0},0,false,{c.pawn},0,hit,true,color,color,0)end)
      if not a then return nil,{code='world_trace_adapter_error',error=tostring(blocked)}end
      if not blocked and not hit.bBlockingHit and not hit.bStartPenetrating then
       return {position={x=x,y=y,z=p.z+1},rotation={X=0,Y=0,Z=0,W=1},ground=p,ground_samples=samples,clear_half_size={x=120,y=120,z=120},distance_from_player_cm=radius}
      end
     end
    elseif #errors<8 then errors[#errors+1]={radius=radius,reason=reason}end
   end
  end end
  return nil,{code='no_clear_outside_ground',player_position=snapshot.position,bases=snapshot.bases,trace_errors=errors}
 end
 local api,plans={},{}
 function api.take_stock(uid)
  assert(o.allow_build==true,'Normal owned material Move must be enabled')
  local snapshot,c=context(uid);local need={Wood=math.max(0,15-snapshot.wood),Stone=math.max(0,5-snapshot.stone)}
  if need.Wood==0 and need.Stone==0 then return {ok=true,moved={},actual=snapshot}end
  local manager=one('PalItemContainerManager');local inv=c.pc:GetPalPlayerState():GetInventoryData()
  local bag=manager:GetContainer(inv.MyInventoryInfo.CommonContainerId);assert(live(bag),'Actual player bag unavailable')
  local discovery=dofile(dir..'discovery.lua').discover{group_id=snapshot.guild_id};assert(discovery.ok,'Real guild source discovery unavailable')
  local component=c.transmitter:GetItem();assert(live(component)and component:GetOwner():GetFullName()==c.transmitter:GetFullName(),'Player-owned item RPC differs')
  local moved={Wood=0,Stone=0}
  for _,target in ipairs(discovery.targets.chests)do
   if target.base_id==snapshot.source_base_id then
    local owned=R.chests({chests={target}},{include_items=false,require_snapshot_ownership=true});assert(owned.ok,'Actual ordinary source ownership failed')
    local box=manager:GetContainer({ID=R.guid_from_string(target.container_id)})
    for index=0,box:Num()-1 do
     local slot=box:Get(index);local count=slot:GetStackCount()
     if count>0 then local item=slot:GetItemId();local key=item.StaticId:ToString()
      if need[key]and need[key]>0 and guid(item.DynamicId.CreatedWorldId)==ZERO and guid(item.DynamicId.LocalIdInCreatedWorld)==ZERO then
       local destination,room
       for i=0,bag:Num()-1 do local s=bag:Get(i);local n=s:GetStackCount()
        if n==0 then destination=s;room=need[key];break end
        local id=s:GetItemId()
        if id.StaticId:ToString()==key and guid(id.DynamicId.CreatedWorldId)==ZERO and guid(id.DynamicId.LocalIdInCreatedWorld)==ZERO and s:GetMaxStack()>n then destination=s;room=s:GetMaxStack()-n;break end
       end
       if not destination then return {ok=false,code='actual_bag_has_no_space',moved=moved,remaining=need}end
       local n=math.min(need[key],count,room);local id=freshid();local prefix='escrow-stock-'..id
       local op={protocol=3,id=id,status='move_intent',player_uid=uid,guild_id=snapshot.guild_id,item=key,count=n,
        source_container_id=target.container_id,source_slot=index,source_before=count,target_slot=destination:GetSlotId().SlotIndex,target_before=destination:GetStackCount()}
       store.append(prefix,op)
       component:RequestMove_ToServer(R.guid_from_string(id),destination:GetSlotId(),{{SlotId=slot:GetSlotId(),Num=n}})
       op.source_after=slot:GetStackCount();op.target_after=destination:GetStackCount()
       op.status=op.source_after==count-n and op.target_after==op.target_before+n and'moved'or'outcome_unconfirmed';store.append(prefix,op)
       if op.status~='moved'then return {ok=false,code='ordinary_move_not_observed',operation=op,remaining=need}end
       need[key]=need[key]-n;moved[key]=moved[key]+n
      end
     end
    end
   end
  end
  local actual=context(uid);return {ok=need.Wood==0 and need.Stone==0,moved=moved,remaining=need,actual=actual}
 end
 function api.preview(uid)
  local snapshot,c=context(uid);snapshot.chests=boxes(snapshot.guild_id)
  if not snapshot.technology_unlocked then return {ok=false,code='native_technology_locked',actual=snapshot}end
  local needed={Wood=math.max(0,15-snapshot.wood),Stone=math.max(0,5-snapshot.stone)}
  if needed.Wood>0 or needed.Stone>0 then return {ok=false,code='real_carried_material_shortage',needed=needed,actual=snapshot}end
  local target,err=site(c,snapshot);if not target then return {ok=false,error=err,actual=snapshot}end
  local id=freshid();local plan={protocol=3,kind='normal_paid_escrow_setup',id=id,status='preview',before=snapshot,target=target,
   bNotConsumeMaterials=false,created_unix=os.time(),expires_unix=os.time()+60,runtime_verified=false}
  plans[id]=plan;return plan
 end
 function api.submit(id)
  assert(IsInGameThread());assert(o.allow_build==true,'Explicit normal paid-build execution required')
  local prefix='escrow-setup-'..id;local old=store.latest(prefix);if old then check_saved_scope(old);return old end -- never replay a recorded public build call
  local p=assert(plans[id],'Preview missing in this real worker');assert(os.time()<=p.expires_unix,'Preview expired')
  local before,c=context(p.before.player_uid);assert(before.guild_id==p.before.guild_id and before.wood>=15 and before.stone>=5 and before.technology_unlocked,'Actual owner/materials changed')
  assert(outside(p.target.position,before.bases),'A base now overlaps this site')
  before.chests=boxes(before.guild_id);before.world_totals=world_totals();p.before=before;p.status='prepared';store.append(prefix,p)
  p.status='submitted';p.attempted=true;store.append(prefix,p)
  local ok,why=pcall(function()c.component:RequestBuild_ToServer(FName('ItemChest'),{X=p.target.position.x,Y=p.target.position.y,Z=p.target.position.z},p.target.rotation,{}, {bNotConsumeMaterials=false})end)
  p.request_returned=ok;p.request_error=not ok and tostring(why)or nil;p.submitted_unix=os.time()
  local immediate=context(p.before.player_uid);immediate.world_totals=world_totals();p.native_after=immediate
  p.native_delta={Wood=immediate.world_totals.Wood-before.world_totals.Wood,Stone=immediate.world_totals.Stone-before.world_totals.Stone}
  p.native_cost_observed=p.native_delta.Wood==-15 and p.native_delta.Stone==-5
  store.append(prefix,p)
  return api.observe(id)
 end
 function api.observe(id)
  assert(IsInGameThread());local prefix='escrow-setup-'..id;local op=assert(store.latest(prefix),'Paid setup intent not found')
  check_saved_scope(op)
  if op.status=='ready_for_saved_enrollment'then return op end
  local after=context(op.before.player_uid);after.chests=boxes(after.guild_id);op.after=after
  op.material_delta={Wood=after.wood-op.before.wood,Stone=after.stone-op.before.stone}
  local known={};for _,v in ipairs(op.before.chests)do known[v.model_id]=true end;local selected={}
  for _,v in ipairs(after.chests)do if not known[v.model_id]and v.build_player_uid==op.before.player_uid and distance(v.position,op.target.position)<=150 then selected[#selected+1]=v end end
  op.paid_cost_observed=op.native_cost_observed==true or(op.material_delta.Wood==-15 and op.material_delta.Stone==-5)
  if #selected==1 and op.paid_cost_observed then
   op.candidate=selected[1];op.candidate.source_base_id=op.before.source_base_id
   local model=one('PalMapObjectManager'):FindModel(R.guid_from_string(op.candidate.model_id))
   local work=live(model.BuildProcess)and model.BuildProcess:GetWorkProgress()or nil
   if live(work)then op.work_samples=op.work_samples or J.array();op.work_samples[#op.work_samples+1]={unix=os.time(),current=work:GetCurrentWorkAmount(),required=work:GetRequiredWorkAmount(),completed=model.BuildProcess:IsCompleted()}end
   op.status=op.candidate.completed and op.candidate.hp>0 and op.candidate.empty and op.candidate.base_id==ZERO and outside(op.candidate.position,after.bases)and'ready_for_saved_enrollment'or'awaiting_normal_work'
  else op.status='awaiting_native_cost_and_model';op.observation_reason='Do not repeat the build RPC; retain actual cost/model evidence' end
  store.append(prefix,op);return op
 end
 function api.start_work(id)
  assert(IsInGameThread());assert(o.allow_build==true,'Normal work execution must be enabled')
  local prefix='escrow-setup-'..id;local op=assert(store.latest(prefix));assert(op.paid_cost_observed and op.candidate,'Actual paid construction site required')
  check_saved_scope(op)
  if op.work_request then return op end
  local snapshot,c=context(op.before.player_uid);local model=one('PalMapObjectManager'):FindModel(R.guid_from_string(op.candidate.model_id))
  assert(live(model)and guid(model.BuildPlayerUId)==snapshot.player_uid,'Actual owned build model changed')
  local process=model.BuildProcess;assert(live(process));if process:IsCompleted()then return api.observe(id)end
  local work=process:GetWorkProgress();assert(live(work),'Native construction work is not ready')
  local work_id=guid(work:GetWorkId());assert(guid(work.OwnerMapObjectModelId)==op.candidate.model_id,'Native work belongs to another model')
  local utility=StaticFindObject('/Script/Pal.Default__PalUtility');assert(valid(utility))
  local canonical=utility:GetWorkProgressManager(c.pawn):GetWork(R.guid_from_string(work_id))
  assert(live(canonical)and canonical:GetFullName()==work:GetFullName(),'Native work is not registered')
  local component=c.transmitter:GetWorkProgress();assert(live(component)and component:GetOwner():GetFullName()==c.transmitter:GetFullName(),'Player-owned work RPC differs')
  op.work_request={id=freshid(),work_id=work_id,before=work:GetCurrentWorkAmount(),required=work:GetRequiredWorkAmount(),submitted_unix=os.time()}
  store.append(prefix,op)
  component:RequestStartPlayerWork_ToServer(R.guid_from_string(op.work_request.id),R.guid_from_string(work_id))
  -- The normal engine/player/Pal worker tick determines rate and completion.
  -- No AddWorkAmount, progress write, FinishWork or state setter is called.
  return api.observe(id)
 end
 return api
end
return M
