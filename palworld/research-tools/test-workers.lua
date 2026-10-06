local scripts='work/palworld-live/bridge/PalLiveBridge/Scripts/'
package.path=scripts..'?.lua;'..package.path
local W=require('workers');local R=require('readers');local J=require('json')
local baseid='00000000-0000-4000-8000-000000000031'
local groupid='00000000-0000-4000-8000-00000000001b'
local zero='00000000-0000-0000-0000-000000000000'
local function good(methods,name)
    methods.IsValid=function()return true end
    methods.GetFullName=function()return name end
    return setmetatable({}, {__index=function(_,k)assert(methods[k]~=nil,'unknown read '..k);return methods[k]end,
        __newindex=function()error('attempted native object write')end})
end
local base=good({GetId=function()return R.guid_from_string(baseid)end,
    GetGroupIdBelongTo=function()return R.guid_from_string(groupid)end,IsAvailable=function()return true end},'PalBaseCampModel test')
local states={};local slots={};local directors={};local calls={}
for i=1,6 do
    local s={actor=true,assigned=false,fixed=false,dead=false,sleeping=false,hunger=0,sick=0,group=groupid,
        ranks={[5]=i==2 and 4 or 1,[8]=i==1 and 4 or 0,[12]=i==3 and 4 or 1},sanity=80,base=baseid}
    states[i]=s
    local individual={PlayerUId=R.guid_from_string(zero),InstanceId={A=i,B=0,C=0,D=0},DebugName=''}
    local p=good({GetPalId=function()return individual end,GetBaseCampId=function()return R.guid_from_string(s.base)end,
        GetGroupId=function()return R.guid_from_string(s.group)end,GetCharacterID=function()return 'TestPal'..i end,
        GetLevel=function()return 30 end,IsDead=function()return s.dead end,IsSleeping=function()return s.sleeping end,
        GetSanityValue=function()return s.sanity end,GetMaxSanityValue=function()return 100 end,GetSanityRate=function()return s.sanity/100 end,
        GetFullStomach=function()return 70 end,GetMaxFullStomach=function()return 100 end,GetFullStomachRate=function()return .7 end,
        GetHungerType=function()return s.hunger end,GetWorkerSick=function()return s.sick end,GetPhysicalHealth=function()return 0 end,
        GetCurrentWorkSuitability=function()return 0 end,GetNickname=function(_,out)assert(type(out)=='table');out.outName='Nickname'..i end,
        GetWorkSuitabilityRankWithCharacterRank=function(_,n)assert(type(n)=='number');return s.ranks[n] or 0 end},'Parameter '..i)
    local work=good({GetWorkId=function()return {A=99,B=0,C=0,D=0}end,GetWorkName=function()return 'test work' end,
        IsAssignableFixedOnly=function()return false end},'Work '..i)
    local assign=good({GetAssignedIndividualId=function()return individual end,IsWorking=function()return true end,
        IsWorkable=function()return true end,GetWorkSuitability=function()return 8 end,GetState=function()return 1 end,
        GetWorkingState=function()return 1 end,GetWork=function()return work end},'Assign '..i)
    local cp=good({IsAssignedToAnyWork=function()return s.assigned end,IsAssignedFixed=function()return s.fixed end,
        GetWorkId=function()return s.assigned and {A=99,B=0,C=0,D=0} or R.guid_from_string(zero)end,
        GetWorkAssign=function()return assign end},'CharacterComponent '..i)
    local actor=good({GetCharacterParameterComponent=function()return cp end},'Actor '..i)
    local handle=good({GetIndividualID=function()return individual end,TryGetIndividualParameter=function()return p end,
        TryGetIndividualActor=function()if s.actor then return actor end end},'Handle '..i)
    slots[i]=good({GetSlotIndex=function()return i-1 end,IsEmpty=function()return false end,GetHandle=function()return handle end},'Slot '..i)
end
local director=good({GetOuter=function()return base end,GetCharacterHandleSlots=function(_,out)
    assert(type(out)=='table','OutSlots requires explicit Lua table');for i,s in ipairs(slots)do
        -- Real UE4SS out-array objects are RemoteUnrealParam wrappers.
        out[i]={get=function()return s end}
    end
end},'PalBaseCampWorkerDirector test')
directors[1]=director
function FindAllOf(class)
    calls[class]=(calls[class]or 0)+1
    if class=='PalBaseCampModel'then return{base}end
    if class=='PalBaseCampWorkerDirector'then return directors end
    error('unexpected discovery '..class)
end
local snap=W.list();assert(snap.ok and snap.worker_count==6 and #snap.bases==1)
assert(snap.bases[1].workers[1].nickname=='Nickname1' and snap.bases[1].workers[1].task.known)
assert(#J.decode(J.encode(snap)).bases[1].workers==6)
local req={base_id=baseid,roles={{suitability='Mining'},{suitability='Handcraft'},{suitability='Transport'}}}
local plan=W.plan(snap,req);assert(plan.preview_only and not plan.apply_supported and #plan.assignments==3 and #plan.unfilled==0)
local ids={};for _,a in ipairs(plan.assignments)do assert(not ids[a.individual_id.instance_id]);ids[a.individual_id.instance_id]=true;assert(a.rank==4)end
local beforecalls=calls.PalBaseCampModel+calls.PalBaseCampWorkerDirector
W.plan(snap,req);assert(calls.PalBaseCampModel+calls.PalBaseCampWorkerDirector==beforecalls,'pure plan touched runtime')
states[1].actor=false;states[2].fixed=true;states[2].assigned=true;states[3].hunger=1;states[4].dead=true;states[5].sick=1;states[6].sleeping=true
snap=W.list();assert(snap.ok and not snap.bases[1].workers[1].task.known)
assert(snap.bases[1].workers[2].task.name=='test work')
plan=W.plan(snap,req);assert(#plan.assignments==0 and #plan.retained==6 and #plan.unfilled==3)
states[1].group=zero;snap=W.list();assert(snap.ok and snap.bases[1].workers[1].ok and not snap.bases[1].workers[1].ownership_verified_live)
states[1].group=groupid;states[1].base=zero;snap=W.list()
local first=snap.bases[1].workers[1]
assert(first.ok and not first.ownership_verified_live and first.membership.director_base_id==baseid and first.base_id==zero)
assert(not first.membership.parameter_base_available and #first.warnings>0 and first.sanity==80)
plan=W.plan(snap,req);assert(plan.retained[1].reason=='unverified_ownership')
states[1].base=baseid
states[1].group=groupid;directors[1]=nil;assert(not W.list().ok);directors[1]=director
assert(not W.list({base_id=zero}).ok)
snap=W.list()
assert(not pcall(W.plan,snap,{base_id=baseid,roles={{suitability='Unknown'}}}))
assert(not pcall(W.plan,snap,{base_id=baseid,roles={{suitability='Mining',count=-1}}}))
assert(not pcall(W.plan,snap,{base_id=baseid,roles={{suitability='Mining'},{suitability='Mining'}}}))
print('Worker tests passed: native read chain, out parameters, identity guards, health/task states, JSON, pure unique-worker preview, retained busy/unknown workers and invalid requests.')
