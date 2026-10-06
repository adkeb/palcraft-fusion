-- BridgeLab only. Fresh explicitly superseding operation, one normal RPC, no hooks.
local source=debug.getinfo(1,'S').source
local directory=assert(source:match('^@(.*[/\\])'))
assert(directory:lower():gsub('\\','/')=='d:/palworldserver-lan/bridgelab/pal/binaries/win64/ue4ss/mods/pallivebridge/scripts/','BridgeLab only')
local ROOT='D:/PalworldServer-LAN/BridgeLab/rpc/'
local J=dofile(directory..'json.lua');local R=dofile(directory..'readers.lua')
local B=dofile(directory..'build.lua');local Materials=dofile(directory..'normal-rebuild-materials.lua')
local Site=dofile(directory..'full-observer-readonly-v3-core.lua');local Detail=dofile(directory..'registered-model-details-core.lua')
local Core=dofile(directory..'hook-free-rebuild-v4-core.lua')
local C={player_uid='22222222-0000-0000-0000-000000000000',base_id='00000000-0000-4000-8000-000000000031',guild_id='00000000-0000-4000-8000-00000000001b',
    old_model_id='00000000-0000-4000-8000-000000000030',old_container_id='00000000-0000-4000-8000-00000000002a',
    failed_nonce='00000000-0000-4000-8000-000000000017',old_intent_sha256='70bbd8cb31fe0d7326db4983cfeee20682e39bc584cd648de1695616a060c2d5',
    recovery_sha256='24311965be663d033ece0705826c3ce81cb4c065deb81465c8d233db99afacbf',
    recovery_save_sha256='0724ac39ec482689591fb7fd700677cc3043d8a7133e43f53592a157a0f5801d',
    position={X=-308391.0111896781,Y=189594.97191406583,Z=3330.3418362220582},rotation={X=0,Y=0,Z=-0.93070700155921648,W=0.3657656042449216}}
