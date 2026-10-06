-- BridgeLab fast storage: cached bindings, slot-local checks, bounded frame batches.
-- Live full-stack storage transactions. All methods/ticks run on the game thread.
-- No automatic replay after reload/crash. Every native call has a durable intent.
local M = {}
function M.new(ctx)
    local J,R,T,O=ctx.json,ctx.readers,ctx.targets,ctx.organize
    local plans,active={},nil
    local pump
    local clock=ctx.clock or os.clock
    local max_moves=ctx.max_moves or 12
    local budget_seconds=(ctx.budget_ms or 4)/1000
    local function fail(code,message) error({code=code,message=message},0) end
    local function assertx(v,code,message) if not v then fail(code,message) end return v end
    local function path(kind,id) return ctx.root..kind.."/"..id..".json" end
    local function read(pathname)
        local f=io.open(pathname,"rb"); if not f then return nil end
        local raw=f:read(16777217); f:close()
        assertx(#raw<=16777216,"journal_error","Journal exceeds size limit")
        return J.decode(raw,{max_bytes=16777216,max_depth=64})
    end
    local function write(pathname,value)
        local previous=read(pathname)
        if previous then
            assertx(O.canonical(previous)==O.canonical(value),"journal_conflict","Immutable journal record already exists")
            return
        end
        local f=assert(io.open(pathname..".tmp","wb"))
        assert(f:write(J.encode(value,{max_bytes=16777216,max_depth=64}))); assert(f:close())
        assert(os.rename(pathname..".tmp",pathname))
    end
    local function identity(s)
        return {item=s.item,count=s.count,dynamicGuid=s.dynamicGuid,
            dynamicWorldGuid=s.dynamicWorldGuid,empty=s.empty}
    end
    local function key(cid,index) return cid..":"..index end
    local function indexed(report)
        assertx(report.ok==true,"backend_unavailable","A live chest could not be read")
        local out={}
        for _,c in ipairs(report.chests) do
            assertx(c.ownership_verified_live==true,"ownership_unverified","Live chest ownership has not been verified")
            assertx(c.eligible_for_snapshot_plan==true,"ownership_changed","Chest type, capacity, base or guild no longer matches its allowlist")
            for _,s in ipairs(c.slots) do out[key(c.id,s.index)]=s end
        end
        return out
    end
    local function flat(slots)
        local out={}; for k,s in pairs(slots) do out[k]=identity(s) end; return out
    end
    local function same(a,b) return O.canonical(a)==O.canonical(b) end
    local function selected(plan)
        local ids={};for _,c in ipairs(plan.containers) do ids[#ids+1]=c.id end
        local report=ctx.read_storage(plan.base_id,ids)
        local expected={};for _,c in ipairs(plan.containers) do expected[c.id]=c end
        for _,c in ipairs(report.chests) do
            assertx(expected[c.id] and c.base_id_live==plan.base_id and c.group_id_live==plan.group_id
                and c.type_live==expected[c.id].type and c.capacity==expected[c.id].capacity,
                "ownership_changed","A planned chest's base, guild, type or capacity changed")
        end
        return report
    end
    local function summarize(op)
        return {operation_id=op.operation_id,request_id=op.request_id,kind=op.kind,
            status=op.status,completed_steps=op.completed_steps,total_steps=op.total_steps,
            pending_step=op.pending_step,created_utc=op.created_utc,updated_utc=op.updated_utc,
            error=op.error,plan_id=op.plan_id,server_instance_id=op.server_instance_id,
            expected_revision=op.expected_revision,performance=op.performance,
            live_changes=op.completed_steps>0 or op.pending_step~=nil}
    end
    local function read_operation(id)
        local f=io.open(path("operations",id),"rb");if not f then return nil end
        local last
        for line in f:lines() do
            local ok,value=pcall(J.decode,line,{max_bytes=65536,max_depth=32})
            if ok then last=value end
        end
        f:close()
        assertx(last,"journal_error","Operation journal exists without a complete record; do not retry")
        return last
    end
    local function persist(op)
        op.updated_utc=ctx.utc()
        -- Append-only records preserve the first idempotency intent across crashes.
        -- Never remove the old journal before replacing it on Windows.
        local f=assert(io.open(path("operations",op.operation_id),"ab"))
        assert(f:write("\n"..J.encode(summarize(op),{max_bytes=65536,max_depth=32}).."\n"));assert(f:close())
    end
    local function lookup(request_id)
        local ref=read(path("operation-requests",request_id))
        if not ref then return nil end
        return read_operation(ref.operation_id)
    end
    local function reconcile(op)
        if op and (op.server_instance_id~=ctx.instance_id() or not active or active.operation_id~=op.operation_id)
            and (op.status=="queued" or op.status=="running") then
            op.status="interrupted"
            op.error={code="instance_changed",message="Server or Mod reloaded; no steps are replayed. Inspect current storage and create a fresh plan."}
            persist(op)
        end
        return op
    end
    local api={}
    function api.plan(params)
        assertx(not active,"busy","Wait for the current storage operation to finish")
        local report=ctx.read_storage(params.base_id,params.container_ids)
        local targets=ctx.get_targets and ctx.get_targets() or T
        local baseline=flat(indexed(report))
        params.require_live_ownership=true
        local merge_plan
        if ctx.merge then
            local err
            merge_plan,err=ctx.merge.plan(report,targets,params)
            if not merge_plan then error(err,0) end
        end
        local plan,err=O.plan(merge_plan and merge_plan.projected_snapshot or report,targets,params)
        if not plan then error(err,0) end
        if merge_plan then
            local operations={}
            for _,step in ipairs(merge_plan.operations) do operations[#operations+1]=step end
            for _,step in ipairs(plan.operations) do operations[#operations+1]=step end
            for i,step in ipairs(operations) do step.sequence=i end
            plan.operations=operations;plan.operation_count=#operations
            plan.merge_stacks=true;plan.merge_operation_count=#merge_plan.operations
            plan.merge_quantity_signature=merge_plan.quantity_signature
            plan.merge_summary={freed_slots=merge_plan.freed_slots,occupied_before=merge_plan.occupied_before,
                occupied_after=merge_plan.occupied_after,merge_operations=#merge_plan.operations}
            for _,warning in ipairs(merge_plan.warnings or {}) do plan.warnings[#plan.warnings+1]=warning end
        end
        plan.plan_id=ctx.new_uuid();plan.expected_revision=ctx.new_uuid()
        plan.server_instance_id=ctx.instance_id();plan.created_utc=ctx.utc()
        plan.expires_epoch=os.time()+180;plan.ownership_verified_live=true
        -- Mark empty arrays explicitly for JSON consumers.
        for _,name in ipairs({"operations","stacks","initial_slots","assignments","containers","warnings"}) do J.array(plan[name]) end
        for _,c in ipairs(plan.containers) do J.array(c.slots);J.array(c.categories) end
        plans[plan.plan_id]={plan=plan,baseline=baseline}
        write(path("plans",plan.plan_id),{plan=plan,baseline=baseline})
        -- Drop old in-memory plans; persistent copies remain reviewable.
        for id,v in pairs(plans) do if v.plan.expires_epoch<os.time() then plans[id]=nil end end
        return plan
    end
    function api.apply(params,request_id)
        local existing=reconcile(read_operation(params.idempotency_key))
        if existing then
            assertx(existing.plan_id==params.plan_id and existing.expected_revision==params.expected_revision,
                "idempotency_conflict","This idempotency key was already used with different parameters")
            write(path("operation-requests",request_id),{operation_id=existing.operation_id})
            return summarize(existing)
        end
        assertx(not active,"busy","A storage operation is already running")
        local saved=plans[params.plan_id]
        assertx(saved,"plan_expired","Plan is missing or belongs to a previous Mod load")
        local plan=saved.plan
        assertx(plan.expected_revision==params.expected_revision,"conflict","Plan revision does not match")
        assertx(plan.server_instance_id==ctx.instance_id() and plan.expires_epoch>os.time(),"plan_expired","Create a fresh storage plan")
        assertx(same(flat(indexed(selected(plan))),saved.baseline),"conflict","Chest contents changed since the preview; create a fresh plan")
        local op={operation_id=params.idempotency_key,request_id=request_id,kind="storage.apply",
            plan_id=plan.plan_id,expected_revision=plan.expected_revision,server_instance_id=ctx.instance_id(),
            status="queued",created_utc=ctx.utc(),completed_steps=0,total_steps=#plan.operations,
            plan=plan,expected=saved.baseline,started_clock=clock(),
            performance={mode="fast-slot-batches",batch_count=0,max_batch_ms=0,slot_reads=0,native_calls=0,full_snapshot_reads=2}}
        -- Intent is persisted before queueing any game change. Request mapping is
        -- also persisted before the first tick, so a lost response can be resolved.
        persist(op);write(path("operation-requests",request_id),{operation_id=op.operation_id})
        active=op
        if ctx.schedule then ctx.schedule(16,pump) end
        return summarize(op)
    end
    function api.get(params)
        local op=reconcile(lookup(params.request_id))
        assertx(op,"not_found","No operation is recorded for this request UUID")
        return summarize(op)
    end
    function api.cancel(params)
        local record=lookup(params.request_id)
        assertx(record,"not_found","No operation is recorded for this request UUID")
        if active and active.operation_id==record.operation_id then
            active.status="cancelled";active.performance.elapsed_ms=(clock()-active.started_clock)*1000
            persist(active);local result=summarize(active);active=nil;return result
        end
        return summarize(reconcile(record))
    end
    local function live(o) return o and o:IsValid() and not o:GetFullName():find("Default__",1,true) end
    local function guid(s)
        s=s:gsub("-","");return {A=tonumber(s:sub(1,8),16),B=tonumber(s:sub(9,16),16),C=tonumber(s:sub(17,24),16),D=tonumber(s:sub(25,32),16)}
    end
    local function bindings(op)
        if op.bindings then return op.bindings end
        local manager=FindFirstOf("PalItemContainerManager")
        assertx(live(manager),"backend_unavailable","Item manager is not available")
        local transmitter
        for _,candidate in ipairs(FindAllOf("PalNetworkTransmitter") or {}) do
            if live(candidate) and candidate:HasAuthority() and candidate:GetFullName():find("PersistentLevel",1,true) then
                local owner=candidate:GetOwner()
                if live(owner) and owner:GetFullName():find("BP_PalGameStateInGame",1,true) then
                    assertx(not transmitter,"backend_unavailable","Multiple global transmitters found");transmitter=candidate
                end
            end
        end
        assertx(transmitter,"backend_unavailable","Authoritative global transmitter is unavailable")
        local component=transmitter:GetItem();assertx(live(component),"backend_unavailable","Item RPC component unavailable")
        local bound={component=component,containers={}}
        for _,c in ipairs(op.plan.containers) do
            local container=manager:GetContainer({ID=guid(c.id)})
            assertx(live(container) and container:Num()==c.capacity,"conflict","A planned container is no longer available")
            bound.containers[c.id]=container
        end
        op.bindings=bound;return bound
    end
    local function slots(op,step)
        local b=bindings(op)
        local from,to=b.containers[step.from.container_id],b.containers[step.to.container_id]
        assertx(live(from) and live(to),"conflict","A container is no longer loaded")
        local source=R.read_slot(from:Get(step.from.index),step.from.index,step.from.container_id,true)
        local target=R.read_slot(to:Get(step.to.index),step.to.index,step.to.container_id,true)
        op.performance.slot_reads=op.performance.slot_reads+2
        return {[key(step.from.container_id,step.from.index)]=source,[key(step.to.container_id,step.to.index)]=target}
    end
    local function native_move(op,step)
        local escrow=rawget(_G,"PalCraftEscrowExclusions")
        assertx(not escrow or (not escrow.is_reserved(step.from.container_id) and not escrow.is_reserved(step.to.container_id)),
            "exchange_escrow_reserved","A source or target container is reserved for material exchange")
        local b=bindings(op)
        assertx(live(b.component),"backend_unavailable","Item RPC component unavailable")
        b.component:RequestMove_ToServer(guid(ctx.new_uuid()),b.containers[step.to.container_id]:Get(step.to.index):GetSlotId(),
            {{SlotId=b.containers[step.from.container_id]:Get(step.from.index):GetSlotId(),Num=step.count}})
        op.performance.native_calls=op.performance.native_calls+1
    end
    local function execute_step(op)
        local step=op.plan.operations[op.completed_steps+1]
        if not step then op.status="completed";persist(op);active=nil;return end
        local before=slots(op,step)
        for k,v in pairs(before) do
            assertx(same(identity(v),op.expected[k]),"conflict","A source or target slot changed during sorting; completed moves are retained")
        end
        local fk,tk=key(step.from.container_id,step.from.index),key(step.to.container_id,step.to.index)
        local source,target=before[fk],before[tk]
        local merging=step.kind=="merge"
        assertx(source and target and not source.empty and step.count>0 and step.count<=source.count
            and source.count==step.expected_source.count,"conflict","Source quantity no longer matches the planned move")
        assertx(source.item==step.expected_source.item and source.dynamicGuid==step.expected_source.dynamicGuid
            and source.dynamicWorldGuid==step.expected_source.dynamicWorldGuid,"conflict","Source item identity changed")
        if merging then
            assertx(not target.empty and target.item==source.item and target.dynamicGuid==source.dynamicGuid
                and target.dynamicWorldGuid==source.dynamicWorldGuid
                and source.dynamicGuid=="00000000-0000-0000-0000-000000000000"
                and source.dynamicWorldGuid=="00000000-0000-0000-0000-000000000000",
                "conflict","Only identical ordinary stackable items can be merged")
            assertx(target.count==step.expected_target.count and target.max_stack and target.count+step.count<=target.max_stack
                and target.max_stack==source.max_stack,"conflict","Target stack count or native limit changed")
        else
            assertx(target.empty and step.count==source.count,"conflict","Full-stack moves require an empty target")
        end
        op.status="running";op.pending_step=step.sequence;persist(op)
        native_move(op,step)
        local after=slots(op,step)
        local expected={}
        expected[tk]=identity(source);expected[tk].count=target.count+step.count
        if source.count>step.count then expected[fk]=identity(source);expected[fk].count=source.count-step.count
        else expected[fk]={item="None",count=0,dynamicGuid="00000000-0000-0000-0000-000000000000",
            dynamicWorldGuid="00000000-0000-0000-0000-000000000000",empty=true} end
        assertx(same(flat(after),expected),"native_result_mismatch","Native move readback differs from expected state; inspect the recorded pending step")
        local expected_corruption=merging and target.corruption or source.corruption
        if expected_corruption~=nil and after[tk].corruption~=nil then
            assertx(math.abs(expected_corruption-after[tk].corruption)<0.0005,
                "decay_mismatch","Moved stack decay value changed unexpectedly; inspect the recorded pending step")
        end
        if source.count>step.count and source.corruption~=nil and after[fk].corruption~=nil then
            assertx(math.abs(source.corruption-after[fk].corruption)<0.0005,
                "decay_mismatch","Partial source stack decay changed unexpectedly")
        end
        op.expected[fk]=expected[fk];op.expected[tk]=expected[tk]
        op.completed_steps=op.completed_steps+1;op.pending_step=nil
        if op.completed_steps==op.total_steps then op.status="completed";active=nil end
    end
    local function run_batch()
        if not active then return end
        local op=active
        local started=clock()
        local ok,err=pcall(function()
            for _=1,max_moves do
                execute_step(op)
                if not active or clock()-started>=budget_seconds then break end
            end
        end)
        op.performance.batch_count=op.performance.batch_count+1
        op.performance.max_batch_ms=math.max(op.performance.max_batch_ms,(clock()-started)*1000)
        op.performance.elapsed_ms=(clock()-op.started_clock)*1000
        if not ok then
            op.status=op.pending_step and "needs_inspection" or "stopped_conflict"
            op.error=type(err)=="table" and err or {code="runtime_error",message=tostring(err)}
            active=nil
        end
        persist(op)
    end
    pump=function()
        run_batch()
        if active and ctx.schedule then ctx.schedule(16,pump) end
    end
    function api.tick()
        if not ctx.schedule then run_batch() end
    end
    return api
end
return M
