-- Pure phase-one stack merge planner. No UE calls, filesystem access or mutation.
-- Only complete identical FPalItemId values can aggregate. Dynamic items never
-- merge. Native food semantics retain the destination timer; partial source keeps
-- its timer. Feed projected_snapshot to organize.lua for phase-two classification.
local M={version='0.1.0',native_executor_included=false}
local ZERO='00000000-0000-0000-0000-000000000000'
local function fail(code,message)error({code=code,message=message},0)end
local function check(value,code,message)if not value then fail(code,message)end end
local function integer(n,min,max)return type(n)=='number'and n==n and n%1==0 and n>=min and n<=max end
local function uuid(s)return type(s)=='string'and s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil end
local function clone(v,seen)
    if type(v)~='table'then
        check(v==nil or type(v)=='string'or type(v)=='boolean'or (type(v)=='number'and v==v and v~=math.huge and v~=-math.huge),'invalid_snapshot','Non-primitive snapshot value')
        return v
    end
    seen=seen or {};check(not seen[v],'invalid_snapshot','Cyclic snapshot');seen[v]=true
    local out={} for k,x in pairs(v)do out[k]=clone(x,seen)end seen[v]=nil;return out
end
local function canonical(v)
    if type(v)=='table'then
        local keys={};for k in pairs(v)do keys[#keys+1]=k end
        table.sort(keys,function(a,b)if type(a)~=type(b)then return type(a)<type(b)end return tostring(a)<tostring(b)end)
        local rows={'{'};for _,k in ipairs(keys)do rows[#rows+1]=canonical(k)..'='..canonical(v[k])..';'end
        rows[#rows+1]='}';return table.concat(rows)
    elseif type(v)=='string'then return 's'..#v..':'..v
    elseif type(v)=='number'then return 'n'..string.format('%.17g',v)
    elseif type(v)=='boolean'then return v and 'true'or'false'
    elseif v==nil then return 'nil' end
    fail('invalid_snapshot','Unsupported payload type')
end
local function key(slot)return slot.container_id:lower()..':'..string.format('%04d',slot.index)end
local function ref(slot)return{container_id=slot.container_id:lower(),index=slot.index}end
local function identity(slot)return{item=slot.item,dynamicGuid=slot.dynamicGuid:lower(),dynamicWorldGuid=slot.dynamicWorldGuid:lower()}end
local function content(slot)
    local out={} for k,v in pairs(slot)do
        if k~='index'and k~='slot_id_index'and k~='container_id'then out[k]=clone(v)end
    end return out
end
local function compatibility(slot)
    local out=content(slot)
    out.count=nil;out.corruption=nil;out.corruptionKind=nil;out.is_max_stack=nil
    return canonical(out)
end
local function empty(slot)
    local id,index=slot.container_id,slot.index
    for k in pairs(slot)do slot[k]=nil end
    slot.container_id=id;slot.index=index;slot.slot_id_index=index;slot.item='None';slot.count=0;slot.empty=true
    slot.dynamicGuid=ZERO;slot.dynamicWorldGuid=ZERO;slot.corruption=0;slot.corruptionKind='GetCorruptionProgressRate'
end
local function quantities(slots)
    local sum={}
    for _,s in ipairs(slots)do if not s.empty then
        local id=canonical(identity(s));sum[id]=(sum[id]or 0)+s.count
        check(sum[id]<=9007199254740991,'quantity_overflow','Identity quantity cannot be represented exactly')
    end end
    return canonical(sum),sum
end
local function normalize(snapshot,targets,opts)
    check(type(opts)=='table'and uuid(opts.base_id),'invalid_base','One canonical base UUID is required')
    check(type(snapshot)=='table'and snapshot.ok==true and snapshot.includes_items==true and type(snapshot.chests)=='table','invalid_snapshot','Complete item snapshot required')
    check(type(targets)=='table'and type(targets.chests)=='table','invalid_targets','Ordinary chest allowlist required')
    check(opts.include_shared~=true,'unsupported','Shared storage merging is unsupported')
    local base=opts.base_id:lower();local allow,selected={},{}
    for _,t in ipairs(targets.chests)do
        check(uuid(t.container_id)and uuid(t.base_id)and uuid(t.group_id),'invalid_targets','Invalid target identifiers')
        local id=t.container_id:lower();check(not allow[id],'invalid_targets','Duplicate target');allow[id]=t
        if t.base_id:lower()==base then selected[id]=true end
    end
    if opts.container_ids~=nil then
        check(type(opts.container_ids)=='table'and #opts.container_ids>0,'invalid_targets','Selected container list must be nonempty')
        selected={}
        for _,id in ipairs(opts.container_ids)do
            check(uuid(id),'invalid_targets','Invalid selected UUID');id=id:lower()
            check(not selected[id]and allow[id]and allow[id].base_id:lower()==base,'cross_base','Selected container is duplicated or outside requested base')
            selected[id]=true
        end
    end
    check(next(selected)~=nil,'invalid_base','No allowlisted containers at requested base')
    local projected=clone(snapshot);local found,slots,chests={}, {}, {};local group;local verified=true
    for _,c in ipairs(projected.chests)do
        check(uuid(c.id),'invalid_snapshot','Invalid snapshot container UUID')
        local id=c.id:lower()
        if selected[id]then
            check(not found[id],'invalid_snapshot','Duplicate live container');found[id]=true
            local t=allow[id]
            check(t.type=='ItemChest'or t.type=='ItemChest_02','unsupported_container','Only ordinary ItemChest/ItemChest_02 are allowed')
            check(c.ok==true and uuid(c.actual_id)and c.actual_id:lower()==id,'invalid_snapshot','Selected container is unreadable')
            check(c.base_id_from_snapshot==t.base_id and c.group_id_from_snapshot==t.group_id,'cross_base','Snapshot target membership differs')
            check(not group or group==t.group_id:lower(),'cross_guild','Selected boxes span guilds');group=t.group_id:lower()
            check(integer(c.capacity,1,1000)and c.capacity==t.expected_capacity and type(c.slots)=='table'and #c.slots==c.capacity,'capacity_changed','Full unchanged slot capacity required')
            local has_live=snapshot.verifies_ownership==true or c.ownership_verified_live==true or c.base_id_live~=nil
            if opts.require_live_ownership~=false or has_live then
                check(c.ownership_verified_live==true and c.eligible_for_snapshot_plan==true,'ownership_unverified','Current ordinary-container ownership must match allowlist')
                check(uuid(c.base_id_live)and c.base_id_live:lower()==base and uuid(c.group_id_live)and c.group_id_live:lower()==group,'cross_base','Live base/guild differs')
                check(c.type_live==t.type and c.is_guild_chest_live==false and uuid(c.container_id_from_module_live)and c.container_id_from_module_live:lower()==id,'ownership_unverified','Current type/module binding differs')
            else verified=false end
            local indices={}
            for _,s in ipairs(c.slots)do
                check(integer(s.index,0,c.capacity-1)and not indices[s.index]and s.slot_id_index==s.index and uuid(s.container_id)and s.container_id:lower()==id,'invalid_snapshot','Invalid live slot identity')
                indices[s.index]=true
                check(type(s.item)=='string'and uuid(s.dynamicGuid)and uuid(s.dynamicWorldGuid)and integer(s.count,0,2147483647)and type(s.empty)=='boolean','invalid_snapshot','Invalid complete item identity or quantity')
                check((s.empty and s.count==0 and (s.item=='None'or s.item==''))or(not s.empty and s.count>0 and s.item~='None'and s.item~=''),'invalid_snapshot','Inconsistent empty slot')
                if not s.empty then
                    check(integer(s.max_stack,1,2147483647),'missing_max_stack','Every occupied slot needs its current native max_stack')
                    check(s.count<=s.max_stack,'stack_overflow','Existing stack exceeds its native limit; manual review required')
                end
                slots[#slots+1]=s
            end
            chests[#chests+1]=c
        end
    end
    for id in pairs(selected)do check(found[id],'incomplete_snapshot','Selected container missing from snapshot')end
    table.sort(slots,function(a,b)return key(a)<key(b)end)
    return projected,slots,chests,group,verified
end
function M.plan(snapshot,targets,opts)
    local ok,result=pcall(function()
        local projected,slots,chests,group,verified=normalize(snapshot,targets,opts or {})
        local before,total_before=quantities(slots)
        local groups,limits={},{};local skipped_dynamic,occupied_before=0,0
        for _,s in ipairs(slots)do if not s.empty then
            occupied_before=occupied_before+1
            check(not limits[s.item]or limits[s.item]==s.max_stack,'inconsistent_max_stack','Same static item has different native stack limits')
            limits[s.item]=s.max_stack
            if s.dynamicGuid:lower()~=ZERO or s.dynamicWorldGuid:lower()~=ZERO then skipped_dynamic=skipped_dynamic+1
            elseif s.max_stack>1 then
                local id=canonical(identity(s))..compatibility(s)
                if not groups[id]then groups[id]={}end groups[id][#groups[id]+1]=s
            end
        end end
        local groupkeys={};for id in pairs(groups)do groupkeys[#groupkeys+1]=id end table.sort(groupkeys)
        local operations={}
        for _,id in ipairs(groupkeys)do
            local rows=groups[id]
            table.sort(rows,function(a,b)if a.count~=b.count then return a.count>b.count end return key(a)<key(b)end)
            local target_index,source_index=1,#rows
            while target_index<source_index do
                local target,source=rows[target_index],rows[source_index]
                if target.count==target.max_stack then target_index=target_index+1
                elseif source.empty then source_index=source_index-1
                else
                    check(canonical(identity(source))==canonical(identity(target)),'identity_mismatch','Merge identities differ')
                    local amount=math.min(source.count,target.max_stack-target.count)
                    check(amount>0,'internal_error','No legal merge amount')
                    local operation={kind='merge',sequence=#operations+1,from=ref(source),to=ref(target),count=amount,
                        max_stack=target.max_stack,expected_source=content(source),expected_target=content(target),
                        expected_target_empty=false,food_timer_policy='retain_target_timer'}
                    source.count=source.count-amount;target.count=target.count+amount
                    if source.is_max_stack~=nil then source.is_max_stack=source.count==source.max_stack end
                    if target.is_max_stack~=nil then target.is_max_stack=target.count==target.max_stack end
                    if source.count==0 then empty(source);source_index=source_index-1 end
                    operation.expected_after={source=content(source),target=content(target)}
                    operations[#operations+1]=operation
                    if target.count==target.max_stack then target_index=target_index+1 end
                end
            end
        end
        local after,total_after=quantities(slots)
        check(before==after,'conservation_failed','Static/dynamic identity quantities changed')
        local occupied_after=0
        for _,c in ipairs(chests)do
            c.occupied=0;for _,s in ipairs(c.slots)do if not s.empty then c.occupied=c.occupied+1;occupied_after=occupied_after+1 end end
        end
        return{version=M.version,base_id=opts.base_id:lower(),group_id=group,ownership_verified_live=verified,
            scope='fixed_snapshot_allowlist',cross_base=false,operations=operations,operation_count=#operations,
            projected_snapshot=projected,quantity_signature=before,identity_quantities_before=total_before,
            identity_quantities_after=total_after,occupied_before=occupied_before,occupied_after=occupied_after,
            freed_slots=occupied_before-occupied_after,dynamic_stacks_skipped=skipped_dynamic,max_stack_by_item=limits,
            warnings={{code='native_food_timer',message='Food merges retain the target stack timer; a partial source keeps its own timer. Natural decay can advance during execution.'},
                {code='normal_native_merge',message='Apply must use native partial-count moves, recheck both full item identities and native max-stack, then independently verify readback. Dynamic items are never merged.'}}}
    end)
    if ok then return result end
    if type(result)=='table'and result.code then return nil,result end
    return nil,{code='planner_error',message=tostring(result)}
end
M.canonical=canonical
return M
