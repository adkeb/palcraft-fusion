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
        return object('Mock PalItemContainer '..id,{Num=function()local _,c=m.slot(id,0);return c.capacity end,Get=function(_,index)m.slot(id,index);return slot_object(id,index)end})
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
    local runtime=assert(loadfile('work/palworld-live/fast-storage/storage-runtime-fast.lua','t',env))()
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
    local ctx={json=J,organize=O,merge=enable_merge and Merge or nil,readers={read_slot=function(_,index,id)return clone(m.slot(id,index))end},clock=os.clock,max_moves=3,targets=T,root=m.root,utc=utc,new_uuid=new_uuid,
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

local function totals(world)
    local out={}
    for _,c in ipairs(world.chests) do for _,s in ipairs(c.slots) do if not s.empty then
        local id=O.canonical({s.item,s.dynamicGuid,s.dynamicWorldGuid})
        out[id]=(out[id]or 0)+s.count
    end end end
    return O.canonical(out)
end
if arg and arg[1]=='escrow'then
 for _,side in ipairs({'from','to'})do
  local m=mock(fixture('newbase'),false);local p=m.plan();assert(p.operations[1])
  local cid=p.operations[1][side].container_id
  _G.PalCraftEscrowExclusions={is_reserved=function(value)return value==cid end}
  local before=totals(m.world);m.queue(p);m.api.tick()
  assert(m.native_calls==0 and totals(m.world)==before,'Reserved '..side..' must be rejected before native Move')
  assert(m.status().error.code=='exchange_escrow_reserved')
 end
 _G.PalCraftEscrowExclusions=nil
 local normal=mock(fixture('newbase'),false);normal.queue(normal.plan());normal.api.tick();assert(normal.native_calls>0,'Unrelated normal sorting must remain usable')
 print('PASS actual fast Move gate: reserved source, reserved target, ordinary sorting pass-through');return
end
for _,name in ipairs({'newbase','oldbase'})do
    local m=mock(fixture(name),false)
    local before=totals(m.world)
    local p=m.plan();m.queue(p)
    local result=m.drain()
    assert(result.status=='completed',J.encode(result))
    assert(totals(m.world)==before,'Inventory conservation failed')
    assert(m.reads==2,'Fast mode must read only two full snapshots')
    assert(m.native_calls==p.operation_count)
    assert(result.performance.slot_reads==4*p.operation_count)
    assert(m.api.apply(m.params,guid(60003)).status=='completed')
    print('PASS '..name..' moves='..p.operation_count..' full_reads='..m.reads..' batches='..result.performance.batch_count)
end
local m=mock(fixture('oldbase'),false);local p=m.plan();m.queue(p);m.api.tick()
assert(m.status().completed_steps>0)
local count=m.native_calls
local cancelled=m.api.cancel({request_id=m.request_id})
assert(cancelled.status=='cancelled')
for _=1,10 do m.api.tick()end
assert(m.native_calls==count,'Cancellation must stop queued moves')
print('PASS cancel between batches; completed moves retained')
for _,mode in ipairs({'wrong_count','wrong_dynamic','wrong_decay','noop'})do
    local m=mock(fixture('newbase'),false);m.queue(m.plan());m.mode=mode;m.api.tick()
    assert(m.status().status=='needs_inspection' and m.native_calls==1)
end
print('PASS native quantity, identity, decay and no-op failures halt immediately')

local f=assert(io.open('work/palworld-live/lab/merge-preflight.json','rb'))
local captured=J.decode(f:read('*a'),{max_bytes=8388608,max_depth=64}).before;f:close()
for _,base in ipairs({'00000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000031'})do
    local source=clone(captured);source.base_id=base;source.chests={}
    for _,c in ipairs(captured.chests)do if c.base_id_live==base then source.chests[#source.chests+1]=clone(c)end end
    local m=mock(source,true);local before=totals(m.world);local p=m.plan();m.queue(p)
    local result=m.drain();assert(result.status=='completed',J.encode(result));assert(totals(m.world)==before)
    assert(m.reads==2 and p.merge_operation_count>0)
    print('PASS merged classification moves='..p.operation_count..' merges='..p.merge_operation_count..' full_reads='..m.reads)
end
