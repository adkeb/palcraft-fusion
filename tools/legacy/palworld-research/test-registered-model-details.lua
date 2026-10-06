local root='work/palworld-live/'
local J=dofile(root..'bridge/PalLiveBridge/Scripts/json.lua')
local Core=dofile(root..'lab/registered-model-details-core.lua')
local function obj(name,t)t=t or{};t.IsValid=function()return true end;t.GetFullName=function()return name end;return t end
local function guid(s)return{A=s,B=0,C=0,D=0}end
local function setup()
    local transform_calls=0;local model,cm
    local work=obj('Work',{ID=guid('work'),OwnerMapObjectModelId=guid('model'),OwnerMapObjectConcreteModelId=guid('concrete'),BaseCampIdBelongTo=guid('base'),RequiredWorkAmount=1000,CurrentWorkAmount=37,CurrentState=1,bInProgress=true})
    local process=obj('Process',{State=0,BuildWork=work,IsCompleted=function(self)return self.State==1 end})
    local base=obj('Base',{GetId=function()return guid('base')end,GetGroupIdBelongTo=function()return guid('guild')end,IsAvailable=function()return true end,GetBuildingNum=function()return 45 end})
    local container=obj('Container',{GetId=function()return{ID=guid('container')}end,Num=function()return 10 end,Get=function()return obj('Slot',{GetStackCount=function()return 0 end})end})
    local module=obj('Module',{GetContainerId=function()return{ID=guid('container')}end,GetContainer=function()return container end,GetOuter=function()return cm end})
    cm=obj('Concrete',{bDisposed=false,GetModelInstanceId=function()return guid('model')end,GetInstanceId=function()return guid('concrete')end,
        GetBaseCampIdBelongTo=function()return guid('base')end,GetBaseCampModelBelongTo=function()return base end,
        GetTransform=function()transform_calls=transform_calls+1;return{Translation={X=1,Y=2,Z=3},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}end,
        GetItemContainerModule=function()return module end})
    model=obj('Model',{InstanceId=guid('model'),BuildObjectId='ItemChest',BaseCampIdBelongTo=guid('base'),GroupIdBelongTo=guid('guild'),BuildPlayerUId=guid('player'),BuildProcess=process,GetConcreteModel=function(_,force)assert(force==false);return cm end})
    local data=obj('Data',{GetById=function()return{RequiredBuildWorkAmount=1000,Material1_Count=15,Material1_Id='Wood',Material2_Count=5,Material2_Id='Stone',Material3_Count=0,Material4_Count=0}end})
    local op=obj('Operator',{DataMap=data})
    local mgr=obj('Manager',{FindModel=function(_,id)assert(id.A=='model');return model end,GetBuildOperator=function()return op end})
    local d={readers={guid_to_string=function(v)assert(type(v)=='table');return v.A end,guid_from_string=function(v)assert(type(v)=='string');return guid(v)end},json=J,is_game_thread=function()return true end,now=function()return 1000 end,fname=function(v)return v end,manager=function()return mgr end}
    local cfg={model_id='model',expected_base_id='base',expected_guild_id='guild',expected_player_uid='player',expected_location={X=1,Y=2,Z=3}}
    return{run=function()return Core.read(d,cfg)end,model=model,cm=cm,mgr=mgr,process=process,work=work,module=module,container=container,transform_calls=function()return transform_calls end}
end
local n=0;local function case(name,fn)local ok,e=pcall(fn);assert(ok,name..': '..tostring(e));n=n+1;print('ok '..name)end
case('registered_building_details',function()local e=setup();local r=e.run();assert(r.ok and r.registered and e.transform_calls()==1 and r.build_process.work.current_amount==37 and r.container.empty);assert(r.build_process.completed==false and r.build_process.work.required_matches_recipe);J.encode(r)end)
case('unregistered_never_reads_transform',function()local e=setup();e.mgr.FindModel=function()return nil end;local r=e.run();assert(not r.ok and e.transform_calls()==0)end)
case('model_property_mismatch_never_reads_transform',function()local e=setup();e.model.InstanceId=guid('orphan');local r=e.run();assert(not r.ok and e.transform_calls()==0)end)
case('concrete_guid_mismatch_never_reads_transform',function()local e=setup();e.cm.GetModelInstanceId=function()return guid('orphan')end;local r=e.run();assert(not r.ok and e.transform_calls()==0)end)
case('manager_reverse_mismatch_never_reads_transform',function()local e=setup();local calls=0;e.mgr.FindModel=function()calls=calls+1;if calls==1 then return e.model end;return nil end;local r=e.run();assert(not r.ok and e.transform_calls()==0)end)
case('disposed_never_reads_transform',function()local e=setup();e.cm.bDisposed=true;local r=e.run();assert(not r.ok and e.transform_calls()==0)end)
case('wrong_player_never_reads_transform',function()local e=setup();e.model.BuildPlayerUId=guid('other');local r=e.run();assert(not r.ok and e.transform_calls()==0)end)
case('registration_lost_before_transform',function()local e=setup();local calls=0;e.mgr.FindModel=function()calls=calls+1;if calls<=2 then return e.model end;return nil end;local r=e.run();assert(not r.ok and e.transform_calls()==0)end)
case('completed_work_can_be_gone',function()local e=setup();e.process.State=1;e.process.BuildWork=nil;local r=e.run();assert(r.ok and r.build_process.completed and not r.build_process.work.available)end)
case('incomplete_container_can_be_absent',function()local e=setup();e.cm.GetItemContainerModule=function()return nil end;local r=e.run();assert(r.ok and r.container.module_available==false)end)
case('work_mismatch_reported_not_hidden',function()local e=setup();e.work.OwnerMapObjectModelId=guid('other');local r=e.run();assert(r.ok and #r.warnings==1 and not r.build_process.work.owner_model_matches)end)
print('PASS '..n..' registered model cases')
