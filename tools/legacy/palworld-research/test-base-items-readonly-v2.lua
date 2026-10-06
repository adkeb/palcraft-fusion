local ROOT='work/palworld-live/'
local J=dofile(ROOT..'bridge/PalLiveBridge/Scripts/json.lua')
local R=dofile(ROOT..'bridge/PalLiveBridge/Scripts/readers.lua')
local Core=dofile(ROOT..'lab/base-items-readonly-v2-core.lua')
local BASE='00000000-0000-4000-8000-000000000031'
local GUILD='00000000-0000-4000-8000-00000000001b'
local passed=0
local function test(name,f)f();passed=passed+1;print('PASS '..name)end
local function obj(name,fields)
    fields=fields or{};fields.IsValid=function()return true end;fields.GetFullName=function()return name end
    return fields
end
local function setup(o)
    o=o or{};local poison_reads=0;local index_reads=0;local models={}
    local n=o.count or 12
    for i=1,math.min(n,20)do
        local g={A=i,B=0,C=0,D=0};local id=R.guid_to_string(g)
        local cm=obj('Concrete '..i,{GetModelInstanceId=function()return g end})
        local model=obj('Model '..i,{InstanceId=g,GetConcreteModel=function(_,spawn)assert(spawn==false);return cm end})
        models[id]=model
    end
    local array=setmetatable({GetArrayNum=function()return n end},{__index=function(_,k)
        assert(type(k)=='number'and k%1==0 and k>=1 and k<=n,'unsafe/out-of-bounds array read')
        index_reads=index_reads+1
        return setmetatable({},{__index=function(_,field)
            if field=='InstanceId'then return{A=k,B=0,C=0,D=0}end
            poison_reads=poison_reads+1;error('FORBIDDEN reflected property: '..tostring(field))
        end})
    end})
    local collection=obj('Collection oldbase',{MapObjectInstanceIdRepInfoArray={Items=array}})
    local base=obj('Base oldbase',{GetId=function()return R.guid_from_string(BASE)end,
        GetGroupIdBelongTo=function()return R.guid_from_string(GUILD)end,IsAvailable=function()return true end,
        MapObjectCollection=collection})
    local manager=obj('Manager singleton',{FindModel=function(_,g)return models[R.guid_to_string(g)]end})
    local d={json=J,readers=R,is_game_thread=function()return true end,base=function()return base end,manager=function()return manager end,base_id=BASE,guild_id=GUILD}
    return d,{models=models,base=base,manager=manager,reads=function()return poison_reads,index_reads end}
end
test('first three direct struct reads never probe get',function()
    local d,s=setup();local out=Core.sample(d,3)
    assert(out.sampled_count==3 and out.registered_count==3 and out.concrete_count==3)
    local p,i=s.reads();assert(p==0 and i==3)
end)
test('first ten are strictly in bounds',function()
    local d,s=setup();local out=Core.sample(d,10)
    assert(out.sampled_count==10);local p,i=s.reads();assert(p==0 and i==10)
end)
test('short array never indexes beyond current count',function()
    local d,s=setup{count=2};assert(Core.sample(d,10).sampled_count==2)
    local p,i=s.reads();assert(p==0 and i==2)
end)
test('over-bound count stops before any index',function()
    local d,s=setup{count=501};assert(not pcall(Core.sample,d,10));local p,i=s.reads();assert(p==0 and i==0)
end)
test('missing model stops without later getter',function()
    local d,s=setup();s.models[R.guid_to_string{A=1,B=0,C=0,D=0}]=nil
    assert(not pcall(Core.sample,d,3));local p,i=s.reads();assert(p==0 and i==1)
end)
test('wrong registered GUID refused',function()
    local d,s=setup();s.models[R.guid_to_string{A=1,B=0,C=0,D=0}].InstanceId={A=99,B=0,C=0,D=0}
    assert(not pcall(Core.sample,d,3))
end)
test('unloaded concrete accepted without spawn',function()
    local d,s=setup();s.models[R.guid_to_string{A=1,B=0,C=0,D=0}].GetConcreteModel=function(_,spawn)assert(not spawn);return nil end
    assert(Core.sample(d,3).concrete_count==2)
end)
test('wrong game thread refuses before resolution',function()
    local d=setup();d.is_game_thread=function()return false end;d.base=function()error('must not resolve')end
    assert(not pcall(Core.sample,d,3))
end)
local function host_env(path)
    local d,s=setup();local store={};local callbacks={};local scheduled;local game=false
    local dir='D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'
    local real_io=io;local f=assert(real_io.open(ROOT..'lab/base-items-readonly-v2.lua'));local source=f:read('*a');f:close()
    local env=setmetatable({},{__index=_G})
    env.dofile=function(p)
        assert(p:sub(1,#dir)==dir);local name=p:sub(#dir+1)
        if name=='json.lua'then return J elseif name=='readers.lua'then return R elseif name=='base-items-readonly-v2-core.lua'then return Core end
        error('unexpected dependency '..name)
    end
    env.io={open=function(p,mode)
        assert(mode=='wb');local data=''
        return{write=function(_,v)data=data..v;return true end,close=function()store[p]=data;return true end}
    end}
    env.os={time=function()return 1000 end,remove=function(p)store[p]=nil;return true end,rename=function(a,b)assert(store[a]and not store[b]);store[b]=store[a];store[a]=nil;return true end}
    env.LoopAsync=function(ms,fn)assert(ms==250);scheduled=fn end
    env.ExecuteInGameThread=function(fn)callbacks[#callbacks+1]=fn end
    env.IsInGameThread=function()return game end
    env.FindAllOf=function(kind)assert(game);if kind=='PalBaseCampModel'then return{s.base}elseif kind=='PalMapObjectManager'then return{s.manager}end;error('unexpected scan')end
    env.RegisterHook=function()error('no hooks allowed')end
    env.print=function()end
    local chunk=assert(load(source,'@'..(path or dir..'base-items-readonly-v2.lua'),'t',env))
    return chunk,s,store,function()return scheduled end,function()
        local fn=table.remove(callbacks,1);assert(fn);game=true;fn();game=false
    end,function()return #callbacks end
end
test('actual host executes forty delayed bounded read-only ticks',function()
    local chunk,s,store,loop,run,pending=host_env();local report=chunk()
    for i=1,40 do
        assert(loop()()==false);assert(pending()==1)
        assert(loop()()==false);assert(pending()==1) -- does not double-queue
        run();assert(pending()==0)
    end
    assert(loop()()==true and report.status=='complete'and #report.samples==40)
    assert(#report.errors==0 and report.gameplay_mutation_calls==0 and report.hooks_registered==0)
    local p,i=s.reads();assert(p==0 and i==372)
    local persisted=J.decode(assert(store['D:/PalworldServer-LAN/BridgeLab/rpc/base-items-readonly-v2.json']))
    assert(persisted.status=='complete'and #persisted.samples==40)
end)
test('actual host refuses production path before dependencies',function()
    local chunk=host_env('D:/PalworldServer-LAN/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/base-items-readonly-v2.lua')
    local ok,e=pcall(chunk);assert(not ok and tostring(e):find('BridgeLab only',1,true))
end)
print('All '..passed..' readonly-v2 cases passed.')
