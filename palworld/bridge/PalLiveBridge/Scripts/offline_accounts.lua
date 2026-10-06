-- Read-only offline builder prerequisites. Run only on the game thread.
-- No login, player spawning, UFunction writes, inventory changes, raw offsets,
-- account creation or identity substitution. No C++ bridge is needed for these reads.
-- Runtime candidate: account handle -> actual UID; account-owned technology and
-- inventory; native guild lookup/permission; verified ordinary chest materials.
local M={version='offline-account-probe-0.1',runtime_verified=false}
function M.read(J,R,T)
    local ZERO='00000000-0000-0000-0000-000000000000'
    local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
    local function instances(class)
        local out={};for _,o in ipairs(FindAllOf(class)or{})do if live(o)then out[#out+1]=o end end;return out
    end
    local function same(a,b)return live(a)and live(b)and a:GetFullName()==b:GetFullName()end
    local function text(s)return type(s)=='string'and s or s:ToString()end
    local function num(v)assert(type(v)=='number'and v==v and math.abs(v)<9007199254740992 and v>=0 and v%1==0,'invalid count');return v end
    local result={probe='offline_survival_builder_prerequisites',read_only=true,ok=false,
        accounts=J.array(),errors=J.array(),online_player_uids=J.array(),base_materials=J.array(),
        not_a_builder=true,construction_verified=false,
        material_scope='native carried inventory count and allowlisted, live-owned ordinary chests reported separately; not a complete engine consume set'}
    local online={}
    for _,pc in ipairs(instances('PalPlayerController'))do
        local ok,id=pcall(function()return R.guid_to_string(pc:GetPlayerUId())end)
        if ok and id~=ZERO then online[id]=true;result.online_player_uids[#result.online_player_uids+1]=id end
    end
    local contexts=instances('PalItemContainerManager');assert(#contexts==1,'expected one item manager')
    local wc=contexts[1]
    local utility=StaticFindObject('/Script/Pal.Default__PalUtility')
    assert(utility and utility:IsValid(),'PalUtility CDO unavailable')
    local manager=utility:GetPlayerManager(wc);assert(live(manager),'player manager unavailable')
    result.player_manager=manager:GetFullName()
    local mapman=instances('PalMapObjectManager');assert(#mapman==1,'expected one map-object manager')
    local operator=mapman[1]:GetBuildOperator();assert(live(operator)and live(operator.DataMap),'build data unavailable')
    local raw=operator.DataMap:GetById(FName('ItemChest'));assert(type(raw)=='table'and text(raw.MapObjectId)=='ItemChest','recipe mismatch')
    result.recipe={build_id='ItemChest',materials=J.array(),work_amount=num(raw.RequiredBuildWorkAmount)}
    for i=1,4 do local n=num(raw['Material'..i..'_Count']);if n>0 then
        result.recipe.materials[#result.recipe.materials+1]={item=text(raw['Material'..i..'_Id']),count=n}
    end end
    local seen={}
    for _,account in ipairs(instances('PalPlayerAccount'))do
        local row={object=account:GetFullName(),ok=false};result.accounts[#result.accounts+1]=row
        local ok,err=pcall(function()
            assert(same(account:GetOuter(),manager),'account does not belong to live player manager')
            local handle=account.IndividualHandle;assert(live(handle),'offline account handle is not loaded')
            local iid=handle:GetIndividualID();assert(type(iid)=='table','individual ID not materialized')
            row.player_uid=R.guid_to_string(iid.PlayerUId)
            row.instance_id=R.guid_to_string(iid.InstanceId)
            assert(row.player_uid~=ZERO and row.instance_id~=ZERO,'empty identity')
            assert(not seen[row.player_uid],'duplicate loaded account identity');seen[row.player_uid]=true
            row.online_controller_observed=online[row.player_uid]==true
            row.identity_source='account.IndividualHandle:GetIndividualID()'
            local tech=account.TechnologyData;local inv=account.InventoryData
            assert(live(tech)and same(tech:GetOuter(),account),'technology/account ownership mismatch')
            assert(live(inv)and same(inv:GetOuter(),account),'inventory/account ownership mismatch')
            row.technology_object=tech:GetFullName();row.inventory_object=inv:GetFullName()
            row.chest_unlocked=tech:IsUnlockBuildObject(FName('ItemChest'))
            row.chest_denied=tech:IsDeniedBuildObject(FName('ItemChest'))
            assert(type(row.chest_unlocked)=='boolean'and type(row.chest_denied)=='boolean','technology read invalid')
            row.carried_materials=J.array()
            for _,material in ipairs(result.recipe.materials)do
                row.carried_materials[#row.carried_materials+1]={item=material.item,count=num(inv:CountItemNum64(FName(material.item)))}
            end
            local guild=utility:GetGuildByPlayerUId(wc,R.guid_from_string(row.player_uid))
            assert(live(guild),'native guild lookup returned no guild')
            row.guild_id=R.guid_to_string(guild:GetId());assert(row.guild_id~=ZERO,'zero guild')
            row.guild_build_permission=guild:HasGuildPermission(R.guid_from_string(row.player_uid),4)
            assert(type(row.guild_build_permission)=='boolean','invalid guild permission')
            row.ok=true
        end)
        if not ok then row.error=tostring(err);result.errors[#result.errors+1]={object=row.object,error=row.error}end
    end
    assert(#result.accounts>0,'no loaded player accounts')
    local chests=R.chests(T,{include_items=true,verify_ownership=true,require_snapshot_ownership=true})
    assert(chests.ok and chests.verified_live,'verified chest snapshot unavailable')
    local buckets={}
    for _,c in ipairs(chests.chests)do
        assert(c.base_id_live and c.group_id_live,'missing live chest ownership')
        local b=buckets[c.base_id_live]
        if not b then b={base_id=c.base_id_live,guild_id=c.group_id_live,container_ids=J.array(),counts={}};buckets[c.base_id_live]=b end
        assert(b.guild_id==c.group_id_live,'mixed guild ownership in one base')
        b.container_ids[#b.container_ids+1]=c.id
        for _,s in ipairs(c.slots)do if not s.empty then
            for _,material in ipairs(result.recipe.materials)do if s.item==material.item then b.counts[s.item]=(b.counts[s.item]or 0)+num(s.count)end end
        end end
    end
    for _,b in pairs(buckets)do result.base_materials[#result.base_materials+1]=b end
    table.sort(result.base_materials,function(a,b)return a.base_id<b.base_id end)
    result.ok=#result.errors==0
    return result
end
return M
