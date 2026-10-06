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
function FindAllOf()return actors end
local last_packet
package.loadlib=function(_,symbol)
 assert(symbol=='palcraft_create_model')
 return function()
  local f=assert(io.open(ROOT..'model-request.bin','rb'));local raw=f:read('*a');f:close();last_packet=raw
  local format='<c8'..string.rep('I8',18)..'dddI4I4'
  local fields={string.unpack(format,raw)}
  assert(fields[1]=='PALCPRC4'and fields[2]==10 and fields[11]==19 and fields[19]==27)
  assert(fields[23]==1 and (fields[24]==0 or fields[24]==1))
  assert(fields[25]==185,'184 byte native header required')
  local material,vertices,indices=string.unpack('<I8I4I4',raw,185)
  assert(material==1000 and vertices==4 and indices==6)
  serial=serial+1;local a=object(serial);a.hidden=fields[24]==1;actors[#actors+1]=a
  f=assert(io.open(ROOT..'model-result.json','wb'));f:write(J.encode({ok=true,actor=('0x%x'):format(serial),component='0x9000',version=4,sections=1,vertices=4,indices=6,stage='created'}));f:close()
 end
end
local M=dofile(dir..'/models.lua')
local groups={{texture='minecraft:block/oak_planks',alpha_mode='opaque',tint=-1,
 vertices={{0,0,0,0,0,1,0,0},{100,0,0,0,0,1,1,0},{100,100,0,0,0,1,1,1},{0,100,0,0,0,1,0,1}},indices={0,2,1,0,3,2}}}
local ctx=object(10,'world');local origin={X=100,Y=200,Z=300}
local fence={world_session='world-A',dim='minecraft:overworld',view=3,mapping='origin-1'}
local function batch(revision,f)return{groups=groups,at={1,64,2},revision=revision or 1,fence=f or fence}end
local function fails(f)assert(not pcall(f));tests=tests+1 end
local before=J.encode(groups)
local h1=M.prepare(ctx,origin,batch());assert(actors[1].hidden and h1.state=='prepared');tests=tests+1
local h2=M.prepare(ctx,origin,batch());assert(actors[2].hidden);tests=tests+1
local collcalls={};local adapter={preflight=function()collcalls[#collcalls+1]='preflight'end,commit=function()collcalls[#collcalls+1]='commit'end}
local result=M.commit_transaction({h1,h2},{},{adapter=adapter,expected_fence=fence});assert(result.registered and not actors[1].hidden and not actors[2].hidden and table.concat(collcalls,',')=='preflight,commit');tests=tests+1
local fresh=M.prepare(ctx,origin,batch(2));M.commit({fresh},{h1,h2});assert(not actors[1].valid and not actors[2].valid and fresh.state=='active');tests=tests+1
local dropped=M.prepare(ctx,origin,batch(3));M.discard(dropped);assert(not actors[4].valid);tests=tests+1
local mixed=M.prepare(ctx,origin,batch(4));local mixed2=M.prepare(ctx,origin,batch(5));fails(function()M.commit({mixed,mixed2},{fresh})end);assert(fresh.state=='active'and actors[3].valid and actors[5].hidden)
local other={world_session='world-A',dim='minecraft:the_nether',view=3,mapping='origin-1'}
local cross=M.prepare(ctx,origin,batch(4,other));fails(function()M.commit_transaction({mixed,cross},{fresh})end)
fails(function()M.commit_transaction({mixed},{fresh},{adapter=adapter,expected_fence=other})end)
fails(function()M.commit_transaction({mixed,mixed},{fresh})end)
fails(function()M.prepare(object(12),origin,batch())end)
local unsupported=batch();unsupported.groups={{texture='x',alpha_mode='cutout'}};fails(function()M.prepare(ctx,origin,unsupported)end)
local unsupportedTint=batch();unsupportedTint.groups={{texture='x',alpha_mode='opaque',tint=0}};fails(function()M.prepare(ctx,origin,unsupportedTint)end)
local unsupportedAnim=batch();unsupportedAnim.groups={{texture='x',alpha_mode='opaque',animation=true}};fails(function()M.prepare(ctx,origin,unsupportedAnim)end)
local failAdapter={preflight=function()error('physics not ready')end,commit=function()error('must never mutate')end}
fails(function()M.commit_transaction({mixed},{fresh},{adapter=failAdapter})end);assert(fresh.state=='active'and mixed.state=='prepared')
M.reset(2,false);fails(function()M.commit({mixed},{})end);assert(M.status().generation==2)
assert(J.encode(groups)==before,'Cached geometry changed');tests=tests+1
local nullBatch=batch(6);nullBatch.groups={{texture=groups[1].texture,alpha_mode='opaque',tint=-1,
 vertices=groups[1].vertices,indices=groups[1].indices,animation_clip={}}}
local nullHandle=M.prepare(ctx,origin,nullBatch);M.discard(nullHandle);tests=tests+1
local provider_calls=0
M.set_material_provider(function(_,g,asset_root)
 assert(g.texture and asset_root:find('/models',1,true));provider_calls=provider_calls+1
 return{material=object(1000,'profile material'),texture=object(2000,'profile texture')}
end)
local provided=M.prepare(ctx,origin,batch(6));assert(provided.state=='prepared'and provider_calls==1);M.discard(provided);tests=tests+1
local f=assert(io_open(temporary..'lua-native-request.bin','wb'));f:write(last_packet);f:close()
print(J.encode({ok=true,tests=tests,wire_bytes=184,immutable_geometry=true,hidden_prepare=true,atomic_revision_fencing=true,collision_preflight=true,capabilities_reject_unsupported=true}))
