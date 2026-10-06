-- Local mock tests exercise safety/state transitions only, not Palworld correctness.
local path='work/palworld-live/bridge/PalLiveBridge/Scripts/'
local J=dofile(path..'json.lua');local R=dofile(path..'readers.lua')
local f=assert(io.open(path..'build.lua','rb'));local source=f:read('*a');f:close()
local Build=assert(load(source,'@D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/build.lua'))()
local now=1000;os.time=function()return now end
FName=function(s)return s end
local function g(n)return{A=n,B=0,C=0,D=0}end
local function id(n)return R.guid_to_string(g(n))end
local function obj(name,extra)
    local t=extra or{};t.GetFullName=function()return name end;t.IsValid=function()return true end;return t
end
local state,pc,transmitter,pawn,component,guild,tech,inv,builder,connection,container,mgr,manager
local counts,models,classes,journal,base_count,calls,unlocked,denied,permission,owner_override,persist_count,persist_fail_at
local function make_model(n,kind,pos)
    local concrete=obj('Concrete'..n,{GetModelInstanceId=function()return g(n)end,
        GetBaseCampIdBelongTo=function()return g(4)end,GetTransform=function()return{Translation=pos}end})
    return obj('Model'..n,{_test_id=n,_test_registered=true,BuildObjectId=kind,GetConcreteModel=function(_,force)assert(force==false);return concrete end,
        GetBuildPlayerUId_BP=function()return g(1)end})
