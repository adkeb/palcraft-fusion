-- Read-only helpers for the lead's future exclusive BridgeLab window.
-- This module never schedules itself, changes an Actor, builds, moves or saves.
local M={}
local ZERO='00000000-0000-0000-0000-000000000000'
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
function M.survey(R,guild_id)
 assert(IsInGameThread(),'Game thread required')
 local function guid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
 local map,item
 for _,o in ipairs(FindAllOf('PalMapObjectManager')or{})do if live(o)then assert(not map,'Ambiguous map manager');map=o end end
 for _,o in ipairs(FindAllOf('PalItemContainerManager')or{})do if live(o)then assert(not item,'Ambiguous item manager');item=o end end
 assert(map and item,'Managers unavailable')
 local bases=R.bases();assert(bases.ok,'Base census unavailable')
 local out={read_only=true,lab_only=true,bases=bases.bases,players={},ordinary_chests={},errors={},runtime_isolation_verified=false}
 for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do if live(pc)and pc:HasAuthority()then
  local state=pc:GetPalPlayerState();out.players[#out.players+1]={uid=guid(pc:GetPlayerUId()),name=state:GetPlayerName():ToString(),connected=true}
 end end
 for _,model in ipairs(FindAllOf('PalMapObjectModel')or{})do
  if live(model)then
   local ok,row=pcall(function()
    local group=guid(model.GroupIdBelongTo);if guild_id and group~=guild_id then return nil end
    local kind=model.BuildObjectId:ToString();if kind~='ItemChest'and kind~='ItemChest_02'then return nil end
    local target=guid(model.InstanceId);local registered=map:FindModel(R.guid_from_string(target))
    assert(live(registered)and registered:GetFullName()==model:GetFullName(),'Model is not canonical/registered before concrete lookup')
    local concrete=model:GetConcreteModel(false);assert(live(concrete),'No-force concrete unavailable')
    local mid=guid(concrete:GetModelInstanceId());assert(mid==target,'Concrete/model scalar identity mismatch')
    local module=concrete:GetItemContainerModule();assert(live(module),'Container module unavailable')
    local cid=guid(module:GetContainerId().ID);local box=item:GetContainer({ID=R.guid_from_string(cid)})
    assert(live(box)and live(module:GetContainer())and module:GetContainer():GetFullName()==box:GetFullName(),'Canonical module/container mismatch')
    local p=concrete:GetTransform().Translation;local hp=model:GetHP();local pos={x=p.X,y=p.Y,z=p.Z}
    local row={model_id=mid,concrete_id=guid(concrete:GetInstanceId()),container_id=cid,type=kind,
     guild_id=group,base_id=guid(concrete:GetBaseCampIdBelongTo()),capacity=box:Num(),position=pos,
     hp=hp.CurrentValue,completed=live(model.BuildProcess)and model.BuildProcess:IsCompleted()or false,
     private_locked=model:IsLockedPrivate()==true,private_lock_uid=guid(model.PrivateLockPlayerUId),slots={},outside_all_base_ranges=true}
    for _,b in ipairs(bases.bases or{})do
     assert(b.ok and b.position and type(b.range)=='number','Unreadable base range')
     local d=math.sqrt((p.X-b.position.x)^2+(p.Y-b.position.y)^2)
     if d<=b.range+1000 then row.outside_all_base_ranges=false end
    end
    for i=0,box:Num()-1 do local s=box:Get(i);local n=s:GetStackCount();local entry={slot=i,count=n,item=''}
     if n>0 then local id=s:GetItemId();entry.item=id.StaticId:ToString();entry.dynamic_world=guid(id.DynamicId.CreatedWorldId);entry.dynamic_guid=guid(id.DynamicId.LocalIdInCreatedWorld)end
     row.slots[#row.slots+1]=entry
    end
    row.empty=true;for _,s in ipairs(row.slots)do if s.count>0 then row.empty=false end end
    row.private_denials={};for _,p in ipairs(out.players)do row.private_denials[#row.private_denials+1]={uid=p.uid,denied=model:IsLockedPrivateByNot(R.guid_from_string(p.uid))==true}end
    row.candidate_for_daily_challenges=row.base_id==ZERO and row.outside_all_base_ranges and row.empty and row.hp>0 and row.completed
    return row
   end)
   if ok and row then out.ordinary_chests[#out.ordinary_chests+1]=row
   elseif not ok then out.errors[#out.errors+1]={model=model:GetFullName(),reason=tostring(row)}end
  end
 end
 table.sort(out.ordinary_chests,function(a,b)return a.model_id<b.model_id end)
 return out
end
function M.observe_candidate(R,adapter,candidate)
 assert(IsInGameThread(),'Game thread required')
 local backend=adapter.game_backend(R)
 local observation=backend.chest(candidate)
 local bases=R.bases();assert(bases.ok,'Base census unavailable');observation.bases=bases.bases
 observation.runtime_isolation_verified=false;observation.note='Read-only observations do not replace the three normal gameplay challenges.'
 return observation
end
return M
