-- Runtime drives start()/poll() through its existing game-thread client-op callbacks. No timer/hook/socket.
local D={}
local DIR=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local WINROOT=assert(os.getenv('PALCRAFT_WINDOWS_ROOT'),'Configured installed Windows root required'):gsub('\\','/'):gsub('/+$','')
local ROOT=WINROOT..'/PalCraft-Dev/bridge/'
local UID='22222222-0000-0000-0000-000000000000'
local WORLD='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
local GUILD='00000000-0000-4000-8000-00000000001b'
local BASE='00000000-0000-4000-8000-000000000031'
local MODEL='00000000-0000-4000-8000-00000000001c'
local CID='00000000-0000-4000-8000-000000000021'
local ZERO='00000000-0000-0000-0000-000000000000'
local function live(x)return x and x:IsValid()and not x:GetFullName():find('Default__',1,true)end
local function guid(g)return('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)end
local function fg(s)local h=s:gsub('%-','');return {A=tonumber(h:sub(1,8),16),B=tonumber(h:sub(9,16),16),C=tonumber(h:sub(17,24),16),D=tonumber(h:sub(25,32),16)}end
local function plain(v)
 if type(v)~='table'then return v end
 local r={};for k,x in pairs(v)do if type(k)=='string'or type(k)=='number'then r[k]=plain(x)end end;return r
end
function D.new(o)
 assert(IsInGameThread(),'Existing trusted game-thread callback required');o=o or{}
 local boot=assert(o.server_session_id,'Bind the current actually verified Pal boot')
 assert(type(boot)=='string'and #boot<=128 and boot:match('^[%w_%-]+$'),'Invalid boot identifier')
 local J=dofile(WINROOT..'/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
 local observer=dofile(DIR..'normal_food_operator.lua').new{json=J}
 local journal=ROOT..'honey-once-'..boot..'.json'
 local S={version=1,phase='idle',terminal=false,server_session_id=boot,item='Honey',quantity=1,
  source_container_id=CID,source_slot=5,source_model_id=MODEL,base_id=BASE,guild_id=GUILD,player_uid=UID,
  move_calls=0,use_calls=0,polls=0,deadline_seconds=15,max_polls=16,food_effect_verified=false,
  MC_paid_food_pipeline_verified=false,items_granted=0,hp_writes=0,cooldown_writes=0,events={}}
 local function read(name)
  local f=io.open(ROOT..name,'rb');if not f then return nil end
  local n=f:seek('end');assert(n and n<=1048576,'Bounded current record required');f:seek('set');local raw=f:read('*a');f:close();return J.decode(raw)
 end
 local function checkpoint()
  local f=assert(io.open(journal..'.pending','wb'));assert(f:write(J.encode(plain(S))));assert(f:flush());assert(f:close())
  os.remove(journal);assert(os.rename(journal..'.pending',journal),'Honey checkpoint publication failed')
 end
 -- A previous intent/final record, including an interrupted .pending file, blocks another action in this boot.
 for _,p in ipairs({journal,journal..'.pending'})do local f=io.open(p,'rb');if f then f:close();error('Existing Honey attempt record; inspect it, never construct a retry driver')end end
 local function note(t)S.events[#S.events+1]={unix=os.time(),stage=t}end
 local function finish(phase,why)
  S.phase=phase;S.terminal=true;S.reason=why;note(phase);checkpoint();return plain(S)
 end
 local function numeric(v)
  if type(v)=='number'then return v end
  local lib=StaticFindObject('/Script/Pal.Default__FixedPoint64MathLibrary');assert(lib and lib:IsValid())
  return lib:Convert_FixedPoint64ToFloat(v)
 end
 local function item(slot)
  local n=slot:GetStackCount();assert(type(n)=='number'and n%1==0 and n>=0)
  if n==0 then return n,nil end
  local id=slot:GetItemId();return n,{name=id.StaticId:ToString(),dynamic_guid=guid(id.DynamicId.LocalIdInCreatedWorld),dynamic_world=guid(id.DynamicId.CreatedWorldId)}
 end
 local function honey(slot)local n,id=item(slot);assert(n>0 and id.name=='Honey'and id.dynamic_guid==ZERO and id.dynamic_world==ZERO,'Actual plain Honey slot required');return n end
 local function context()
  assert(IsInGameThread(),'Existing trusted game-thread callback required')
  local paired=observer.observe();assert(paired.world_id==WORLD and paired.server_session_id==boot,'Current world/boot differs')
  local f=assert(_G.PalCraftClientFeatures,'Use the existing client-op route');local b=assert(f.binding);local nb=assert(f.mc_binding)
  assert(b.pal_uid==UID and b.world_id==WORLD and b.server_session_id==boot and b.expires_at>os.time(),'Fresh exact host required')
  assert(nb.pal_uid==UID and nb.world_id==WORLD and nb.server_session_id==boot and nb.expires_at>os.time(),'Fresh native MC lease required')
  assert(f.mc_view and f.mc_view.waiting_ack==false,'Actual world ACK required')
  local input=assert(read('input-state.json'),'Current publisher unavailable')
  assert(type(input.unix)=='number'and os.time()-input.unix>=-5 and os.time()-input.unix<=2 and input.stale~=true and input.menu~=true,'Current non-menu lifecycle required')
  local pc
  for _,p in ipairs(FindAllOf('PalPlayerController')or{})do
   if live(p)and guid(p:GetPlayerUId())==UID and live(p.Player)and p.Player:GetFullName():match('^PalLocalPlayer ')then assert(not pc,'Ambiguous personal controller');pc=p end
  end
  assert(pc and live(pc.NetConnection),'Actual connected personal PC required')
  local pawn=pc.Pawn;assert(live(pawn)and pawn:IsInitialized(),'Current initialized possession required')
  assert(pawn:GetController():GetAddress()==pc:GetAddress(),'Possession ownership differs')
  local ps=pc:GetPalPlayerState();assert(live(ps)and live(ps.GuildBelongTo)and guid(ps.GuildBelongTo:GetId())==GUILD,'Actual current guild differs')
  local cp=pawn:GetCharacterParameterComponent();assert(live(cp)and not cp:IsDead()and not cp:IsDying(),'Current live native character required')
  local ip=cp:GetIndividualParameter();assert(live(ip))
  local u=StaticFindObject('/Script/Pal.Default__PalUtility');assert(u and u:IsValid())
  local cm=u:GetCharacterManager(pc);assert(live(cm));local handle=cm:GetIndividualHandleFromCharacterParameter(ip);assert(live(handle))
  local target=handle:GetIndividualID();assert(guid(target.PlayerUId)==UID,'Actual native IndividualID differs')
  assert(paired.pal.id=='pal:'..UID..'/'..guid(target.InstanceId),'Authority snapshot/possession differs')
  local transmitter=pc.Transmitter;assert(live(transmitter)and transmitter:GetOwner():GetAddress()==pc:GetAddress(),'Transmitter owner differs')
  local net=transmitter:GetItem();assert(live(net)and net:GetOwner():GetAddress()==transmitter:GetAddress(),'Native inventory RPC owner differs')
  local mm=u:GetMapObjectManager(pc);assert(live(mm));local model=mm:FindModel(fg(MODEL));assert(live(model)and guid(model.InstanceId)==MODEL and guid(model.GroupIdBelongTo)==GUILD,'Registered source model differs')
  local concrete=model:GetConcreteModel(false);assert(live(concrete)and guid(concrete:GetModelInstanceId())==MODEL,'Existing source concrete unavailable')
  assert(guid(concrete:GetBaseCampIdBelongTo())==BASE,'Native source base differs')
  local base=concrete:GetBaseCampModelBelongTo();assert(live(base)and base:IsAvailable()and guid(base:GetId())==BASE and guid(base:GetGroupIdBelongTo())==GUILD,'Native base/guild differs')
  if concrete:IsA('/Script/Pal.PalMapObjectItemChestModel')then local lock=guid(concrete.PrivateLockPlayerUId);assert(lock==ZERO or lock==UID,'Source privately locked by another player')end
  local es=rawget(_G,'PalCraftEscrowExclusions');assert(not es or not es.is_reserved(CID,MODEL),'Registered escrow is not a food source')
  local module=concrete:GetItemContainerModule();assert(live(module)and guid(module:GetContainerId().ID)==CID,'Source container module differs')
  local im=u:GetItemContainerManager(pc);assert(live(im));local box=im:GetContainer({ID=fg(CID)});assert(live(box)and module:GetContainer():GetAddress()==box:GetAddress(),'Canonical source container differs')
  assert(box.bIsGuildChestContainer==false and box:Num()>5,'Actual ordinary source slot unavailable')
  local source=box:Get(5);assert(live(source));local sid=source:GetSlotId();assert(guid(sid.ContainerId.ID)==CID and sid.SlotIndex==5,'Source SlotId differs')
  local inv=ps:GetInventoryData();assert(live(inv));local bag=im:GetContainer(inv.MyInventoryInfo.CommonContainerId);assert(live(bag)and bag:Num()<=256,'Actual bounded common bag unavailable')
  local c={pc=pc,pawn=pawn,cp=cp,ip=ip,target=target,net=net,source=source,bag=bag,u=u,
   target_id='pal:'..UID..'/'..guid(target.InstanceId),pc_address=pc:GetAddress(),pawn_address=pawn:GetAddress(),transmitter_address=transmitter:GetAddress(),net_connection_address=pc.NetConnection:GetAddress(),
   paired=paired,input_generation=input.generation,physical_focus=input.focus,bag_id=guid(bag:GetId().ID)}
  if S.scope then
   assert(c.target_id==S.target_id and c.pc_address==S.pc_address and c.pawn_address==S.pawn_address and c.transmitter_address==S.transmitter_address and c.net_connection_address==S.net_connection_address and c.bag_id==S.bag_id and input.generation==S.input_generation,'Native possession/connection lifecycle changed')
   assert(paired.pal_epoch==S.scope.pal_epoch and paired.mc_epoch==S.scope.mc_epoch,'Entity authority epoch changed')
   for _,k in ipairs({'host_session_id','host_generation','mc_session_id','mc_generation','native_mc_epoch'})do assert(paired.connection[k]==S.scope.connection[k],'Native/host lease changed: '..k)end
  end
  return c
 end
 local function vitals(c)return{hp=numeric(c.cp:GetHP()),max_hp=numeric(c.cp:GetMaxHP()),shield=numeric(c.ip:GetShieldHP()),
  full_stomach=c.cp:GetFullStomach(),max_full_stomach=c.cp:GetMaxFullStomach(),alive=not c.cp:IsDead(),dying=c.cp:IsDying()}end
 local function destination(c,index)
  local s=c.bag:Get(index);assert(live(s));local id=s:GetSlotId();assert(guid(id.ContainerId.ID)==c.bag_id and id.SlotIndex==index,'Current bag SlotId differs');return s
 end
 local function can_eat(c,s)
  honey(s)
  assert(c.cp:GetFullStomach()<c.cp:GetMaxFullStomach(),'Native consumer is already full')
  local mgr=c.u:GetItemIDManager(c.pc);assert(live(mgr));local data=mgr:GetStaticItemData(s:GetItemId().StaticId)
  assert(live(data)and data:IsA('/Script/Pal.PalStaticConsumeItemData'),'Actual Honey is not native consume data')
  local sat,hp=data:GetRestoreSatiety(),data:GetRestoreHP();assert(type(sat)=='number'and sat>0 and type(hp)=='number'and hp>=0,'Actual native nutrition unavailable')
  assert(s:CanUseItemToCharacter(c.target)==true,'Normal native item rules/cooldown rejected this Honey')
  return {restore_satiety=sat,restore_hp=hp,data_class=data:GetClass():GetFullName(),normal_can_use=true}
 end
 local api={}
 function api.status()assert(IsInGameThread());return plain(S)end
 function api.start()
  assert(IsInGameThread());if S.phase~='idle'then return plain(S)end
  for _,p in ipairs({journal,journal..'.pending'})do local f=io.open(p,'rb');if f then f:close();S.phase='existing_attempt';S.terminal=true;S.reason='Another Honey attempt already owns this boot; its record is preserved';return plain(S)end end
  local ok,why=pcall(function()
   local c=context();local n=honey(c.source);S.native_food=can_eat(c,c.source)
   local dest,di,before
   for i=0,c.bag:Num()-1 do local s=destination(c,i);local count,id=item(s)
    if count==0 or id.name=='Honey'and id.dynamic_guid==ZERO and id.dynamic_world==ZERO and s:GetMaxStack()>count then dest,di,before=s,i,count;break end
   end
   assert(dest,'No actual empty/compatible common-bag slot')
   local lib=StaticFindObject('/Script/Engine.Default__KismetGuidLibrary');assert(lib and lib:IsValid());local req=lib:NewGuid()
   S.move_request_id=guid(req);S.scope=plain(c.paired);S.target_id=c.target_id;S.pc_address=c.pc_address;S.pawn_address=c.pawn_address;S.transmitter_address=c.transmitter_address;S.net_connection_address=c.net_connection_address
   S.bag_id=c.bag_id;S.input_generation=c.input_generation;S.physical_focus=c.physical_focus;S.physical_focus_is_gate=false
   S.destination_slot=di;S.destination_before=before;S.source_before=n;S.before=vitals(c);S.started_unix=os.time();S.deadline_unix=S.started_unix+S.deadline_seconds
   S.phase='move_in_flight';S.move_intent=true;note('normal_move_intent');checkpoint()
   S.move_calls=1
   c.net:RequestMove_ToServer(req,dest:GetSlotId(),{{SlotId=c.source:GetSlotId(),Num=1}})
   checkpoint()
  end)
  if not ok then return finish(S.move_calls>0 and'ambiguous_move'or'preflight_rejected',tostring(why))end
  return plain(S)
 end
 function api.poll()
  assert(IsInGameThread());if S.terminal or S.phase=='idle'then return plain(S)end
  S.polls=S.polls+1
  if os.time()<S.started_unix-5 or os.time()>=S.deadline_unix or S.polls>S.max_polls then return finish('ambiguous_deadline','Observe the same recorded native intent; no automatic retry')end
  local ok,why=pcall(function()
   local c=context();local dst=destination(c,S.destination_slot);local sn,si=item(c.source);local dn,di=item(dst)
   if sn>0 then assert(si.name=='Honey'and si.dynamic_guid==ZERO and si.dynamic_world==ZERO,'Source item changed')end
   if dn>0 then assert(di.name=='Honey'and di.dynamic_guid==ZERO and di.dynamic_world==ZERO,'Destination item changed')end
   S.last={unix=os.time(),source_count=sn,destination_count=dn,native=vitals(c),paired=plain(c.paired)}
   if S.phase=='move_in_flight'then
    if sn==S.source_before and dn==S.destination_before then return end
    assert(sn==S.source_before-1 and dn==S.destination_before+1,'Move delta not exactly one; outcome ambiguous')
    S.move_observed=true;S.native_food=can_eat(c,dst);S.before_use=vitals(c)
    S.phase='use_in_flight';S.use_intent=true;note('normal_use_intent');checkpoint()
    S.use_calls=1
    c.pc:RequestUseItemToCharacter({SlotId=dst:GetSlotId(),Num=1},c.target)
   else
    assert(sn==S.source_before-1,'Source changed during use observation')
    if dn==S.destination_before+1 then return end
    assert(dn==S.destination_before,'Normal use did not debit exactly one; outcome ambiguous')
    S.normal_food_paid_once=true;S.after_use=vitals(c)
    local changed=S.after_use.full_stomach>S.before_use.full_stomach or S.native_food.restore_hp>0 and S.after_use.hp>S.before_use.hp
    local p=c.paired.pal
    local mirrored_change=p.full_stomach>S.before_use.full_stomach or S.native_food.restore_hp>0 and p.hp>S.before_use.hp
    if changed and c.paired.shared_vitals_match and mirrored_change then S.food_effect_verified=true;S.after=plain(c.paired);finish('complete','One observed normal native move and consume; MC-paid food/damage/death remain unverified')end
   end
  end)
  if not ok then return finish(S.use_calls>0 and'ambiguous_use'or'ambiguous_move',tostring(why))end
  if not S.terminal then checkpoint()end;return plain(S)
 end
 function api.stop()
  assert(IsInGameThread());if S.terminal then return plain(S)end
  return finish(S.move_calls>0 and'observation_stopped_ambiguous'or'stopped_before_action','No native intent is replayed or compensated')
 end
 return api
end
return D
