local scripts='work/palworld-live/bridge/PalLiveBridge/Scripts/'
local R=dofile(scripts..'readers.lua')
local T=dofile(scripts..'targets.lua')
local J=dofile(scripts..'json.lua')
local function good(o,name)
 function o:IsValid()return true end
 function o:GetFullName()return name end
 return o
end
local states,containers,models={},{},{}
local concrete_calls=0
for _,t in ipairs(T.chests)do
 assert(R.guid_to_string(t.instance_guid)==t.instance_id)
 local state={type=t.type,base=t.base_id,group=t.group_id,concrete_loaded=true,model_loaded=true,
  module_container=t.container_id,linked_container=t.container_id,capacity=t.expected_capacity,guild=false}
 states[t.container_id]=state
 local c=good({},'PalItemContainer test.'..t.container_id)
 function c:GetId()return{ID=t.guid}end
 function c:Num()return state.capacity end
 setmetatable(c,{__index=function(_,k)if k=='bIsGuildChestContainer'then return state.guild end end,
  __newindex=function()error('native UObject write attempted')end})
 containers[t.container_id]=c
 local base=good({},'PalBaseCampModel test.'..t.base_id)
 function base:GetId()return R.guid_from_string(state.base)end
 function base:GetGroupIdBelongTo()return R.guid_from_string(state.group)end
 function base:IsAvailable()return true end
 local module=good({},'PalMapObjectItemContainerModule test')
 function module:GetContainerId()return{ID=R.guid_from_string(state.module_container)}end
 function module:GetContainer()return containers[state.linked_container]end
 local concrete=good({},'PalMapObjectItemChestModel test')
 function concrete:GetModelInstanceId()return t.instance_guid end
 function concrete:GetInstanceId()return{A=1,B=2,C=3,D=4}end
 function concrete:TryGetMapObjectId()return{ToString=function()return state.type end}end
 function concrete:GetItemContainerModule()return module end
 function concrete:GetBaseCampIdBelongTo()return R.guid_from_string(state.base)end
 function concrete:GetBaseCampModelBelongTo()return base end
 local model=good({},'PalMapObjectModel test')
 function model:GetConcreteModel(force)
  assert(force==false,'force object creation is forbidden')
  concrete_calls=concrete_calls+1
  if state.concrete_loaded then return concrete end
 end
 models[t.instance_id]={object=model,state=state}
end
local im=good({},'PalItemContainerManager test')
function im:GetContainer(id)return containers[R.guid_to_string(id.ID)]end
local mm=good({},'PalMapObjectManager test')
function mm:FindModel(id)local x=models[R.guid_to_string(id)];if x and x.state.model_loaded then return x.object end end
function FindAllOf(class)
 if class=='PalItemContainerManager'then return{im}end
 if class=='PalMapObjectManager'then return{mm}end
 if class=='PalItemContainer'then local a={}for _,c in pairs(containers)do a[#a+1]=c end return a end
 return{}
end
local report=R.ownership(T)
assert(report.ok and report.verified_live and #report.chests==18 and concrete_calls==18)
for _,c in ipairs(report.chests)do assert(c.verified_live and c.eligible_for_snapshot_plan and not c.is_guild_chest_live)end
assert(#J.decode(J.encode(report)).chests==18)
local first=T.chests[1]
local state=states[first.container_id]
local function fail_case(key,value)
 local old=state[key];state[key]=value
 local data=R.ownership(T,{limit=1})
 assert(not data.ok and not data.verified_live and not data.chests[1].ownership_verified_live,key)
 state[key]=old
end
fail_case('concrete_loaded',false)
fail_case('model_loaded',false)
fail_case('type','PalFoodBox')
fail_case('type','GuildChest')
fail_case('guild',true)
fail_case('module_container',T.chests[2].container_id)
fail_case('linked_container',T.chests[2].container_id)
fail_case('base','00000000-0000-0000-0000-000000000000')
fail_case('group','00000000-0000-0000-0000-000000000000')
local oldbase,oldgroup=state.base,state.group
state.base=T.chests[3].base_id
local changed=R.ownership(T,{limit=1})
assert(changed.ok and changed.chests[1].verified_live and not changed.chests[1].snapshot_membership_matches_live)
assert(not changed.chests[1].eligible_for_snapshot_plan)
changed=R.ownership(T,{limit=1,require_snapshot_ownership=true})
assert(not changed.ok)
state.base=oldbase
state.group='11111111-2222-3333-4444-555555555555'
changed=R.ownership(T,{limit=1});assert(changed.ok and not changed.chests[1].eligible_for_snapshot_plan)
state.group=oldgroup
local calls=concrete_calls
local legacy=R.chests(T,{limit=1,verify_ownership=false,ownership_only=true})
assert(legacy.ok and not legacy.verified_live and concrete_calls==calls)
print('Ownership tests passed: 18 model/container/base/guild bindings, strict no-force calls, stale membership, type/shared-container rejection, missing models and legacy-unverified mode.')
