-- Read-only helpers for Palworld 1.0.5 + UE4SS 2281fa31.
-- Base/slot readers runtime validated in BridgeLab. New ownership chain is candidate pending probe.
-- Load with dofile/require, then call on the GAME THREAD in a stable loaded world.
-- No loops, hooks, file/network I/O, RPCs, writes, OnRep calls, or custom memory offsets.
-- Interface: Readers.chests(targets, opts), Readers.bases(), Readers.snapshot(targets, opts).
-- targets is the plain Lua table returned by targets.lua.
-- opts: {include_items=true, limit=1, lookup="manager"|"enumerate", manager_name=...,
--        verify_ownership=true, require_snapshot_ownership=false, map_manager_name=...}.
-- Ownership verification defaults ON and fails closed; GetConcreteModel is always called false.
-- verify_ownership=false is the explicitly unverified legacy read mode, never an apply preflight.
-- Default include_items=false permits an initial container/slot-count preflight.
-- Never retain returned UObjects/UScriptStructs: only primitive data leaves this module.
-- Lua pcall handles Lua errors, not native access violations. Test staged in BridgeLab.
-- Evidence: Okaetsu/RE-UE4SS@2281fa31/UE4SS/src/LuaType/LuaUObject.cpp
-- 528..607 recursively marshals Lua table->struct; 301..309+707..783 materializes
-- UFunction struct return values as Lua tables. 1.0.5 ObjectDump matches used getters.
local M = { candidate_unvalidated = true }
local UINT32 = 4294967296
local ZERO_GUID = "00000000-0000-0000-0000-000000000000"

local function finite(n)
    assert(type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge,
        "expected finite number")
    return n
end
local function uint32(n)
    n = finite(n)
    assert(n % 1 == 0 and n >= -2147483648 and n < UINT32, "invalid uint32")
    if n < 0 then n = n + UINT32 end
    return n
end
local function plain(v, kind)
    assert(type(v) == "table", (kind or "struct") .. " was not a materialized Lua table; raw nested property fallback disabled")
    return v
end
local function guid(g)
    g = plain(g, "FGuid")
    local h = string.format("%08x%08x%08x%08x", uint32(g.A), uint32(g.B), uint32(g.C), uint32(g.D))
    return h:sub(1,8).."-"..h:sub(9,12).."-"..h:sub(13,16).."-"..h:sub(17,20).."-"..h:sub(21,32)
