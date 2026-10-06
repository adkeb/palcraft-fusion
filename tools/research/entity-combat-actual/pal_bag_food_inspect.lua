-- Optional independent read-only current native bag inspection through the existing client RPC.
-- Lists actual slots only. It does not invoke CanUse, UseItem, item credit, crafting, or HP setters.
local M={}
local UID='22222222-0000-0000-0000-000000000000'
local function valid(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function guid(g)return('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)end
function M.run()
 assert(IsInGameThread(),'Existing trusted client RPC required')
 local features=assert(_G.PalCraftClientFeatures);local b=assert(features.binding)
 assert(b.pal_uid==UID and b.world_id=='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'and b.expires_at>os.time(),'Current exact host lease required')
 local pc
 for _,p in ipairs(FindAllOf('PalPlayerController')or{})do
  if valid(p)and guid(p:GetPlayerUId())==UID and valid(p.Player)and p.Player:GetFullName():match('^PalLocalPlayer ')then assert(not pc,'Ambiguous personal controller');pc=p end
 end
 assert(pc and valid(pc.Pawn),'Exact possessed local player required')
 local inventory=pc:GetPalPlayerState():GetInventoryData();assert(valid(inventory),'Actual inventory unavailable')
 local utility=StaticFindObject('/Script/Pal.Default__PalUtility');assert(utility and utility:IsValid())
 local manager=utility:GetItemContainerManager(pc);assert(valid(manager),'Native container manager unavailable')
 local bag=manager:GetContainer(inventory.MyInventoryInfo.CommonContainerId);assert(valid(bag),'Actual common bag unavailable')
 local id=guid(bag:GetId().ID);local slots={}
 assert(bag:Num()<=256,'Bounded native bag required')
 for i=0,bag:Num()-1 do
  local slot=bag:Get(i);assert(valid(slot),'Live engine-owned slot required')
  local count=slot:GetStackCount()
  if count>0 then local sid=slot:GetSlotId();local item=slot:GetItemId().StaticId:ToString()
   assert(guid(sid.ContainerId.ID)==id,'Native bag/slot owner mismatch')
   slots[#slots+1]={container_id=id,slot=sid.SlotIndex,item=item,count=count,
    possible_plain_food_name=item=='RedBerry'or item=='BakedBerry',food_class_and_effects_not_verified=true}
  end
 end
 return {read_only=true,observed_unix=os.time(),pal_uid=UID,world_id=b.world_id,server_session_id=b.server_session_id,
  native_bag_id=id,slots=slots,scope='current_common_bag_only_other_native_containers_not_inspected',
  candidate_name_match_is_not_nutrition_or_consumption_proof=true,items_granted=0,hp_writes=0}
end
return M
