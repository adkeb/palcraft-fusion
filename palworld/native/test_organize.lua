local M=dofile("work/palworld-live/bridge/PalLiveBridge/Scripts/organize.lua")
local ZERO="00000000-0000-0000-0000-000000000000"
local function guid(n) return string.format("00000000-0000-0000-0000-%012x",n) end
local BASE,GROUP=guid(10000),guid(10001)
local passed=0
local function test(name,fn)
    local ok,err=pcall(fn)
    if not ok then error(name..": "..tostring(err),0) end
    passed=passed+1; print("PASS "..name)
end
local function clone(v) if type(v)~="table" then return v end; local o={};for k,x in pairs(v) do o[k]=clone(x) end;return o end
local function content(item,count,dynamic)
    return {item=item,count=count or 1,dynamicGuid=dynamic or ZERO,dynamicWorldGuid=dynamic and guid(50000) or ZERO,
        corruption=0.42,corruptionKind="GetCorruptionProgressRate"}
end
local function fixture(specs)
    local targets={chests={}},snapshot
    snapshot={ok=true,includes_items=true,chests={}}
    for ci,spec in ipairs(specs) do
        local id=guid(ci);local base=spec.base_id or BASE
        targets.chests[ci]={container_id=id,base_id=base,group_id=GROUP,type=spec.type or "ItemChest_02",expected_capacity=spec.capacity}
        local chest={id=id,actual_id=id,ok=true,capacity=spec.capacity,base_id_from_snapshot=base,group_id_from_snapshot=GROUP,slots={}}
        snapshot.chests[ci]=chest
        for index=0,spec.capacity-1 do
            local s=clone((spec.slots or {})[index]) or content("None",0)
            s.index=index;s.slot_id_index=index;s.container_id=id;s.empty=s.count==0
            chest.slots[#chest.slots+1]=s
        end
    end
    return snapshot,targets,{base_id=BASE}
end
local function assign(fromci,fromi,toci,toi) return {from={container_id=guid(fromci),index=fromi},to={container_id=guid(toci),index=toi}} end
local function expect_plan(snapshot,targets,opts,assignment)
    local plan,err
    if assignment then plan,err=M.plan_assignment(snapshot,targets,opts,assignment) else plan,err=M.plan(snapshot,targets,opts) end
    assert(plan,err and (err.code..": "..err.message))
    local result,simerr=M.simulate(snapshot,targets,opts,plan)
    assert(result,simerr and (simerr.code..": "..simerr.message))
    assert(result.inventory_signature==plan.inventory_signature)
    for _,move in ipairs(plan.operations) do assert(move.expected_target_empty and move.count==move.expected_source.count) end
    return plan,result
end

test("charcoal is processed and stays separate from raw coal",function()
    assert(M.classify("Charcoal")=="processed" and M.classify("Coal")=="raw")
    local s,t,o=fixture({{capacity=3,slots={[0]=content("Charcoal",40),[1]=content("Coal",8)}},{capacity=3,slots={[0]=content("Cloth",6)}}})
    local plan=expect_plan(s,t,o)
    for _,box in ipairs(plan.containers)do
        local kinds={}; for _,slot in ipairs(box.slots)do kinds[slot.item]=true end
        if kinds.Charcoal then assert(kinds.Cloth and not kinds.Coal and box.label=="加工材料")end
    end
end)
test("three-stack cycle uses one empty scratch slot",function()
    local s,t,o=fixture({{capacity=4,slots={[0]=content("Wood",7),[1]=content("Stone",8),[2]=content("Fiber",9)}}})
    local plan=expect_plan(s,t,o,{assign(1,0,1,1),assign(1,1,1,2),assign(1,2,1,0)})
    assert(#plan.operations==4 and plan.operations[1].temporary)
end)
test("empty-target chain uses no temporary move",function()
    local s,t,o=fixture({{capacity=3,slots={[0]=content("Wood",7),[1]=content("Stone",8)}}})
    local plan=expect_plan(s,t,o,{assign(1,0,1,1),assign(1,1,1,2)})
    assert(#plan.operations==2)
    for _,move in ipairs(plan.operations) do assert(not move.temporary) end
end)
test("identical stacks retain separate origin tokens",function()
    local s,t,o=fixture({{capacity=3,slots={[0]=content("Wood",7),[1]=content("Wood",7)}}})
    local plan,result=expect_plan(s,t,o,{assign(1,0,1,1),assign(1,1,1,0)})
    assert(plan.stacks[1].token~=plan.stacks[2].token and result.stack_count==2 and #plan.operations==3)
end)
test("full nontrivial permutation is refused",function()
    local s,t,o=fixture({{capacity=2,slots={[0]=content("Wood"),[1]=content("Stone")}}})
    local plan,err=M.plan_assignment(s,t,o,{assign(1,0,1,1),assign(1,1,1,0)})
    assert(not plan and err.code=="no_empty_slot")
end)
test("full already-correct arrangement needs no scratch",function()
    local s,t,o=fixture({{capacity=2,slots={[0]=content("Wood"),[1]=content("Stone")}}})
    local plan=expect_plan(s,t,o,{assign(1,0,1,0),assign(1,1,1,1)})
    assert(#plan.operations==0)
end)
test("dynamic identity and opaque metadata are conserved",function()
    local weapon=content("HandGun",1,guid(9876));weapon.dynamic_data={durability=98.25,ammo=5,traits={"one","two"}}
    local s,t,o=fixture({{capacity=2,slots={[0]=weapon}},{capacity=2,slots={[0]=content("Wood",57)}}})
    local before=M.canonical(s)
    local plan=expect_plan(s,t,o,{assign(1,0,2,1),assign(2,0,1,1)})
    assert(M.canonical(s)==before)
    assert(plan.stacks[1].content.dynamic_data.ammo==5 and plan.stacks[1].content.dynamicGuid==guid(9876))
end)
test("base scope excludes all other-base stacks",function()
    local s,t,o=fixture({{capacity=3,slots={[0]=content("Wood"),[1]=content("Stone")}},{capacity=3,base_id=guid(10002),slots={[0]=content("Money",800)}}})
    local plan=expect_plan(s,t,o)
    assert(plan.stack_count==2 and #plan.containers==1)
    for _,move in ipairs(plan.operations) do assert(move.from.container_id==guid(1) and move.to.container_id==guid(1)) end
    local _,err=M.plan_assignment(s,t,o,{assign(1,0,2,1),assign(1,1,1,0)})
    assert(err.code=="invalid_assignment")
end)
test("category allocation explicitly reports mixed overflow",function()
    local s,t,o=fixture({{capacity=4,slots={[0]=content("Wood"),[1]=content("CopperIngot"),[2]=content("PalOil")}},{capacity=4,slots={[0]=content("Money"),[1]=content("Potion"),[2]=content("Cake")}}})
    local plan=expect_plan(s,t,o)
    local mixed=false;for _,c in ipairs(plan.containers) do if c.mixed then mixed=true end end
    assert(mixed and plan.stack_count==6 and plan.capacity==8)
end)
test("category allocation keeps categories pure when space permits",function()
    local s,t,o=fixture({{capacity=3,slots={[0]=content("Money"),[1]=content("Wood")}},{capacity=3,slots={[0]=content("Stone"),[1]=content("Ruby")}}})
    local plan=expect_plan(s,t,o)
    for _,c in ipairs(plan.containers) do assert(not c.mixed) end
end)
local function food_medicine_fixture(raw_count,policy)
    local all={}
    for _=1,12 do all[#all+1]=content("Cake") end
    for _=1,raw_count do all[#all+1]=content("Wood") end
    all[#all+1]=content("Potion");all[#all+1]=content("Potion");all[#all+1]=content("Herbs")
    local specs={};local at=1
    for _,capacity in ipairs({24,10,10}) do
        local spec={capacity=capacity,slots={}}
        for index=0,capacity-1 do if all[at] then spec.slots[index]=all[at];at=at+1 end end
        specs[#specs+1]=spec
    end
    local s,t,o=fixture(specs);o.policy=policy or "category";return s,t,o
end
test("medicine borrows reserved food capacity before unrelated raw overflow",function()
    local s,t,o=food_medicine_fixture(11)
    local plan=expect_plan(s,t,o);local medicines=0
    for _,box in ipairs(plan.containers) do
        local cats={};for _,category in ipairs(box.categories) do cats[category.id]=category.stacks end
        if cats.medicine then assert(cats.food_seeds==12 and not cats.raw);medicines=medicines+cats.medicine end
        if cats.raw then assert(#box.categories==1) end
    end
    assert(medicines==3 and plan.stack_count==26 and plan.empty_slots==18)
end)
test("medicine still gets its own box when capacity permits",function()
    local s,t,o=food_medicine_fixture(8)
    local plan=expect_plan(s,t,o);local found=false
    for _,box in ipairs(plan.containers) do
        for _,category in ipairs(box.categories) do
            if category.id=="medicine" then assert(#box.categories==1);found=true end
        end
    end
    assert(found)
end)
test("successive medicine item groups can share food reserve with correct budget",function()
    local s,t,o=food_medicine_fixture(11,"item_type")
    local plan=expect_plan(s,t,o);local medicines=0
    for _,box in ipairs(plan.containers) do
        local cats={};for _,category in ipairs(box.categories) do cats[category.id]=category.stacks end
        if cats.medicine then assert(cats.food_seeds==12 and not cats.raw);medicines=medicines+cats.medicine end
    end
    assert(medicines==3)
end)
test("all empty containers produce a valid zero-operation plan",function()
    local s,t,o=fixture({{capacity=3},{capacity=2}})
    local plan=expect_plan(s,t,o);assert(plan.stack_count==0 and #plan.operations==0)
end)
test("nonordinary boxes are rejected",function()
    local s,t,o=fixture({{capacity=3,type="FeedBox"}})
    local plan,err=M.plan(s,t,o);assert(not plan and err.code=="unsupported_container")
end)
test("live ownership is required when requested and never invented",function()
    local s,t,o=fixture({{capacity=2,slots={[0]=content("Wood")}}})
    local p=expect_plan(s,t,o);assert(p.ownership_verified_live==false)
    o.require_live_ownership=true
    local _,err=M.plan(s,t,o);assert(err.code=="ownership_unverified")
    s.verifies_ownership=true
    local c=s.chests[1]
    c.ownership_verified_live=true;c.eligible_for_snapshot_plan=true
    c.base_id_live=BASE;c.group_id_live=GROUP;c.type_live=t.chests[1].type
    c.is_guild_chest_live=false;c.container_id_from_module_live=c.id
    p=expect_plan(s,t,o);assert(p.ownership_verified_live==true)
end)
test("live base changes or shared containers reject snapshot plans",function()
    local s,t,o=fixture({{capacity=2,slots={[0]=content("Wood")}}})
    s.verifies_ownership=true
    local c=s.chests[1]
    c.ownership_verified_live=true;c.eligible_for_snapshot_plan=true
    c.base_id_live=guid(10002);c.group_id_live=GROUP;c.type_live=t.chests[1].type
    c.is_guild_chest_live=false;c.container_id_from_module_live=c.id
    local _,err=M.plan(s,t,o);assert(err.code=="cross_base")
    c.base_id_live=BASE;c.is_guild_chest_live=true
    _,err=M.plan(s,t,o);assert(err.code=="ownership_unverified")
end)
test("changed capacity and incomplete snapshots are rejected",function()
    local s,t,o=fixture({{capacity=3}})
    t.chests[1].expected_capacity=2
    local _,err=M.plan(s,t,o);assert(err.code=="capacity_changed")
    t.chests[1].expected_capacity=3;s.chests[1].slots[3]=nil
    _,err=M.plan(s,t,o);assert(err.code=="incomplete_snapshot")
end)
test("partial-stack or occupied-target execution is refused",function()
    local s,t,o=fixture({{capacity=3,slots={[0]=content("Wood",7),[1]=content("Stone",8)}}})
    local plan=expect_plan(s,t,o,{assign(1,0,1,1),assign(1,1,1,2)})
    local tampered=clone(plan);tampered.operations[1].count=1
    local result,err=M.simulate(s,t,o,tampered);assert(not result and err.code=="conflict")
    tampered=clone(plan);tampered.operations[1].to.index=0
    result,err=M.simulate(s,t,o,tampered);assert(not result and err.code=="conflict")
end)
test("same-multiset relocation is detected as stale input",function()
    local s,t,o=fixture({{capacity=3,slots={[0]=content("Wood",7),[1]=content("Stone",8)}}})
    local plan=expect_plan(s,t,o,{assign(1,0,1,0),assign(1,1,1,1)})
    local a,b=s.chests[1].slots[1],s.chests[1].slots[2]
    a.item,b.item=b.item,a.item;a.count,b.count=b.count,a.count
    local result,err=M.simulate(s,t,o,plan);assert(not result and err.code=="conflict")
end)
test("unknown static items are kept in explicit unclassified category",function()
    assert(M.classify("FutureItemThatDoesNotExistYet")=="unclassified")
    local s,t,o=fixture({{capacity=2,slots={[0]=content("FutureItemThatDoesNotExistYet",99)}}})
    local plan=expect_plan(s,t,o);assert(plan.stacks[1].category=="unclassified")
end)
test("500 random permutations preserve every full stack",function()
    math.randomseed(90210)
    for trial=1,500 do
        local n=math.random(1,20);local empties=math.random(1,4);local slots={}
        for index=0,n-1 do slots[index]=content(index%2==0 and "Wood" or "Stone",index+1) end
        local s,t,o=fixture({{capacity=n+empties,slots=slots}})
        local locations={};for i=0,n+empties-1 do locations[#locations+1]=i end
        for i=#locations,2,-1 do local j=math.random(i);locations[i],locations[j]=locations[j],locations[i] end
        local assignments={};for i=0,n-1 do assignments[#assignments+1]=assign(1,i,1,locations[i+1]) end
        local plan=expect_plan(s,t,o,assignments);assert(#plan.operations<=2*n)
    end
end)
print(string.format("OK %d tests; 500 randomized permutations",passed))
