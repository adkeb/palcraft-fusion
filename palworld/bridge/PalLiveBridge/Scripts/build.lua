-- BridgeLab ONLY. Palworld 1.0.5 / UE4SS 2281fa31 experimental normal-survival builder.
-- Production use is refused before accessing any game object.
-- Every public method must run on the GAME THREAD. No file I/O, async callbacks,
-- hooks, identity changes, raw offsets, free spawning or direct item mutations.
-- preview/apply initially support ONE ItemChest on an existing empty foundation.
-- All Unreal references are re-resolved per call and never stored in plans/ops.
-- M.new {json, readers, instance_id, allow_apply=false, new_id?, persist?, read_operation?}
-- persist(op) must durably commit and return true BEFORE native RPC; read_operation
-- must read the persistent idempotency journal. Runtime validation is still pending.
local MODULE_SOURCE=debug.getinfo(1,'S').source:lower():gsub('\\','/')
local LAB_SOURCE=MODULE_SOURCE:find('@d:/palworldserver-lan/bridgelab/',1,true)==1
    and MODULE_SOURCE:match('/pallivebridge/scripts/build%.lua$')~=nil
local M={version='build-lab-candidate-0.2.0',runtime_verified=false,lab_only=true}
local ZERO='00000000-0000-0000-0000-000000000000'
local function fail(c,m)error({code=c,message=m},0)end
local function check(v,c,m)if not v then fail(c,m)end end
local function finite(v)return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function integer(v,lo,hi)return finite(v)and v%1==0 and v>=lo and v<=hi end
local function uuid(v)return type(v)=='string'and #v==36 and v:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil end
local function uid(v)check(uuid(v),'invalid_request','Canonical UUID required');return v:lower()end
local function live(o)return o~=nil and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function same(a,b)return live(a)and live(b)and a:GetFullName()==b:GetFullName()end
local function text(v)if type(v)=='string'then return v end;return v:ToString()end
local function objects(class)
    local out={};for _,o in ipairs(FindAllOf(class)or{})do if live(o)then out[#out+1]=o end end;return out
end
local function one(class)local a=objects(class);check(#a==1,'backend_unavailable','Expected one '..class);return a[1]end
local function fguid(s)s=uid(s):gsub('-','');return{A=tonumber(s:sub(1,8),16),B=tonumber(s:sub(9,16),16),C=tonumber(s:sub(17,24),16),D=tonumber(s:sub(25,32),16)}end
local function vector(v)
    check(type(v)=='table'and finite(v.X)and finite(v.Y)and finite(v.Z),'backend_unavailable','FVector getter did not materialize')
    return{x=v.X,y=v.Y,z=v.Z}
end
local function distance(a,b,xy)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(xy and 0 or(a.z-b.z)^2))end
local function strict(t,keys,required)
    check(type(t)=='table','invalid_request','Expected object')
    for k in pairs(t)do check(keys[k],'invalid_request','Unknown field '..tostring(k))end
    for _,k in ipairs(required or{})do check(t[k]~=nil,'invalid_request','Missing '..k)end
end
local function canonical(v)
    local k=type(v);if k=='table'then local keys={};for x in pairs(v)do keys[#keys+1]=x end
        table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
        local r={'{'};for _,x in ipairs(keys)do r[#r+1]=canonical(x)..'='..canonical(v[x])..';'end;r[#r+1]='}';return table.concat(r)
    elseif k=='string'then return's'..#v..':'..v elseif k=='number'then check(finite(v),'backend_unavailable','Non-finite snapshot');return string.format('n%.17g',v)
    elseif k=='boolean'then return tostring(v)elseif k=='nil'then return'nil'end
    fail('backend_unavailable','Non-primitive snapshot')
end
function M.new(opts)
    check(LAB_SOURCE,'unsupported','Experimental build module is restricted to BridgeLab')
    assert(type(opts)=='table'and opts.json and opts.readers,'json/readers dependencies required')
    local J,R=opts.json,opts.readers
    local instance=uid(opts.instance_id)
    local plans,operations={},{}
    local active=nil
    local self={}
    local function arr(v)return J.array(v or{})end
    local function copy(v)return J.decode(J.encode(v,{max_bytes=33554432,max_depth=64}),{max_bytes=33554432,max_depth=64})end
    local function new_id()
        if opts.new_id then return uid(opts.new_id())end
        local lib=StaticFindObject('/Script/Engine.Default__KismetGuidLibrary')
        check(lib and lib:IsValid(),'backend_unavailable','Guid library missing');return uid(R.guid_to_string(lib:NewGuid()))
    end
    local function id(g)return uid(R.guid_to_string(g))end
    local function context(pc)
        check(live(pc)and pc:HasAuthority()and pc:IsPlayerController(),'player_unavailable','Controller is not authoritative')
        local state=pc:GetPalPlayerState()
        check(live(state)and same(state:GetPlayerController(),pc),'player_unavailable','PlayerState/controller link unavailable')
        local connection=pc.NetConnection
        check(live(connection),'player_unavailable','A real connected client is required')
        local player_id=id(pc:GetPlayerUId());check(player_id~=ZERO,'player_unavailable','Zero player identity')
        local transmitter=pc.Transmitter
        check(live(transmitter)and same(transmitter:GetOwner(),pc),'player_unavailable','Player-owned transmitter unavailable')
        local component=transmitter:GetPlayer()
        check(live(component)and same(component:GetOwner(),transmitter),'player_unavailable','Player RPC component owner mismatch')
        local pawn=pc:GetDefaultPlayerCharacter()
        check(live(pawn),'player_unavailable','Living player character unavailable')
        local guild=state.GuildBelongTo
        check(live(guild),'player_unavailable','Player guild unavailable')
        local technology=state:GetTechnologyData();local inventory=state:GetInventoryData()
        check(live(technology)and live(inventory),'player_unavailable','Player technology/inventory unavailable')
        local builder=pawn.BuilderComponent
        check(live(builder),'player_unavailable','Player builder component unavailable')
        local summary={player_uid=player_id,name=text(state:GetPlayerName()),guild_id=id(guild:GetId()),
            controller=pc:GetFullName(),player_state=state:GetFullName(),connection=connection:GetFullName(),
            transmitter=transmitter:GetFullName(),player_component=component:GetFullName(),
            pawn=pawn:GetFullName(),builder=builder:GetFullName(),position=vector(pawn:K2_GetActorLocation()),
            can_build_in_guild=guild:HasGuildPermission(fguid(player_id),4)==true,
            material_scope='selected player carried inventory only; no global/base storage assumption',
            candidate_unvalidated=true}
        return{summary=summary,pc=pc,state=state,component=component,pawn=pawn,guild=guild,technology=technology,inventory=inventory,builder=builder}
    end
    local function resolve(player_id)
        player_id=uid(player_id);local found={}
        for _,pc in ipairs(objects('PalPlayerController'))do
            local good,pid=pcall(function()return id(pc:GetPlayerUId())end)
            if good and pid==player_id then found[#found+1]=pc end
        end
        check(#found==1,'player_unavailable','Selected player must have exactly one live controller')
        return context(found[1])
    end
    function self.players()
        local out={server_instance_id=instance,players=arr(),errors=arr(),candidate_unvalidated=true}
        for _,pc in ipairs(objects('PalPlayerController'))do
            local good,c=pcall(function()
                local c=context(pc)
                c.summary.wood_carried=c.inventory:CountItemNum64(FName('Wood'))
                c.summary.stone_carried=c.inventory:CountItemNum64(FName('Stone'))
                c.summary.wood_chest_unlocked=c.technology:IsUnlockBuildObject(FName('ItemChest'))
                c.summary.wood_chest_denied=c.technology:IsDeniedBuildObject(FName('ItemChest'))
                return c
            end)
            if good then
                local row=c.summary
                out.players[#out.players+1]=row
            else out.errors[#out.errors+1]={controller=pc:GetFullName(),error=type(c)=='table'and c.message or tostring(c)}end
        end
        out.ok=#out.errors==0;table.sort(out.players,function(a,b)return a.player_uid<b.player_uid end);return out
    end
    local function request(p)
        strict(p,{player_uid=true,guild_id=true,base_id=true,structures=true},{'player_uid','guild_id','base_id','structures'})
        local out={player_uid=uid(p.player_uid),guild_id=uid(p.guild_id),base_id=uid(p.base_id),structures=arr()}
        check(type(p.structures)=='table'and #p.structures==1,'unsupported','Initial normal-build probe supports exactly one structure')
        for k in pairs(p.structures)do check(k==1,'invalid_request','Structures must be a one-element array')end
        for _,s in ipairs(p.structures)do
            strict(s,{build_id=true,position=true,rotation=true,support_model_id=true},{'build_id','position','rotation','support_model_id'})
            check(s.build_id=='ItemChest','unsupported','Only the initial ItemChest normal-build path is enabled')
            strict(s.position,{x=true,y=true,z=true},{'x','y','z'});strict(s.rotation,{pitch=true,yaw=true,roll=true},{'pitch','yaw','roll'})
            for _,v in pairs(s.position)do check(finite(v)and math.abs(v)<=10000000,'invalid_request','Position outside bounds')end
            check(s.rotation.pitch==0 and s.rotation.roll==0 and finite(s.rotation.yaw)and math.abs(s.rotation.yaw)<=360,'invalid_request','Initial chest path permits upright yaw rotation only')
            out.structures[1]={build_id=s.build_id,position=copy(s.position),rotation=copy(s.rotation),support_model_id=uid(s.support_model_id)}
        end
        return out
    end
    local function get_base(base_id)
        local report=R.bases();check(report.ok,'backend_unavailable','Base reader failed')
        for _,b in ipairs(report.bases)do if b.id==base_id then check(b.ok and b.available,'base_unavailable','Base unavailable');return b end end
        fail('not_found','Base not found')
    end
    local function recipe(build_id)
        local manager=one('PalMapObjectManager');local operator=manager:GetBuildOperator()
        check(live(operator)and live(operator.DataMap),'backend_unavailable','Build data map unavailable')
        local data=operator.DataMap:GetById(FName(build_id))
        check(type(data)=='table'and text(data.MapObjectId)==build_id,'backend_unavailable','Build recipe missing or mismatched')
        local out={build_id=build_id,materials=arr(),work_amount=data.RequiredBuildWorkAmount,
            max_per_base=data.InstallMaxNumInBaseCamp,only_indoors=data.bIsInstallOnlyInDoor,
            only_hub_around=data.bIsInstallOnlyHubAround,neighbor_threshold=data.InstallNeighborThreshold}
        check(out.only_indoors==false and out.only_hub_around==false,'unsupported','Unsupported recipe placement restriction')
        for i=1,4 do local count=data['Material'..i..'_Count'];check(integer(count,0,1000000),'backend_unavailable','Invalid recipe count')
            if count>0 then out.materials[#out.materials+1]={item=text(data['Material'..i..'_Id']),count=count}end end
        check(#out.materials>0,'unsupported','Zero-cost recipe rejected');return out,manager
    end
    local function world_models()
        local out=arr();local manager=one('PalMapObjectManager')
        for _,model in ipairs(objects('PalMapObjectModel'))do
            local concrete=model:GetConcreteModel(false)
            if live(concrete)then
                -- GetModelInstanceId is a scalar GUID read. Other concrete getters
                -- may Fatal if the backing model was removed but UObject is alive.
                local gid=concrete:GetModelInstanceId()
                local registered=manager:FindModel(gid)
                local linked=live(registered)and registered:GetConcreteModel(false)or nil
                if same(registered,model)and same(linked,concrete)then
                local process=model.BuildProcess
                out[#out+1]={instance_id=id(concrete:GetModelInstanceId()),build_id=text(model.BuildObjectId),
                    base_id=id(concrete:GetBaseCampIdBelongTo()),position=vector(concrete:GetTransform().Translation),
                    build_player_uid=id(model:GetBuildPlayerUId_BP()),
                    construction_complete=live(process)and process:IsCompleted()or false}
                end
            end
        end
        table.sort(out,function(a,b)return a.instance_id<b.instance_id end);return out
    end
    local function inventory_snapshot()
        local mgr=one('PalItemContainerManager');local out={containers=arr(),totals={}};local seen={}
        for _,c in ipairs(objects('PalItemContainer'))do
            local cid=c:GetId();local container_id=id(cid.ID);local authoritative=mgr:GetContainer(cid)
            if same(c,authoritative)then
                check(not seen[container_id],'backend_unavailable','Duplicate canonical container');seen[container_id]=true
                local capacity=c:Num();check(integer(capacity,0,1000),'backend_unavailable','Unexpected container size')
                local row={id=container_id,capacity=capacity,slots=arr()};out.containers[#out.containers+1]=row
                for i=0,capacity-1 do local slot=c:Get(i);check(live(slot),'backend_unavailable','Missing item slot')
                    local n=slot:GetStackCount();check(integer(n,0,2147483647),'backend_unavailable','Invalid stack count')
                    if n>0 then local item=slot:GetItemId();local static=text(item.StaticId)
                        row.slots[#row.slots+1]={index=i,item=static,count=n,dynamic_guid=id(item.DynamicId.LocalIdInCreatedWorld),dynamic_world_guid=id(item.DynamicId.CreatedWorldId)}
                        out.totals[static]=(out.totals[static]or 0)+n
                    end
                end
            end
        end
        check(#out.containers>0 and #out.containers<=10000,'backend_unavailable','Unexpected world inventory coverage')
        table.sort(out.containers,function(a,b)return a.id<b.id end);return out
    end
    local function inspect(p)
        local c=resolve(p.player_uid);local b=get_base(p.base_id);local s=p.structures[1]
        check(c.summary.guild_id==p.guild_id and b.group_id==p.guild_id,'forbidden','Player and base must belong to selected guild')
        check(c.summary.can_build_in_guild,'forbidden','Player lacks guild BuildConstruct permission')
        check(c.technology:IsUnlockBuildObject(FName(s.build_id))==true and c.technology:IsDeniedBuildObject(FName(s.build_id))==false,'technology_locked','Selected player has not unlocked this structure')
        local r,manager=recipe(s.build_id)
        local base_distance=distance(s.position,b.position,true)
        check(base_distance<b.range-200,'invalid_placement','Structure too close to/outside base boundary')
        check(distance(c.summary.position,b.position,true)<b.range-100,'player_unavailable','Selected player must stand inside this base')
        check(distance(s.position,c.summary.position,false)<=1500,'invalid_placement','Selected player must stand within 15 metres of placement')
        local support=manager:FindModel(fguid(s.support_model_id));check(live(support),'invalid_placement','Support model no longer exists')
        check(text(support.BuildObjectId)=='Wooden_foundation','unsupported','Initial placement requires a wooden foundation')
        local concrete=support:GetConcreteModel(false);check(live(concrete),'invalid_placement','Support concrete model not loaded')
        check(id(concrete:GetModelInstanceId())==s.support_model_id and same(manager:FindModel(concrete:GetModelInstanceId()),support),
            'invalid_placement','Support is not registered under its concrete model ID')
        check(id(concrete:GetBaseCampIdBelongTo())==p.base_id,'invalid_placement','Support belongs to another base')
        local sp=vector(concrete:GetTransform().Translation)
        check(distance(s.position,sp,true)<=100 and math.abs(s.position.z-sp.z)<=150,'invalid_placement','Place near the selected foundation centre')
        local nearby=arr();local all=world_models();local count=0
        for _,m in ipairs(all)do
            if m.base_id==p.base_id and m.build_id==s.build_id then count=count+1 end
            local d=distance(m.position,s.position,true)
            if d<3000 then nearby[#nearby+1]=m end
            if not m.build_id:lower():find('foundation',1,true)then
                check(d>=1000 or math.abs(m.position.z-s.position.z)>1000,'invalid_placement','Nearby structure requires manual placement review')
            end
        end
        if r.max_per_base and r.max_per_base>0 then check(count<r.max_per_base,'invalid_placement','Per-base structure limit reached')end
        local materials=arr()
        for _,m in ipairs(r.materials)do local n=c.inventory:CountItemNum64(FName(m.item))
            check(integer(n,0,9007199254740991),'backend_unavailable','Invalid carried material count')
            materials[#materials+1]={item=m.item,required=m.count,carried=n,sufficient=n>=m.count}
            check(n>=m.count,'insufficient_materials','Carry the required '..m.item..' on the selected player for the initial validated path')
        end
        local observation={player=c.summary,base=b,recipe=r,materials=materials,support={id=s.support_model_id,position=sp},nearby=nearby}
        return observation,c,all
    end
    local function summary(op)
        return{operation_id=op.operation_id,plan_id=op.plan_id,status=op.status,server_instance_id=op.server_instance_id,
            request_returned=op.request_returned,error=op.error,delta=op.delta,
            normal_survival_rules_verified=false,persistence_verified=false,client_replication_verified=false}
    end
    local function persist(op)
        check(type(opts.persist)=='function'and opts.persist(copy(op))==true,'journal_failed','Durable operation journal is required')
    end
    function self.preview(params)
        local p=request(params);local observed=inspect(p);local pid=new_id();local rev=new_id()
        local plan={plan_id=pid,expected_revision=rev,server_instance_id=instance,created_at=os.time(),expires_at=os.time()+60,
            request=p,observation=observed,status='preview',placement_verified=false,normal_survival_rules_verified=false,
            apply_enabled=opts.allow_apply==true,limitations=arr({'Initial path requires carried materials; base/guild storage availability is not inferred.',
                'Position checks are conservative geometry checks, not complete native collision validation.',
                'Normal RequestBuild RPC must create the construction site and consume materials; workers/player complete the build normally.'})}
        plans[pid]=copy(plan);return copy(plan)
    end
    function self.apply(params)
        strict(params,{plan_id=true,expected_revision=true,idempotency_key=true},{'plan_id','expected_revision','idempotency_key'})
        local key=uid(params.idempotency_key)
        local existing=operations[key]
        if not existing and type(opts.read_operation)=='function'then existing=opts.read_operation(key)end
        if existing then check(existing.plan_id==params.plan_id,'idempotency_conflict','Key already belongs to another plan');return summary(existing)end
        check(opts.allow_apply==true,'unsupported','Normal build execution is not enabled in this runtime')
        check(type(opts.persist)=='function'and type(opts.read_operation)=='function','journal_failed','Persistent idempotency journal required')
        check(active==nil,'busy','Another build is awaiting verification')
        local p=plans[params.plan_id];check(p~=nil and p.server_instance_id==instance,'stale_plan','Plan missing or from another server instance')
        check(p.status=='preview'and p.expected_revision==params.expected_revision and os.time()<p.expires_at,'stale_plan','Plan consumed, expired or revision mismatch')
        local fresh,c,models=inspect(p.request)
        check(canonical(fresh)==canonical(p.observation),'stale_plan','Player, materials or placement changed; preview again')
        local op={operation_id=key,plan_id=p.plan_id,server_instance_id=instance,status='prepared',created_at=os.time(),
            request=copy(p.request),observation=copy(fresh),before={inventory=inventory_snapshot(),models=models,base_building_count=fresh.base.building_count}}
        persist(op) -- no native call unless this completes successfully
        operations[key]=op;p.status='consumed';active=key
        op.status='submitted'
        local journal_ok,journal_error=pcall(persist,op)
        if not journal_ok then
            op.status='not_submitted_journal_error';op.error=type(journal_error)=='table'and journal_error.message or tostring(journal_error)
            active=nil;return summary(op)
        end -- unknown outcomes must never be retried
        local s=p.request.structures[1];local half=math.rad(s.rotation.yaw)*0.5
        local good,err=pcall(function()c.component:RequestBuild_ToServer(FName(s.build_id),
            {X=s.position.x,Y=s.position.y,Z=s.position.z},{X=0,Y=0,Z=math.sin(half),W=math.cos(half)}, {},{bNotConsumeMaterials=false})end)
        op.request_returned=good;op.submitted_at=os.time()
        if not good then op.error=tostring(err);op.status='outcome_unknown'end
        persist(op);return summary(op)
    end
    function self.tick()
        if not active then return end
        local op=operations[active];if not op.submitted_at or os.time()-op.submitted_at<2 then return end
        if op.last_audit_at==os.time()then return end;op.last_audit_at=os.time()
        local good,err=pcall(function()
            local after={inventory=inventory_snapshot(),models=world_models(),base_building_count=get_base(op.request.base_id).building_count}
            local old={};for _,m in ipairs(op.before.models)do old[m.instance_id]=true end
            local s=op.request.structures[1];local new=arr()
            for _,m in ipairs(after.models)do if not old[m.instance_id]and m.build_id==s.build_id and distance(m.position,s.position,false)<100 then new[#new+1]=m end end
            local delta={materials={},new_models=new,base_building_count=after.base_building_count-op.before.base_building_count,exact_recipe_cost=true}
            local keys={};for k in pairs(op.before.inventory.totals)do keys[k]=true end;for k in pairs(after.inventory.totals)do keys[k]=true end
            local expected={};for _,m in ipairs(op.observation.recipe.materials)do expected[m.item]=(expected[m.item]or 0)-m.count end
            for k in pairs(keys)do local n=(after.inventory.totals[k]or 0)-(op.before.inventory.totals[k]or 0)
                if n~=0 then delta.materials[k]=n end
                if n~=(expected[k]or 0)then delta.exact_recipe_cost=false end
            end
            local owned=#new==1 and new[1].build_player_uid==op.request.player_uid and new[1].base_id==op.request.base_id
            op.delta=delta
            if owned and delta.exact_recipe_cost and delta.base_building_count==1 then
                op.status='observed_success';op.after=after;active=nil
            elseif os.time()-op.submitted_at>=10 then op.status='outcome_unknown';op.after=after;active=nil end
            persist(op)
        end)
        if not good then op.status='outcome_unknown';op.error=type(err)=='table'and err.message or tostring(err);active=nil;persist(op)end
    end
    function self.get(operation_id)
        local key=uid(operation_id);local op=operations[key]
        if not op and type(opts.read_operation)=='function'then op=opts.read_operation(key)end
        check(op~=nil,'not_found','Operation unknown; absence is not proof it never ran');return summary(op)
    end
    return self
end
return M
