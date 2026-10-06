-- Experimental read-only preflight for a future native fixed-assignment test.
-- NOT wired into core. No apply method, RPC, AI action creation or native writes.
-- No-PC BaseCamp RPCs require a player guild and return early; see research JSON.
-- Existing active PalAIActionCompositeWorker:RegisterFixedAssignWork(WorkId)
-- reaches the same native work-manager request path without a player-context gate,
-- but has NOT been runtime validated. Do not call on CDO or create/spawn AI actors.
local R=require('readers');local J=require('json')
local M={candidate_unvalidated=true,apply_supported=false}
local ZERO='00000000-0000-0000-0000-000000000000'
local function valid(o)return o~=nil and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function all(class)local a={};for _,o in ipairs(FindAllOf(class)or{})do if valid(o)then a[#a+1]=o end end;return a end
local function txt(o)if type(o)=='string'then return o end;return o:ToString()end
local function same(a,b)return valid(a)and valid(b)and a:GetFullName()==b:GetFullName()end
local function palid(v)assert(type(v)=='table','returned PalInstanceID table required');return{instance_id=R.guid_to_string(v.InstanceId),player_uid=R.guid_to_string(v.PlayerUId)}end
local function identity_matches(a,b)return a.instance_id==b.instance_id and a.player_uid==b.player_uid end

local function work_bindings(options)
    local rows,objects,errors=J.array({}),{},J.array({})
    for _,module in ipairs(all('PalMapObjectWorkeeModule'))do
        local ok,err=pcall(function()
            local concrete=module:GetOuter();assert(valid(concrete),'workee module outer unavailable')
            local baseid=R.guid_to_string(concrete:GetBaseCampIdBelongTo())
            if baseid==ZERO or(options.base_id and options.base_id~=baseid)then return end
            local base=concrete:GetBaseCampModelBelongTo();assert(valid(base),'base model unavailable')
            assert(R.guid_to_string(base:GetId())==baseid and base:IsAvailable(),'base identity/state mismatch')
            local group=R.guid_to_string(base:GetGroupIdBelongTo())
            if options.group_id and group~=options.group_id then return end
            assert(same(concrete:GetWorkeeModule(),module),'module/concrete binding mismatch')
            local work=module:GetWork();if not valid(work)then return end
            local id=R.guid_to_string(work:GetWorkId());assert(id~=ZERO and not objects[id],'zero/duplicate work ID')
            local row={work_id=id,base_id=baseid,group_id=group,model_instance_id=R.guid_to_string(concrete:GetModelInstanceId()),
                map_object_type=txt(concrete:TryGetMapObjectId()),name=txt(work:GetWorkName()),
                fixed_only=work:IsAssignableFixedOnly(),assignable_fixed_type=work:GetAssignableFixedType(),
                assigned_individuals=J.array({}),source='workee module -> concrete/base and GetWork()',
                work_object=work:GetFullName()}
            local slots={};work:GetAssignedCharacters(slots)
            for _,element in ipairs(slots)do
                local slot=element:get()
                if valid(slot)and not slot:IsEmpty()then
                    local handle=slot:GetHandle();assert(valid(handle),'assigned handle unavailable')
                    row.assigned_individuals[#row.assigned_individuals+1]=palid(handle:GetIndividualID())
                end
            end
            rows[#rows+1]=row;objects[id]={work=work,base=base,row=row}
        end)
        if not ok then errors[#errors+1]={object=module:GetFullName(),error=tostring(err)}end
    end
    table.sort(rows,function(a,b)if a.base_id~=b.base_id then return a.base_id<b.base_id end;return a.work_id<b.work_id end)
    return rows,objects,errors
end

function M.works(options)
    options=options or {}
    local rows,_,errors=work_bindings(options)
    return{ok=#errors==0,candidate_unvalidated=true,works=rows,errors=errors,
        native_assignment_called=false,coverage='existing workee modules in available bases; no force loading'}
end

local function handle_in_base(base,identity)
    local found
    for _,director in ipairs(all('PalBaseCampWorkerDirector'))do
        if same(director:GetOuter(),base)then
            local slots={};director:GetCharacterHandleSlots(slots)
            for _,element in ipairs(slots)do
                local slot=element:get()
                if valid(slot)and not slot:IsEmpty()then
                    local h=slot:GetHandle()
                    if valid(h)and identity_matches(palid(h:GetIndividualID()),identity)then
                        assert(not found,'duplicate target worker slot');found=h
                    end
                end
            end
        end
    end
    assert(found,'worker is not in selected base director slots');return found
end
local function active_worker_action(cp)
    local found
    for _,action in ipairs(all('PalAIActionCompositeWorker'))do
        if same(action:GetCharacterParameter(),cp)then
            local owner=action:GetOwnerComponent()
            if valid(owner)and not action:IsPaused()then
                local current=owner:GetCompositeRoot();local in_chain=false
                for _=1,32 do
                    if not valid(current)then break end
                    if same(current,action)then in_chain=true;break end
                    current=current:GetChild()
                end
                if in_chain then assert(not found,'multiple active worker AI actions');found=action end
            end
        end
    end
    assert(found,'no existing active worker AI action for selected individual');return found
end

function M.prepare_fixed_assignment(request)
    assert(type(request)=='table','request required')
    for _,k in ipairs({'base_id','group_id','work_id'})do R.guid_from_string(request[k])end
    assert(type(request.individual_id)=='table','individual_id required')
    R.guid_from_string(request.individual_id.instance_id);R.guid_from_string(request.individual_id.player_uid)
    local out={candidate_unvalidated=true,preview_only=true,apply_supported=false,native_assignment_called=false,eligible_for_lab_experiment=false}
    local ok,err=pcall(function()
        local _,bindings,errors=work_bindings(request);assert(#errors==0,'work catalog has read errors')
        local binding=assert(bindings[request.work_id],'work not found at requested base/guild')
        local handle=handle_in_base(binding.base,request.individual_id)
        local p=handle:TryGetIndividualParameter();assert(valid(p),'worker parameter unavailable')
        assert(identity_matches(palid(p:GetPalId()),request.individual_id),'worker identity mismatch')
        assert(R.guid_to_string(p:GetBaseCampId())==request.base_id and R.guid_to_string(p:GetGroupId())==request.group_id,'worker parameter base/guild not verified')
        assert(not p:IsDead()and not p:IsSleeping()and p:GetHungerType()==0 and p:GetWorkerSick()==0,'worker is not healthy/awake')
        local actor=handle:TryGetIndividualActor();assert(valid(actor)and actor:HasAuthority(),'authoritative actor not loaded; no spawning permitted')
        local cp=actor:GetCharacterParameterComponent();assert(valid(cp),'character component unavailable')
        assert(same(cp:GetIndividualParameter(),p),'actor/parameter binding mismatch')
        assert(not cp:IsAssignedFixed()and not cp:IsAssignedToAnyWork(),'worker currently assigned; experiment will not displace it')
        local action=active_worker_action(cp)
        assert(binding.work:IsExistAssignableSlot(handle,true),'native fixed-assign suitability/capacity query rejected target')
        out.eligible_for_lab_experiment=true;out.work=binding.row
        out.individual_id=request.individual_id;out.action_object=action:GetFullName()
        out.future_native_call={receiver_class='PalAIActionCompositeWorker',method='RegisterFixedAssignWork',work_id=request.work_id}
        out.validation_needed='Single lab pal only; read back cp:GetWorkAssign/GetWorkId and fixed flag after a game-thread delay, then verify server save. Lua void return is not proof.'
        -- Future lab-only experiment, intentionally NOT executable in this module:
        -- action:RegisterFixedAssignWork(R.guid_from_string(request.work_id))
    end)
    out.ok=ok;if not ok then out.error=tostring(err)end
    return out
end
return M
