local P='work/palworld-live/'
local J=dofile(P..'bridge/PalLiveBridge/Scripts/json.lua')
local R=dofile(P..'bridge/PalLiveBridge/Scripts/readers.lua')
local Core=dofile(P..'lab/hook-free-rebuild-v4-core.lua')
local function read(p)local f=assert(io.open(p,'rb'));local v=f:read('*a');f:close();return v end
local source=read(P..'lab/hook-free-rebuild-v4-previewdiag.lua')
local capture=J.decode(read(P..'lab/manual-build-observation-live.json'))
local manual=J.decode(read(P..'lab/manual-chest-registered-details-live.json'))
local baseline=J.decode(read(P..'lab/client-manual-nearby-saved-buildings.json'))
local Site=dofile(P..'lab/full-observer-readonly-v3-core.lua')
local targets=dofile(P..'bridge/PalLiveBridge/Scripts/targets.lua')
local DIR='D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'
local ROOT='D:/PalworldServer-LAN/BridgeLab/rpc/'
local function copy(v)return J.decode(J.encode(v))end
local function object(name,t)t=t or{};t.GetFullName=function()return name end;t.IsValid=function()return true end;return t end
local function param(v)return{get=function()return v end,set=function()error('hook attempted parameter mutation')end}end
local function setup(options)
    options=options or{};local clock=1000;local fs={};local queues={};local loops={};local hooks={};local calls=0;local transforms=0
    local p=copy(capture.verified_context);p.position={x=capture.request.location.X,y=capture.request.location.Y,z=capture.request.location.Z}
    local state,pc,tr,component,base,mgr,inventory,collection;local rows={};local new_present=false;local old_present=options.old_present or false;local after=false
    local old_id=manual.model_id;local new_id='11111111-2222-3333-4444-555555555555';local existing_id='00000000-0000-4000-8000-000000000027'
    local gid=R.guid_from_string
    local function transform(pos)return{Translation=copy(pos),Rotation=copy(capture.request.rotation),Scale3D={X=1,Y=1,Z=1}}end
    local function make_model(id,pos,rotation,concrete_id)
        concrete_id=concrete_id or '00000000-0000-4000-8000-000000000026'
        local function mt()local t=transform(pos);if rotation then t.Rotation=copy(rotation)end;return t end
        local cm=object('Concrete '..id,{bDisposed=false,GetModelInstanceId=function()return gid(id)end,GetInstanceId=function()return gid(concrete_id)end,
            GetTransform=function()transforms=transforms+1;return mt()end})
        local process=object('BuildProcess '..id,{State=0,BuildWork=object('Work '..id,{RequiredWorkAmount=1000,CurrentWorkAmount=0,ID=gid('00000000-0000-4000-8000-00000000001d'),
            OwnerMapObjectModelId=gid(id),OwnerMapObjectConcreteModelId=gid(concrete_id),BaseCampIdBelongTo=gid(manual.base_id),CurrentState=0,bInProgress=false})})
        local model=object('Model '..id,{InstanceId=gid(id),BaseCampIdBelongTo=gid(manual.base_id),GroupIdBelongTo=gid(manual.guild_id),BuildPlayerUId=gid(manual.build_player_uid),
            BuildObjectId=id==existing_id and'Factory_Hard_01'or'ItemChest',InitialTransformCache=mt(),BuildProcess=process,GetConcreteModel=function(_,force)assert(force==false);if options.concrete_pending and id==new_id and clock<1002 then return nil end;return cm end})
        rows[id]={model=model,cm=cm};return model,cm
    end
    local existing_ids={}
    for _,saved in ipairs(baseline.nearest_10)do if saved.id~=old_id then
        local pos={X=saved.location.x,Y=saved.location.y,Z=saved.location.z};local rot={X=saved.rotation.x,Y=saved.rotation.y,Z=saved.rotation.z,W=saved.rotation.w}
        if options.neighbor_moved and #existing_ids==0 then pos.X=pos.X+10 end
        local model=make_model(saved.id,pos,rot,saved.concrete_id);model.BuildObjectId=saved.type
        existing_ids[#existing_ids+1]=saved.id
    end end
    if old_present then make_model(old_id,capture.request.location)end
    local array={GetArrayNum=function()local n=#existing_ids;if old_present then n=n+1 end;if new_present then n=n+1 end;return n end}
    setmetatable(array,{__index=function(_,i)
        local ids={table.unpack(existing_ids)};if old_present then ids[#ids+1]=old_id end;if new_present then ids[#ids+1]=new_id end
        assert(ids[i],'out-of-bound TArray access');return setmetatable({InstanceId=gid(ids[i])},{__index=function(_,key)error('unexpected ScriptStruct member '..tostring(key))end})
    end})
    collection=object('Collection Base',{MapObjectInstanceIdRepInfoArray={Items=array}})
    local base_collection=collection
    collection.MapObjectInstanceIdRepInfoArray=nil
    base=object(manual.base_object,{MapObjectCollection=object('Collection Base',{MapObjectInstanceIdRepInfoArray={Items=array}}),GetId=function()return gid(manual.base_id)end,
        GetGroupIdBelongTo=function()return gid(manual.guild_id)end,IsAvailable=function()return true end,GetBuildingNum=function()return 83+(new_present and 1 or 0)+(old_present and 1 or 0)end,
        GetTransform=function()return transform(capture.request.location)end,GetRange=function()return 5000 end})
    collection=base.MapObjectCollection
    local recipe={RequiredBuildWorkAmount=1000,Material1_Id='Wood',Material1_Count=15,Material2_Id='Stone',Material2_Count=5,Material3_Count=0,Material4_Count=0}
    mgr=object(manual.manager,{FindModel=function(_,g)local id=R.guid_to_string(g);return rows[id]and rows[id].model end,
        GetBuildOperator=function()return object('Operator',{DataMap=object('Data',{GetById=function(_,id)assert(id=='ItemChest');return recipe end})})end})
    inventory=object('Inventory Player')
    state=object(p.player_state,{GetPlayerController=function()return pc end,GetInventoryData=function()return inventory end})
    pc=object(p.controller,{GetPalPlayerState=function()return state end,GetPlayerUId=function()return gid(p.player_uid)end})
    tr=object(p.transmitter,{GetOwner=function()return pc end})
    local request_path='/Script/Pal.PalNetworkPlayerComponent:RequestBuild_ToServer'
    component=object(p.player_component,{GetOwner=function()return tr end,RequestBuild_ToServer=function(self,id,location,rotation,archives,debugparam)
        assert(fs[ROOT..'hook-free-rebuild-v4.intent.json'],'RPC happened without persistent intent')
        assert(self==component and id=='ItemChest'and #archives==0 and debugparam.bNotConsumeMaterials==false)
        assert(J.encode(location)==J.encode(capture.request.location)and J.encode(rotation)==J.encode(capture.request.rotation),'changed manual request')
        calls=calls+1
        after=true;new_present=true;local model=make_model(new_id,location);if options.bad_owner then model.BuildPlayerUId=gid('00000000-0000-4000-8000-000000000027')end
    end})
    local objects={};for _,o in ipairs({mgr,base,state,pc,tr,component})do objects[o:GetFullName():match('^[^ ]+ (.*)$')]=o end
    local item_manager=object('ItemManager Live')
    local base_manager=object('BaseManager Live',{TryGetModel=function(_,g,out)assert(R.guid_to_string(g)==manual.base_id);out.OutModel=base;return true end})
    local cfg={nonce='00000000-0000-4000-8000-00000000000d',mode=options.preview and'preview'or'execute',expires_unix=1300,operator_confirmed_normal_dismantle=true,execute_exact_manual_request=true,supersedes_failed_operation='00000000-0000-4000-8000-000000000017',backup_evidence_sha256='1a45786afbee068e402a7fa9ae5ba4ce3507f5d2e912732f8968106c39944a52'}
    fs[ROOT..'hook-free-rebuild-v4-arm.json']=J.encode(cfg)
    fs[ROOT..'normal-rebuild-nearby-baseline.json']=J.encode(baseline)
    fs[ROOT..'manual-build-observation-'..capture.observation_id..'.json']=J.encode(capture)
    fs[ROOT..'registered-model-details-00000000-0000-4000-8000-000000000018.json']=J.encode(manual)
    fs[ROOT..'normal-rebuild-once.intent.json']=read(P..'lab/rebuild-crash-20261004/intent.json')
    fs[ROOT..'hook-free-rebuild-v4-recovery-evidence.json']=read(P..'lab/rebuild-crash-20261004/last-save-state-summary.json')
    fs[ROOT..'hook-free-rebuild-v4-checkpoint.json']=read(P..'lab/hook-free-rebuild-v4-checkpoint.json')
    if options.bad_evidence then fs[ROOT..'normal-rebuild-once.intent.json']='wrong'end
    if options.temp_fence then fs[ROOT..'hook-free-rebuild-v4.intent.json.tmp']='partial'end
    if options.fence then fs[ROOT..'hook-free-rebuild-v4.intent.json']='existing durable intent'end
    local materials={read=function(d)assert(type(d.fname)=='function'and d.fname('Wood')=='Wood');return{totals={Wood=after and 15 or 30,Stone=after and 5 or 10}}end,
        diff=function(a,b)return{exact_recipe_cost=a.totals.Wood-b.totals.Wood==15 and a.totals.Stone-b.totals.Stone==5,changed_slots=a.totals.Wood~=b.totals.Wood and{{}}or{},concurrent_or_unexplained_changes=false}end}
    local detail={read=function(_,c)local v=copy(manual);v.model_id=c.model_id;v.container.id='00000000-0000-4000-8000-00000000000e';v.container.empty=false;return v end}
    local modules={['json.lua']=J,['readers.lua']=R,['targets.lua']=targets,['hook-free-rebuild-v4-core.lua']=Core,['full-observer-readonly-v3-core.lua']=Site,['normal-rebuild-materials.lua']=materials,
        ['registered-model-details-core.lua']=detail,['build.lua']={new=function(opts)assert(opts.allow_apply==false);return{players=function()return{ok=true,errors={},players={copy(p)}}end}end}}
    local delayed={}
    local env=setmetatable({},{__index=_G})
    env.dofile=function(path)return assert(modules[path:match('[^/]+$')],'unexpected module '..path)end
    env.io={open=function(path,mode)
        if mode=='rb'then if not fs[path]then return nil end;return{read=function(_,n)if n=='*a'then return fs[path]end;return fs[path]:sub(1,n)end,close=function()return true end}end
        assert(mode=='wb'or mode=='ab');if mode=='wb'then fs[path]=''else fs[path]=fs[path]or''end;return{write=function(_,s)fs[path]=fs[path]..s;return true end,flush=function()return true end,close=function()return true end}
    end}
    env.os={time=function()return clock end,remove=function(path)fs[path]=nil;return true end,rename=function(a,b)assert(fs[a]);if fs[b]then return nil end;fs[b]=fs[a];fs[a]=nil;return true end}
    env.StaticFindObject=function(path)return objects[path]end
    env.FindAllOf=function(class)if class=='PalItemContainerManager'then return{item_manager}elseif class=='PalBaseCampManager'then return{base_manager}elseif class=='PalMapObjectManager'then return{mgr}else error('forbidden world enumeration '..class)end end
    env.FName=setmetatable({},{__call=function(_,s)return s end});env.IsInGameThread=function()return true end
    env.RegisterHook=function()error('hooks forbidden')end
    env.UnregisterHook=function(name,a,b)assert(a==1 and b==2);hooks[name]=nil end
    env.ExecuteInGameThread=function()error('direct GT scheduling forbidden in diagnostic')end
    env.ExecuteInGameThreadWithDelay=function(ms,fn)assert(ms==1000 or ms==2000);delayed[#delayed+1]={due=clock+ms/1000,fn=fn};return #delayed end
    env.LoopAsync=function()error('async callbacks forbidden in diagnostic')end
    loops[#loops+1]=function()local ready={};for i=#delayed,1,-1 do if delayed[i].due<=clock then ready[#ready+1]=table.remove(delayed,i).fn end end;for _,fn in ipairs(ready)do queues[#queues+1]=fn end end
    env.print=function()end
    local function drain()while #queues>0 do local q=table.remove(queues,1);q()end end
    local original_encode=J.encode
    modules['json.lua']=setmetatable({encode=function(v,opts)
        if options.fail_site_encode and type(v)=='table'and v[1]and v[1].position then error('ORIGINAL_SITE_ERROR')end
        if options.fail_report_encode and type(v)=='table'and v.probe=='hook_free_rebuild_v4_previewdiag' then error('SECONDARY_JSON_ERROR')end
        return original_encode(v,opts)
    end},{__index=J})
    local function run(path)local f=assert(load(source,'@'..(path or(DIR..'hook-free-rebuild-v4.lua')),'t',env));local out=f();drain();return out end
    return{run=run,fs=fs,calls=function()return calls end,transforms=function()return transforms end,cfg=cfg,
        tick=function(seconds)clock=clock+seconds;if rows[new_id]then rows[new_id].model.BuildProcess.State=clock>=1002 and 1 or 0 end;for _,fn in ipairs(loops)do fn()end;drain()end,
        report=function()return J.decode(assert(fs[ROOT..'hook-free-rebuild-v4-previewdiag.json']))end,trace=function()return fs[ROOT..'hook-free-rebuild-v4-previewdiag.trace.txt']or''end}
end
local n=0;local function test(name,fn)local ok,e=pcall(fn);assert(ok,name..': '..tostring(e));n=n+1;print('ok '..name)end
test('three_delayed_GT_only_readonly_samples',function()local e=setup();e.run();assert(e.calls()==0 and e.trace():find('MAIN_LAST_ACTION_REGISTER_DELAY',1,true));e.tick(2);assert(e.report().status=='observing');e.tick(1);e.tick(1);assert(e.report().status=='complete'and #e.report().samples==3 and e.calls()==0)end)
test('original_error_written_before_report',function()local e=setup{fail_site_encode=true};e.run();e.tick(2);assert(e.report().status=='failed'and e.trace():find('ORIGINAL_SITE_ERROR',1,true)and e.calls()==0)end)
test('secondary_JSON_error_cannot_hide_original_plain_trace',function()local e=setup{fail_site_encode=true,fail_report_encode=true};e.run();e.tick(2);assert(e.trace():find('ORIGINAL_SITE_ERROR',1,true)and e.trace():find('SECONDARY_REPORT_ERROR',1,true)and e.calls()==0)end)
test('historical_neighbor_moved_fails_readonly',function()local e=setup{neighbor_moved=true};e.run();e.tick(2);assert(e.report().status=='failed'and e.calls()==0)end)
test('wrong_path_blocks_before_game_access',function()local e=setup();assert(not pcall(e.run,'D:/Production/hook-free-rebuild-v4-previewdiag.lua'));assert(e.calls()==0)end)
print('PASS '..n..' isolated preview diagnostic mocks')