local function raw_read(path,max)local f=assert(io.open(path,'rb'));local s=f:read(max+1);f:close();assert(#s<=max,'oversized evidence');return s end
local function read(path,max)return J.decode(raw_read(path,max),{max_bytes=max})end
local function exists(path)local f=io.open(path,'rb');if f then f:close();return true end;return false end
local cfg=read(ROOT..'hook-free-rebuild-v4-arm.json',8192)
assert(type(cfg.nonce)=='string'and cfg.nonce:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'invalid nonce')
assert(cfg.nonce==cfg.nonce:lower(),'nonce must be canonical lowercase')
assert(cfg.nonce~=C.failed_nonce,'old failed nonce must never be reused')
local output=ROOT..'hook-free-rebuild-v4-'..cfg.nonce..'.json'
local tracepath=ROOT..'hook-free-rebuild-v4-'..cfg.nonce..'.trace.jsonl'
local FENCE=ROOT..'hook-free-rebuild-v4.intent.json'
if exists(output)then print('[HookFreeRebuildV4] Existing report, no replay\n');return end
local function trace(stage,detail)
    local f=assert(io.open(tracepath,'ab'));assert(f:write(J.encode({unix=os.time(),stage=stage,detail=detail or J.null})..'\n'));assert(f:flush());assert(f:close())
end
local function write(path,value,replace)
    local raw=J.encode(value,{max_bytes=16777216});local f=assert(io.open(path..'.tmp','wb'));assert(f:write(raw));assert(f:flush());assert(f:close())
    assert(raw_read(path..'.tmp',16777216)==raw,'journal readback differs')
    if replace then os.remove(path)else assert(not exists(path),'nonreplace journal already exists')end
    assert(os.rename(path..'.tmp',path),'journal rename failed')
end
local function live(o)return o~=nil and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function same(a,b)return live(a)and live(b)and a:GetFullName()==b:GetFullName()end
local function finite(n)assert(type(n)=='number'and n==n and math.abs(n)<math.huge,'nonfinite field');return n end
local function text(v)return type(v)=='string'and v or v:ToString()end
local function propid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
local function one(class)
    local list=FindAllOf(class)or{};assert(#list<=32,'unexpected instance count');local found
    for _,o in ipairs(list)do if live(o)then assert(not found,'duplicate '..class);found=o end end
    return assert(found,'missing '..class)
end
local function static(full)local o=StaticFindObject(assert(full:match('^[^ ]+ (.*)$')));assert(live(o)and o:GetFullName()==full,'fresh context object missing');return o end
local function distance(a,b,xy)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(xy and 0 or(a.Z-b.Z)^2))end
local baseline=read(ROOT..'normal-rebuild-nearby-baseline.json',65536)
local targets={snapshot_sha256='fixed-oldbase-subset',chests={}}
for _,t in ipairs(dofile(directory..'targets.lua').chests)do if t.base_id==C.base_id then assert(t.group_id==C.guild_id,'target guild differs');targets.chests[#targets.chests+1]=t end end
assert(#targets.chests==13,'expected original 13 ordinary chests')
local sd={json=J,readers=R,constants=C,baseline=baseline,is_game_thread=IsInGameThread,manager=one,trace=trace}
local function context(expected)
    trace('live_player_context')
    local status=B.new{json=J,readers=R,instance_id=cfg.nonce,allow_apply=false}.players()
    assert(status.ok and #status.errors==0 and #status.players==1,'exactly one healthy Lab client required')
    local p=status.players[1]
    assert(p.player_uid==C.player_uid and p.guild_id==C.guild_id and p.can_build_in_guild==true and p.wood_chest_unlocked==true and p.wood_chest_denied==false,'UID/guild BuildConstruct(4)/technology differs')
    if expected then for _,k in ipairs({'controller','player_state','connection','transmitter','player_component','pawn','builder'})do assert(p[k]==expected[k],'active client changed: '..k)end end
    local pc,state,tr,component=static(p.controller),static(p.player_state),static(p.transmitter),static(p.player_component)
    assert(same(pc:GetPalPlayerState(),state)and same(state:GetPlayerController(),pc)and same(tr:GetOwner(),pc)and same(component:GetOwner(),tr),'active player ownership chain differs')
    assert(R.guid_to_string(pc:GetPlayerUId())==C.player_uid,'active UID differs')
    local inv=state:GetInventoryData();assert(live(inv),'inventory unavailable')
    return{summary=p,state=state,inventory=inv,component=component}
end
local function materials(ctx)
    trace('materials');local c=context(ctx and ctx.summary)
    return Materials.read{json=J,readers=R,targets=targets,inventory=c.inventory,state=c.state,player_uid=C.player_uid,item_manager=one('PalItemContainerManager'),fname=function(v)return FName(v)end}
end
local function range(ctx,site)
    local p={X=ctx.summary.position.x,Y=ctx.summary.position.y,Z=ctx.summary.position.z}
    assert(distance(C.position,site.base_position,true)<site.base_range-200 and distance(p,site.base_position,true)<site.base_range-100,'player or position outside base')
    assert(distance(C.position,p,false)<=1500,'player farther than 15m')
end
local function exact_site(a,b)
    assert(b.old_manual_model_absent and #b.unavailable==0,'manual or unregistered model remains')
    assert(a.base_object==b.base_object and a.collection==b.collection and a.base_building_count==b.base_building_count,'base lifecycle/count changed')
    assert(J.encode(a.models)==J.encode(b.models),'existing structure fingerprint changed')
    for _,m in ipairs(b.models)do if m.distance_from_manual_cm<500 then assert(m.position_source=='registered_concrete'and m.distance_from_manual_cm>=200,'nearby model prevents unambiguous exact position')end end
end
local function evidence()
    trace('failed_operation_evidence')
    assert(cfg.supersedes_failed_operation==C.failed_nonce,'explicit supersedes_failed_operation missing')
    local raw=raw_read(ROOT..'normal-rebuild-once.intent.json',1048576)
    assert(Core.sha256(raw)==C.old_intent_sha256,'immutable old intent hash differs')
    local prior=J.decode(raw);assert(prior.nonce==C.failed_nonce,'old intent nonce differs')
    local recoveryraw=raw_read(ROOT..'hook-free-rebuild-v4-recovery-evidence.json',65536)
    assert(Core.sha256(recoveryraw)==C.recovery_sha256,'reviewed recovery evidence hash differs')
    local r=J.decode(recoveryraw)
    assert(r.save_parse_ok and r.save_sha256==C.recovery_save_sha256 and r.evidence.nonce==C.failed_nonce and r.evidence.source_save_precedes_submission==true,'reviewed prior save evidence differs')
    assert(r.old_manual_present==false and r.saved_base_chest_count==13 and #r.new_chests==0 and #r.near_attempt==0,'prior save contains attempted building')
    assert(r.totals.saved.Wood==r.totals.before.Wood and r.totals.saved.Stone==r.totals.before.Stone,'prior recipe debit persisted')
    for _,s in ipairs(r.source_slots)do assert(s.matches_before==true,'prior material source not restored by prior save')end
    local out={old_intent_sha256=C.old_intent_sha256,recovery_evidence_sha256=C.recovery_sha256,recovery_save_sha256=C.recovery_save_sha256,
        scope='Reviewed historical pre-submission save. Current site/materials are independently read live; this is not a current save assertion.'}
    if cfg.mode=='execute'then
        trace('fresh_backup_evidence')
        local br=raw_read(ROOT..'hook-free-rebuild-v4-checkpoint.json',65536)
        assert(cfg.backup_evidence_sha256=='1a45786afbee068e402a7fa9ae5ba4ce3507f5d2e912732f8968106c39944a52'and Core.sha256(br)==cfg.backup_evidence_sha256,'fresh checkpoint hash differs')
        local b=J.decode(br)
        assert(b.lab_only==true and b.file_count==97 and #b.files==97,'reviewed checkpoint cardinality differs')
        local function path(v)return v:gsub('\\','/'):gsub('/+','/')end
        assert(path(b.source_root)=='D:/PalworldServer-LAN/BridgeLab/Pal/Saved','checkpoint source must be Lab Saved')
        assert(path(b.backup_root)=='D:/PalworldServer-LAN/BridgeLab/checkpoints/v4-20261004-00000000-0000-4000-8000-000000000014','reviewed checkpoint path differs')
        assert(b.level_sha256=='01e4c81ffb2b8511380e8ca645108d33d5cd5ba3b0ae921e6679f94bef9ec53d','reviewed checkpoint Level hash differs')
        local level=0;local seen={}
        for _,f in ipairs(b.files)do
            assert(type(f.path)=='string'and not f.path:find('..',1,true)and not seen[f.path],'invalid checkpoint entry');seen[f.path]=true
            assert(type(f.sha256)=='string'and #f.sha256==64 and f.sha256:match('^%x+$')and type(f.bytes)=='number'and f.bytes>=0,'invalid checkpoint file evidence')
            if path(f.path)=='SaveGames/0/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/Level.sav'then assert(f.sha256==b.level_sha256,'checkpoint Level entry differs');level=level+1 end
        end
        assert(level==1,'checkpoint must contain one main Level save')
        out.fresh_backup={backup_root=b.backup_root,file_count=b.file_count,level_sha256=b.level_sha256,created_utc=b.created_utc,
            verification='Exact hash of root-reviewed, source/copy SHA-verified 97-file checkpoint manifest.'}
        out.backup_evidence_sha256=cfg.backup_evidence_sha256
    end
    return out
end
local function building_ids()
    trace('poll_registered_ids')
    local bm,mgr=one('PalBaseCampManager'),one('PalMapObjectManager');local found={}
    assert(bm:TryGetModel(R.guid_from_string(C.base_id),found),'base not registered');local base=found.OutModel
    assert(live(base)and R.guid_to_string(base:GetId())==C.base_id and R.guid_to_string(base:GetGroupIdBelongTo())==C.guild_id and base:IsAvailable(),'registered base differs')
    local collection=base.MapObjectCollection;assert(live(collection),'base collection unavailable')
    local a=collection.MapObjectInstanceIdRepInfoArray.Items;local n=a:GetArrayNum()
    assert(type(n)=='number'and n%1==0 and n>0 and n<=500,'base array bound exceeded')
    local ids,unavailable,seen=J.array(),J.array(),{}
    for i=1,n do
        -- Known numeric-index UScriptStruct. Never probe .get/.Get or ForEach wrappers.
        local id=propid(a[i].InstanceId);assert(not seen[id],'duplicate collection ID');seen[id]=true
        local model=mgr:FindModel(R.guid_from_string(id))
        if not live(model)then unavailable[#unavailable+1]=id
        else
            assert(propid(model.InstanceId)==id,'registered model ID differs')
            local kind=text(model.BuildObjectId)
            if kind~='None'and kind~=''and not kind:match('^CommonDrop')and not kind:match('^Damagable')and not kind:match('^PickupItem')then
                assert(propid(model.BaseCampIdBelongTo)==C.base_id,'building base differs');ids[#ids+1]=id
            end
        end
    end
    assert(not live(mgr:FindModel(R.guid_from_string(C.old_model_id))),'old manual model reappeared')
    table.sort(ids);return ids,unavailable,mgr
end
local function candidate(mgr,id)
    trace('candidate_known_properties',{id=id})
    local model=mgr:FindModel(R.guid_from_string(id));assert(live(model)and propid(model.InstanceId)==id,'candidate no longer registered')
    assert(text(model.BuildObjectId)=='ItemChest'and propid(model.BaseCampIdBelongTo)==C.base_id and propid(model.GroupIdBelongTo)==C.guild_id and propid(model.BuildPlayerUId)==C.player_uid,'new model type/owner/base differs')
    local out={ok=true,model_id=id,build_id='ItemChest',concrete_pending=true,completed_verified=false,normal_unfinished_work_observed=false}
    local process=model.BuildProcess;assert(live(process),'new model BuildProcess unavailable')
    local state=finite(process.State);assert(state==0 or state==1,'unexpected build state')
    local work=process.BuildWork;out.early_process={state=state,work_available=live(work)==true}
    if live(work)then
        local w={id=propid(work.ID),owner_model_id=propid(work.OwnerMapObjectModelId),owner_concrete_id=propid(work.OwnerMapObjectConcreteModelId),
            base_id=propid(work.BaseCampIdBelongTo),required=finite(work.RequiredWorkAmount),current=finite(work.CurrentWorkAmount),
            current_state=finite(work.CurrentState),in_progress=work.bInProgress}
        assert(w.owner_model_id==id and w.base_id==C.base_id and w.required==1000 and w.current>=0 and w.current<=1000,'native work identity/recipe differs')
        out.early_process.work=w
    end
    local cm=model:GetConcreteModel(false)
    if not live(cm)then assert(state==0,'completed model lacks concrete');return out end
    trace('candidate_concrete_detail',{id=id})
    local detail=Detail.read({json=J,readers=R,now=os.time,is_game_thread=IsInGameThread,fname=function(v)return FName(v)end,manager=function()return mgr end},
        {model_id=id,expected_base_id=C.base_id,expected_guild_id=C.guild_id,expected_player_uid=C.player_uid,expected_location=C.position})
    assert(detail.ok,'candidate detailed registration read failed: '..J.encode(detail.errors))
    local q=detail.transform.Rotation;local direct,opposite=0,0
    for k,v in pairs(C.rotation)do direct=math.max(direct,math.abs(q[k]-v));opposite=math.max(opposite,math.abs(q[k]+v))end
    assert(math.min(direct,opposite)<0.00000001 and detail.distance_from_expected_cm<=2,'new transform differs from captured exact request')
    out.concrete_pending=false;out.detail=detail
    local p=detail.build_process;assert(p.available,'build process unavailable')
    if p.work.available then
        local w=p.work
        assert(w.owner_model_matches and w.owner_concrete_matches and w.base_matches and w.required_matches_recipe,'work reverse ownership differs')
        if p.state==0 and w.required_amount==1000 and w.current_amount>=0 and w.current_amount<1000 then out.normal_unfinished_work_observed=true end
    end
    if p.completed then
        local c=detail.container
        assert(c.module_available and c.available and c.capacity==10 and c.id~='00000000-0000-0000-0000-000000000000'and c.id~=C.old_container_id,'completed new 10-slot container not available')
        out.completed_verified=true
    end
    return out
end
local deps={json=J,now=os.time,is_game_thread=IsInGameThread,has_fence=function()return exists(FENCE)or exists(FENCE..'.tmp')end,
    emit=function(r)write(output,r,true)end,verify_evidence=evidence,material_diff=Materials.diff,read_materials=materials,
    claim_intent=function(r)write(FENCE,r,false);assert(read(FENCE,16777216).nonce==cfg.nonce,'v4 persisted nonce differs');return true end,
    preflight=function()
        local ctx=context();local site=Site.site(sd);range(ctx,site);exact_site(site,site)
        local history=Site.history(sd,site);local op=one('PalMapObjectManager'):GetBuildOperator();assert(live(op)and live(op.DataMap),'recipe unavailable')
        local recipe=op.DataMap:GetById(FName('ItemChest'));assert(recipe.RequiredBuildWorkAmount==1000,'recipe work differs')
        local ingredients={};for i=1,4 do local n=recipe['Material'..i..'_Count'];if n>0 then ingredients[text(recipe['Material'..i..'_Id'])]=n end end
        assert(ingredients.Wood==15 and ingredients.Stone==5,'recipe differs');for k in pairs(ingredients)do assert(k=='Wood'or k=='Stone','unexpected material')end
        local m=materials(ctx)
        return{live_context_verified=true,tech_guild_base_verified=true,old_manual_model_absent=site.old_manual_model_absent,
            context=ctx.summary,site=site,history=history,materials=m,materials_sufficient=m.totals.Wood>=15 and m.totals.Stone>=5,
            fixed_request={build_id='ItemChest',location=C.position,rotation=C.rotation,archives=J.array(),debug={bNotConsumeMaterials=false}},recipe={Wood=15,Stone=5,work=1000}},
            {summary=ctx.summary,site=site}
    end,
    final_check=function(ctx,before)
        evidence();local c=context(ctx.summary);local site=Site.site(sd);range(c,site);exact_site(ctx.site,site);Site.history(sd,site)
        local diff=Materials.diff(before.materials,materials(ctx));assert(#diff.changed_slots==0,'materials changed before native request')
        return true
    end,
    submit=function(ctx)
        trace('native_request_once');assert(IsInGameThread()and exists(FENCE),'native request missing intent or wrong thread')
        local c=context(ctx.summary)
        c.component:RequestBuild_ToServer(FName('ItemChest'),{X=C.position.X,Y=C.position.Y,Z=C.position.Z},
            {X=C.rotation.X,Y=C.rotation.Y,Z=C.rotation.Z,W=C.rotation.W},{},{bNotConsumeMaterials=false})
        trace('native_request_returned')
    end,
    observe=function(before,ctx)
        local ids,unavailable,mgr=building_ids();local prior,seen={},{};local new,missing=J.array(),J.array()
        for _,row in ipairs(before.site.models)do prior[row.id]=true end
        for _,id in ipairs(ids)do seen[id]=true;if not prior[id]then new[#new+1]=id end end
        for id in pairs(prior)do if not seen[id]then missing[#missing+1]=id end end;table.sort(missing)
        local out={new_models=new,missing_models=missing,unavailable=unavailable}
        if #new==1 and #missing==0 and #unavailable==0 then
            out.candidate=candidate(mgr,new[1])
            if out.candidate.completed_verified then
                -- Completed terminal candidate: one complete old-environment recheck, excluding only its exact new ID.
                local site=Site.site(sd);local remaining=J.array();for _,row in ipairs(site.models)do if row.id~=new[1]then remaining[#remaining+1]=row end end
                site.models=remaining;assert(site.base_building_count==before.site.base_building_count+1,'completed base building count differs')
                site.base_building_count=site.base_building_count-1;exact_site(before.site,site);out.final_history=Site.history(sd,site)
            end
        end
        return out
    end}
local runner=Core.new(deps,cfg)
ExecuteInGameThread(function()runner.start();print('[HookFreeRebuildV4] '..runner.report.status..'\n')end)
if cfg.mode=='execute'then
    local queued=false
    LoopAsync(1000,function()
        if runner.report.finished_unix then return true end
        if not queued then queued=true;ExecuteInGameThread(function()
            local ok,e=pcall(runner.tick);queued=false
            if not ok then runner.report.status='indeterminate_no_retry';runner.report.finished_unix=os.time()
                runner.report.errors[#runner.report.errors+1]={stage='tick_outer',error=tostring(e)};deps.emit(runner.report)end
        end)end
        return false
    end)
end
return runner
