-- Isolated Lab only. One exact normal RPC, root-armed after reviewed preview. No automatic retry.
local source=debug.getinfo(1,'S').source
local directory=assert(source:match('^@(.*[/\\])'))
assert(directory:lower():gsub('\\','/')=='d:/palworldserver-lan/bridgelab/pal/binaries/win64/ue4ss/mods/pallivebridge/scripts/','BridgeLab only')
local ROOT='D:/PalworldServer-LAN/BridgeLab/rpc/'
local J=dofile(directory..'json.lua');local R=dofile(directory..'readers.lua')
local B=dofile(directory..'build.lua');local Detail=dofile(directory..'registered-model-details-core.lua')
local Materials=dofile(directory..'normal-rebuild-materials.lua');local Core=dofile(directory..'normal-rebuild-execute-core.lua')
local C={player_uid='22222222-0000-0000-0000-000000000000',base_id='00000000-0000-4000-8000-000000000031',guild_id='00000000-0000-4000-8000-00000000001b',
    old_model_id='00000000-0000-4000-8000-000000000030',old_container_id='00000000-0000-4000-8000-00000000002a',manual_observation_id='00000000-0000-4000-8000-00000000002d',
    position={X=-308391.0111896781,Y=189594.97191406583,Z=3330.3418362220582},rotation={X=0,Y=0,Z=-0.93070700155921648,W=0.3657656042449216}}
