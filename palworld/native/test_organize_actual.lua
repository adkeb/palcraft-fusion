-- Replays captured BridgeLab read-only snapshots. Does not connect to a server.
local directory='work/palworld-live/bridge/PalLiveBridge/Scripts/'
local M=dofile(directory..'organize.lua')
local Json=dofile(directory..'json.lua')
local Targets=dofile(directory..'targets.lua')
local function read(path)
    local f=assert(io.open(path,'rb'));local data=f:read('*a');f:close()
    return Json.decode(data,{max_bytes=8388608,max_depth=64})
end
local reports={}
for _,name in ipairs({'oldbase','newbase'}) do
    local snapshot=read('work/palworld-live/lab/rpc-'..name..'-after-restart.json')
    local opts={base_id=snapshot.base_id,policy='category'}
    local t0=os.clock()
    local plan,err=M.plan(snapshot,Targets,opts)
    assert(plan,err and (err.code..': '..err.message))
    local result,simerr=M.simulate(snapshot,Targets,opts,plan)
    assert(result,simerr and (simerr.code..': '..simerr.message))
    assert(result.stack_count==plan.stack_count and result.inventory_signature==plan.inventory_signature)
    local mixed,pure,categories,unknown=0,0,{},{}
    for _,chest in ipairs(plan.containers) do
        if chest.mixed then mixed=mixed+1 elseif chest.used>0 then pure=pure+1 end
        for _,c in ipairs(chest.categories) do categories[c.id]=(categories[c.id] or 0)+c.stacks end
    end
    for _,stack in ipairs(plan.stacks) do if stack.category=='unclassified' then unknown[stack.content.item]=(unknown[stack.content.item] or 0)+1 end end
    local report={name=name,base_id=plan.base_id,stack_count=plan.stack_count,capacity=plan.capacity,
        empty_slots=plan.empty_slots,changed_stacks=plan.changed_stacks,operation_count=plan.operation_count,
        pure_boxes=pure,mixed_boxes=mixed,categories=categories,unclassified=unknown,elapsed_ms=math.floor((os.clock()-t0)*1000)}
    reports[#reports+1]=report
    print('PASS actual '..name..' '..Json.encode(report))
end
local f=assert(io.open('work/palworld-live/native-research/organize-actual-results.json','wb'))
f:write(Json.encode(Json.array(reports)));f:close()
