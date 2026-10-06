-- Pure mock of storage-runtime.lua. No SSH, live game, disk journals or save edits.
-- Real snapshot fixtures supply item diversity; all ownership flags here are mocks.
local S='work/palworld-live/bridge/PalLiveBridge/Scripts/'
local J=dofile(S..'json.lua')
local O=dofile(S..'organize.lua')
local Merge=dofile(S..'merge.lua')
local T=dofile(S..'targets.lua')
local ZERO='00000000-0000-0000-0000-000000000000'
local function guid(n)return string.format('00000000-0000-0000-0000-%012x',n)end
local function encode_guid(s)
    local h=s:gsub('-','')
    return{A=tonumber(h:sub(1,8),16),B=tonumber(h:sub(9,16),16),C=tonumber(h:sub(17,24),16),D=tonumber(h:sub(25,32),16)}
end
local function decode_guid(v)
    local h=string.format('%08x%08x%08x%08x',v.A,v.B,v.C,v.D)
    return h:sub(1,8)..'-'..h:sub(9,12)..'-'..h:sub(13,16)..'-'..h:sub(17,20)..'-'..h:sub(21,32)
end
local function clone(t)
    if type(t)~='table'then return t end
    local o={} for k,v in pairs(t)do o[k]=clone(v)end return o
end
local function fixture(name)
    local f=assert(io.open('work/palworld-live/lab/rpc-'..name..'-after-restart.json','rb'))
    local report=J.decode(f:read('*a'),{max_bytes=8388608,max_depth=64});f:close();return report
end
local function annotate(report)
    report.verifies_ownership=true;report.verified_live=true
    local by_id={} for _,t in ipairs(T.chests)do by_id[t.container_id]=t end
    for _,c in ipairs(report.chests)do
        local t=assert(by_id[c.id])
        c.ownership_verified_live=true;c.verified_live=true;c.eligible_for_snapshot_plan=true
        c.base_id_live=t.base_id;c.group_id_live=t.group_id;c.type_live=t.type
        c.is_guild_chest_live=false;c.container_id_from_module_live=c.id
    end
    return report
