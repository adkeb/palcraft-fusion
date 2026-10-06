from pathlib import Path
p=Path('work/palworld-live/bridge/PalLiveBridge/Scripts/readers.lua')
s=p.read_text()
s=s.replace('-- Candidate read-only helpers; NOT runtime validated. Palworld 1.0.5 + UE4SS 2281fa31.', '-- Read-only helpers for Palworld 1.0.5 + UE4SS 2281fa31.\n-- Base/slot readers runtime validated in BridgeLab. New ownership chain is candidate pending probe.')
s=s.replace('-- opts: {include_items=true, limit=1, lookup="manager"|"enumerate", manager_name=...}.', '-- opts: {include_items=true, limit=1, lookup="manager"|"enumerate", manager_name=...,\n--        verify_ownership=true, require_snapshot_ownership=false, map_manager_name=...}.\n-- Ownership verification defaults ON and fails closed; GetConcreteModel is always called false.\n-- verify_ownership=false is the explicitly unverified legacy read mode, never an apply preflight.')
s=s.replace('local UINT32 = 4294967296', 'local UINT32 = 4294967296\nlocal ZERO_GUID = "00000000-0000-0000-0000-000000000000"')
anchor='local function container_id(c)\n'
insert='''local function guid_from_string(s)
    assert(type(s)=="string" and #s==36 and
        s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"), "invalid GUID string")
    local h=s:gsub("-", "")
    return {A=tonumber(h:sub(1,8),16), B=tonumber(h:sub(9,16),16),
        C=tonumber(h:sub(17,24),16), D=tonumber(h:sub(25,32),16)}
end
'''
s=s.replace(anchor,insert+anchor)
s=s.replace('        ownership_verified_live=false, ok=false, slots={}', '        verified_live=false, ownership_verified_live=false,\n        snapshot_membership_matches_live=false, eligible_for_snapshot_plan=false, ok=false, slots={}')
anchor='local function slot_read(slot, index, id, include_items)\n'
insert='''local function map_object_manager(options)
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
'''
s=s.replace(anchor,insert+anchor)
s=s.replace('        includes_items=options.include_items == true, chests={}, errors={} }', '        includes_items=options.include_items == true, verifies_ownership=options.verify_ownership~=false,\n        ownership_only=options.ownership_only==true, force_concrete_requested=false, chests={}, errors={} }')
s=s.replace('    local by_id = {}\n    local mgr', '    local by_id = {}\n    local mapmgr\n    if out.verifies_ownership then mapmgr=map_object_manager(options) end\n    local mgr')
s=s.replace('            assert(row.actual_id == t.container_id, "container identity mismatch")\n            row.capacity', '            assert(row.actual_id == t.container_id, "container identity mismatch")\n            if mapmgr then verify_owner(t,c,mapmgr,row) end\n            row.capacity')
s=s.replace('            row.capacity_matches_snapshot = row.capacity == t.expected_capacity\n            row.occupied = 0\n            for index=0,row.capacity-1 do', '            row.capacity_matches_snapshot = row.capacity == t.expected_capacity\n            row.eligible_for_snapshot_plan=row.verified_live and row.snapshot_membership_matches_live\n                and row.snapshot_type_matches_live and row.capacity_matches_snapshot\n            if options.require_snapshot_ownership then\n                assert(row.eligible_for_snapshot_plan, "live ownership/type/capacity does not match snapshot target")\n            end\n            if not options.ownership_only then\n            row.occupied = 0\n            for index=0,row.capacity-1 do')
s=s.replace('                if not sr.empty then row.occupied=row.occupied+1 end\n            end\n            row.ok=true', '                if not sr.empty then row.occupied=row.occupied+1 end\n            end\n            end\n            row.ok=true')
s=s.replace('            row.error=tostring(err)\n            out.errors', '            row.error=tostring(err)\n            if out.verifies_ownership and not row.ownership_verified_live then row.ownership_error=row.error end\n            out.errors')
s=s.replace('    out.ok = #out.errors == 0\n    return out\nend\n\nfunction M.bases()', '    out.ok = #out.errors == 0\n    out.verified_live=out.verifies_ownership and out.ok\n    return out\nend\n\nfunction M.ownership(targets, options)\n    local opts={}\n    for k,v in pairs(options or {}) do opts[k]=v end\n    opts.verify_ownership=true; opts.ownership_only=true; opts.include_items=false\n    return M.chests(targets, opts)\nend\n\nfunction M.bases()')
s=s.replace('M.guid_to_string=guid\nreturn M', 'M.guid_to_string=guid\nM.guid_from_string=guid_from_string\nreturn M')
p.write_text(s)
