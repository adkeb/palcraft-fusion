-- Pure storage planner. No UE calls, hooks, file I/O, RPCs or gameplay mutations.
-- Input is Readers.chests(targets,{include_items=true}) and the fixed targets table.
-- Every stack has an origin token, even when several stacks have identical items.
-- Native executor must recheck each source/empty target on the GAME THREAD, move
-- exactly the full stack, and independently read back before advancing the plan.
local M = {version="0.1.0", native_executor_included=false}
local ZERO = "00000000-0000-0000-0000-000000000000"
local ORDINARY = {ItemChest=true, ItemChest_02=true}

local CATEGORIES = {
    {id="raw", label="建材矿物"}, {id="processed", label="加工材料"},
    {id="pal_materials", label="帕鲁素材"}, {id="equipment", label="装备弹药捕获"},
    {id="blueprint_armor", label="防具图纸"}, {id="blueprint_weapon", label="武器及建筑图纸"},
    {id="blueprint_accessory", label="饰品图纸"}, {id="pal_eggs_skills", label="帕鲁蛋与技能果"},
    {id="pal_training", label="帕鲁培养材料"}, {id="food_seeds", label="食物种子"},
    {id="valuables", label="贵重物品"}, {id="medicine", label="药品"},
    {id="unclassified", label="待确认杂物"}
}
local CATEGORY = {}
for rank, c in ipairs(CATEGORIES) do c.rank=rank; CATEGORY[c.id]=c end

local function fail(code, message) error({code=code,message=message}, 0) end
local function check(condition, code, message) if not condition then fail(code,message) end end
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function integer(n, low, high) return finite(n) and n%1==0 and n>=low and n<=high end
local function uuid(v)
    return type(v)=="string" and #v==36 and v:sub(9,9)=="-" and v:sub(14,14)=="-"
        and v:sub(19,19)=="-" and v:sub(24,24)=="-" and #v:gsub("-","")==32
        and v:gsub("-",""):match("^%x+$")~=nil
end
local function copy(v, seen)
    if type(v)~="table" then
        check(v==nil or type(v)=="string" or type(v)=="boolean" or finite(v), "invalid_snapshot", "Non-primitive snapshot value")
        return v
    end
    seen=seen or {}; check(not seen[v], "invalid_snapshot", "Cyclic snapshot value"); seen[v]=true
    local out={}
    for k,x in pairs(v) do
        check(type(k)=="string" or type(k)=="number", "invalid_snapshot", "Invalid snapshot key")
        out[k]=copy(x,seen)
    end
    seen[v]=nil; return out
end
local function sorted_keys(t)
    local keys={}; for k in pairs(t) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end); return keys