end
local function guid_from_string(s)
    assert(type(s)=="string" and #s==36 and
        s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"), "invalid GUID string")
    local h=s:gsub("-", "")
    return {A=tonumber(h:sub(1,8),16), B=tonumber(h:sub(9,16),16),
        C=tonumber(h:sub(17,24),16), D=tonumber(h:sub(25,32),16)}
end
local function container_id(c)
    return guid(plain(c, "FPalContainerId").ID)
end
local function text(v)
    if type(v) == "string" then return v end
    assert(v ~= nil, "missing text value")
    local s = v:ToString()
    assert(type(s) == "string", "text conversion failed")
    return s
end
local function live(o)
    return o ~= nil and o:IsValid() and not o:GetFullName():find("Default__", 1, true)
end
local function instances(class)
    local out = {}
    for _, o in ipairs(FindAllOf(class) or {}) do
        if live(o) then out[#out+1] = o end
    end
    return out
end
local function vector(v)
    v = plain(v, "FVector")
    return {x=finite(v.X), y=finite(v.Y), z=finite(v.Z)}
end
local function manager(options)
    local found = instances("PalItemContainerManager")
    if options.manager_name then
        for _, o in ipairs(found) do
            if o:GetFullName() == options.manager_name then return o end
        end
        error("requested manager instance not found")
    end
    assert(#found == 1, "expected exactly one live PalItemContainerManager, found "..#found)
    return found[1]
end
local function copy_target(t)
    return {
        id=t.container_id, base_id_from_snapshot=t.base_id,
        instance_id_from_snapshot=t.instance_id, group_id_from_snapshot=t.group_id,
        type_from_snapshot=t.type, expected_capacity=t.expected_capacity,
        verified_live=false, ownership_verified_live=false,
        snapshot_membership_matches_live=false, eligible_for_snapshot_plan=false, ok=false, slots={}
    }
end
local function map_object_manager(options)
    local found=instances("PalMapObjectManager")
    if options.map_manager_name then
        for _,o in ipairs(found) do if o:GetFullName()==options.map_manager_name then return o end end
        error("requested map-object manager instance not found")
    end
    assert(#found==1, "expected exactly one live PalMapObjectManager, found "..#found)
    return found[1]
end
local function verify_owner(t, c, mapmgr, row)
    row.ownership_check={stage="model_lookup", force_concrete_requested=false,
        source="FindModel -> GetConcreteModel(false) -> container module -> base"}
    local model_guid=t.instance_guid or guid_from_string(t.instance_id)
    assert(guid(model_guid)==t.instance_id, "snapshot model GUID encoding mismatch")
    local model=mapmgr:FindModel(model_guid)
    assert(live(model), "snapshot map-object model not loaded/found")
    row.model_object_live=model:GetFullName()
    row.ownership_check.stage="concrete_lookup_no_force"
    -- IMPORTANT: bIsForce=false is literal; no fallback with true, spawning, asset loading,
    -- actor construction or raw-property interpretation is permitted here.
    local concrete=model:GetConcreteModel(false)
    assert(live(concrete), "concrete model not loaded; no-force lookup refused to create it")
    row.concrete_object_live=concrete:GetFullName()
    row.model_instance_id_live=guid(concrete:GetModelInstanceId())
    row.concrete_instance_id_live=guid(concrete:GetInstanceId())
    assert(row.model_instance_id_live==t.instance_id, "concrete-to-model identity mismatch")
    row.ownership_check.stage="ordinary_type"
    row.type_live=text(concrete:TryGetMapObjectId())
    assert(row.type_live=="ItemChest" or row.type_live=="ItemChest_02", "live map object is not an allowed ordinary chest")
    row.ownership_check.stage="container_binding"
    local module=concrete:GetItemContainerModule()
    assert(live(module), "ordinary chest has no live item-container module")
    row.container_id_from_module_live=container_id(module:GetContainerId())
    assert(row.container_id_from_module_live==t.container_id, "module container differs from target container")
    local linked_container=module:GetContainer()
    assert(live(linked_container), "item-container module has no live container")
    assert(container_id(linked_container:GetId())==t.container_id, "linked container identity mismatch")
    -- This is one reflected scalar bool, never a nested struct memory access or write.
    row.is_guild_chest_live=c.bIsGuildChestContainer
    assert(type(row.is_guild_chest_live)=="boolean", "guild-chest scalar flag unavailable")
    assert(not row.is_guild_chest_live, "shared guild container is excluded")
    row.ownership_check.stage="base_and_guild"
    row.base_id_live=guid(concrete:GetBaseCampIdBelongTo())
    assert(row.base_id_live~=ZERO_GUID, "ordinary chest has no current base")
    local base=concrete:GetBaseCampModelBelongTo()
    assert(live(base), "owning base model not loaded/found")
    assert(guid(base:GetId())==row.base_id_live, "base id and base model disagree")
    assert(base:IsAvailable(), "owning base is unavailable")
    row.group_id_live=guid(base:GetGroupIdBelongTo())
    assert(row.group_id_live~=ZERO_GUID, "owning base has no guild")
    row.ownership_verified_live=true
    row.verified_live=true
    row.snapshot_membership_matches_live=row.base_id_live==t.base_id and row.group_id_live==t.group_id
    row.snapshot_type_matches_live=row.type_live==t.type
    row.ownership_check.stage="verified"
end
local function slot_read(slot, index, id, include_items)
    assert(live(slot), "slot instance missing")
    local row = { index=index, count=finite(slot:GetStackCount()), empty=slot:IsEmpty() }
    assert(row.count % 1 == 0 and row.count >= 0, "invalid stack count")
    local sid = plain(slot:GetSlotId(), "FPalItemSlotId return")
    row.container_id = container_id(sid.ContainerId)
    row.slot_id_index = finite(sid.SlotIndex)
    assert(row.container_id == id and row.slot_id_index == index, "slot identity mismatch")
    if include_items then
        -- IMPORTANT: this is a UFunction return materialized as Lua table, not slot.ItemId.
        local iid = plain(slot:GetItemId(), "FPalItemId return")
        local dynamic = plain(iid.DynamicId, "FPalDynamicItemId return")
        row.item = text(iid.StaticId)
        row.dynamicGuid = guid(dynamic.LocalIdInCreatedWorld)
        row.dynamicWorldGuid = guid(dynamic.CreatedWorldId)
        row.corruption = finite(slot:GetCorruptionProgressRate())
        row.corruptionKind = "GetCorruptionProgressRate"
        if not row.empty then
            -- Capacity of the actual occupied slot, never a hard-coded item limit.
            -- Empty None slots have no meaningful max-stack requirement.
            row.max_stack = finite(slot:GetMaxStack())
            assert(row.max_stack%1==0 and row.max_stack>0, "invalid max stack")
        end
    end
    return row
end

function M.chests(targets, options)
    options = options or {}
    assert(type(targets) == "table" and type(targets.chests) == "table", "targets.lua table required")
    local out = { candidate_unvalidated=true, source="runtime_read_only",
        snapshot_sha256=targets.snapshot_sha256, lookup=options.lookup or "manager",
        includes_items=options.include_items == true, verifies_ownership=options.verify_ownership~=false,
        ownership_only=options.ownership_only==true, force_concrete_requested=false, chests={}, errors={} }
    local max = options.limit or #targets.chests
    assert(type(max)=="number" and max%1==0 and max>0, "invalid target limit")
    max = math.min(max, #targets.chests)
    local wanted = {}
    for i=1,max do
        local t = targets.chests[i]
        assert(t.type == "ItemChest" or t.type == "ItemChest_02", "nonordinary target rejected")
        assert(guid(t.guid) == t.container_id, "target GUID encoding mismatch")
        wanted[t.container_id] = true
    end
    local by_id = {}
    local mapmgr
    if out.verifies_ownership then mapmgr=map_object_manager(options) end
    local mgr
    if out.lookup == "manager" then
        mgr = manager(options)
        out.manager = mgr:GetFullName()
    elseif out.lookup == "enumerate" then
        -- Explicit fallback only; no automatic raw-property or memory-offset fallback.
        for _, c in ipairs(instances("PalItemContainer")) do
            local ok, id = pcall(function() return container_id(c:GetId()) end)
            if ok and wanted[id] then
                assert(by_id[id] == nil, "duplicate live container GUID")
                by_id[id] = c
            end
        end
    else error("unknown lookup mode") end
    for i=1,max do
        local t = targets.chests[i]
        local row = copy_target(t)
        out.chests[#out.chests+1] = row
        local ok, err = pcall(function()
            local c
            if mgr then
                -- FPalContainerId { FGuid ID }; confirmed nested-table support in fork source.
                c = mgr:GetContainer({ID={A=t.guid.A,B=t.guid.B,C=t.guid.C,D=t.guid.D}})
            else c = by_id[t.container_id] end
            assert(live(c), "target container is not loaded/found")
            row.object = c:GetFullName()
            row.actual_id = container_id(c:GetId())
            assert(row.actual_id == t.container_id, "container identity mismatch")
            if mapmgr then verify_owner(t,c,mapmgr,row) end
            row.capacity = finite(c:Num())
            assert(row.capacity%1==0 and row.capacity>=0 and row.capacity<=1000, "invalid capacity")
            row.capacity_matches_snapshot = row.capacity == t.expected_capacity
            row.eligible_for_snapshot_plan=row.verified_live and row.snapshot_membership_matches_live
                and row.snapshot_type_matches_live and row.capacity_matches_snapshot
            if options.require_snapshot_ownership then
                assert(row.eligible_for_snapshot_plan, "live ownership/type/capacity does not match snapshot target")
            end
            if not options.ownership_only then
            row.occupied = 0
            for index=0,row.capacity-1 do
                local sr = slot_read(c:Get(index), index, row.actual_id, options.include_items == true)
                row.slots[#row.slots+1] = sr
                if not sr.empty then row.occupied=row.occupied+1 end
            end
            end
            row.ok=true
        end)
        if not ok then
            row.error=tostring(err)
            if out.verifies_ownership and not row.ownership_verified_live then row.ownership_error=row.error end
            out.errors[#out.errors+1]={id=t.container_id,error=row.error}
        end
    end
    out.ok = #out.errors == 0
    out.verified_live=out.verifies_ownership and out.ok
    return out
end

function M.ownership(targets, options)
    local opts={}
    for k,v in pairs(options or {}) do opts[k]=v end
    opts.verify_ownership=true; opts.ownership_only=true; opts.include_items=false
    return M.chests(targets, opts)
end

function M.bases()
    local out = {candidate_unvalidated=true, source="runtime_read_only", bases={}, errors={}}
    for _, base in ipairs(instances("PalBaseCampModel")) do
        local row = {object=base:GetFullName(), ok=false}
        out.bases[#out.bases+1]=row
        local ok, err = pcall(function()
            row.id=guid(base:GetId())
            row.group_id=guid(base:GetGroupIdBelongTo())
            row.owner_map_object_id=guid(base:GetOwnerMapObjectInstanceId())
            row.available=base:IsAvailable()
            row.level=finite(base:GetLevel())
            row.building_count=finite(base:GetBuildingNum())
            row.name=text(base:GetBaseCampName())
            row.range=finite(base:GetRange())
            row.position=vector(plain(base:GetTransform(), "FTransform return").Translation)
            row.ok=true
        end)
        if not ok then row.error=tostring(err); out.errors[#out.errors+1]=row.error end
    end
    out.ok=#out.errors==0
    return out
end

function M.snapshot(targets, options)
    return {candidate_unvalidated=true, bases=M.bases(), storage=M.chests(targets, options)}
end

-- Pure GUID conversion exposed for caller's local tests. Does not touch UE objects.
M.read_slot=slot_read
M.guid_to_string=guid
M.guid_from_string=guid_from_string
return M
