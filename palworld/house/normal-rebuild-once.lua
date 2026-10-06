-- Isolated Lab only. Root deploys; preview is currently the only enabled mode.
local source=debug.getinfo(1,'S').source
local directory=assert(source:match('^@(.*[/\\])'))
assert(directory:lower():gsub('\\','/')=='d:/palworldserver-lan/bridgelab/pal/binaries/win64/ue4ss/mods/pallivebridge/scripts/','BridgeLab only')
local ROOT='D:/PalworldServer-LAN/BridgeLab/rpc/'
local J=dofile(directory..'json.lua');local R=dofile(directory..'readers.lua')
local B=dofile(directory..'build.lua');local Detail=dofile(directory..'registered-model-details-core.lua')
local Materials=dofile(directory..'normal-rebuild-materials.lua');local Core=dofile(directory..'normal-rebuild-once-core.lua')
local C={player_uid='22222222-0000-0000-0000-000000000000',base_id='00000000-0000-4000-8000-000000000031',guild_id='00000000-0000-4000-8000-00000000001b',
    old_model_id='00000000-0000-4000-8000-000000000030',manual_observation_id='00000000-0000-4000-8000-00000000002d',
    position={X=-308391.0111896781,Y=189594.97191406583,Z=3330.3418362220582},rotation={X=0,Y=0,Z=-0.93070700155921648,W=0.3657656042449216}}
local function read(p,max)local f=assert(io.open(p,'rb'));local s=f:read(max+1);f:close();assert(#s<=max,'oversized input');return J.decode(s,{max_bytes=max})end
local cfg=read(ROOT..'normal-rebuild-once-arm.json',8192)
assert(type(cfg.nonce)=='string'and cfg.nonce:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'invalid nonce')
assert(cfg.mode=='preview','execute remains disabled pending independent review')
local capture=read(ROOT..'manual-build-observation-'..C.manual_observation_id..'.json',1048576)
assert(capture.status=='complete'and capture.target_player_uid==C.player_uid and #capture.errors==0,'manual capture invalid')
local request=capture.request
assert(request.build_id=='ItemChest'and #request.archives==0 and request.archive_total_bytes==0 and request.debug.bNotConsumeMaterials==false,'manual request differs')
for k,v in pairs(C.position)do assert(math.abs(request.location[k]-v)<0.000001,'manual position differs')end
for k,v in pairs(C.rotation)do assert(math.abs(request.rotation[k]-v)<0.000000000001,'manual rotation differs')end
local manual=read(ROOT..'registered-model-details-00000000-0000-4000-8000-000000000018.json',1048576)
assert(manual.ok and manual.registered and manual.model_id==C.old_model_id and manual.base_id==C.base_id and manual.guild_id==C.guild_id and manual.build_player_uid==C.player_uid,'manual model evidence differs')
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
            if kind~='None'and kind~=''then
                assert(propid(model.BaseCampIdBelongTo)==C.base_id,'collection model base differs')
                local row={id=id,build_id=kind,guild_id=propid(model.GroupIdBelongTo),builder_uid=propid(model.BuildPlayerUId)}
                local cm=model:GetConcreteModel(false)
                if live(cm)then
                    local gid=cm:GetModelInstanceId()
                    assert(R.guid_to_string(gid)==id and same(mgr:FindModel(gid),model)and same(model:GetConcreteModel(false),cm)and cm.bDisposed==false,'concrete registration mismatch')
                    row.position=vec(cm:GetTransform().Translation);row.position_source='registered_concrete'
                else row.position=vec(model.InitialTransformCache.Translation);row.position_source='model_initial_cache_only'end
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
local runner
local deps={json=J,now=os.time,is_game_thread=IsInGameThread,has_fence=function()return exists(FENCE)end,
    emit=function(report)write_json(output,report,true)end,cleanup=function()end,
    material_diff=Materials.diff,read_materials=materials,
    preflight=function()
        local ctx=resolve();local site=site_snapshot();local p={X=ctx.summary.position.x,Y=ctx.summary.position.y,Z=ctx.summary.position.z}
        assert(distance(C.position,site.base_position,true)<site.base_range-200 and distance(p,site.base_position,true)<site.base_range-100,'player/manual point must remain inside old base')
        assert(distance(C.position,p,false)<=1500,'player must stand within 15m of exact manual point')
        local op=manager():GetBuildOperator();assert(live(op)and live(op.DataMap),'build recipe unavailable')
        local r=op.DataMap:GetById(FName('ItemChest'));assert(r.RequiredBuildWorkAmount==1000,'recipe work differs')
        local recipe={};for i=1,4 do local n=r['Material'..i..'_Count'];if n>0 then recipe[text(r['Material'..i..'_Id'])]=n end end
        assert(recipe.Wood==15 and recipe.Stone==5,'recipe material differs');for id in pairs(recipe)do assert(id=='Wood'or id=='Stone','unexpected recipe ingredient')end
        local m=materials(ctx)
        return{live_context_verified=true,tech_guild_base_verified=true,old_manual_model_absent=site.old_manual_model_absent,
            context=ctx.summary,site=site,materials=m,materials_sufficient=m.totals.Wood>=15 and m.totals.Stone>=5,
            recipe={Wood=15,Stone=5,work=1000},fixed_request={build_id='ItemChest',location=C.position,rotation=C.rotation,archives=J.array(),debug={bNotConsumeMaterials=false}},
            placement_precheck='Exact successfully built manual position only; native server remains responsible for current collision, ground and support validation.'}, {summary=ctx.summary,site=site}
    end,
    claim_intent=function(report)write_json(FENCE,report,false);return true end,
    final_check=function()error('execute not yet enabled')end,
    submit=function()error('execute not yet enabled')end,
    observe=function()error('execute not yet enabled')end}
runner=Core.new(deps,cfg)
ExecuteInGameThread(function()runner.start();print('[NormalRebuildOnce] '..runner.report.status..'\n')end)
return runner