end
local function canonical(v)
    local kind=type(v)
    if kind=="table" then
        local parts={"{"}; for _,k in ipairs(sorted_keys(v)) do
            parts[#parts+1]=canonical(k); parts[#parts+1]="="; parts[#parts+1]=canonical(v[k]); parts[#parts+1]=";"
        end
        parts[#parts+1]="}"; return table.concat(parts)
    elseif kind=="string" then return "s"..#v..":"..v
    elseif kind=="number" then check(finite(v),"invalid_snapshot","Non-finite number"); return "n"..string.format("%.17g",v)
    elseif kind=="boolean" then return v and "true" or "false"
    elseif kind=="nil" then return "nil"
    else fail("invalid_snapshot","Unsupported canonical value") end
end
local function words(s) local t={}; for word in s:gmatch("%S+") do t[word]=true end; return t end
local RAW=words("Wood Fiber CopperOre IronOre Coal Sulfur Stone Pal_crystal_S MeteorDrop Wood_Ancient Wood_Fine CrudeOil Quartz PureQuartz Chromite HexoliteQuartz")
local PROCESSED=words("Charcoal CopperIngot IronIngot StealIngot SteelIngot PalMetalIngot Plasteel Cement Cloth MachineParts MachineParts2 GunPowder GunPowder2 Processed_Wood YakushimaIngot001 Bio_Coolant Polymer CarbonFiber CircuitBoard")
local PAL=words("bone Bone PalOil PalFluid Leather Venom Horn Wool FireOrgan IceOrgan ElectricOrgan")
local VALUABLE=words("Money DogCoin Ruby Sapphire BountyProof_1")
local FOOD=words("Berries Wheat Flour Honey Sweet CaveMushroom Mushroom Egg Milk Cake Lettuce Tomato")
local MEDICINE=words("Potion Potion_Low Medicines Herbs Poppy")
local function begins(s,p) return s:sub(1,#p)==p end
local function has(s,p) return s:find(p,1,true)~=nil end
local function any_prefix(s, prefixes) for _,p in ipairs(prefixes) do if begins(s,p) then return true end end; return false end

function M.classify(slot)
    local item=type(slot)=="table" and slot.item or slot
    check(type(item)=="string", "invalid_snapshot", "Missing static item name")
    if begins(item,"Blueprint_") then
        if has(item,"Accessory") or has(item,"Otomo_") then return "blueprint_accessory" end
        if has(item,"Armor") or has(item,"Helmet") or has(item,"HeadEquip") then return "blueprint_armor" end
        return "blueprint_weapon"
    end
    if RAW[item] then return "raw" end
    if PROCESSED[item] or has(item,"Ingot") then return "processed" end
    if PAL[item] then return "pal_materials" end
    if VALUABLE[item] or any_prefix(item,{"PalItem_ToSell_","TreasureMap","TreasureBoxKey","BountyProof_"}) then return "valuables" end
    if any_prefix(item,{"PalEgg_","SkillCard_"}) or item=="Rankup_1" then return "pal_eggs_skills" end
    if any_prefix(item,{"WorkSuitability_","PalUpgrade","Lotus_","ExpBoost_","Fruit_","AffectionFruit_","Rankup_","PalSummon_","Elixir_"})
        or item=="PredatorCrystal" or item=="PalCrystal_Ex" or item=="AncientParts3" then return "pal_training" end
    if FOOD[item] or item:sub(-5)=="Seeds" or any_prefix(item,{"Meat_","Baked","Pan"}) then return "food_seeds" end
    if MEDICINE[item] or any_prefix(item,{"Potion","Medicine"}) then return "medicine" end
    if any_prefix(item,{"PalSphere","FishingBait_","SphereModule_","Shield_"})
        or has(item,"Bullet") or has(item,"Arrow") or has(item,"Grenade") or has(item,"Armor") or has(item,"Helmet")
        or (type(slot)=="table" and slot.dynamicGuid and slot.dynamicGuid~=ZERO) then return "equipment" end
    if begins(item,"PalItem_") then return "pal_materials" end
    return "unclassified"
end

local function location(id,index) return id:lower()..":"..string.format("%04d",index) end
local function ref(node) return {container_id=node.container_id,index=node.index} end
local function payload(slot)
    local out={}
    for k,v in pairs(slot) do
        if k~="container_id" and k~="index" and k~="slot_id_index" and k~="empty" then out[k]=copy(v) end
    end
    return out
end

local function normalize(snapshot, targets, opts)
    opts=opts or {}
    check(type(snapshot)=="table" and snapshot.ok==true and snapshot.includes_items==true and type(snapshot.chests)=="table",
        "invalid_snapshot","Complete successful Readers.chests snapshot with include_items=true required")
    check(type(targets)=="table" and type(targets.chests)=="table", "invalid_targets","Fixed ordinary-chest allowlist required")
    check(uuid(opts.base_id),"invalid_base","One base_id is required; cross-base plans are unsupported")
    check(opts.include_shared~=true,"unsupported","Shared guild storage is outside the ordinary-chest allowlist")
    check(opts.policy==nil or opts.policy=="category" or opts.policy=="item_type","unsupported","Unknown sorting policy")
    local base=opts.base_id:lower()
    local allow={}
    for _,t in ipairs(targets.chests) do
        check(uuid(t.container_id) and uuid(t.base_id) and uuid(t.group_id),"invalid_targets","Invalid target identifiers")
        local id=t.container_id:lower(); check(not allow[id],"invalid_targets","Duplicate allowlist container")
        allow[id]=t
    end
    local selected={}
    if opts.container_ids~=nil then
        check(type(opts.container_ids)=="table" and #opts.container_ids>0,"invalid_targets","container_ids must be nonempty")
        for _,id in ipairs(opts.container_ids) do
            check(uuid(id),"invalid_targets","Invalid selected container UUID"); id=id:lower()
            check(not selected[id],"invalid_targets","Duplicate selected container")
            check(allow[id]~=nil and allow[id].base_id:lower()==base,"cross_base","Selected container is not allowlisted at this base")
            selected[id]=true
        end
    else for id,t in pairs(allow) do if t.base_id:lower()==base then selected[id]=true end end end
    check(next(selected)~=nil,"invalid_base","No allowlisted ordinary chests at this base")
    local by_id={}
    for _,c in ipairs(snapshot.chests) do
        check(uuid(c.id),"invalid_snapshot","Invalid container id")
        local id=c.id:lower(); check(not by_id[id],"invalid_snapshot","Duplicate live container id"); by_id[id]=c
    end
    local state={base_id=base,chests={},nodes={},node_order={},tokens={},token_order={},current={},targets=allow,initial_slots={},ownership_verified_live=true}
    local group
    for _,id in ipairs(sorted_keys(selected)) do
        local t=allow[id]; local c=by_id[id]
        check(ORDINARY[t.type],"unsupported_container","Only ItemChest and ItemChest_02 are allowed")
        check(c and c.ok==true and c.actual_id and c.actual_id:lower()==id,"invalid_snapshot","Allowlisted live chest is missing or unreadable")
        check(c.base_id_from_snapshot and c.base_id_from_snapshot:lower()==base,"cross_base","Snapshot base id does not match allowlist")
        check(c.group_id_from_snapshot and c.group_id_from_snapshot:lower()==t.group_id:lower(),"invalid_snapshot","Snapshot guild id does not match allowlist")
        local has_ownership=snapshot.verifies_ownership==true or c.ownership_verified_live==true or c.base_id_live~=nil
        if has_ownership then
            check(c.ownership_verified_live==true and c.eligible_for_snapshot_plan==true,
                "ownership_unverified","Live ordinary-container ownership and snapshot membership must both be verified")
            check(uuid(c.base_id_live) and c.base_id_live:lower()==base and uuid(c.group_id_live)
                and c.group_id_live:lower()==t.group_id:lower(),"cross_base","Live base or guild differs from the requested allowlist")
            check(c.type_live==t.type and c.is_guild_chest_live==false and uuid(c.container_id_from_module_live)
                and c.container_id_from_module_live:lower()==id,"ownership_unverified","Live ordinary type or container-module binding differs from allowlist")
        else
            state.ownership_verified_live=false
            check(opts.require_live_ownership~=true,"ownership_unverified","Live ownership verification is required for this plan")
        end
        check(not group or group==t.group_id:lower(),"cross_guild","Selected boxes span guilds"); group=t.group_id:lower()
        check(integer(c.capacity,1,1000) and c.capacity==t.expected_capacity,"capacity_changed","Container capacity changed; refresh allowlist first")
        check(type(c.slots)=="table" and #c.slots==c.capacity,"incomplete_snapshot","Every slot including empty slots must be present")
        local chest={id=id,type=t.type,capacity=c.capacity,map=copy(t.map),world=copy(t.world),entries={},allocations={},free=c.capacity}
        state.chests[#state.chests+1]=chest
        local seen={}
        for _,slot in ipairs(c.slots) do
            check(integer(slot.index,0,c.capacity-1) and not seen[slot.index],"invalid_snapshot","Duplicate or out-of-range slot index")
            seen[slot.index]=true
            check(type(slot.container_id)=="string" and slot.container_id:lower()==id and slot.slot_id_index==slot.index,
                "invalid_snapshot","Live slot identity does not match its chest")
            check(integer(slot.count,0,2147483647) and type(slot.empty)=="boolean", "invalid_snapshot","Invalid slot count or empty flag")
            check(type(slot.item)=="string" and uuid(slot.dynamicGuid) and uuid(slot.dynamicWorldGuid),"invalid_snapshot","Missing complete item identity")
            check(slot.corruption==nil or finite(slot.corruption),"invalid_snapshot","Invalid corruption value")
            check((slot.empty and slot.count==0 and (slot.item=="None" or slot.item==""))
                or (not slot.empty and slot.count>0 and slot.item~="None" and slot.item~=""),"invalid_snapshot","Empty flag, item and count disagree")
            local key=location(id,slot.index); local node={container_id=id,index=slot.index,key=key,chest=chest}
            state.nodes[key]=node; state.node_order[#state.node_order+1]=key
            if not slot.empty then
                local token={id=key,origin=ref(node),payload=payload(slot),category=M.classify(slot)}
                state.tokens[key]=token; state.token_order[#state.token_order+1]=key; state.current[key]=key
            end
            state.initial_slots[#state.initial_slots+1]={container_id=id,index=slot.index,token=state.current[key]}
        end
    end
    table.sort(state.node_order); table.sort(state.token_order)
    table.sort(state.initial_slots,function(a,b) return location(a.container_id,a.index)<location(b.container_id,b.index) end)
    state.group_id=group; state.empty_count=#state.node_order-#state.token_order
    return state
end

local function token_less(a,b)
    if CATEGORY[a.category].rank~=CATEGORY[b.category].rank then return CATEGORY[a.category].rank<CATEGORY[b.category].rank end
    if a.payload.item~=b.payload.item then return a.payload.item<b.payload.item end
    if a.payload.dynamicGuid~=b.payload.dynamicGuid then return a.payload.dynamicGuid<b.payload.dynamicGuid end
    if a.payload.count~=b.payload.count then return a.payload.count>b.payload.count end
    return a.id<b.id
end

local function allocate(state, policy)
    local buckets={}
    for _,id in ipairs(state.token_order) do
        local token=state.tokens[id]
        local key=policy=="item_type" and (token.category..":"..token.payload.item) or token.category
        if not buckets[key] then buckets[key]={key=key,category=token.category,tokens={}} end
        local b=buckets[key]; b.tokens[#b.tokens+1]=token
    end
    local groups={}; for _,b in pairs(buckets) do table.sort(b.tokens,token_less); groups[#groups+1]=b end
    table.sort(groups,function(a,b)
        if #a.tokens~=#b.tokens then return #a.tokens>#b.tokens end
        return a.key<b.key
    end)
    local slack=state.empty_count
    local function affinity(chest,group)
        local count=0; for _,t in ipairs(group.tokens) do if t.origin.container_id==chest.id then count=count+1 end end; return count
    end
    for _,group in ipairs(groups) do
        local remaining={}; for _,t in ipairs(group.tokens) do remaining[#remaining+1]=t end
        while #remaining>0 do
            local candidates={}
            -- Prefer a fresh box whose spare space fits the global spare budget.
            for _,chest in ipairs(state.chests) do
                if #chest.entries==0 and chest.free>=#remaining and chest.free-#remaining<=slack then candidates[#candidates+1]=chest end
            end
            local dedicate=#candidates>0
            local borrow_food_reserve=false
            if dedicate then
                table.sort(candidates,function(a,b)
                    if a.free~=b.free then return a.free<b.free end
                    local aa,bb=affinity(a,group),affinity(b,group); if aa~=bb then return aa>bb end
                    return a.id<b.id
                end)
            else
                -- Medicine fits with food when no separate box can be reserved.
                -- Reuse food's reserved empty capacity before unrelated overflow.
                if group.category=="medicine" then
                    for _,chest in ipairs(state.chests) do
                        if chest.dedicated and chest.free>0 then
                            local food_only,has_food=true,false
                            for _,token in ipairs(chest.entries) do
                                if token.category=="food_seeds" then has_food=true
                                elseif token.category~="medicine" then food_only=false end
                            end
                            if food_only and has_food then candidates[#candidates+1]=chest end
                        end
                    end
                    borrow_food_reserve=#candidates>0
                    table.sort(candidates,function(a,b)
                        local af,bf=a.free>=#remaining,b.free>=#remaining
                        if af~=bf then return af end
                        if a.free~=b.free then return af and a.free<b.free or (not af and a.free>b.free) end
                        return a.id<b.id
                    end)
                end
                if not borrow_food_reserve then
                    -- Fill a whole fresh box before mixing partial overflow boxes.
                    for _,chest in ipairs(state.chests) do if #chest.entries==0 and chest.free>0 then candidates[#candidates+1]=chest end end
                    table.sort(candidates,function(a,b)
                        local af,bf=a.free<=#remaining,b.free<=#remaining
                        if af~=bf then return af end
                        if a.free~=b.free then return af and a.free>b.free or (not af and a.free<b.free) end
                        local aa,bb=affinity(a,group),affinity(b,group); if aa~=bb then return aa>bb end
                        return a.id<b.id
                    end)
                    if #candidates==0 then
                        for _,chest in ipairs(state.chests) do if not chest.dedicated and chest.free>0 then candidates[#candidates+1]=chest end end
                        table.sort(candidates,function(a,b) if a.free~=b.free then return a.free>b.free end; return a.id<b.id end)
                    end
                end
            end
            check(#candidates>0,"capacity_exceeded","No capacity remains for whole-stack allocation")
            local chest=candidates[1]; local amount=math.min(#remaining,chest.free)
            -- Keep existing stacks in their assigned chest when quotas permit.
            table.sort(remaining,function(a,b)
                local aa,bb=a.origin.container_id==chest.id,b.origin.container_id==chest.id
                if aa~=bb then return aa end; return token_less(a,b)
            end)
            for _=1,amount do chest.entries[#chest.entries+1]=table.remove(remaining,1) end
            chest.allocations[group.key]=(chest.allocations[group.key] or 0)+amount
            chest.free=chest.free-amount
            if dedicate then chest.dedicated=true; slack=slack-chest.free end
            -- These slots were previously charged to food's empty-space reserve.
            -- Consuming them releases that amount for other dedicated boxes.
            if borrow_food_reserve then slack=slack+amount end
            local reserved=0
            for _,box in ipairs(state.chests) do if box.dedicated then reserved=reserved+box.free end end
            check(slack>=0 and slack+reserved==state.empty_count,"internal_error","Dedicated empty-slot budget is inconsistent")
        end
    end
    local desired={}
    for _,chest in ipairs(state.chests) do
        table.sort(chest.entries,token_less)
        for i,t in ipairs(chest.entries) do desired[t.id]=location(chest.id,i-1) end
    end
    return desired
end

local function inventory(state)
    local rows={}; for _,id in ipairs(state.token_order) do rows[#rows+1]=canonical(state.tokens[id].payload) end
    table.sort(rows); return table.concat(rows,"\n")
end

local function make_plan(state, desired, policy)
    local wanted,current,positions={},{},{}
    for _,id in ipairs(state.token_order) do
        local target=desired[id]
        check(target and state.nodes[target],"invalid_assignment","Every stack needs an in-scope destination")
        check(not wanted[target],"invalid_assignment","Two stacks target the same slot")
        wanted[target]=id; current[id]=id; positions[id]=id
    end
    local plan={version=M.version,base_id=state.base_id,group_id=state.group_id,policy=policy or "explicit",
        scope="fixed_snapshot_allowlist",ownership_verified_live=state.ownership_verified_live,merge_stacks=false,cross_base=false,
        stack_count=#state.token_order,capacity=#state.node_order,empty_slots=state.empty_count,
        initial_slots=copy(state.initial_slots),stacks={},assignments={},containers={},operations={},warnings={}}
    local pending=0
    for _,id in ipairs(state.token_order) do
        local t=state.tokens[id]
        plan.stacks[#plan.stacks+1]={token=id,origin=copy(t.origin),category=t.category,content=copy(t.payload)}
        plan.assignments[#plan.assignments+1]={token=id,from=copy(t.origin),to=ref(state.nodes[desired[id]])}
        if id~=desired[id] then pending=pending+1 end
    end
    plan.changed_stacks=pending
    check(pending==0 or state.empty_count>0,"no_empty_slot","At least one empty ordinary slot at this base is required; full stacks will not be merged or swapped")
    local function move(id,to,temporary)
        local from=positions[id]
        check(current[from]==id and current[to]==nil,"internal_error","Planner violated Move-to-empty invariant")
        local token=state.tokens[id]
        plan.operations[#plan.operations+1]={sequence=#plan.operations+1,token=id,from=ref(state.nodes[from]),to=ref(state.nodes[to]),
            count=token.payload.count,expected_source=copy(token.payload),expected_target_empty=true,temporary=temporary==true}
        current[from]=nil; current[to]=id; positions[id]=to
    end
    while pending>0 do
        local progress=false
        for _,to in ipairs(state.node_order) do
            local token=wanted[to]
            if current[to]==nil and token and positions[token]~=to then
                move(token,to,false); pending=pending-1; progress=true
            end
        end
        if not progress then
            local scratch
            for _,key in ipairs(state.node_order) do if current[key]==nil then scratch=key; break end end
            check(scratch~=nil,"no_empty_slot","No empty temporary slot available")
            local token
            for _,id in ipairs(state.token_order) do if positions[id]~=desired[id] then token=id; break end end
            check(token~=nil,"internal_error","No unresolved cycle token")
            move(token,scratch,true)
        end
        check(#plan.operations<=2*#state.token_order+1,"internal_error","Move planning failed to converge")
    end
    local target_by_chest={}
    for _,id in ipairs(state.token_order) do
        local target=state.nodes[desired[id]]; target_by_chest[target.container_id]=target_by_chest[target.container_id] or {}
        local rows=target_by_chest[target.container_id]; rows[#rows+1]={index=target.index,token=id,category=state.tokens[id].category,item=state.tokens[id].payload.item,count=state.tokens[id].payload.count}
    end
    for _,chest in ipairs(state.chests) do
        local rows=target_by_chest[chest.id] or {}; table.sort(rows,function(a,b) return a.index<b.index end)
        local cats={}; for _,row in ipairs(rows) do cats[row.category]=(cats[row.category] or 0)+1 end
        local catrows={}; for key,count in pairs(cats) do catrows[#catrows+1]={id=key,label=CATEGORY[key].label,stacks=count,rank=CATEGORY[key].rank} end
        table.sort(catrows,function(a,b) return a.rank<b.rank end)
        local labels={}; for _,c in ipairs(catrows) do labels[#labels+1]=c.label end
        local mixed=#catrows>1
        plan.containers[#plan.containers+1]={id=chest.id,type=chest.type,map=copy(chest.map),world=copy(chest.world),
            capacity=chest.capacity,used=#rows,free=chest.capacity-#rows,categories=catrows,slots=rows,
            mixed=mixed,label=#labels==0 and "空箱预留" or table.concat(labels," / ")..(mixed and "（明确混放）" or "")}
        if mixed then plan.warnings[#plan.warnings+1]={code="mixed_overflow",container_id=chest.id,message="Planner allocated multiple categories to this box; review listed categories"} end
    end
    plan.operation_count=#plan.operations
    plan.inventory_signature=inventory(state)
    plan.warnings[#plan.warnings+1]={code="execution_preconditions",message="Executor must recheck same-base allowlist, source identity/count and empty target before every full-stack move; native permissions and filters still apply"}
    plan.warnings[#plan.warnings+1]={code="volatile_corruption",message="Corruption values are recorded for review; live decay can advance naturally between planning and execution"}
    return plan
end

local function guarded(fn,...)
    local ok,result=pcall(fn,...)
    if ok then return result end
    if type(result)=="table" and result.code then return nil,result end
    return nil,{code="planner_error",message=tostring(result)}
end

function M.plan(snapshot,targets,opts)
    return guarded(function()
        local state=normalize(snapshot,targets,opts)
        return make_plan(state,allocate(state,(opts or {}).policy or "category"),(opts or {}).policy or "category")
    end)
end

function M.plan_assignment(snapshot,targets,opts,assignments)
    return guarded(function()
        local state=normalize(snapshot,targets,opts)
        check(type(assignments)=="table" and #assignments==#state.token_order,"invalid_assignment","Supply one assignment per occupied stack")
        local desired={}
        for _,a in ipairs(assignments) do
            check(type(a.from)=="table" and type(a.to)=="table" and uuid(a.from.container_id) and uuid(a.to.container_id)
                and integer(a.from.index,0,999) and integer(a.to.index,0,999),"invalid_assignment","Invalid slot reference")
            local from,to=location(a.from.container_id,a.from.index),location(a.to.container_id,a.to.index)
            check(state.tokens[from]~=nil and state.nodes[to]~=nil and not desired[from],"invalid_assignment","Source or target is outside the selected base, empty or duplicated")
            desired[from]=to
        end
        return make_plan(state,desired,"explicit")
    end)
end

function M.simulate(snapshot,targets,opts,plan)
    return guarded(function()
        local state=normalize(snapshot,targets,opts)
        check(type(plan)=="table" and plan.base_id==state.base_id and #plan.stacks==#state.token_order,"invalid_plan","Plan scope differs from snapshot")
        check(plan.inventory_signature==inventory(state),"conflict","Inventory changed since planning")
        local original_tokens={}
        for _,stack in ipairs(plan.stacks) do
            check(state.tokens[stack.token] and not original_tokens[stack.token]
                and canonical(stack.content)==canonical(state.tokens[stack.token].payload),"conflict","A stack changed at its original location")
            original_tokens[stack.token]=true
        end
        check(#plan.assignments==#state.token_order,"invalid_plan","Incomplete final assignment")
        local current={}; for k,v in pairs(state.current) do current[k]=v end
        for _,operation in ipairs(plan.operations) do
            local from,to=location(operation.from.container_id,operation.from.index),location(operation.to.container_id,operation.to.index)
            check(state.nodes[from] and state.nodes[to],"invalid_plan","Operation leaves selected ordinary containers")
            local token=current[from]
            check(token==operation.token and state.tokens[token]~=nil,"conflict","Source stack identity changed")
            check(current[to]==nil and operation.expected_target_empty==true,"conflict","Target is occupied")
            check(operation.count==state.tokens[token].payload.count and canonical(operation.expected_source)==canonical(state.tokens[token].payload),
                "conflict","Source contents changed or operation is not a full-stack move")
            current[from]=nil; current[to]=token
        end
        local destinations,assigned_tokens={},{}
        for _,a in ipairs(plan.assignments) do
            local to=location(a.to.container_id,a.to.index)
            check(not destinations[to] and not assigned_tokens[a.token] and current[to]==a.token,"invalid_plan","Final target assignment was not reached")
            destinations[to]=a.token; assigned_tokens[a.token]=true
        end
        local seen,count={},0
        for _,token in pairs(current) do check(not seen[token],"conservation_failed","Duplicated stack token"); seen[token]=true; count=count+1 end
        check(count==#state.token_order,"conservation_failed","A stack was lost")
        return {ok=true,stack_count=count,operation_count=#plan.operations,inventory_signature=inventory(state),positions=current}
    end)
end

M.categories=copy(CATEGORIES)
M.canonical=canonical
return M
