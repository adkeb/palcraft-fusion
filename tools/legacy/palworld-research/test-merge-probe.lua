local root='work/palworld-live/'
package.path=root..'bridge/PalLiveBridge/Scripts/?.lua;'..package.path
local J=require('json');local realR=require('readers')
local source=assert(io.open(root..'lab/merge-once.lua','rb')):read('a')
local ZERO='00000000-0000-0000-0000-000000000000'
local function id(n)return string.format('00000000-0000-0000-0000-%012x',n)end
local function clone(t)return J.decode(J.encode(t))end
local function test(opts)
    opts=opts or{};local fs={}
    local calls,queue=0,{}
    local chests={
        {id=id(1),base_id_live=id(10),group_id_live=id(100),slots={{index=0,count=opts.full and 100 or 56,item='Wood',empty=false,dynamicGuid=ZERO,dynamicWorldGuid=ZERO}}},
        {id=id(2),base_id_live=opts.cross_base and id(11)or id(10),group_id_live=id(100),slots={{index=0,count=opts.full and 100 or 1,item='Wood',empty=false,dynamicGuid=opts.dynamic and id(33)or ZERO,dynamicWorldGuid=ZERO}}}}
    if opts.missing_base then chests[1].base_id_live=nil end
    local function obj(name,t)t=t or{};function t:IsValid()return true end;function t:GetFullName()return name end;return t end
    local function slot(c,s)return obj('slot',{
        GetSlotId=function()return{ContainerId={ID=realR.guid_from_string(c.id)},SlotIndex=s.index}end,
        GetStackCount=function()return s.count end,
        GetMaxStack=function()return opts.zero_max and 0 or 100 end,
        IsMaxStack=function()return s.count>=100 end})end
    local manager=obj('manager',{GetContainer=function(_,cid)
        for _,c in ipairs(chests)do if realR.guid_to_string(cid.ID)==c.id then
            return obj('container',{GetId=function()return{ID=cid.ID}end,Get=function(_,n)return slot(c,c.slots[n+1])end})
        end end
    end})
    local component=obj('component',{RequestMove_ToServer=function(_,request,to,froms)
        calls=calls+1;assert(#froms==1 and froms[1].Num==1)
        assert(realR.guid_to_string(to.ContainerId.ID)==id(2));assert(realR.guid_to_string(froms[1].SlotId.ContainerId.ID)==id(1))
        if not opts.no_change then chests[1].slots[1].count=55;chests[2].slots[1].count=2 end
    end})
    local transmitter=obj('transmitter',{HasAuthority=function()return true end,GetItem=function()return component end})
    local R={guid_to_string=realR.guid_to_string,guid_from_string=realR.guid_from_string,
        chests=function(_,options)assert(options.verify_ownership and options.require_snapshot_ownership)
            return {ok=true,verified_live=true,chests=clone(chests)}end}
    local fakeio={open=function(path,mode)
        if mode=='rb' and not fs[path]then return nil end
        if mode=='wb'then fs[path]='' end
        return{write=function(_,s)fs[path]=fs[path]..s;return true end,flush=function()return true end,close=function()return true end}
    end}
    if opts.marker then fs['D:/PalworldServer-LAN/BridgeLab/rpc/merge-probe-once.attempted']='attempted'end
    local env=setmetatable({io=fakeio,print=function()end,require=function(n)return({json=J,readers=R,targets={}})[n]end,
        FindAllOf=function(n)return n=='PalItemContainerManager'and{manager}or{transmitter}end,
        StaticFindObject=function()return obj('guidlib',{NewGuid=function()return realR.guid_from_string(id(500))end})end,
        ExecuteWithDelay=function(_,f)queue[#queue+1]=f end,ExecuteInGameThread=function(f)f()end},{__index=_G})
    local code=opts.apply and source:gsub('local ATTEMPT_MERGE=false','local ATTEMPT_MERGE=true',1)or source
    assert(load(code,'merge-probe','t',env))()
    while #queue>0 do table.remove(queue,1)()end
    return J.decode(assert(fs['D:/PalworldServer-LAN/BridgeLab/rpc/merge-preflight.json'])),calls,fs
end
local a,n=test();assert(a.ok and a.read_only and a.candidate.item=='Wood'and a.candidate.amount==1 and n==0)
local b,n=test{apply=true};assert(b.ok and b.status=='observed_merge_success'and b.verification.expected_source==55 and b.verification.expected_target==2 and n==1)
for _,option in ipairs({'cross_base','dynamic','full'})do local c,n=test{[option]=true,apply=true};assert(not c.ok and c.candidate==J.null and n==0,option)end
for _,option in ipairs({'zero_max','missing_base','marker'})do local c,n=test{[option]=true,apply=true};assert(not c.ok and n==0,option)end
local c,n=test{apply=true,no_change=true};assert(not c.ok and c.status=='outcome_unknown'and n==1)
print('PASS 9 merge probe checks: read-only, native increment/readback, cross-base/dynamic/full/missing base/max/marker refusal, no-op outcome unknown')
