local dir=assert(arg[1],'Source client directory required')
local temporary=assert(arg[2],'Temporary test directory required')..'/'
local io_open,io_lines,rename,remove=io.open,io.lines,os.rename,os.remove
local ROOT='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local function path(p)return p:sub(1,#ROOT)==ROOT and temporary..p:sub(#ROOT+1)or p end
io.open=function(p,mode)return io_open(path(p),mode)end
io.lines=function(p,...)
 if p:find('UE4SS.log',1,true)then local done=false;return function()if not done then done=true;return'ProcessEvent address 0x13'end end end
 return io_lines(p,...)
end
os.rename=function(a,b)return rename(path(a),path(b))end
os.remove=function(p)return remove(path(p))end
local J=dofile(dir..'/json.lua')
local actors,operations={},{};local serial=0x8000;local tests=0
local function object(address,name)
 return{valid=true,IsValid=function(self)return self.valid end,GetAddress=function()return address end,GetFullName=function()return name or'Actor'end,
  SetActorHiddenInGame=function(self,hidden)self.hidden=hidden;operations[#operations+1]=hidden and'hide'or'show'end,
  K2_DestroyActor=function(self)self.valid=false;operations[#operations+1]='destroy'end,
  SetTextureParameterValue=function()end,SetScalarParameterValue=function()end}
end
local pointers={
 ['/Script/Engine.Default__GameplayStatics']=11,['/Script/Engine.Actor']=12,
 ['/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass']=13,
 ['/Script/Engine.GameplayStatics:FinishSpawningActor']=14,
 ['/Script/ProceduralMeshComponent.ProceduralMeshComponent']=15,
 ['/Script/Engine.Actor:AddComponentByClass']=16,
 ['/Script/ProceduralMeshComponent.ProceduralMeshComponent:CreateMeshSection']=17,
 ['/Script/Engine.PrimitiveComponent:SetMaterial']=18,
 ['/Script/Engine.Actor:K2_SetActorLocation']=20,['/Script/Engine.Actor:FinishAddComponent']=21,
 ['/Script/Engine.PrimitiveComponent:SetCollisionEnabled']=22,
 ['/Script/Engine.PrimitiveComponent:SetCollisionResponseToAllChannels']=23,
 ['/Script/Engine.SceneComponent:SetMobility']=24,['/Script/Engine.PrimitiveComponent:SetGenerateOverlapEvents']=25,
 ['/Script/Engine.Actor:K2_DestroyActor']=26,['/Script/Engine.Actor:SetActorHiddenInGame']=27}
function StaticFindObject(p)
 local o=object(pointers[p]or 1000,p)
 o.CreateDynamicMaterialInstance=function()return object(1000,'material')end
 o.ImportFileAsTexture2D=function()return object(2000,'texture')end
 return o
end
function LoadAsset(p)return object(3000,p)end
function FName(p)return p end
function IsInGameThread()return true end
local components={}
function FindAllOf(kind)return kind=='ProceduralMeshComponent'and components or actors end
local last_packet
local updates,spawns,releases=0,0,0
local states={};local allow_release=true
local function response(value)local f=assert(io.open(ROOT..'model-result.json','wb'));f:write(J.encode(value));f:close()end
package.loadlib=function(_,symbol)
 if symbol=='palcraft_create_model'then return function()
  local f=assert(io.open(ROOT..'model-request.bin','rb'));local raw=f:read('*a');f:close()
  serial=serial+1;spawns=spawns+1
  local actor=object(serial);actor.GetOwner=function()return object(10)end
  local comp=object(serial+0x1000);comp.GetOwner=function()return actor end
  actor.RootComponent=comp;actors[#actors+1]=actor;components[#components+1]=comp
  states[serial]={id=serial+1,component=serial+0x1000}
  response({ok=true,actor=('0x%x'):format(serial),component=('0x%x'):format(serial+0x1000),native_id=serial+1,version=5,sections=1,vertices=4,indices=6,stage='created'})
 end end
 if symbol=='palcraft_update_model'then return function()
  local f=assert(io.open(ROOT..'model-update-request.bin','rb'));local raw=f:read('*a');f:close()
  assert(raw:sub(1,8)=='PALCUPD1')
  local actor,component,id,fn=string.unpack('<I8I8I8I8',raw,185)
  assert(states[actor].id==id and states[actor].component==component and fn~=0)
  local x,y,z,count,flag=string.unpack('<dddI4I4',raw,153);assert(x==200 and y==0 and z==300 and count==1 and flag==0)
  local mat,verts,indices=string.unpack('<I8I4I4',raw,217);assert(mat==1000 and verts==4 and indices==6)
  local f=assert(io_open(temporary..'actual-lua-update.bin','wb'));f:write(raw);f:close()
  updates=updates+1;response({ok=true,actor=('0x%x'):format(actor),component=('0x%x'):format(component),native_id=id,stage='updated'})
 end end
 if symbol=='palcraft_release_model'then return function()
  local f=assert(io.open(ROOT..'model-release-request.bin','rb'));local raw=f:read('*a');f:close()
  local magic,ctx,actor,component,id,destroy,pe,action=string.unpack('<c8I8I8I8I8I8I8I4I4',raw)
  assert(magic=='PALCREL1'and ctx==10 and #raw==64)
  if not allow_release then response({ok=false,stage='stale_model'});return end
  if action==2 then states={};response({ok=true,stage='abandoned'});return end
  assert(states[actor].id==id);states[actor]=nil;releases=releases+1
  if action==1 then for _,a in ipairs(actors)do if a:GetAddress()==actor then a:K2_DestroyActor()end end end
  response({ok=true,stage=action==1 and'destroyed'or'released'})
 end end
 error(symbol)
end
local Models=dofile(dir..'/models.lua')
local groups={{texture='minecraft:block/oak_planks',alpha_mode='opaque',tint=-1,vertices={{0,0,0,0,0,1,0,0},{100,0,0,0,0,1,1,0},{100,100,0,0,0,1,1,1},{0,100,0,0,0,1,0,1}},indices={0,2,1,0,3,2}}}
local ctx=object(10);local actor,component=Models.spawn_groups(ctx,{X=100,Y=200,Z=300},groups,{1,64,2})
local moved={{texture=groups[1].texture,vertices={},indices=groups[1].indices}}
for i,v in ipairs(groups[1].vertices)do moved[1].vertices[i]={table.unpack(v)}end;moved[1].vertices[3][3]=35
Models.update_groups(actor,moved);assert(updates==1 and spawns==1 and releases==0)
allow_release=false;assert(not pcall(Models.release_model,actor,true));allow_release=true
Models.update_groups(actor,moved);assert(updates==2 and spawns==1)
Models.release_model(actor,true);assert(releases==1 and not actors[1].valid)
local nextactor=Models.spawn_groups(ctx,{X=100,Y=200,Z=300},groups,{1,64,2});Models.reset(2,false);assert(next(states)==nil)
print(J.encode({ok=true,checks=6,update_wire_bytes=216,real_lua_serialization=true,no_spawn_per_update=true,failed_release_retains_state=true,abandon_captured_context=true}))
