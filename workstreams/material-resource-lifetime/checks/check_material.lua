-- Four source fixtures; all UObject/asset/drop data are explicitly synthetic.
local root=assert(arg[1],'delta root required')
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local source=read(root..'/source/client/palcraft-collisions.lua')
local material=assert(source:match('(local function material_for%(id%).-)\nlocal function invoke'))
local update=assert(source:match('(local function update_items%(%).-)\nfunction M.status'))
local begin=assert(source:find('function M.stop(',1,true));local finish=assert(source:find('\nlocal tick',begin,true));local cleanup=source:sub(begin,finish-1)
local PARENT='/Game/Pal/Model/Prop/Architecture/Architecture_Wood/Material/MI_PalProp_Wall_Wood.MI_PalProp_Wall_Wood'
local NORMAL='/Engine/EngineMaterials/DefaultNormal.DefaultNormal'
local serial=0
local function object(label)
 serial=serial+1
 local o={label=label,valid=true,address=serial,scalars={},textures={}}
 function o:IsValid()return self.valid end
 function o:GetAddress()assert(self.valid,'stale synthetic resource');return self.address end
 function o:GetFullName()return self.label end
 function o:SetTextureParameterValue(name,texture)self.textures[name]=texture end
 function o:SetScalarParameterValue(name,value)self.scalars[name]=value end
 function o:SetActorEnableCollision(on)self.collision=on end
 function o:K2_SetActorLocation(at)self.position=at end
 function o:K2_SetActorRotation(at)self.rotation=at end
 function o:K2_DestroyActor()self.destroyed=true;self.valid=false end
 return o
end
local function fixture()
 local e={client=true,minecraft_renderer=false,materials={},SHARED='synthetic/',loads={},creates=0,imports=0,
  M={items={},actors={},queue={},queued={}},O={X=10,Y=20,Z=30},bound_context=nil}
 setmetatable(e,{__index=_G})
 e.ctx=object('owned-synthetic-context');e.parent=object('stale-parent');e.parent.valid=false
 e.normal=object('old-normal');e.normal.valid=false
 e.context=function()return e.ctx end
 e.io={open=function(path,mode)return{close=function()end,read=function()return'synthetic-drop-data'end}end}
 e.FName=function(name)return name end
 e.LoadAsset=function(path)assert(path==PARENT or path==NORMAL,'different asset requested');e.loads[#e.loads+1]=path;return object(path)end
 local library={}
 function library:CreateDynamicMaterialInstance(ctx,parent,name,flags)
  assert(ctx==e.ctx and parent.valid and parent.label==PARENT and flags==0,'stale/wrong parent passed to reflection')
  e.creates=e.creates+1;e.last_parent=parent;e.last_name=name;return object('material')
 end
 function library:ImportFileAsTexture2D(ctx,path)assert(ctx==e.ctx);e.imports=e.imports+1;return object(path)end
 e.StaticFindObject=function(path)assert(path:find('Default__Kismet',1,true));return library end
 e.M.context_alive=function()return true end;e.M.status=function()return{running=e.M.running}end
 e.clear_accepted_views=function()end;e.world_observers={};e.world_observer_order={}
 local m=assert(load(material..'\nreturn material_for','actual-source-material','t',e))()
 return e,m
end
local names={};local function check(name,fn)fn();names[#names+1]=name;print('PASS '..name)end
check('stale_parent_is_reloaded_from_exact_original_asset_before_create',function()
 local e,m=fixture();local old_parent=e.parent;local address=m('torch')
 assert(address>0 and e.loads[#e.loads]==PARENT and e.last_parent~=old_parent and e.last_parent.valid)
 assert(e.last_name=='PalCraft_torch' and e.creates==1 and e.imports==1)
 local row=e.materials.torch;assert(row.material.textures['Base Texture']==row.texture and row.texture.Filter==0)
 assert(row.material.scalars['Roughness Add']==0.6 and row.material.scalars['ChangeColor Rate']==nil)
 local serverSource=read(root..'/source/server/palcraft-server.lua')
 local serverMaterial=assert(serverSource:match('(local function material_for%(id%).-)\nlocal function invoke'))
 e.client=false;local old=#e.loads;local server=assert(load(serverMaterial..'\nreturn material_for','actual-source-server-material','t',e))()
 assert(server('torch')==0 and #e.loads==old) -- Preserved server/non-material role gate.
end)
check('cached_MID_texture_pair_is_reused_or_reacquired_only_when_invalid',function()
 local e,m=fixture();local first=m('torch');local calls=e.creates
 assert(m('torch')==first and e.creates==calls)
 e.materials.torch.material.valid=false;local second=m('torch');assert(second~=first and e.creates==calls+1)
 e.materials.torch.texture.valid=false;local third=m('torch');assert(third~=second and e.creates==calls+2)
 assert(e.loads[#e.loads]==PARENT and e.materials.torch.texture.valid)
end)
check('original_nonsolid_torch_drop_path_still_spawns_and_moves_with_same_material',function()
 local e,m=fixture();local actor=object('StaticMeshActor');local data={unix=100,items={{id=12,item='minecraft:torch',x=1,y=63,z=-16}}}
 e.os={time=function()return 100 end,clock=function()return 2 end};e.J={decode=function()return data end}
 e.live=function(o)return o and o:IsValid()end;e.FindAllOf=function(name)assert(name=='StaticMeshActor');return{actor}end
 e.invokes=0;e.invoke=function(action,prior,x,y,z,bounds,id)
  assert(action==0 and id=='minecraft:torch'and bounds[1]==-.15);e.invokes=e.invokes+1;m(id);return actor:GetAddress()
 end
 local fn=assert(load(update..'\nreturn update_items','actual-source-update-items','t',e))();fn()
 assert(e.invokes==1 and e.M.items['12'].actor==actor and actor.collision==false)
 assert(actor.position.X==110 and actor.position.Y==1620 and math.abs(actor.position.Z+40)<.00001)
 assert(e.materials.torch.material.textures['Base Texture']==e.materials.torch.texture)
end)
check('stop_and_abandon_release_only_owned_Lua_cache_references',function()
 for _,method in ipairs({'stop','abandon'})do
  local e,m=fixture();m('torch');local borrowed=e.materials.torch.material;local unrelated=object('unrelated-resource')
  assert(load(cleanup,'actual-source-cleanup','t',e))()
  e.M[method](true)
  assert(next(e.materials)==nil and e.parent==nil and e.normal==nil)
  assert(borrowed.valid and not borrowed.destroyed and unrelated.valid and not unrelated.destroyed)
 end
end)
assert(#names==4);print('RESULT 4 PASS; source fixture only; no Game/Save/GC-root or actual crash-fix acceptance')