local function read(p,max)local f=assert(io.open(p,'rb'));local s=f:read(max+1);f:close();assert(#s<=max,'oversized input');return J.decode(s,{max_bytes=max})end
local cfg=read(ROOT..'normal-rebuild-once-arm.json',8192)
assert(type(cfg.nonce)=='string'and cfg.nonce:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'invalid nonce')
assert(cfg.mode=='preview'or cfg.mode=='execute','unknown mode')
local capture=read(ROOT..'manual-build-observation-'..C.manual_observation_id..'.json',1048576)
assert(capture.status=='complete'and capture.target_player_uid==C.player_uid and #capture.errors==0,'manual capture invalid')
local request=capture.request
assert(request.build_id=='ItemChest'and #request.archives==0 and request.archive_total_bytes==0 and request.debug.bNotConsumeMaterials==false,'manual request differs')
for k,v in pairs(C.position)do assert(math.abs(request.location[k]-v)<0.000001,'manual position differs')end
for k,v in pairs(C.rotation)do assert(math.abs(request.rotation[k]-v)<0.000000000001,'manual rotation differs')end
local manual=read(ROOT..'registered-model-details-00000000-0000-4000-8000-000000000018.json',1048576)
assert(manual.ok and manual.registered and manual.model_id==C.old_model_id and manual.base_id==C.base_id and manual.guild_id==C.guild_id and manual.build_player_uid==C.player_uid,'manual model evidence differs')
local baseline=read(ROOT..'normal-rebuild-nearby-baseline.json',65536)
assert(baseline.source_save_sha256=='2e91cded2333ee1e33700baf83aa85e05d987f631447f5fd5e93e9b5bf597344'and baseline.base_id==C.base_id and #baseline.nearest_10==10,'manual-time saved neighborhood evidence differs')
local targets={snapshot_sha256='fixed-oldbase-subset',chests={}}
for _,t in ipairs(dofile(directory..'targets.lua').chests)do if t.base_id==C.base_id then assert(t.group_id==C.guild_id,'target guild mismatch');targets.chests[#targets.chests+1]=t end end
assert(#targets.chests==13,'expected exactly the original old-base 13 ordinary chests')
local output=ROOT..'normal-rebuild-once-'..cfg.nonce..'.json'
local FENCE=ROOT..'normal-rebuild-once.intent.json'
local function exists(p)local f=io.open(p,'rb');if f then f:close();return true end;return false end
if exists(output)then print('[NormalRebuildOnce] Existing report; no replay\n');return end
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function same(a,b)return live(a)and live(b)and a:GetFullName()==b:GetFullName()end
local function text(v)return type(v)=='string'and v or v:ToString()end
local function finite(n)assert(type(n)=='number'and n==n and math.abs(n)<math.huge,'nonfinite number');return n end
local function vec(v)return{X=finite(v.X),Y=finite(v.Y),Z=finite(v.Z)}end
local function quat(v)local q=vec(v);q.W=finite(v.W);return q end
local function propid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
local function static(full)local o=StaticFindObject(assert(full:match('^[^ ]+ (.*)$')));assert(live(o)and o:GetFullName()==full,'named live object missing');return o end
local function manager()return static(manual.manager)end
local function base()local b=static(manual.base_object);assert(R.guid_to_string(b:GetId())==C.base_id and R.guid_to_string(b:GetGroupIdBelongTo())==C.guild_id and b:IsAvailable(),'base identity mismatch');return b end
local function distance(a,b,xy)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(xy and 0 or(a.Z-b.Z)^2))end
local function unwrap(v)
    if type(v)=='userdata'then local ok,f=pcall(function()return v.get end);if ok and type(f)=='function'then return v:get()end end
    if type(v)=='table'and type(v.get)=='function'then return v:get()end;return v
end
local function resolve(expected)
    local status=B.new{json=J,readers=R,instance_id=cfg.nonce,allow_apply=false}.players()
    assert(status.ok and #status.errors==0 and #status.players==1,'exactly one healthy connected Lab player required')
    local p=status.players[1];assert(p.player_uid==C.player_uid and p.guild_id==C.guild_id and p.can_build_in_guild and p.wood_chest_unlocked and not p.wood_chest_denied,'UID/guild/technology permission mismatch')
    if expected then for _,k in ipairs({'controller','player_state','connection','transmitter','player_component','pawn','builder'})do assert(p[k]==expected[k],'real client identity changed: '..k)end end
    local pc=static(p.controller);local state=static(p.player_state);local tr=static(p.transmitter);local component=static(p.player_component)
    assert(same(state:GetPlayerController(),pc)and same(pc:GetPalPlayerState(),state)and same(tr:GetOwner(),pc)and same(component:GetOwner(),tr),'real client ownership chain changed')
    assert(R.guid_to_string(pc:GetPlayerUId())==C.player_uid,'live player UID changed')
    local inventory=state:GetInventoryData();assert(live(inventory),'player inventory unavailable')
    return{summary=p,inventory=inventory,state=state,component=component}
end
local function item_manager()
    local found={};for _,o in ipairs(FindAllOf('PalItemContainerManager')or{})do if live(o)then found[#found+1]=o end end
    assert(#found==1,'expected one item manager');return found[1]
end
local function materials(ctx)
    local c=resolve(ctx and ctx.summary)
    return Materials.read{json=J,readers=R,targets=targets,inventory=c.inventory,state=c.state,player_uid=C.player_uid,item_manager=item_manager(),fname=function(v)return FName(v)end}
end
local function site_snapshot()
    local mgr,b=manager(),base();local collection=b.MapObjectCollection;assert(live(collection),'base collection missing')
    local array=collection.MapObjectInstanceIdRepInfoArray.Items
    local count=array:GetArrayNum();assert(type(count)=='number'and count%1==0 and count>0 and count<=500,'base ID array must contain 1..500 items')
    local out={collection=collection:GetFullName(),collection_count=count,models=J.array(),unavailable=J.array(),nearby=J.array(),old_manual_model_absent=not live(mgr:FindModel(R.guid_from_string(C.old_model_id)))}
    local seen={}
    for i=1,count do
        local entry=unwrap(array[i]);local id=propid(entry.InstanceId);assert(not seen[id],'duplicate base collection ID');seen[id]=true
        local model=mgr:FindModel(R.guid_from_string(id))
        if not live(model)then out.unavailable[#out.unavailable+1]=id
        else
            assert(propid(model.InstanceId)==id,'registered property ID differs')
            local kind=text(model.BuildObjectId)
            if kind~='None'and kind~=''and not kind:match('^CommonDrop')and not kind:match('^Damagable')and not kind:match('^PickupItem')then
                assert(propid(model.BaseCampIdBelongTo)==C.base_id,'collection model base differs')
                local row={id=id,build_id=kind,guild_id=propid(model.GroupIdBelongTo),builder_uid=propid(model.BuildPlayerUId)}
                local cm=model:GetConcreteModel(false)
                if live(cm)then
                    local gid=cm:GetModelInstanceId()
                    assert(R.guid_to_string(gid)==id and same(mgr:FindModel(gid),model)and same(model:GetConcreteModel(false),cm)and cm.bDisposed==false,'concrete registration mismatch')
                    row.concrete_id=R.guid_to_string(cm:GetInstanceId())
                    local transform=cm:GetTransform();row.position=vec(transform.Translation);row.rotation=quat(transform.Rotation);row.position_source='registered_concrete'
                else row.position=vec(model.InitialTransformCache.Translation);row.rotation=quat(model.InitialTransformCache.Rotation);row.position_source='model_initial_cache_only'end
                row.distance_from_manual_cm=distance(row.position,C.position,false)
                out.models[#out.models+1]=row
                if row.distance_from_manual_cm<2000 then out.nearby[#out.nearby+1]=row end
            end
        end
    end
    table.sort(out.models,function(a,b)return a.id<b.id end);table.sort(out.nearby,function(a,b)return a.distance_from_manual_cm<b.distance_from_manual_cm end)
    out.base_building_count=b:GetBuildingNum();out.base_position=vec(b:GetTransform().Translation);out.base_range=finite(b:GetRange())
    return out
end
local function write_json(p,value,replace)
    local raw=J.encode(value,{max_bytes=16777216});local f=assert(io.open(p..'.tmp','wb'));assert(f:write(raw));assert(f:flush());assert(f:close())
    local check=assert(io.open(p..'.tmp','rb'));assert(check:read('*a')==raw,'journal readback mismatch');check:close()
    if replace then os.remove(p)else assert(not exists(p),'nonreplace journal already exists')end
    assert(os.rename(p..'.tmp',p),'journal rename failed')
end
local function assert_site_unchanged(previous,current)
    assert(current.old_manual_model_absent,'manual chest is still registered')
    assert(#current.unavailable==0,'base collection has unregistered IDs; cannot prove stable scope')
    assert(J.encode(previous.models)==J.encode(current.models),'base structure fingerprint changed before submission')
    assert(previous.collection==current.collection and previous.base_building_count==current.base_building_count,'base collection/count changed')
    for _,row in ipairs(current.nearby)do
        if row.distance_from_manual_cm<500 then
            assert(row.position_source=='registered_concrete','nearby structure has only an initial position cache')
            assert(row.distance_from_manual_cm>=200,'another registered structure is too close to the exact manual position')
        end
    end
end
local function verify_manual_neighborhood(site)
    local byid={};for _,row in ipairs(site.models)do byid[row.id]=row end
    local verified=J.array();local expected_inner={};local expected_inner_count=0
    for _,saved in ipairs(baseline.nearest_10)do if saved.id~=C.old_model_id then
        local row=assert(byid[saved.id],'manual-time neighbor no longer registered in base')
        assert(row.position_source=='registered_concrete'and row.concrete_id==saved.concrete_id,'manual-time neighbor concrete identity changed')
        assert(row.build_id==saved.type and row.guild_id==saved.guild_id,'manual-time neighbor type/guild changed')
        local point={X=saved.location.x,Y=saved.location.y,Z=saved.location.z}
        local distance_cm=distance(row.position,point,false);assert(distance_cm<=2,'manual-time neighbor moved')
        local expected={X=saved.rotation.x,Y=saved.rotation.y,Z=saved.rotation.z,W=saved.rotation.w}
        local direct,opposite=0,0;for k,v in pairs(expected)do direct=math.max(direct,math.abs(row.rotation[k]-v));opposite=math.max(opposite,math.abs(row.rotation[k]+v))end
        assert(math.min(direct,opposite)<0.000001,'manual-time neighbor rotation changed')
        verified[#verified+1]={id=row.id,distance_from_saved_cm=distance_cm,concrete_id=row.concrete_id}
        if saved.distance_3d<1190 then expected_inner[saved.id]=saved.type;expected_inner_count=expected_inner_count+1 end
    end end
    assert(#verified==9,'expected 9 preserved neighboring structures')
    assert(expected_inner_count==8,'manual-time inner neighborhood differs')
    local inner_count=0
    for _,row in ipairs(site.models)do if row.id~=C.old_model_id and row.distance_from_manual_cm<1190 then
        assert(expected_inner[row.id]==row.build_id,'new or different structure inside the historical 11.9m neighborhood')
        inner_count=inner_count+1
    end end
    assert(inner_count==8,'historical inner structure count changed')
    return{source_save_sha256=baseline.source_save_sha256,verified=verified,inner_radius_cm=1190,inner_registered_structure_count=inner_count,
        scope='saved neighbor identities and transforms; not a terrain/support or collision proof'}
end
local runner
local hooks={}
local function cleanup()
    for _,h in ipairs(hooks)do UnregisterHook(h.name,h.pre,h.post)end
    hooks={}
end
local deps={json=J,now=os.time,is_game_thread=IsInGameThread,has_fence=function()return exists(FENCE)end,
    emit=function(report)write_json(output,report,true)end,cleanup=cleanup,
    material_diff=Materials.diff,read_materials=materials,
    preflight=function()
        local ctx=resolve();local site=site_snapshot();local p={X=ctx.summary.position.x,Y=ctx.summary.position.y,Z=ctx.summary.position.z}
        assert(distance(C.position,site.base_position,true)<site.base_range-200 and distance(p,site.base_position,true)<site.base_range-100,'player/manual point must remain inside old base')
        assert(distance(C.position,p,false)<=1500,'player must stand within 15m of exact manual point')
        local op=manager():GetBuildOperator();assert(live(op)and live(op.DataMap),'build recipe unavailable')
        local r=op.DataMap:GetById(FName('ItemChest'));assert(r.RequiredBuildWorkAmount==1000,'recipe work differs')
        local recipe={};for i=1,4 do local n=r['Material'..i..'_Count'];if n>0 then recipe[text(r['Material'..i..'_Id'])]=n end end
        assert(recipe.Wood==15 and recipe.Stone==5,'recipe material differs');for id in pairs(recipe)do assert(id=='Wood'or id=='Stone','unexpected recipe ingredient')end
        local neighborhood=verify_manual_neighborhood(site);local m=materials(ctx)
        if cfg.mode=='execute'then assert_site_unchanged(site,site)end
        return{live_context_verified=true,tech_guild_base_verified=true,old_manual_model_absent=site.old_manual_model_absent,
            context=ctx.summary,site=site,manual_neighborhood=neighborhood,materials=m,materials_sufficient=m.totals.Wood>=15 and m.totals.Stone>=5,
            recipe={Wood=15,Stone=5,work=1000},fixed_request={build_id='ItemChest',location=C.position,rotation=C.rotation,archives=J.array(),debug={bNotConsumeMaterials=false}},
            placement_precheck='Exact successfully built manual position only; native server remains responsible for current collision, ground and support validation.'}, {summary=ctx.summary,site=site}
    end,
    claim_intent=function(report)write_json(FENCE,report,false);return true end,
    final_check=function(ctx)
        assert(IsInGameThread()and os.time()<cfg.expires_unix,'submission expired or wrong thread')
        local c=resolve(ctx.summary);local site=site_snapshot();assert_site_unchanged(ctx.site,site);verify_manual_neighborhood(site)
        local p={X=c.summary.position.x,Y=c.summary.position.y,Z=c.summary.position.z}
        assert(distance(C.position,p,false)<=1500 and distance(p,site.base_position,true)<site.base_range-100,'player moved outside allowed placement range')
        return true
    end,
    submit=function(ctx)
        assert(IsInGameThread()and exists(FENCE),'native call requires persisted intent and game thread')
        local c=resolve(ctx.summary)
        -- The only gameplay mutation in this probe. Exact normal client payload;
        -- no owner changes, free spawn, item edits, work completion or refund code.
        c.component:RequestBuild_ToServer(FName('ItemChest'),
            {X=C.position.X,Y=C.position.Y,Z=C.position.Z},
            {X=C.rotation.X,Y=C.rotation.Y,Z=C.rotation.Z,W=C.rotation.W},{},{bNotConsumeMaterials=false})
    end,
    observe=function(before,ctx)
        local site=site_snapshot();local old,seen={},{};local new,missing=J.array(),J.array()
        for _,m in ipairs(before.site.models)do old[m.id]=true end
        for _,m in ipairs(site.models)do seen[m.id]=true;if not old[m.id]then new[#new+1]=m.id end end
        for id in pairs(old)do if not seen[id]then missing[#missing+1]=id end end
        local out={new_models=new,missing_models=missing,base_building_count=site.base_building_count,materials=materials(ctx),unavailable=site.unavailable}
        if #new==1 then
            local detail=Detail.read({json=J,readers=R,now=os.time,is_game_thread=IsInGameThread,fname=FName,manager=manager},
                {model_id=new[1],expected_base_id=C.base_id,expected_guild_id=C.guild_id,expected_player_uid=C.player_uid,expected_location=C.position})
            if detail.ok then
                local q=detail.transform.Rotation
                local direct,opposite=0,0
                for k,v in pairs(C.rotation)do direct=math.max(direct,math.abs(q[k]-v));opposite=math.max(opposite,math.abs(q[k]+v))end
                detail.rotation_matches=math.min(direct,opposite)<0.00000001
                if not detail.rotation_matches or detail.distance_from_expected_cm>2 then detail.ok=false;detail.errors[#detail.errors+1]={stage='request_match',error='new model transform differs from captured request'}end
                if detail.build_process.available and detail.build_process.completed then
                    local c=detail.container
                    if not(c.module_available and c.available and c.capacity==10 and c.id~='00000000-0000-0000-0000-000000000000'and c.id~=C.old_container_id)then
                        detail.ok=false;detail.errors[#detail.errors+1]={stage='completed_container',error='completed wooden chest has no verified new 10-slot container'}
                    end
                end
            end
            out.candidate=detail
        end
        return out
    end}
runner=Core.new(deps,cfg)
local function register(name,pre,post)
    local a,b=RegisterHook(name,pre,post);hooks[#hooks+1]={name=name,pre=a,post=b}
end
local function active()return runner.report.submitted_unix~=nil and runner.report.finished_unix==nil end
local function model_event(model)
    if not active()or not live(model)then return end
    assert(IsInGameThread(),'model observer outside game thread')
    local id=propid(model.InstanceId);local mgr=manager()
    if not same(mgr:FindModel(R.guid_from_string(id)),model)then return end
    if text(model.BuildObjectId)~='ItemChest'or propid(model.BaseCampIdBelongTo)~=C.base_id
        or propid(model.GroupIdBelongTo)~=C.guild_id or propid(model.BuildPlayerUId)~=C.player_uid then return end
    local cm=model:GetConcreteModel(false)
    if not live(cm)or R.guid_to_string(cm:GetModelInstanceId())~=id or not same(mgr:FindModel(cm:GetModelInstanceId()),model)then return end
    local event={model_id=id,source='native_model_event',observed_unix=os.time()}
    local process=model.BuildProcess
    if live(process)then event.state=finite(process.State);local work=process.BuildWork
        if live(work)then
            event.required_work=finite(work.RequiredWorkAmount);event.current_work=finite(work.CurrentWorkAmount)
            event.work_id=propid(work.ID);event.work_owner_model=propid(work.OwnerMapObjectModelId)
            event.work_owner_concrete=propid(work.OwnerMapObjectConcreteModelId);event.work_base_id=propid(work.BaseCampIdBelongTo)
            event.work_binding_verified=event.work_owner_model==id and event.work_owner_concrete==R.guid_to_string(cm:GetInstanceId())and event.work_base_id==C.base_id
            if not event.work_binding_verified then event.work_owner_mismatch=true;event.required_work=nil;event.current_work=nil end
        end
    end
    runner.on_model(event)
end
if cfg.mode=='execute'then
    local ok,e=pcall(function()
        register('/Script/Pal.PalNetworkPlayerComponent:RequestBuild_ToServer',function(context,build,location,rotation,archives,debugparam)
            if not active()then return end
            local good,event=pcall(function()
                assert(IsInGameThread(),'request observer outside game thread')
                local o=unwrap(context);local name=runner.report.before.context.player_component
                local b=text(unwrap(build));local p=unwrap(location);local q=unwrap(rotation);local a=unwrap(archives);local dbg=unwrap(debugparam)
                local count=type(a)=='table'and #a or a:GetArrayNum()
                local matches=live(o)and o:GetFullName()==name and b=='ItemChest'and count==0 and dbg.bNotConsumeMaterials==false
                for k,v in pairs(C.position)do matches=matches and math.abs(p[k]-v)<0.000001 end
                for k,v in pairs(C.rotation)do matches=matches and math.abs(q[k]-v)<0.000000000001 end
                return{matches_fixed_request=matches}
            end)
            runner.on_request(good and event or{matches_fixed_request=false,error=tostring(event)})
            -- nil return: never change any argument or override the original RPC.
        end)
        register('/Script/Pal.PalBaseCampMapObjectCollection:OnAvailableConcreteModel_ServerInternal',function()end,function(context,param)
            if not active()then return end
            local ok,event_error=pcall(function()
                assert(IsInGameThread(),'collection observer outside game thread')
                local collection=unwrap(context)
                if not live(collection)or collection:GetFullName()~=runner.report.before.site.collection then return end
                local cm=unwrap(param);if not live(cm)then return end
                local model=manager():FindModel(cm:GetModelInstanceId())
                if live(model)and same(model:GetConcreteModel(false),cm)then model_event(model)end
            end)
            if not ok then runner.report.errors[#runner.report.errors+1]={stage='model_event',error=tostring(event_error)}end
        end)
        register('/Script/Pal.PalMapObjectModel:OnUpdateBuildProcess_ServerInternal',function()end,function(context)
            if not active()then return end
            local ok,e=pcall(model_event,unwrap(context));if not ok then runner.report.errors[#runner.report.errors+1]={stage='build_process_event',error=tostring(e)}end
        end)
    end)
    if not ok then cleanup();error('observer registration failed before build: '..tostring(e))end
end
ExecuteInGameThread(function()runner.start();print('[NormalRebuildOnce] '..runner.report.status..'\n')end)
if cfg.mode=='execute'then
    local queued=false
    LoopAsync(250,function()
        if runner.report.finished_unix then return true end
        if not queued then queued=true;ExecuteInGameThread(function()
            local ok,e=pcall(runner.tick);queued=false
            if not ok then
                cleanup();runner.report.status='indeterminate_no_retry';runner.report.finished_unix=os.time()
                runner.report.errors[#runner.report.errors+1]={stage='tick_uncaught',error=tostring(e)};deps.emit(runner.report)
            end
        end)end
        return false
    end)
end
return runner
