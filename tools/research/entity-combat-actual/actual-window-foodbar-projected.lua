assert(IsInGameThread())
local DIR='Z:/path/to/workspace/work/minecraft-fusion/entity-combat-actual/'
local J=dofile('D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
_G.PalCraftEntityFoodLease=dofile(DIR..'normal_food_operator.lua').new{json=J}
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function g(x)return('%08x-%04x-%04x-%04x-%04x%08x'):format(x.A&0xffffffff,(x.B>>16)&0xffff,x.B&0xffff,(x.C>>16)&0xffff,x.C&0xffff,x.D&0xffffffff)end
local UID='22222222-0000-0000-0000-000000000000'
local pc
for _,p in ipairs(FindAllOf('PalPlayerController')or{})do if live(p)and g(p:GetPlayerUId())==UID and live(p.Player)and p.Player:GetFullName():match('^PalLocalPlayer ')then assert(not pc);pc=p end end
assert(pc and live(pc.Pawn))
local u=StaticFindObject('/Script/Pal.Default__PalUtility');assert(u:IsValid())
local im=u:GetItemContainerManager(pc);local inv=pc:GetPalPlayerState():GetInventoryData()
local box=im:GetContainer(inv.MyInventoryInfo.FoodEquipContainerId);assert(live(box),'Real equipped food container unavailable')
local cm=u:GetCharacterManager(pc);local cp=pc.Pawn:GetCharacterParameterComponent();local ip=cp:GetIndividualParameter()
local handle=cm:GetIndividualHandleFromCharacterParameter(ip);assert(live(handle));local individual=handle:GetIndividualID();assert(g(individual.PlayerUId)==UID)
local items=u:GetItemIDManager(pc);assert(live(items));local rows={}
assert(box:Num()<=256)
for i=0,box:Num()-1 do
 local s=box:Get(i);assert(live(s));local n=s:GetStackCount()
 if n>0 then
  local sid=s:GetSlotId();local item=s:GetItemId();local data=items:GetStaticItemData(item.StaticId)
  local row={container_id=g(sid.ContainerId.ID),slot=sid.SlotIndex,item=item.StaticId:ToString(),count=n,data_valid=live(data)}
  if live(data)then row.data_class=data:GetClass():GetFullName();row.native_consume_class=data:IsA('/Script/Pal.PalStaticConsumeItemData')
   if row.native_consume_class then row.restore_satiety=data:GetRestoreSatiety();row.restore_hp=data:GetRestoreHP();row.normal_can_use=s:CanUseItemToCharacter(individual)end
  end
  rows[#rows+1]=row
 end
end
local ok,v=pcall(_G.PalCraftEntityFoodLease.observe)
local out={read_only=true,food_attempts=0,items_granted=0,hp_writes=0,food_container_id=g(box:GetId().ID),actual_food_slots=rows,
 actual_target={pal_uid=g(individual.PlayerUId),instance_id=g(individual.InstanceId)},vitals={ok=ok,result=ok and v or nil,error=not ok and tostring(v)or nil},commands=_G.PalCraftClientFeatures.composition.features.commands.instance.status()}
local function plain(v)
 local t=type(v)
 if t=='table'then local r={};for k,x in pairs(v)do if type(k)=='string'or type(k)=='number'then r[k]=plain(x)end end;return r end
 if t=='nil'or t=='boolean'or t=='number'or t=='string'then return v end
 return {lua_type=t,string_view=tostring(v)}
end
return J.encode(plain(out))
