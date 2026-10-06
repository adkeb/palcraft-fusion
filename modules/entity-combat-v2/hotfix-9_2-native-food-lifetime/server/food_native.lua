-- Normal native item-effect processor over transient MC food data; the MC stack was already consumed once.
local N={}
local function valid(o)return o and o:IsValid()end
local function name(v)return type(v)=='string'and v or v:ToString()end
function N.new(o)
 assert(IsInGameThread(),'Native food game thread required')
 local gs=assert(o.game_state);local epoch=assert(o.epoch)
 local M={confirmed=0,effects={},night_modes={},errors={},caps={},serial=0,native_route='PalItemUseProcessor:UseItemToCharacter_ServerInternal'}
 local function provider()
  assert(IsInGameThread(),'Native food game thread required')
  assert(valid(gs)and gs:HasAuthority(),'Authoritative food world required')
  local utility=StaticFindObject('/Script/Pal.Default__PalUtility');assert(valid(utility),'Native food utility unavailable')
  local manager=utility:GetItemIDManager(gs)
  assert(valid(manager)and manager:IsA('/Script/Pal.PalItemIDManager'),'Native item manager unavailable')
  -- Read the engine-owned UPROPERTY map anew. A Lua UObject wrapper is not a UE GC reference.
  local proc
  manager.ItemUseProcessorMap:ForEach(function(_,value)
   local candidate=value:get()
   if valid(candidate)and candidate:IsA('/Script/Pal.PalItemUseProcessor_CommonEffectToIndividualParameter')then
    local outer=candidate:GetOuter()
    assert(valid(outer)and outer:GetAddress()==manager:GetAddress(),'Food processor owner mismatch')
    proc=candidate;return true
   end
  end)
  assert(proc,'Engine-owned native food processor unavailable')
  return proc,manager
 end
 local function numeric(v)return type(v)=='number'and v or o.fixed:Convert_FixedPoint64ToFloat(v)end
 local function template(q,target,owner)
  local max=target.cp:GetMaxFullStomach();assert(type(max)=='number'and max>0,'Native max full stomach required')
  local heal=0
  for _,e in ipairs(q.effects or{})do
   if e.id=='minecraft:regeneration'then heal=heal+math.floor((e.duration or 0)/math.max(1,50/2^(e.amplifier or 0)))end
  end
  local satiety=math.max(0,math.floor(q.nutrition/20*max+.5));local hp=math.max(0,math.floor(heal/20*numeric(target.cp:GetMaxHP())+.5))
  local data_class=StaticFindObject('/Script/Pal.PalStaticConsumeItemData')
  assert(valid(data_class),'Native food data class unavailable')
  M.serial=M.serial+1
  -- This temporary data is constructed, used and released in one game-thread call; never cache across ticks.
  local d=StaticConstructObject(data_class,owner,FName('PalCraftFood_'..epoch:gsub('%-','')..'_'..M.serial),64,0)
  assert(valid(d)and d:IsA('/Script/Pal.PalStaticConsumeItemData'),'Native food data construction failed')
  d.ID=FName('PalCraftMC_'..q.item:gsub('[^%w_]','_'));d.ItemBaseName=d.ID;d.TypeA=8;d.TypeB=53;d.MaxStackCount=64
  d.RestoreSatiety=satiety;d.RestoreHP=hp
  d.RestoreSP=0;d.RestoreSanity=0;d.WazaID=0;d.bNotConsumed=false
  assert(d:GetRestoreSatiety()==math.floor(q.nutrition/20*max+.5)and d:GetRestoreHP()==math.floor(heal/20*numeric(target.cp:GetMaxHP())+.5),'Native food data getter mismatch')
  return d
 end
 function M.readiness(target)
  -- Availability permits a paid request, whose exact item still passes normal native CanUse rules.
  -- Scanning a player must not allocate food or call CanUseItemToCharacter on their behalf.
  local ok,r=pcall(function()
   assert(target.player and valid(target.actor)and target.actor:IsInitialized(),'Initialized real food consumer required')
   assert(not target.cp:IsDead()and not target.cp:IsDying(),'Live food consumer required')
   provider();return true
  end)
  if not ok then M.errors[target.id]=tostring(r);return false end
  M.errors[target.id]=nil;M.caps[target.id]=r==true;return r==true
 end
 local function status_component(a)
  local c=a.StatusComponent;assert(valid(c),'Native status component unavailable');return c
 end
 local function nightvision(target,e)
  local pc=target.actor:GetController();assert(valid(pc),'Night vision owner controller unavailable')
  local c=pc.BP_PalNightVisionComponent;assert(valid(c),'Real player night vision component unavailable')
  local key=c:GetAddress();local active=M.night_modes[key]
  if not active then active={component=c,before=c:IsNightVisionEnabled_ForServer(),expires=0};M.night_modes[key]=active end
  active.expires=math.max(active.expires,o.now()+e.duration/20)
  c:SetNightVisionEnabled_ForServer(true);c:SetNightVisionEnabled_ToClient(true,1)
  assert(c:IsNightVisionEnabled_ForServer(),'Native night vision state was not confirmed')
  return {id=e.id,native='PalNightVisionComponent:SetNightVisionEnabled_ForServer/ToClient',duration=e.duration/20,native_server_enabled=true,client_visual_pending=true}
 end
 function M.apply(q,target)
  assert(IsInGameThread(),'Native food game thread required');assert(target.player and not target.cp:IsDead()and not target.cp:IsDying(),'Real live Pal player required')
  local proc,owner=provider();local d=template(q,target,owner);local individual=target.handle:GetIndividualID()
  assert(proc:CanUseItemToCharacter(d,individual),'Native food rejected by normal item rules')
  local before=target.cp:GetFullStomach();local hp_before=numeric(target.cp:GetHP())
  local accepted=proc:UseItemToCharacter_ServerInternal(d,individual)
  local applied_effects,unsupported={},{}
  -- Saturation is a temporary modifier of Pal's existing metabolism, never another starvation or healing loop.
  if accepted and q.saturation>0 then
   local key='PalCraftMCSaturation_'..q.id;target.ip:SetDecreaseFullStomachRates(FName(key),0)
   M.effects[key]={target=target,expires=o.now()+math.min(1200,q.saturation*30),kind='saturation'};applied_effects[#applied_effects+1]={id='minecraft:saturation',native='SetDecreaseFullStomachRates',duration=q.saturation*30}
  end
  if accepted then for _,e in ipairs(q.effects)do
   if e.id=='minecraft:hunger'then
    local key='PalCraftMCHunger_'..q.id;target.ip:SetDecreaseFullStomachRates(FName(key),1+.1*((e.amplifier or 0)+1))
    M.effects[key]={target=target,expires=o.now()+e.duration/20,kind='hunger'};applied_effects[#applied_effects+1]={id=e.id,native='SetDecreaseFullStomachRates',duration=e.duration/20}
   elseif e.id=='minecraft:poison'then
    local c=status_component(target.actor);c:AddStatusParameter(5,{GeneralIndex=e.amplifier or 0,GeneralFloatValue=e.duration/20,GeneralName=FName('PalCraftMCFood')})
    local s=c:GetExecutionStatus(5);if valid(s)then s.Duration=e.duration/20;applied_effects[#applied_effects+1]={id=e.id,native='PalStatusComponent:AddStatusParameter',duration=e.duration/20}else unsupported[#unsupported+1]={id=e.id,status='native_status_pending'}end
   elseif e.id=='minecraft:regeneration'then applied_effects[#applied_effects+1]={id=e.id,native='ordinary_consume_RestoreHP',heal_budget=d:GetRestoreHP()}
   elseif e.id=='minecraft:night_vision'then
    local good,r=pcall(nightvision,target,e);if good then applied_effects[#applied_effects+1]=r else unsupported[#unsupported+1]={id=e.id,status='native_nightvision_pending',error=tostring(r)}end
   else unsupported[#unsupported+1]={id=e.id,status='native_equivalent_pending'}end
  end end
  local after=target.cp:GetFullStomach();local hp_after=numeric(target.cp:GetHP())
  local changed=after~=before or hp_after~=hp_before
  if changed then M.confirmed=M.confirmed+1 end
  return {ok=accepted==true and changed,status=accepted and(changed and(#unsupported==0 and'applied'or'applied_with_pending_status_equivalents')or'pending_native_effect_confirmation')or'native_item_rules_rejected',
   native_route=M.native_route,before_full_stomach=before,after_full_stomach=after,before_hp=hp_before,after_hp=hp_after,
   native_restore_satiety=d:GetRestoreSatiety(),native_restore_hp=d:GetRestoreHP(),native_items_credited=0,
   effects=applied_effects,unsupported_effects=unsupported,semantics='native_nutrition_and_native_status_equivalents'}
 end
 function M.tick()
  for key,e in pairs(M.effects)do if o.now()>=e.expires then if valid(e.target.ip)then e.target.ip:RemoveDecreaseFullStomachRates(FName(key))end;M.effects[key]=nil end end
  for key,e in pairs(M.night_modes)do if o.now()>=e.expires then if valid(e.component)then e.component:SetNightVisionEnabled_ForServer(e.before);e.component:SetNightVisionEnabled_ToClient(e.before,e.before and 1 or 0)end;M.night_modes[key]=nil end end
 end
 function M.stop()
  for key,e in pairs(M.effects)do if valid(e.target.ip)then e.target.ip:RemoveDecreaseFullStomachRates(FName(key))end end;M.effects={}
  for _,e in pairs(M.night_modes)do if valid(e.component)then e.component:SetNightVisionEnabled_ForServer(e.before);e.component:SetNightVisionEnabled_ToClient(e.before,e.before and 1 or 0)end end;M.night_modes={}
 end
 function M.status()return {native_route=M.native_route,confirmed=M.confirmed,errors=M.errors,
  processor_lifetime='engine_owned_ItemUseProcessorMap_reacquired_per_call',food_data_lifetime='single_game_thread_call',
  readiness_scope='owned_provider_available_exact_item_CanUse_only_on_paid_request',native_effect_verified=M.confirmed>0,
  unsupported_status_equivalents={'minecraft:absorption','minecraft:resistance','minecraft:fire_resistance'},inventory_credit_calls=0}end
 return M
end
return N
