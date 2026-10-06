-- Read-only, Lab-only normal-rebuild material evidence. No hooks/RPCs/file I/O.
-- Caller must resolve context and call read/RPC/read in the SAME game-thread callback.
-- A snapshot is coverage of 13 specified ordinary chests + CommonContainer only.
-- CountItemNum64 congruence is required for Wood/Stone; other inventory containers
-- are deliberately not inferred. Native work/other actors can still change later.
local M = {}
local ZERO = '00000000-0000-0000-0000-000000000000'
local RECIPE = { Wood=15, Stone=5 }
local function int(v,what,max)
    assert(type(v)=='number' and v==v and v>=0 and v%1==0 and v<=(max or 9007199254740991), 'invalid '..what)
    return v
end
local function live(o)
    return o and o:IsValid() and not o:GetFullName():find('Default__',1,true)
end
local function name(v)
    if type(v)=='string' then return v end
    assert(v~=nil,'missing FName'); local s=v:ToString(); assert(type(s)=='string','invalid FName'); return s
end
local function property_guid(R,g)
    -- Reflected struct properties are UScriptStruct wrappers, unlike return values.
    assert(g~=nil,'missing GUID property')
    return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})
end
local function slot_copy(s,id,index)
    assert(type(s)=='table' and s.index==index and s.slot_id_index==index and s.container_id==id,'slot identity mismatch')
    local n=int(s.count,'slot count'); assert(type(s.empty)=='boolean' and s.empty==(n==0),'empty/count mismatch')
    assert(type(s.item)=='string' and type(s.dynamicGuid)=='string' and type(s.dynamicWorldGuid)=='string','incomplete slot identity')
    if n>0 then assert(s.item~='' and s.item~='None','occupied None slot') end
    return {index=index,container_id=id,item=s.item,count=n,empty=s.empty,
        dynamicGuid=s.dynamicGuid,dynamicWorldGuid=s.dynamicWorldGuid}
end
local function totals(containers)
    local out={Wood=0,Stone=0}
    for _,c in ipairs(containers) do for _,s in ipairs(c.slots) do
        if RECIPE[s.item] then out[s.item]=int(out[s.item]+s.count,'material total') end
    end end
    return out
