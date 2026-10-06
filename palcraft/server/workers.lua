-- CANDIDATE: Palworld 1.0.5 worker readers; game-thread only, pending lab probe.
-- No property/memory writes, object creation, RPC, hooks, file I/O or assignments.
-- Uses only UObject GetOuter and reflected UFunction getters. Out parameters use
-- explicit tables, as required by UE4SS 2281fa31 LuaUObject.cpp:190-280.
local R = require('readers')
local json = require('json')
local M = { candidate_unvalidated=true }
local ZERO='00000000-0000-0000-0000-000000000000'
-- SDK e6632458 + 1.0.5 reflected EPalWorkSuitability, excluding None/Anyone/MAX.
local names={'EmitFlame','Watering','Seeding','GenerateElectricity','Handcraft',
    'Collection','Deforest','Mining','OilExtraction','ProductMedicine','Cool','Transport','MonsterFarm'}
local index={}; for i,n in ipairs(names) do index[n]=i end
local function num(v)
    assert(type(v)=='number' and v==v and v~=math.huge and v~=-math.huge,'nonfinite number')
    return v
end
local function bool(v) assert(type(v)=='boolean','expected bool'); return v end
local function txt(v)
    if type(v)=='string' then return v end
    assert(v~=nil,'missing text'); local s=v:ToString(); assert(type(s)=='string','expected text'); return s
