-- One explicit model ID. Only reads, with manager registration/reverse checks first.
local M={}
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function same(a,b)return live(a)and live(b)and a:GetFullName()==b:GetFullName()end
local function finite(n)assert(type(n)=='number'and n==n and math.abs(n)<math.huge,'invalid numeric field');return n end
local function text(v)return type(v)=='string'and v or v:ToString()end
local function vector(v,quat)local t={X=finite(v.X),Y=finite(v.Y),Z=finite(v.Z)};if quat then t.W=finite(v.W)end;return t end
function M.read(d,cfg)
    local R,J=d.readers,d.json;local id=R.guid_to_string;local guid=R.guid_from_string
    local function propid(g)return id({A=g.A,B=g.B,C=g.C,D=g.D})end
    assert(d.is_game_thread(),'game-thread required')
    for _,k in ipairs({'model_id','expected_base_id','expected_guild_id','expected_player_uid'})do assert(id(guid(cfg[k]))==cfg[k],'invalid '..k)end
    local out={probe='registered_model_details',lab_only=true,read_only=true,model_id=cfg.model_id,observed_unix=d.now(),
        ok=false,errors=J.array(),warnings=J.array(),mutation_calls=0,registered=false,world_models_enumerated=0}
    local ok,e=pcall(function()
        out.stage='manager';local manager=d.manager();assert(live(manager),'map manager unavailable');out.manager=manager:GetFullName()
        out.stage='canonical_model';local model=manager:FindModel(guid(cfg.model_id));assert(live(model),'model is not registered')
        assert(propid(model.InstanceId)==cfg.model_id,'model property ID mismatch');out.model_object=model:GetFullName()
        out.stage='concrete_reverse';local cm=model:GetConcreteModel(false);assert(live(cm),'no existing concrete model')
        local cmid=cm:GetModelInstanceId();assert(id(cmid)==cfg.model_id,'concrete model ID mismatch')
        assert(same(manager:FindModel(cmid),model),'manager reverse lookup differs')
        assert(same(model:GetConcreteModel(false),cm),'model concrete reverse lookup differs')
        assert(cm.bDisposed==false,'concrete model disposed')
        out.concrete_object=cm:GetFullName();out.concrete_id=id(cm:GetInstanceId());out.registered=true
        out.stage='identity'
        out.build_id=text(model.BuildObjectId);assert(out.build_id=='ItemChest','explicit model is not a wooden ItemChest')
        out.base_id=propid(model.BaseCampIdBelongTo);out.guild_id=propid(model.GroupIdBelongTo);out.build_player_uid=propid(model.BuildPlayerUId)
        assert(out.base_id==cfg.expected_base_id and out.guild_id==cfg.expected_guild_id and out.build_player_uid==cfg.expected_player_uid,'builder/base/guild mismatch')
        assert(id(cm:GetBaseCampIdBelongTo())==out.base_id,'concrete base mismatch')
        local base=cm:GetBaseCampModelBelongTo();assert(live(base),'base unavailable')
        assert(id(base:GetId())==out.base_id and id(base:GetGroupIdBelongTo())==out.guild_id and base:IsAvailable(),'base reverse identity mismatch')
        out.base_object=base:GetFullName();out.base_building_count=finite(base:GetBuildingNum())
        out.stage='transform'
        -- No yielding occurs between registration checks and this getter. Never use an enumerated orphan.
        assert(same(manager:FindModel(cmid),model)and same(model:GetConcreteModel(false),cm),'registration changed before transform')
        local t=cm:GetTransform();out.transform={Translation=vector(t.Translation),Rotation=vector(t.Rotation,true),Scale3D=vector(t.Scale3D)}
        if cfg.expected_location then local a,b=out.transform.Translation,cfg.expected_location
            out.distance_from_expected_cm=math.sqrt((a.X-finite(b.X))^2+(a.Y-finite(b.Y))^2+(a.Z-finite(b.Z))^2)
        end
        out.stage='recipe';local op=manager:GetBuildOperator();assert(live(op)and live(op.DataMap),'recipe data unavailable')
        local recipe=op.DataMap:GetById(d.fname('ItemChest'));out.recipe={required_build_work=finite(recipe.RequiredBuildWorkAmount),materials=J.array()}
        for i=1,4 do local n=finite(recipe['Material'..i..'_Count']);if n>0 then out.recipe.materials[#out.recipe.materials+1]={item=text(recipe['Material'..i..'_Id']),count=n}end end
        out.stage='build_process';local process=model.BuildProcess;out.build_process={available=live(process)==true}
        if live(process)then
            local p=out.build_process;p.object=process:GetFullName();p.state=finite(process.State)
            -- Exact 1.0.5 thunk RVA 02744D70 only compares State +0x48 with 1.
            p.completed=process:IsCompleted();assert(type(p.completed)=='boolean','invalid completion flag')
            local work=process.BuildWork;p.work={available=live(work)==true}
            if live(work)then
                local w=p.work;w.object=work:GetFullName();w.id=propid(work.ID)
                w.owner_model_id=propid(work.OwnerMapObjectModelId);w.owner_concrete_id=propid(work.OwnerMapObjectConcreteModelId);w.base_id=propid(work.BaseCampIdBelongTo)
                w.required_amount=finite(work.RequiredWorkAmount);w.current_amount=finite(work.CurrentWorkAmount)
                w.current_state=finite(work.CurrentState);w.in_progress=work.bInProgress
                w.owner_model_matches=w.owner_model_id==cfg.model_id;w.owner_concrete_matches=w.owner_concrete_id==out.concrete_id;w.base_matches=w.base_id==out.base_id
                w.required_matches_recipe=w.required_amount==out.recipe.required_build_work
                -- No work methods, completion callbacks, virtual IsCompleted, or work state writes.
                if not w.owner_model_matches or not w.owner_concrete_matches or not w.base_matches then out.warnings[#out.warnings+1]='BuildWork owner/base IDs differ; inspect before interpreting progress.'end
            else p.work.note='BuildWork may already be released after normal completion; absence does not prove missing construction work.'end
        end
        out.stage='container';local module=cm:GetItemContainerModule();out.container={module_available=live(module)==true}
        if live(module)then
            assert(same(module:GetOuter(),cm),'container module outer differs from concrete model')
            out.container.module=module:GetFullName();out.container.id=id(module:GetContainerId().ID)
            local c=module:GetContainer();out.container.available=live(c)==true
            if live(c)then
                assert(id(c:GetId().ID)==out.container.id,'container reverse mismatch')
                out.container.object=c:GetFullName();out.container.capacity=finite(c:Num());assert(out.container.capacity>=0 and out.container.capacity<=100 and out.container.capacity%1==0,'unexpected chest capacity')
                local occupied,total=0,0;for index=0,out.container.capacity-1 do local s=c:Get(index);assert(live(s),'chest slot missing');local n=finite(s:GetStackCount());assert(n>=0 and n%1==0,'invalid stack');if n>0 then occupied=occupied+1;total=total+n end end
                out.container.occupied_slots=occupied;out.container.total_stack_units=total;out.container.empty=occupied==0
            end
        end
        out.stage='complete';out.ok=true
    end)
    if not ok then out.errors[#out.errors+1]={stage=out.stage,error=tostring(e)}end
    return out
end
return M
