local scripts='work/palworld-live/bridge/PalLiveBridge/Scripts/'
local R=dofile(scripts..'readers.lua');local T=dofile(scripts..'targets.lua')
local t=T.chests[1];local zero={A=0,B=0,C=0,D=0}
local cap=9999;local calls=0
local function obj(name)
    return {IsValid=function()return true end,GetFullName=function()return name end}
end
local c=obj('PalItemContainer test')
function c:GetId()return {ID=t.guid}end
function c:Num()return 2 end
function c:Get(i)
    local s=obj('PalItemSlot test.'..i)
    function s:GetStackCount()return i==0 and 57 or 0 end
    function s:IsEmpty()return i==1 end
    function s:GetSlotId()return {ContainerId={ID=t.guid},SlotIndex=i}end
    function s:GetItemId()return {StaticId=i==0 and 'Wood' or 'None',DynamicId={LocalIdInCreatedWorld=zero,CreatedWorldId=zero}}end
    function s:GetCorruptionProgressRate()return 0 end
    function s:GetMaxStack()assert(i==0,'empty slots must not need item limits');calls=calls+1;return cap end
    return s
end
local mgr=obj('PalItemContainerManager test');function mgr:GetContainer()return c end
function FindAllOf(class)assert(class=='PalItemContainerManager');return {mgr}end
local function scan()return R.chests(T,{limit=1,verify_ownership=false,include_items=true})end
local p=scan();assert(p.ok and calls==1 and p.chests[1].slots[1].max_stack==9999 and p.chests[1].slots[2].max_stack==nil)
for _,n in ipairs({0,-1,1.5,math.huge})do cap=n;assert(not scan().ok)end
cap=1;p=scan();assert(p.ok and p.chests[1].slots[1].max_stack==1,'report actual overfull slot, do not silently alter it')
print('Slot limit tests passed: occupied native limits, empty-slot exclusion, rejection of zero/negative/noninteger/nonfinite limits, no state changes.')
