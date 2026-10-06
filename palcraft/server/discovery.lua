-- Read-only runtime discovery for Palworld 1.0.5. Candidate pending lab probe.
-- Enumerates EXISTING concrete chest models, resolves each through the unique
-- manager before model-dependent getters, then rechecks Readers.ownership.
-- Coordinates are optional metadata and intentionally omitted: a concrete UObject
-- can be IsValid while its model is unregistered; GetTransform asserts natively.
local R=require('readers')
local J=require('json')
local M={candidate_unvalidated=true}
local ZERO='00000000-0000-0000-0000-000000000000'
local function live(o)return o~=nil and o:IsValid() and not o:GetFullName():find('Default__',1,true)end
local function same(a,b)return live(a)and live(b)and a:GetFullName()==b:GetFullName()end
local function num(v)assert(type(v)=='number' and v==v and v~=math.huge and v~=-math.huge,'nonfinite number');return v end
local function text(v)if type(v)=='string'then return v end;assert(v~=nil,'text unavailable');return v:ToString()end
local function cid(v)assert(type(v)=='table','container ID must be materialized struct');return R.guid_to_string(v.ID)end
local function reject(out,name,reason)
    out.excluded[#out.excluded+1]={object=name,reason=reason}
end

function M.discover(options)
    options=options or {}
    if options.group_id then R.guid_from_string(options.group_id) end
    local stamp=os.date('!%Y-%m-%dT%H:%M:%SZ')
    local targets={snapshot_sha256='runtime-'..stamp,snapshot_sha256_is_file_hash=false,
        source_kind='runtime_discovery',captured_utc=stamp,chests=J.array({})}
    local out={candidate_unvalidated=true,source='runtime_read_only',targets=targets,
        excluded=J.array({}),errors=J.array({}),warnings=J.array({}),enumerated=0,
        force_concrete_requested=false,coverage='existing PalMapObjectItemChestModel instances; optional guild filter',
        position_coverage='omitted; no concrete GetTransform call',
        registration_guard='unique manager -> FindModel -> GetConcreteModel(false) identity',
        group_filter=options.group_id,verified_live=false}
    local managers={}
    for _,manager in ipairs(FindAllOf('PalMapObjectManager')or{})do
        if live(manager)then managers[#managers+1]=manager end
    end
    if #managers~=1 then
        out.errors[#out.errors+1]={stage='manager',error='expected exactly one live map-object manager'}
        out.discovered_count=0;out.ok=false;return out
    end
    local manager=managers[1]
    local seen_container,seen_model={},{}
    for _,concrete in ipairs(FindAllOf('PalMapObjectItemChestModel') or {})do
        if live(concrete) then
            local name=concrete:GetFullName();out.enumerated=out.enumerated+1
            local ok,err=pcall(function()
                -- GetModelInstanceId copies the concrete's own GUID; it does not
                -- look up a model (1.0.5 thunk RVA 0x28632F0). It is the only
                -- native candidate getter allowed before registration is proved.
                local modelguid=concrete:GetModelInstanceId()
                local modelid=R.guid_to_string(modelguid)
                if modelid==ZERO then reject(out,name,'zero_model_id');return end
                local registered=manager:FindModel(modelguid)
                if not live(registered)then reject(out,name,'unregistered_model');return end
                local current=registered:GetConcreteModel(false)
                if not same(current,concrete)then reject(out,name,'stale_concrete_binding');return end
                assert(R.guid_to_string(current:GetModelInstanceId())==modelid,'registered concrete ID mismatch')
                assert(not seen_model[modelid],'duplicate model binding')
                local kind=text(concrete:TryGetMapObjectId())
                if kind~='ItemChest' and kind~='ItemChest_02' then reject(out,name,'type:'..tostring(kind));return end
                local module=concrete:GetItemContainerModule();assert(live(module),'item-container module unavailable')
                local container=module:GetContainer();assert(live(container),'linked container unavailable')
                local id=cid(module:GetContainerId());assert(cid(container:GetId())==id,'module/container ID mismatch')
                local escrow=rawget(_G,'PalCraftEscrowExclusions')
                if escrow and escrow.is_reserved(id,modelid)then reject(out,name,'exchange_escrow_reserved');return end
                local guild=container.bIsGuildChestContainer
                assert(type(guild)=='boolean','guild-container flag unavailable')
                if guild then reject(out,name,'shared_guild_container');return end
                local baseid=R.guid_to_string(concrete:GetBaseCampIdBelongTo())
                if baseid==ZERO then reject(out,name,'outside_base');return end
                local base=concrete:GetBaseCampModelBelongTo();assert(live(base),'base model unavailable')
                assert(R.guid_to_string(base:GetId())==baseid,'base identity mismatch')
                if not base:IsAvailable()then reject(out,name,'base_unavailable');return end
                local groupid=R.guid_to_string(base:GetGroupIdBelongTo())
                assert(groupid~=ZERO,'owning base has zero guild')
                if options.group_id and groupid~=options.group_id then reject(out,name,'outside_guild_filter');return end
                assert(modelid~=ZERO and id~=ZERO,'zero model/container ID')
                assert(not seen_container[id],'duplicate container binding')
                assert(not seen_model[modelid],'duplicate model binding')
                local cap=num(container:Num());assert(cap%1==0 and cap>0 and cap<=1000,'invalid capacity')
                local t={container_id=id,guid=R.guid_from_string(id),instance_id=modelid,
                    instance_guid=R.guid_from_string(modelid),base_id=baseid,group_id=groupid,
                    type=kind,expected_capacity=cap,discovered_live=true}
                seen_container[id]=true;seen_model[modelid]=true
                targets.chests[#targets.chests+1]=t
            end)
            if not ok then out.errors[#out.errors+1]={object=name,error=tostring(err)}end
        end
    end
    table.sort(targets.chests,function(a,b)if a.base_id~=b.base_id then return a.base_id<b.base_id end;return a.container_id<b.container_id end)
    out.discovered_count=#targets.chests
    if #targets.chests>0 and #out.errors==0 then
        local ok,v=pcall(R.ownership,targets,{require_snapshot_ownership=true})
        if ok then
            J.array(v.chests);J.array(v.errors)
            for _,row in ipairs(v.chests)do J.array(row.slots)end
            out.verification=v
            out.verified_live=v.ok==true and v.verified_live==true
            if not out.verified_live then out.errors[#out.errors+1]={stage='identity_recheck',error='discovered target failed strict native ownership recheck'}end
        else out.errors[#out.errors+1]={stage='identity_recheck',error=tostring(v)}end
    end
    out.ok=#out.errors==0
    -- No targets is a successful empty discovery, not a verified operation target.
    return out
end

-- Pure comparison of stable identities, deliberately ignoring snapshot timestamps
-- and positions. Extra discovered chests are reported, never hidden or discarded.
function M.compare_known(discovered,known)
    assert(type(discovered)=='table' and type(discovered.chests)=='table','discovered targets required')
    assert(type(known)=='table' and type(known.chests)=='table','known targets required')
    local result={matched=0,missing=J.array({}),extra=J.array({}),mismatches=J.array({})}
    local byid={};local knownids={}
    for _,t in ipairs(discovered.chests)do assert(not byid[t.container_id],'duplicate discovered ID');byid[t.container_id]=t end
    for _,t in ipairs(known.chests)do
        assert(not knownids[t.container_id],'duplicate known ID');knownids[t.container_id]=true
        local found=byid[t.container_id]
        if not found then result.missing[#result.missing+1]=t.container_id
        else
            local fields=J.array({})
            for _,field in ipairs({'instance_id','base_id','group_id','type','expected_capacity'})do
                if found[field]~=t[field]then fields[#fields+1]={field=field,known=t[field],live=found[field]}end
            end
            if #fields==0 then result.matched=result.matched+1
            else result.mismatches[#result.mismatches+1]={container_id=t.container_id,fields=fields}end
        end
    end
    for _,t in ipairs(discovered.chests)do if not knownids[t.container_id]then result.extra[#result.extra+1]=t.container_id end end
    result.all_known_match=#result.missing==0 and #result.mismatches==0
    result.exact_match=result.all_known_match and #result.extra==0
    return result
end
return M