end
local function valid(o) return o~=nil and o:IsValid() and not o:GetFullName():find('Default__',1,true) end
local function all(class)
    local a={}; for _,o in ipairs(FindAllOf(class) or {}) do if valid(o) then a[#a+1]=o end end
    return a
end
local function iid(t)
    assert(type(t)=='table','individual ID must be returned struct table')
    return {instance_id=R.guid_to_string(t.InstanceId),player_uid=R.guid_to_string(t.PlayerUId)}
end
local function sameid(a,b) return a.instance_id==b.instance_id and a.player_uid==b.player_uid end
local function warn(row,stage,e) row.warnings[#row.warnings+1]={stage=stage,error=tostring(e)} end
local function optional(row,stage,fn)
    local ok,e=pcall(fn); if not ok then warn(row,stage,e) end; return ok
end
local function read_worker(slot,base,options)
    local row={ok=false,warnings=json.array({}),suitabilities=json.array({}),task={known=false}}
    local ok,err=pcall(function()
        assert(valid(slot),'invalid slot')
        row.slot_index=num(slot:GetSlotIndex()); row.empty=bool(slot:IsEmpty())
        if row.empty then row.ok=true; return end
        local handle=slot:GetHandle(); assert(valid(handle),'worker handle unavailable')
        row.individual_id=iid(handle:GetIndividualID())
        assert(row.individual_id.instance_id~=ZERO,'worker has zero instance ID')
        local p=handle:TryGetIndividualParameter(); assert(valid(p),'worker parameter unavailable')
        assert(sameid(row.individual_id,iid(p:GetPalId())),'worker handle/parameter identity mismatch')
        row.base_id=R.guid_to_string(p:GetBaseCampId())
        row.group_id=R.guid_to_string(p:GetGroupId())
        row.membership={director_base_id=base.id,director_group_id=base.group_id,
            director_slot_present=true,parameter_base_id=row.base_id,parameter_group_id=row.group_id,
            parameter_base_available=row.base_id~=ZERO,
            base_matches=row.base_id==base.id,group_matches=row.group_id==base.group_id}
        row.ownership_verified_live=row.membership.base_matches and row.membership.group_matches
        if not row.ownership_verified_live then
            warn(row,'membership',row.base_id==ZERO and 'parameter base ID is zero; only director slot membership observed'
                or 'parameter base/group differs from director base/group')
        end
        row.character_id=txt(p:GetCharacterID()); row.level=num(p:GetLevel())
        row.dead=bool(p:IsDead()); row.sleeping=bool(p:IsSleeping())
        row.sanity=num(p:GetSanityValue()); row.sanity_max=num(p:GetMaxSanityValue())
        row.sanity_rate=num(p:GetSanityRate())
        row.full_stomach=num(p:GetFullStomach()); row.full_stomach_max=num(p:GetMaxFullStomach())
        row.full_stomach_rate=num(p:GetFullStomachRate()); row.hunger_type=num(p:GetHungerType())
        row.worker_sick_type=num(p:GetWorkerSick()); row.physical_health_type=num(p:GetPhysicalHealth())
        row.current_work_suitability=num(p:GetCurrentWorkSuitability())
        row.current_work_suitability_name=names[row.current_work_suitability]
        optional(row,'nickname',function()
            local out={}; p:GetNickname(out); row.nickname=txt(out.outName)
        end)
        if options.include_suitabilities~=false then
            for enum,name in ipairs(names) do
                local rank=num(p:GetWorkSuitabilityRankWithCharacterRank(enum))
                assert(rank%1==0 and rank>=0 and rank<=100,'invalid work suitability rank')
                if rank>0 then row.suitabilities[#row.suitabilities+1]={name=name,enum=enum,rank=rank} end
            end
        end
        local actor=handle:TryGetIndividualActor()
        row.actor_loaded=valid(actor) and true or false
        if row.actor_loaded then optional(row,'current_task',function()
            local cp=actor:GetCharacterParameterComponent(); assert(valid(cp),'character component unavailable')
            local t=row.task
            t.assigned=bool(cp:IsAssignedToAnyWork()); t.fixed=bool(cp:IsAssignedFixed())
            t.work_id=R.guid_to_string(cp:GetWorkId())
            if t.assigned then
                local a=cp:GetWorkAssign(); assert(valid(a),'assigned work object unavailable')
                assert(sameid(iid(a:GetAssignedIndividualId()),row.individual_id),'work assignment individual mismatch')
                t.working=bool(a:IsWorking()); t.workable=bool(a:IsWorkable())
                t.suitability_enum=num(a:GetWorkSuitability()); t.suitability_name=names[t.suitability_enum]
                t.state_enum=num(a:GetState()); t.working_state_enum=num(a:GetWorkingState())
                local work=a:GetWork(); assert(valid(work),'work model unavailable')
                assert(R.guid_to_string(work:GetWorkId())==t.work_id,'work model id mismatch')
                t.name=txt(work:GetWorkName()); t.fixed_only=bool(work:IsAssignableFixedOnly())
            end
            t.known=true
        end) end
        row.ok=true
    end)
    if not ok then row.error=tostring(err) end
    return row
end

function M.list(options)
    options=options or {}
    local out={candidate_unvalidated=true,source='runtime_read_only',bases=json.array({}),errors=json.array({}),
        coverage='WorkerDirector slots for loaded base models; no forced spawning or loading',
        native_assignment_called=false,worker_count=0}
    local base_by_object={}; local seen={}
    for _,b in ipairs(all('PalBaseCampModel')) do
        local ok,res=pcall(function()
            return {id=R.guid_to_string(b:GetId()),group_id=R.guid_to_string(b:GetGroupIdBelongTo()),
                available=bool(b:IsAvailable()),object=b:GetFullName(),workers=json.array({}),errors=json.array({}),ok=false}
        end)
        if ok then
            if not options.base_id or options.base_id==res.id then
                assert(not seen[res.id],'duplicate base GUID'); seen[res.id]=true
                out.bases[#out.bases+1]=res; base_by_object[res.object]=res
            end
        else out.errors[#out.errors+1]=tostring(res) end
    end
    if options.base_id and not seen[options.base_id] then out.errors[#out.errors+1]='requested base not loaded/found' end
    for _,d in ipairs(all('PalBaseCampWorkerDirector')) do
        local ok,err=pcall(function()
            local outer=d:GetOuter(); if not valid(outer) then return end
            local b=base_by_object[outer:GetFullName()]; if not b then return end
            assert(not b.director_object,'multiple worker directors for one base')
            b.director_object=d:GetFullName()
            local slots={}; d:GetCharacterHandleSlots(slots)
            assert(#slots<=100,'unexpected worker slot count')
            b.slot_count=#slots; b.worker_count=0; local ids={}
            -- UE4SS 2281fa31 array materialization uses Operation::GetParam for
            -- each UObject element (LuaUObject.cpp:825,427), yielding a
            -- RemoteUnrealParam, not a direct UObject. Unwrap immediately;
            -- never retain these wrappers outside this native-read scope.
            b.slot_element_format='RemoteUnrealParam:get()'
            for _,element in ipairs(slots) do
                local slot=element:get()
                local row=read_worker(slot,b,options)
                if not row.empty or options.include_empty then b.workers[#b.workers+1]=row end
                if row.ok and not row.empty then
                    local id=row.individual_id.instance_id
                    assert(not ids[id],'duplicate worker instance in base slots'); ids[id]=true
                    b.worker_count=b.worker_count+1; out.worker_count=out.worker_count+1
                elseif not row.ok then b.errors[#b.errors+1]=row.error end
            end
            b.ok=#b.errors==0
        end)
        if not ok then out.errors[#out.errors+1]=tostring(err) end
    end
    for _,b in ipairs(out.bases) do
        if not b.director_object then b.errors[#b.errors+1]='worker director not found without creating objects' end
        if not b.ok then out.errors[#out.errors+1]={base_id=b.id,errors=b.errors} end
        table.sort(b.workers,function(a,c) return (a.slot_index or 1e9)<(c.slot_index or 1e9) end)
    end
    table.sort(out.bases,function(a,b) return a.id<b.id end)
    out.ok=#out.errors==0
    return out
end

-- Pure preview only: explicit demand list, no inferred facility requirements, no WorkId
-- assignment token and no apply function. Each pal appears at most once. Health scores
-- only break rank ties; fixed, busy, sleeping, dead or unknown-task workers are retained.
function M.plan(snapshot,request)
    assert(type(snapshot)=='table' and snapshot.ok==true,'successful worker snapshot required')
    assert(type(request)=='table' and type(request.base_id)=='string','base_id required')
    assert(type(request.roles)=='table' and #request.roles>0 and #request.roles<=13,'1..13 roles required')
    local base; for _,b in ipairs(snapshot.bases or {}) do if b.id==request.base_id then base=b end end
    assert(base and base.ok and base.available,'requested base unavailable')
    local out={preview_only=true,apply_supported=false,candidate_unvalidated=true,base_id=base.id,
        group_id=base.group_id,assignments=json.array({}),unfilled=json.array({}),retained=json.array({}),
        strategy='greedy rarest-suitability demand first, rank then sanity/fullness; one worker per role slot',
        limitation='Role suggestions only. Facility capacity, pathing and disabled suitability options are not validated; no work assignment is authorized.'}
    local pool={}; for _,w in ipairs(base.workers) do
        if w.ok and not w.empty then
            local reason
            if not w.ownership_verified_live then reason='unverified_ownership'
            elseif w.dead then reason='dead'
            elseif w.sleeping then reason='sleeping'
            elseif not w.task.known then reason='current_task_unknown'
            elseif w.task.fixed then reason='fixed_assignment'
            elseif w.task.assigned then reason='already_assigned'
            elseif w.hunger_type~=0 then reason='hungry'
            elseif w.worker_sick_type~=0 then reason='sick'
            elseif w.sanity<=0 then reason='zero_sanity' end
            if reason then out.retained[#out.retained+1]={individual_id=w.individual_id,reason=reason}
            else pool[#pool+1]=w end
        end
    end
    local roles={}; local role_seen={}; local total=0
    for _,r in ipairs(request.roles) do
        assert(type(r)=='table' and index[r.suitability],'unknown suitability')
        assert(not role_seen[r.suitability],'duplicate role'); role_seen[r.suitability]=true
        local n=r.count or 1; local minimum=r.min_rank or 1
        assert(type(n)=='number' and n%1==0 and n>=1 and n<=50,'invalid role count')
        assert(type(minimum)=='number' and minimum%1==0 and minimum>=1 and minimum<=100,'invalid min_rank')
        total=total+n; assert(total<=50,'too many requested assignments')
        local candidates={}
        for _,w in ipairs(pool) do for _,s in ipairs(w.suitabilities) do
            if s.name==r.suitability and s.rank>=minimum then candidates[#candidates+1]={worker=w,rank=s.rank} end
        end end
        table.sort(candidates,function(a,b)
            if a.rank~=b.rank then return a.rank>b.rank end
            if a.worker.sanity_rate~=b.worker.sanity_rate then return a.worker.sanity_rate>b.worker.sanity_rate end
            if a.worker.full_stomach_rate~=b.worker.full_stomach_rate then return a.worker.full_stomach_rate>b.worker.full_stomach_rate end
            return a.worker.individual_id.instance_id<b.worker.individual_id.instance_id
        end)
        roles[#roles+1]={name=r.suitability,count=n,min_rank=minimum,candidates=candidates}
    end
    table.sort(roles,function(a,b) if #a.candidates~=#b.candidates then return #a.candidates<#b.candidates end; return a.name<b.name end)
    local used={}
    for _,r in ipairs(roles) do
        local filled=0
        for _,c in ipairs(r.candidates) do
            local w=c.worker; local id=w.individual_id.instance_id
            if filled<r.count and not used[id] then
                used[id]=true; filled=filled+1
                out.assignments[#out.assignments+1]={individual_id=w.individual_id,character_id=w.character_id,
                    suitability=r.name,suitability_enum=index[r.name],rank=c.rank,slot_index=w.slot_index}
            end
        end
        if filled<r.count then out.unfilled[#out.unfilled+1]={suitability=r.name,count=r.count-filled,min_rank=r.min_rank} end
    end
    return out
end

return M