end
function M.read(d)
    assert(type(d)=='table','dependencies required')
    local R,J,T=d.readers,d.json,d.targets
    assert(R and J and T and type(T.chests)=='table' and #T.chests==13,'exactly 13 specified ordinary chests required')
    assert(live(d.inventory) and live(d.item_manager),'live inventory and manager required')
    assert(type(d.player_uid)=='string' and R.guid_to_string(R.guid_from_string(d.player_uid))==d.player_uid and d.player_uid~=ZERO,'canonical player UID required')
    assert(property_guid(R,d.inventory.OwnerPlayerUId)==d.player_uid,'inventory owner mismatch')
    if d.state then
        assert(live(d.state),'player state unavailable')
        local inv=d.state:GetInventoryData()
        assert(live(inv) and inv:GetFullName()==d.inventory:GetFullName(),'state/inventory mismatch')
    end
    local base,guild=T.chests[1].base_id,T.chests[1].group_id
    assert(type(base)=='string' and base~=ZERO and type(guild)=='string' and guild~=ZERO,'base/guild required')
    local wanted={}
    for _,t in ipairs(T.chests) do
        assert(t.base_id==base and t.group_id==guild,'cross-base/guild snapshot forbidden')
        assert(not wanted[t.container_id],'duplicate target container')
        wanted[t.container_id]=t
    end
    local report=R.chests(T,{include_items=true,verify_ownership=true,require_snapshot_ownership=true,
        manager_name=d.item_manager:GetFullName()})
    assert(report.ok==true and report.verified_live==true and #report.chests==13,'ordinary chest ownership/read failed')
    local out={ok=true,kind='normal_rebuild_materials_v1',player_uid=d.player_uid,base_id=base,guild_id=guild,
        coverage={ordinary_chests=13,player_container='CommonContainerId',other_player_containers_included=false,
            world_containers_enumerated=false,wood_stone_inventory_count_congruent=true},
        snapshot_sha256=T.snapshot_sha256,containers=J.array({})}
    local seen={}
    for _,c in ipairs(report.chests) do
        local t=wanted[c.id]
        assert(t and not seen[c.id],'unexpected/duplicate chest');seen[c.id]=true
        assert(c.ok==true and c.verified_live==true and c.eligible_for_snapshot_plan==true and c.actual_id==c.id,'chest verification failed')
        assert(c.base_id_live==base and c.group_id_live==guild,'chest owner changed')
        local n=int(c.capacity,'chest capacity',1000)
        assert(n==t.expected_capacity and #c.slots==n,'chest capacity/slot count mismatch')
        local row={id=c.id,kind='ordinary_chest',capacity=n,slots=J.array({})}
        for i=0,n-1 do row.slots[#row.slots+1]=slot_copy(c.slots[i+1],c.id,i) end
        out.containers[#out.containers+1]=row
    end
    local common=d.inventory.MyInventoryInfo.CommonContainerId
    local id=property_guid(R,common.ID)
    assert(id~=ZERO and not seen[id],'invalid/aliased player common container')
    local c=d.item_manager:GetContainer({ID=R.guid_from_string(id)})
    assert(live(c) and R.guid_to_string(c:GetId().ID)==id,'common container manager identity mismatch')
    local n=int(c:Num(),'common capacity',1000)
    assert(n>0,'empty common capacity')
    local row={id=id,kind='player_common',capacity=n,slots=J.array({})}
    for i=0,n-1 do
        local s=c:Get(i);assert(live(s),'common slot unavailable')
        local sid=s:GetSlotId();local iid=s:GetItemId()
        assert(type(sid)=='table' and type(iid)=='table' and type(iid.DynamicId)=='table','nonmaterialized slot return')
        local data={index=i,slot_id_index=sid.SlotIndex,container_id=R.guid_to_string(sid.ContainerId.ID),
            item=name(iid.StaticId),count=s:GetStackCount(),empty=s:IsEmpty(),
            dynamicGuid=R.guid_to_string(iid.DynamicId.LocalIdInCreatedWorld),dynamicWorldGuid=R.guid_to_string(iid.DynamicId.CreatedWorldId)}
        row.slots[#row.slots+1]=slot_copy(data,id,i)
    end
    local carry=totals({row})
    local fname=d.fname or FName
    assert(type(fname)=='function','FName constructor required')
    for item in pairs(RECIPE) do
        local native=int(d.inventory:CountItemNum64(fname(item)),'inventory material count')
        assert(native==carry[item],'CommonContainer does not cover inventory '..item..' count')
    end
    out.common_container_id=id;out.carried=carry
    out.containers[#out.containers+1]=row
    table.sort(out.containers,function(a,b)return a.id<b.id end)
    out.totals=totals(out.containers)
    return out
end
local function identity(s)
    if s.count==0 then return '<empty>' end
    return s.item..'|'..s.dynamicGuid..'|'..s.dynamicWorldGuid
end
function M.diff(before,after)
    assert(before and after and before.ok==true and after.ok==true,'successful snapshots required')
    assert(before.kind=='normal_rebuild_materials_v1' and after.kind==before.kind,'snapshot type mismatch')
    for _,k in ipairs({'player_uid','base_id','guild_id','common_container_id','snapshot_sha256'}) do
        assert(before[k]==after[k],'snapshot context changed: '..k)
    end
    assert(#before.containers==#after.containers,'container coverage changed')
    local delta={Wood=after.totals.Wood-before.totals.Wood,Stone=after.totals.Stone-before.totals.Stone}
    local mt=getmetatable(before.containers)
    local changed,unrelated,illegal=setmetatable({},mt),setmetatable({},mt),setmetatable({},mt)
    for i,b in ipairs(before.containers) do
        local a=after.containers[i]
        assert(a.id==b.id and a.kind==b.kind and a.capacity==b.capacity and #a.slots==#b.slots,'container binding/capacity changed')
        for j,old in ipairs(b.slots) do
            local new=a.slots[j]
            assert(old.index==new.index and old.container_id==new.container_id,'slot coverage changed')
            if old.count~=new.count or identity(old)~=identity(new) then
                local change={container_id=b.id,kind=b.kind,index=old.index,before=old,after=new}
                changed[#changed+1]=change
                local material=RECIPE[old.item]~=nil or RECIPE[new.item]~=nil
                if not material then unrelated[#unrelated+1]=change
                else
                    local reduction=RECIPE[old.item]~=nil and old.count>new.count and old.count>0
                    local same_or_empty=new.count==0 or identity(old)==identity(new)
                    local nondynamic=old.dynamicGuid==ZERO and old.dynamicWorldGuid==ZERO
                    if not (reduction and same_or_empty and nondynamic) then illegal[#illegal+1]=change end
                end
            end
        end
    end
    return {exact_recipe_cost=delta.Wood==-15 and delta.Stone==-5 and #illegal==0 and #unrelated==0,
        recipe_totals_match=delta.Wood==-15 and delta.Stone==-5,material_changes_only_legal_decrements=#illegal==0,
        unrelated_slots_unchanged=#unrelated==0,concurrent_or_unexplained_changes=#illegal>0 or #unrelated>0,
        deltas=delta,changed_slots=changed,illegal_material_changes=illegal,unrelated_changes=unrelated,
        limitation='Evidence within fixed CommonContainer + 13 ordinary chests; no causal proof against concurrent actors.'}
end
return M