end
local function setup()
    now=1000;counts={Wood=50,Stone=20};models={make_model(5,'Wooden_foundation',{X=0,Y=0,Z=0})}
    journal={};base_count=1;calls=0;unlocked=true;denied=false;permission=true;owner_override=nil;persist_count=0;persist_fail_at=nil
    guild=obj('Guild',{GetId=function()return g(3)end,HasGuildPermission=function(_,who,permission_id)assert(who.A==1 and permission_id==4);return permission end})
    tech=obj('Tech',{IsUnlockBuildObject=function()return unlocked end,IsDeniedBuildObject=function()return denied end})
    inv=obj('Inventory',{CountItemNum64=function(_,item)return counts[item]or 0 end})
    builder=obj('Builder');connection=obj('IpConnection')
    pawn=obj('Pawn',{BuilderComponent=builder,K2_GetActorLocation=function()return{X=500,Y=0,Z=0}end})
    component=obj('PlayerComponent',{GetOwner=function()return transmitter end,RequestBuild_ToServer=function(_,build,location,rotation,archives,debug)
        assert(build=='ItemChest'and #archives==0 and debug.bNotConsumeMaterials==false)
        assert(rotation.X==0 and rotation.Y==0 and math.abs(rotation.Z^2+rotation.W^2-1)<1e-8)
        calls=calls+1;counts.Wood=counts.Wood-15;counts.Stone=counts.Stone-5;base_count=base_count+1
        models[#models+1]=make_model(6,'ItemChest',location)
    end})
    transmitter=obj('PlayerTransmitter',{GetOwner=function()return owner_override or pc end,GetPlayer=function()return component end})
    state=obj('State',{GuildBelongTo=guild,GetPlayerController=function()return pc end,GetTechnologyData=function()return tech end,GetInventoryData=function()return inv end,GetPlayerName=function()return 'Tester'end})
    pc=obj('Controller',{NetConnection=connection,Transmitter=transmitter,HasAuthority=function()return true end,IsPlayerController=function()return true end,
        GetPalPlayerState=function()return state end,GetPlayerUId=function()return g(1)end,GetDefaultPlayerCharacter=function()return pawn end})
    local recipe={MapObjectId='ItemChest',RequiredBuildWorkAmount=10,InstallMaxNumInBaseCamp=0,bIsInstallOnlyInDoor=false,bIsInstallOnlyHubAround=false,InstallNeighborThreshold=0,
        Material1_Id='Wood',Material1_Count=15,Material2_Id='Stone',Material2_Count=5,Material3_Id='None',Material3_Count=0,Material4_Id='None',Material4_Count=0}
    local map=obj('BuildDataMap',{GetById=function()return recipe end});local operator=obj('Operator',{DataMap=map})
    manager=obj('MapManager',{GetBuildOperator=function()return operator end,FindModel=function(_,which)for _,m in ipairs(models)do if m._test_id==which.A and m._test_registered then return m end end end})
    container=obj('CanonicalContainer',{GetId=function()return{ID=g(7)}end,Num=function()return 2 end,Get=function(_,i)
        local item=i==0 and 'Wood'or 'Stone'
        return obj('Slot'..i,{GetStackCount=function()return counts[item]end,GetItemId=function()return{StaticId=item,DynamicId={CreatedWorldId=g(0),LocalIdInCreatedWorld=g(0)}}end})
    end})
    mgr=obj('ItemManager',{GetContainer=function()return container end})
    classes={PalPlayerController={pc},PalMapObjectManager={manager},PalItemContainerManager={mgr},PalItemContainer={container},PalMapObjectModel=models}
    FindAllOf=function(class)return classes[class]or{}end
end
local counter=100
local function factory(enabled)
    return Build.new{json=J,readers={guid_to_string=R.guid_to_string,bases=function()return{ok=true,bases={{id=id(4),group_id=id(3),ok=true,available=true,position={x=0,y=0,z=0},range=3500,building_count=base_count}}}end},
        instance_id=id(2),allow_apply=enabled,new_id=function()counter=counter+1;return id(counter)end,
        persist=function(op)persist_count=persist_count+1;if persist_count==persist_fail_at then return false end;journal[op.operation_id]=J.decode(J.encode(op));return true end,
        read_operation=function(key)return journal[key]end}
end
local function req()return{player_uid=id(1),guild_id=id(3),base_id=id(4),structures={{build_id='ItemChest',position={x=0,y=0,z=1},rotation={pitch=0,yaw=30,roll=0},support_model_id=id(5)}}}end
local function args(plan,key)return{plan_id=plan.plan_id,expected_revision=plan.expected_revision,idempotency_key=id(key or 9)}end
local tested=0
local function test(name,fn)setup();local ok,err=pcall(fn);if not ok then error(name..': '..(type(err)=='table'and (err.code..' '..err.message)or tostring(err)))end;tested=tested+1 end
local function rejects(code,fn)local ok,err=pcall(fn);assert(not ok and type(err)=='table'and err.code==code,'expected '..code..', got '..tostring(type(err)=='table'and err.code or err))end

test('read-only player listing',function()local b=factory(false);local r=b.players();assert(r.ok and #r.players==1 and r.players[1].wood_carried==50 and calls==0)end)
test('no online player',function()classes.PalPlayerController={};assert(#factory(false).players().players==0);rejects('player_unavailable',function()factory(false).preview(req())end)end)
test('global owner rejected',function()owner_override=obj('GameState');rejects('player_unavailable',function()factory(true).preview(req())end)end)
test('no real connection rejected',function()pc.NetConnection=nil;rejects('player_unavailable',function()factory(true).preview(req())end)end)
test('wrong guild rejected',function()local r=req();r.guild_id=id(30);rejects('forbidden',function()factory(true).preview(r)end)end)
test('permission rejected',function()permission=false;rejects('forbidden',function()factory(true).preview(req())end)end)
test('technology rejected',function()unlocked=false;rejects('technology_locked',function()factory(true).preview(req())end)end)
test('denied technology rejected',function()denied=true;rejects('technology_locked',function()factory(true).preview(req())end)end)
test('insufficient carried materials',function()counts.Wood=14;rejects('insufficient_materials',function()factory(true).preview(req())end)end)
test('preview read-only and apply disabled',function()local b=factory(false);local p=b.preview(req());assert(calls==0 and p.apply_enabled==false);rejects('unsupported',function()b.apply(args(p))end)end)
test('stale material count',function()local b=factory(true);local p=b.preview(req());counts.Wood=51;rejects('stale_plan',function()b.apply(args(p))end);assert(calls==0)end)
test('expiry rejected',function()local b=factory(true);local p=b.preview(req());now=1060;rejects('stale_plan',function()b.apply(args(p))end)end)
test('durable journal fails before native',function()local b=factory(true);local p=b.preview(req());persist_fail_at=1;rejects('journal_failed',function()b.apply(args(p))end);assert(calls==0)end)
test('second journal fails before native',function()local b=factory(true);local p=b.preview(req());persist_fail_at=2;local op=b.apply(args(p));assert(calls==0 and op.status=='not_submitted_journal_error')end)
test('one normal RPC and idempotent repeat',function()local b=factory(true);local p=b.preview(req());local a=args(p);local r=b.apply(a);assert(calls==1 and r.status=='submitted'and persist_count==3);b.apply(a);assert(calls==1);now=1003;b.tick();r=b.get(id(9));assert(r.status=='observed_success'and r.delta.exact_recipe_cost and #r.delta.new_models==1 and r.normal_survival_rules_verified==false)end)
test('reloaded journal never resubmits',function()local b=factory(true);local p=b.preview(req());local a=args(p);b.apply(a);local another=factory(true);another.apply(a);assert(calls==1)end)
test('same id different plan conflicts',function()local b=factory(true);local p=b.preview(req());b.apply(args(p));local a=args(p);a.plan_id=id(500);rejects('idempotency_conflict',function()b.apply(a)end);assert(calls==1)end)
test('unregistered living UObject is never transformed',function()local orphan=make_model(99,'ItemChest',{X=0,Y=0,Z=0});orphan._test_registered=false;local cm=orphan:GetConcreteModel(false);cm.GetTransform=function()error('NATIVE FATAL WOULD OCCUR')end;models[#models+1]=orphan;assert(factory(false).preview(req()).apply_enabled==false)end)
test('production module source rejected before UObject access',function()local P=assert(load(source,'@D:/steam/steamapps/common/PalServer/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/build.lua'))();rejects('unsupported',function()P.new{}end)end)
print('PASS '..tested..' normal-build safety/state mock cases; not runtime validation')
