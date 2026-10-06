-- Regression for concrete UObjects whose backing map model was unregistered.
-- Uses real discovery/readers modules and 20 independent ordinary chest chains.
local scripts='work/palworld-live/bridge/PalLiveBridge/Scripts/'
package.path=scripts..'?.lua;'..package.path
local R=require('readers');local D=require('discovery');local J=require('json')
local function guid(n)return{A=n,B=2,C=3,D=4}end
local function id(n)return R.guid_to_string(guid(n))end
local function obj(name)
    return{IsValid=function()return true end,GetFullName=function()return name end}
end
local unsafe_calls,transform_calls,force_calls=0,0,0
local function fatal()
    unsafe_calls=unsafe_calls+1;error('FATAL_SENTINEL: stale model-dependent getter reached')
end
local function no_transform()
    transform_calls=transform_calls+1;error('FATAL_SENTINEL: concrete GetTransform reached')
end
local models,containers,concretes={},{},{}
local base=obj('PalBaseCampModel registered')
function base:GetId()return guid(900)end
function base:GetGroupIdBelongTo()return guid(901)end
function base:IsAvailable()return true end
local function add(n,kind,container_number)
    local ci=container_number or n+100
    local container=obj('PalItemContainer '..ci)
    container.bIsGuildChestContainer=false
    function container:GetId()return{ID=guid(ci)}end
    function container:Num()return 40 end
    containers[id(ci)]=container
    local module=obj('PalMapObjectItemContainerModule '..n)
    function module:GetContainerId()return{ID=guid(ci)}end
    function module:GetContainer()return container end
    local concrete=obj('PalMapObjectItemChestModel '..n)
    function concrete:GetModelInstanceId()return guid(n)end
    function concrete:GetInstanceId()return guid(n+500)end
    function concrete:TryGetMapObjectId()return kind or 'ItemChest'end
    function concrete:GetItemContainerModule()return module end
    function concrete:GetBaseCampIdBelongTo()return guid(900)end
    function concrete:GetBaseCampModelBelongTo()return base end
    concrete.GetTransform=no_transform
    local model=obj('PalMapObjectModel '..n)
    function model:GetConcreteModel(force)
        if force~=false then force_calls=force_calls+1;error('force lookup forbidden')end
        return concrete
    end
    models[id(n)]=model;concretes[#concretes+1]=concrete
    return concrete,model
end
for n=1,20 do add(n,n%2==0 and 'ItemChest_02'or'ItemChest')end
local mm=obj('PalMapObjectManager registered')
function mm:FindModel(g)return models[R.guid_to_string(g)]end
local im=obj('PalItemContainerManager registered')
function im:GetContainer(g)return containers[R.guid_to_string(g.ID)]end
local manager_list={mm}
function FindAllOf(class)
    if class=='PalMapObjectManager'then return manager_list end
    if class=='PalItemContainerManager'then return{im}end
    if class=='PalMapObjectItemChestModel'then return concretes end
    return{}
end
local function success()
    local r=D.discover()
    assert(r.ok and r.verified_live and r.discovered_count==20,J.encode(r))
    assert(#r.verification.chests==20)
    for _,t in ipairs(r.targets.chests)do assert(t.world_position==nil)end
    assert(unsafe_calls==0 and transform_calls==0 and force_calls==0)
    return r
end
success()
-- A stale IsValid UObject with no manager entry. Every unsafe method is lethal.
local orphan=obj('PalMapObjectItemChestModel orphan')
function orphan:GetModelInstanceId()return guid(700)end
orphan.TryGetMapObjectId=fatal;orphan.GetItemContainerModule=fatal
orphan.GetBaseCampIdBelongTo=fatal;orphan.GetBaseCampModelBelongTo=fatal
orphan.GetTransform=no_transform
concretes[#concretes+1]=orphan
local r=success();assert(r.excluded[1].reason=='unregistered_model')
-- A stale concrete with a GUID now resolved to another canonical concrete.
local replaced=obj('PalMapObjectItemChestModel replaced')
function replaced:GetModelInstanceId()return guid(1)end
replaced.TryGetMapObjectId=fatal;replaced.GetItemContainerModule=fatal
replaced.GetBaseCampIdBelongTo=fatal;replaced.GetBaseCampModelBelongTo=fatal
replaced.GetTransform=no_transform
concretes[#concretes+1]=replaced
r=success();assert(r.excluded[2].reason=='stale_concrete_binding')
-- Registered nonordinary containers are excluded by type, after identity checks.
add(30,'PalFoodBox');add(31,'GuildChest')
r=success();assert(#r.excluded==4)
-- A duplicate registered model UUID is a failure, never silently merged.
concretes[#concretes+1]=concretes[1]
assert(not D.discover().ok);concretes[#concretes]=nil
-- Independent registered models aliasing one container UUID also fail closed.
add(32,'ItemChest',101)
assert(not D.discover().ok);models[id(32)]=nil;concretes[#concretes]=nil
-- Missing/ambiguous managers fail before any candidate getter.
manager_list={};assert(not D.discover().ok)
manager_list={mm,mm};assert(not D.discover().ok)
manager_list={mm};success()
assert(unsafe_calls==0 and transform_calls==0 and force_calls==0)
print('Discovery registration regression passed: 20 live chains; orphan/replaced concrete fatal getters never called; no GetTransform; duplicate model/container UUIDs rejected; manager uniqueness enforced.')