end
local function inventory(report)
    local rows={}
    for _,c in ipairs(report.chests)do for _,s in ipairs(c.slots)do if not s.empty then
        local content={} for k,v in pairs(s)do
            if k~='index'and k~='slot_id_index'and k~='container_id'and k~='empty'then content[k]=clone(v)end
        end
        rows[#rows+1]=O.canonical(content)
    end end end
    table.sort(rows);return table.concat(rows,'\n'),#rows
end
local function mock(source,enable_merge)
    local m={world=annotate(clone(source)),files={},instance=guid(90001),sequence=91000,clock=2000000000,
        native_calls=0,reads=0,mode='success',events={}}
    m.root='mock/rpc/'
    local function new_uuid()m.sequence=m.sequence+1;return guid(m.sequence)end
    local function utc()return os.date('!%Y-%m-%dT%H:%M:%SZ',m.clock)end
    local function object(name,t)
        t=t or {};t.IsValid=function()return true end;t.GetFullName=function()return name end;return t
    end
    function m.slot(id,index)
        for _,c in ipairs(m.world.chests)do if c.id==id then
            for _,s in ipairs(c.slots)do if s.index==index then return s,c end end
        end end
        error('Mock slot does not exist')
    end
    function m.journal(id)
        local raw=m.files[m.root..'operations/'..id..'.json'];if not raw then return nil end
        local latest
        for line in raw:gmatch('[^\n]+')do local ok,value=pcall(J.decode,line);if ok then latest=value end end
        return latest
    end
    local fakeio={}
    function fakeio.open(path,mode)
        if mode=='rb'then
            local bytes=m.files[path];if bytes==nil then return nil,'not found'end
            return{read=function(_,n)return type(n)=='number'and bytes:sub(1,n)or bytes end,
                lines=function()return bytes:gmatch('[^\n]+')end,close=function()return true end}
        end
        assert(mode=='wb'or mode=='ab','Unexpected write mode')
        if mode=='wb'then m.files[path]=''end
        return{write=function(self,bytes)
            m.files[path]=(m.files[path]or'')..bytes;m.events[#m.events+1]={kind='write',path=path};return self
        end,close=function()return true end}
    end
    local fakeos={time=function()return m.clock end,date=os.date}
    function fakeos.rename(from,to)
        assert(m.files[to]==nil,'Immutable mock rename must not overwrite')
        assert(m.files[from]~=nil,'Rename source missing')
        m.files[to]=m.files[from];m.files[from]=nil;return true
    end
    function fakeos.remove()error('Append-only runtime must not remove journals')end
    local function slot_object(id,index)
        return object('MockSlot',{GetSlotId=function()return{ContainerId={ID=encode_guid(id)},SlotIndex=index}end})
    end
    local manager=object('Mock PalItemContainerManager',{GetContainer=function(_,v)
        local id=decode_guid(v.ID)
        return object('Mock PalItemContainer '..id,{Get=function(_,index)m.slot(id,index);return slot_object(id,index)end})
    end})
    local component=object('Mock item RPC component')
    function component:RequestMove_ToServer(request_guid,to,froms)
        assert(#froms==1,'Only one full source stack per native move')
        local prior=assert(m.journal(m.operation_id),'Native move must have a durable intent')
        assert(prior.status=='running'and prior.pending_step,'Native move must follow pending-step journal')
        m.native_calls=m.native_calls+1;m.events[#m.events+1]={kind='native',sequence=prior.pending_step}
        if m.mode=='noop'then return end
        if m.mode=='throw_before'then error('Mock native failure')end
        local from=froms[1]
        local source_slot=m.slot(decode_guid(from.SlotId.ContainerId.ID),from.SlotId.SlotIndex)
        local target_slot=m.slot(decode_guid(to.ContainerId.ID),to.SlotIndex)
        assert(not source_slot.empty and from.Num>0 and source_slot.count>=from.Num,'Invalid native move amount')
        local source_count=source_slot.count-from.Num
        if target_slot.empty then
            assert(source_count==0,'Move-to-empty remains full-stack only')
            local target_id,target_index=target_slot.container_id,target_slot.index
            local payload=clone(source_slot)
            for k in pairs(target_slot)do target_slot[k]=nil end
            for k,v in pairs(payload)do target_slot[k]=v end
            target_slot.container_id=target_id;target_slot.index=target_index;target_slot.slot_id_index=target_index
        else
            assert(enable_merge,'Native destination must be empty without merge phase')
            assert(source_slot.item==target_slot.item and source_slot.dynamicGuid==target_slot.dynamicGuid
                and source_slot.dynamicWorldGuid==target_slot.dynamicWorldGuid)
            assert(source_slot.dynamicGuid==ZERO and source_slot.dynamicWorldGuid==ZERO)
            assert(source_slot.max_stack==target_slot.max_stack and target_slot.count+from.Num<=target_slot.max_stack)
            target_slot.count=target_slot.count+from.Num
            if target_slot.is_max_stack~=nil then target_slot.is_max_stack=target_slot.count==target_slot.max_stack end
        end
        if source_count>0 then
            source_slot.count=source_count
            if source_slot.is_max_stack~=nil then source_slot.is_max_stack=source_slot.count==source_slot.max_stack end
        else
            local source_id,source_index=source_slot.container_id,source_slot.index
            for k in pairs(source_slot)do source_slot[k]=nil end
            source_slot.container_id=source_id;source_slot.index=source_index;source_slot.slot_id_index=source_index
            source_slot.item='None';source_slot.count=0;source_slot.empty=true
            source_slot.dynamicGuid=ZERO;source_slot.dynamicWorldGuid=ZERO
            source_slot.corruption=0;source_slot.corruptionKind='GetCorruptionProgressRate'
        end
        if m.mode=='wrong_count'then target_slot.count=target_slot.count+1 end
        if m.mode=='wrong_dynamic'then target_slot.dynamicGuid=guid(123)end
        if m.mode=='wrong_decay'then target_slot.corruption=target_slot.corruption+0.1 end
        if m.mode=='crash_after_move'then coroutine.yield('simulated_process_crash')end
        if m.mode=='throw_after'then error('Mock native failure after mutation')end
    end
    local owner=object('/Game/Pal/Maps/MainWorld_5/MainWorld.PersistentLevel.BP_PalGameStateInGame_C_1')
    local transmitter=object('/Game/Pal/Maps/MainWorld_5/MainWorld.PersistentLevel.PalNetworkTransmitter_1',{
        HasAuthority=function()return true end,GetOwner=function()return owner end,GetItem=function()return component end})
    local env=setmetatable({io=fakeio,os=fakeos},{__index=_G})
    env.FindFirstOf=function(class)assert(class=='PalItemContainerManager');return manager end
    env.FindAllOf=function(class)assert(class=='PalNetworkTransmitter');return{transmitter}end
    local runtime=assert(loadfile(S..'storage-runtime.lua','t',env))()
    function m.read_storage(base,ids)
        assert(base==m.world.base_id,'Mock read escaped base')
        m.reads=m.reads+1
        local report=clone(m.world)
        if ids then
            local chosen={};for _,id in ipairs(ids)do chosen[id]=true end
            report.chests={};for _,c in ipairs(m.world.chests)do if chosen[c.id]then report.chests[#report.chests+1]=clone(c)end end
        end
        return report
    end
    local ctx={json=J,organize=O,merge=enable_merge and Merge or nil,readers={},targets=T,root=m.root,utc=utc,new_uuid=new_uuid,
        instance_id=function()return m.instance end,read_storage=function(...)return m.read_storage(...)end}
    m.api=runtime.new(ctx)
    function m.reload()
        m.instance=new_uuid();m.api=runtime.new(ctx);return m.api
    end
    function m.plan()
        return m.api.plan({base_id=m.world.base_id,policy='category'})
    end
    function m.queue(plan)
        m.request_id=new_uuid();m.operation_id=new_uuid()
        m.params={plan_id=plan.plan_id,expected_revision=plan.expected_revision,idempotency_key=m.operation_id}
        return m.api.apply(m.params,m.request_id)
    end
    function m.status()return m.api.get({request_id=m.request_id})end
    function m.drain(maximum)
        for _=1,maximum or 1000 do
            local status=m.status();if status.status~='queued'and status.status~='running'then return status end
            m.api.tick()
        end
        error('Operation failed to finish')
    end
    return m
end
local passed=0
local function test(name,fn)
    local ok,err=pcall(fn)
    if not ok then if type(err)=='table'then err=J.encode(err)end;error(name..': '..tostring(err),0)end
    passed=passed+1;print('PASS '..name)
end
local function error_code(fn,expected)
    local ok,err=pcall(fn);assert(not ok,'Expected rejection')
    assert(type(err)=='table'and err.code==expected,'Expected '..expected..', got '..tostring(type(err)=='table'and err.code or err))
end
local NEW=fixture('newbase')
local OLD=fixture('oldbase')

test('unverified ownership cannot create a plan',function()
    local m=mock(NEW);m.world.chests[1].ownership_verified_live=false
    error_code(m.plan,'ownership_unverified');assert(m.native_calls==0)
end)
test('changed live ownership rejects planning despite intact contents',function()
    local m=mock(NEW);m.world.chests[1].eligible_for_snapshot_plan=false
    error_code(m.plan,'ownership_changed');assert(m.native_calls==0)
end)
test('changed quantity between preview and apply rejects before queueing',function()
    local m=mock(NEW);local p=m.plan();local s=m.slot(p.stacks[1].origin.container_id,p.stacks[1].origin.index)
    s.count=s.count+1
    error_code(function()m.queue(p)end,'conflict');assert(m.native_calls==0)
end)
test('changed layout with same inventory rejects stale preview',function()
    local m=mock(NEW);local p=m.plan();local c=m.world.chests[1]
    local a,b=c.slots[1],c.slots[2]
    local payload=clone(a)
    for k,v in pairs(b)do if k~='index'and k~='slot_id_index'and k~='container_id'then a[k]=clone(v)end end
    for k,v in pairs(payload)do if k~='index'and k~='slot_id_index'and k~='container_id'then b[k]=clone(v)end end
    error_code(function()m.queue(p)end,'conflict');assert(m.native_calls==0)
end)
test('mid-execution conflict preserves completed moves and stops',function()
    local m=mock(NEW);local p=m.plan();m.queue(p);m.api.tick()
    assert(m.status().completed_steps==1 and m.native_calls==1)
    local changed=m.slot(p.operations[1].to.container_id,p.operations[1].to.index);changed.count=changed.count+5
    m.api.tick();local status=m.status()
    assert(status.status=='stopped_conflict'and status.completed_steps==1 and status.error.code=='conflict')
    for _=1,4 do m.api.tick()end;assert(m.native_calls==1)
end)
test('live ownership changes during execution stop before another native call',function()
    local m=mock(NEW);local p=m.plan();m.queue(p);m.api.tick()
    m.world.chests[1].eligible_for_snapshot_plan=false
    m.api.tick();local status=m.status()
    assert(status.status=='stopped_conflict'and status.completed_steps==1 and status.error.code=='ownership_changed')
    assert(m.native_calls==1)
end)
test('same idempotency key while queued and after completion never repeats moves',function()
    local m=mock(NEW);local p=m.plan();m.queue(p)
    assert(m.api.apply(m.params,guid(60001)).status=='queued'and m.native_calls==0)
    local completed=m.drain();assert(completed.status=='completed'and m.native_calls==p.operation_count)
    local count=m.native_calls
    assert(m.api.apply(m.params,guid(60002)).status=='completed')
    assert(m.api.get({request_id=guid(60002)}).operation_id==m.operation_id)
    for _=1,4 do m.api.tick()end;assert(m.native_calls==count)
    local bad=clone(m.params);bad.expected_revision=guid(1)
    error_code(function()m.api.apply(bad,guid(60003))end,'idempotency_conflict')
end)
test('queued operation on reload is interrupted and never auto-replayed',function()
    local m=mock(NEW);local p=m.plan();m.queue(p);m.reload()
    local status=m.status();assert(status.status=='interrupted'and status.completed_steps==0 and not status.live_changes)
    for _=1,4 do m.api.tick()end;assert(m.native_calls==0)
    assert(m.api.apply(m.params,guid(60004)).status=='interrupted')
    assert(m.native_calls==0)
end)
test('reload after one committed move preserves partial result without resuming',function()
    local m=mock(NEW);local p=m.plan();m.queue(p);m.api.tick();m.reload()
    local before=O.canonical(m.world);local status=m.status()
    assert(status.status=='interrupted'and status.completed_steps==1 and status.live_changes)
    for _=1,4 do m.api.tick()end
    assert(m.native_calls==1 and O.canonical(m.world)==before)
    local fresh=clone(m.params);fresh.idempotency_key=guid(60005)
    error_code(function()m.api.apply(fresh,guid(60006))end,'plan_expired')
end)
test('crash after native mutation retains pending intent and does not replay',function()
    local m=mock(NEW);local p=m.plan();m.queue(p);m.mode='crash_after_move'
    local co=coroutine.create(function()m.api.tick()end)
    local ok,message=coroutine.resume(co);assert(ok and message=='simulated_process_crash')
    assert(coroutine.status(co)=='suspended'and m.native_calls==1)
    local intent=m.journal(m.operation_id);assert(intent.status=='running'and intent.pending_step==1 and intent.completed_steps==0)
    local before=O.canonical(m.world);m.reload();m.mode='success'
    local status=m.status();assert(status.status=='interrupted'and status.pending_step==1 and status.live_changes)
    assert(m.api.apply(m.params,guid(60007)).status=='interrupted')
    for _=1,4 do m.api.tick()end
    assert(m.native_calls==1 and O.canonical(m.world)==before)
end)
for _,mode in ipairs({'noop','wrong_count','wrong_dynamic','wrong_decay','throw_before','throw_after'})do
    test('native '..mode..' stops with durable needs-inspection state',function()
        local m=mock(NEW);local p=m.plan();m.queue(p);m.mode=mode;m.api.tick()
        local status=m.status();assert(status.status=='needs_inspection'and status.pending_step==1 and status.completed_steps==0)
        assert(status.live_changes and m.native_calls==1)
        assert(m.api.apply(m.params,guid(60100)).status=='needs_inspection')
        for _=1,4 do m.api.tick()end;assert(m.native_calls==1)
    end)
end
test('torn final journal line retains previous durable intent',function()
    local m=mock(NEW);local p=m.plan();m.queue(p);m.api.tick()
    local path=m.root..'operations/'..m.operation_id..'.json'
    m.files[path]=m.files[path]..'{"status":"run'
    m.reload();local status=m.status()
    assert(status.status=='interrupted'and status.completed_steps==1)
    assert(m.journal(m.operation_id).status=='interrupted','Recovered interruption must itself be a complete durable record')
    m.api.tick();assert(m.native_calls==1)
end)
for _,entry in ipairs({{name='14',report=NEW,count=14},{name='242',report=OLD,count=242}})do
    test('complete '..entry.name..'-stack organization preserves exact metadata and quantities',function()
        local source=clone(entry.report)
        if entry.count==14 then
            local c=source.chests[#source.chests];local slot=c.slots[#c.slots]
            assert(slot.empty)
            slot.empty=false;slot.item='HandGun';slot.count=1;slot.dynamicGuid=guid(777);slot.dynamicWorldGuid=guid(778)
            slot.dynamic_data={durability=83.25,ammo=7,traits={'MockTraitA','MockTraitB'}}
        end
        local m=mock(source);local original,count=inventory(m.world);assert(count==entry.count)
        local p=m.plan();assert(p.stack_count==entry.count and p.operation_count>0)
        m.queue(p);local status=m.drain()
        local after,after_count=inventory(m.world)
        assert(status.status=='completed'and status.completed_steps==p.operation_count)
        assert(after==original and after_count==entry.count and m.native_calls==p.operation_count)
        assert(m.journal(m.operation_id).status=='completed')
        for _,assignment in ipairs(p.assignments)do
            local actual=m.slot(assignment.to.container_id,assignment.to.index)
            local expected
            for _,stack in ipairs(p.stacks)do if stack.token==assignment.token then expected=stack.content;break end end
            assert(expected and actual.item==expected.item and actual.count==expected.count
                and actual.dynamicGuid==expected.dynamicGuid and actual.dynamicWorldGuid==expected.dynamicWorldGuid)
        end
        print(string.format('  stacks=%d native_moves=%d journal_bytes=%d',entry.count,m.native_calls,#m.files[m.root..'operations/'..m.operation_id..'.json']))
    end)
end
local function identity_totals(report)
    local totals,dynamic={},{}
    for _,c in ipairs(report.chests)do for _,s in ipairs(c.slots)do if not s.empty then
        local id=O.canonical({item=s.item,dynamicGuid=s.dynamicGuid,dynamicWorldGuid=s.dynamicWorldGuid})
        totals[id]=(totals[id]or 0)+s.count
        if s.dynamicGuid~=ZERO or s.dynamicWorldGuid~=ZERO then
            local data=clone(s);data.index=nil;data.container_id=nil;data.slot_id_index=nil
            dynamic[#dynamic+1]=O.canonical(data)
        end
    end end end
    table.sort(dynamic);return O.canonical(totals),table.concat(dynamic,'\n')
end
local f=assert(io.open('work/palworld-live/lab/merge-preflight.json','rb'))
local captured=J.decode(f:read('*a'),{max_bytes=8388608,max_depth=64}).before;f:close()
for _,base in ipairs({'00000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000031'})do
    test('combined native merge plus classification conserves base '..base,function()
        local source=clone(captured);source.base_id=base;source.chests={}
        for _,c in ipairs(captured.chests)do if c.base_id_live==base then source.chests[#source.chests+1]=clone(c)end end
        if base=='00000000-0000-4000-8000-000000000011'then
            -- Exercise partial donor consumption and target exactly reaching cap.
            for _,c in ipairs(source.chests)do for _,s in ipairs(c.slots)do
                if s.item=='Wood'then assert(s.count<=100);s.max_stack=100;s.is_max_stack=s.count==100 end
            end end
        end
        local m=mock(source,true);local before,dynamic_before=identity_totals(m.world)
        local p=m.plan();assert(p.merge_stacks and p.merge_operation_count>0 and p.merge_summary.freed_slots>0)
        m.queue(p);local status=m.drain()
        local after,dynamic_after=identity_totals(m.world)
        assert(status.status=='completed'and status.completed_steps==p.operation_count)
        assert(before==after and dynamic_before==dynamic_after)
        assert(m.native_calls==p.operation_count and m.journal(m.operation_id).status=='completed')
        print(string.format('  merge=%d all_native_calls=%d freed_slots=%d',p.merge_operation_count,m.native_calls,p.merge_summary.freed_slots))
    end)
end
print(string.format('OK %d storage runtime mock tests',passed))
