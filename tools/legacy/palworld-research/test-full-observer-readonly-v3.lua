local P='work/palworld-live/'
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local J=dofile(P..'bridge/PalLiveBridge/Scripts/json.lua')
local R=dofile(P..'bridge/PalLiveBridge/Scripts/readers.lua')
local Core=dofile(P..'lab/full-observer-readonly-v3-core.lua')
local baseline=J.decode(read(P..'lab/client-manual-nearby-saved-buildings.json'))
local capture=J.decode(read(P..'lab/manual-build-observation-live.json'))
local targets=dofile(P..'bridge/PalLiveBridge/Scripts/targets.lua')
local source=read(P..'lab/full-observer-readonly-v3.lua')
local DIR='D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'
local ROOT='D:/PalworldServer-LAN/BridgeLab/rpc/'
local BASE=baseline.base_id;local GUILD=capture.verified_context.guild_id
local old_id='00000000-0000-4000-8000-000000000030'
local function copy(v)return J.decode(J.encode(v))end
local function obj(name,t)t=t or{};t.IsValid=function()return true end;t.GetFullName=function()return name end;return t end
local function setup(o)
    o=o or{};local fs={[ROOT..'normal-rebuild-nearby-baseline.json']=J.encode(baseline)}
    local now=1000;local game=false;local online=not o.offline;local loop;local queue={};local state,pc
    local transforms,material_reads,index_reads,poison_reads,base_lookups=0,0,0,0,0
    local rows,ids={},{}
    for _,v in ipairs(baseline.nearest_10)do if v.id~=old_id then
        local pos={X=v.location.x,Y=v.location.y,Z=v.location.z};local q={X=v.rotation.x,Y=v.rotation.y,Z=v.rotation.z,W=v.rotation.w}
        if o.moved and #ids==0 then pos.X=pos.X+3 end
        local t={Translation=pos,Rotation=q,Scale3D={X=1,Y=1,Z=1}}
        local cm=obj('Concrete '..v.id,{bDisposed=o.disposed and #ids==0 or false,
            GetModelInstanceId=function()return R.guid_from_string(v.id)end,
            GetInstanceId=function()return R.guid_from_string(v.concrete_id)end,
            GetTransform=function()transforms=transforms+1;return copy(t)end})
        local model=obj('Model '..v.id,{InstanceId=R.guid_from_string(v.id),BaseCampIdBelongTo=R.guid_from_string(BASE),
            GroupIdBelongTo=R.guid_from_string(GUILD),BuildPlayerUId=R.guid_from_string(capture.target_player_uid),
            BuildObjectId=v.type,InitialTransformCache=t,
            GetConcreteModel=function(_,spawn)assert(spawn==false);if not o.cached then return cm end end})
        rows[v.id]=model;ids[#ids+1]=v.id
    end end
    local array=setmetatable({GetArrayNum=function()return o.overbound and 501 or #ids end},{__index=function(_,i)
        assert(type(i)=='number'and i%1==0 and i>=1 and i<=#ids,'out-of-bound or named TArray read')
        index_reads=index_reads+1
        return setmetatable({},{__index=function(_,field)
            if field=='InstanceId'then return R.guid_from_string(ids[i])end
            poison_reads=poison_reads+1;error('forbidden reflected probe '..tostring(field))
        end})
    end})
    local collection=obj('Collection new-after-restart',{MapObjectInstanceIdRepInfoArray={Items=array}})
    local base=obj('Base new-after-restart-6929',{MapObjectCollection=collection,GetId=function()return R.guid_from_string(BASE)end,
        GetGroupIdBelongTo=function()return R.guid_from_string(GUILD)end,IsAvailable=function()return true end,
        GetBuildingNum=function()return 83 end,GetTransform=function()return{Translation={X=0,Y=0,Z=0}}end,GetRange=function()return 5000 end})
    local bm=obj('BaseManager current',{TryGetModel=function(_,gid,out)
        assert(R.guid_to_string(gid)==BASE);base_lookups=base_lookups+1
        if o.missingbase then return false end;out.OutModel=base;return true
    end})
    local mm=obj('MapManager current',{FindModel=function(_,gid)return rows[R.guid_to_string(gid)]end})
    local im=obj('ItemManager current')
    local inventory=obj('Inventory fresh')
    state=obj('State current',{GetPlayerController=function()return pc end,GetInventoryData=function()return inventory end})
    pc=obj('PC current',{NetConnection=obj('Connection fresh'),GetPlayerUId=function()return R.guid_from_string(capture.target_player_uid)end,GetPalPlayerState=function()return state end})
    local p=copy(capture.verified_context);p.controller=pc:GetFullName();p.player_state=state:GetFullName()
    local readers=setmetatable({chests=function(t,opts)
        assert(game and #t.chests==13 and opts.verify_ownership and opts.require_snapshot_ownership)
        material_reads=material_reads+1;local chests={}
        for _,v in ipairs(t.chests)do chests[#chests+1]={ok=true,verified_live=true,eligible_for_snapshot_plan=true,base_id_live=BASE,group_id_live=GUILD,slots={{item='Wood',count=20},{item='Stone',count=5}}}end
        return{ok=true,verified_live=true,chests=chests}
    end},{__index=R})
    local mods={['json.lua']=J,['readers.lua']=readers,['targets.lua']=targets,['full-observer-readonly-v3-core.lua']=Core,
        ['build.lua']={new=function(opts)assert(opts.allow_apply==false);return{players=function()assert(online and game);return{ok=true,errors={},players={copy(p)}}end}end},
        ['normal-rebuild-materials.lua']={read=function(d)
            assert(game and d.inventory==inventory and d.state==state and d.item_manager==im and #d.targets.chests==13)
            assert(type(d.fname)=='function'and d.fname('Wood')=='Wood');material_reads=material_reads+1
            return{ok=true,totals={Wood=5304,Stone=213},carried={Wood=0,Stone=0}}
        end}}
    local env=setmetatable({},{__index=_G})
    env.dofile=function(pth)assert(pth:sub(1,#DIR)==DIR);return assert(mods[pth:sub(#DIR+1)])end
    env.io={open=function(pth,mode)
        if mode=='rb'then if not fs[pth]then return nil end;return{read=function(_,n)return fs[pth]:sub(1,n)end,close=function()return true end}end
        assert(mode=='wb'or mode=='ab');if mode=='wb'then fs[pth]=''end;fs[pth]=fs[pth]or''
        return{write=function(_,s)fs[pth]=fs[pth]..s;return true end,flush=function()return true end,close=function()return true end}
    end}
    env.os={time=function()return now end,remove=function(pth)fs[pth]=nil;return true end,rename=function(a,b)assert(fs[a]and not fs[b]);fs[b]=fs[a];fs[a]=nil;return true end}
    env.FindAllOf=function(class)
        assert(game)
        if class=='PalPlayerController'then return online and{pc}or{}end
        local byclass={PalBaseCampManager=bm,PalMapObjectManager=mm,PalItemContainerManager=im}
        local found=assert(byclass[class],'unexpected all-world scan');return{found}
    end
    env.StaticFindObject=function(path)assert(game);return({current=pc,['current-state']=state})[path]or(path=='current'and pc)end
    -- Distinct full paths for fresh player objects; no base static-path resolution.
    p.player_state='State current-state';state.GetFullName=function()return p.player_state end
    env.IsInGameThread=function()return game end
    env.FName=setmetatable({},{__call=function(_,v)return v end})
    env.LoopAsync=function(ms,fn)assert(ms==1000);loop=fn end
    env.ExecuteInGameThread=function(fn)queue[#queue+1]=fn end
    env.RegisterHook=function()error('hooks forbidden')end
    env.print=function()end
    local out
    return{run=function(path)out=assert(load(source,'@'..(path or DIR..'full-observer-readonly-v3.lua'),'t',env))();return out end,
        tick=function()now=now+1;loop();assert(#queue<=1);if #queue==1 then game=true;table.remove(queue,1)();game=false end end,
        online=function(v)online=v end,report=function()return out end,
        counters=function()return{transforms=transforms,materials=material_reads,index_reads=index_reads,poison_reads=poison_reads,base_lookups=base_lookups}end,
        trace=function()return fs[ROOT..'full-observer-readonly-v3.trace.jsonl']end}
end
local n=0
local function test(name,f)f();n=n+1;print('PASS '..name)end
test('three complete readonly observations use direct struct numeric entries',function()
    local e=setup();e.run();for i=1,3 do e.tick()end
    local r,c=e.report(),e.counters();assert(r.status=='complete'and #r.samples==3 and #r.errors==0)
    assert(c.index_reads==27 and c.poison_reads==0 and c.transforms==27 and c.materials==3 and c.base_lookups==6)
    assert(r.samples[1].site.base_object=='Base new-after-restart-6929'and #r.samples[1].history.verified==9)
    assert(e.trace():find('registered_transform',1,true)and e.trace():find('sample_complete',1,true))
end)
test('no client still reads site and 13 chests but cannot pass complete chain',function()
    local e=setup{offline=true};e.run();for i=1,3 do e.tick()end
    local r,c=e.report(),e.counters();assert(r.status=='complete_partial_client_unavailable'and not r.full_chain_verified)
    assert(c.materials==3 and c.index_reads==27 and c.base_lookups==6)
    assert(r.samples[1].context.reason=='client_unavailable'and r.samples[1].materials.coverage.player_common_included==false)
end)
test('known base lookup failure stops before model or material reads',function()
    local e=setup{missingbase=true};e.run();e.tick();assert(e.report().status=='failed')
    local c=e.counters();assert(c.index_reads==0 and c.materials==0)
end)
test('oversized array rejected before indexing',function()
    local e=setup{overbound=true};e.run();e.tick();assert(e.report().status=='failed'and e.counters().index_reads==0)
end)
test('disposed concrete stops before native transform',function()
    local e=setup{disposed=true};e.run();e.tick();assert(e.report().status=='failed'and e.counters().transforms==0)
end)
test('historical move rejected as diagnostics without any mutation',function()
    local e=setup{moved=true};e.run();e.tick();assert(e.report().status=='failed'and e.report().errors[1].stage=='historical_neighbors')
    assert(e.report().gameplay_mutation_calls==0 and e.report().construction_attempts==0)
end)
test('cache-only transform never substitutes historical live anchor',function()
    local e=setup{cached=true};e.run();e.tick();assert(e.report().status=='failed'and e.counters().transforms==0)
end)
test('failure stops scheduled observations',function()
    local e=setup{missingbase=true};e.run();e.tick();local c=e.counters().base_lookups
    e.tick();e.tick();assert(e.counters().base_lookups==c and #e.report().errors==1)
end)
test('production path refused before any read',function()
    local e=setup();assert(not pcall(e.run,'D:/PalworldServer-LAN/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/full-observer-readonly-v3.lua'))
    assert(e.counters().base_lookups==0)
end)
print('All '..n..' full-observer v3 cases passed.')
