-- Shared lab companion: MC is authoritative; Unreal owns rendering and physics.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local path=dir:gsub('\\','/');local client=path:lower():find('d:/palworldserver-lan/palcraft-client/',1,true)
assert(client or path:lower():find('d:/palworldserver-lan/bridgelab/',1,true),'Lab paths only')
local J=dofile(dir..'json.lua');local JOURNAL='D:/PalworldServer-LAN/BridgeLab/rpc/'
local SHARED='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local ROOT=client and SHARED or JOURNAL
local minecraft_renderer=false
local models
if client then local f=io.open(dir..'models.lua','rb');if f then f:close();models=dofile(dir..'models.lua')end end
local EVENT_PATH=JOURNAL..'palcraft-events.ndjson'
local settings=io.open(SHARED..'world-backend.json','rb');if settings then local v=J.decode(settings:read('*a'));settings:close();if v.journal then EVENT_PATH=v.journal end end
local O={X=-308099.9282280116,Y=187800.81696803804,Z=3480.330899345611}
local origin=io.open(SHARED..'world-origin.json','rb');if origin then O=J.decode(origin:read('*a'));origin:close()end
local FULL={{0,0,0,1,1,1}}
local M={items={},actors={},queue={},offset=0,pending='',running=true,changes=0,origin=O}
local native,addresses,process_event,world_address,mesh,parent,normal;local materials={}
local function live(x)return x and x:IsValid()and not x:GetFullName():find('Default__',1,true)end
local function write(name,v)local f=assert(io.open(ROOT..name,'wb'));f:write(J.encode(v));f:close()end
local function address(name)local o=StaticFindObject(name);assert(o and o:IsValid(),name);return o:GetAddress()end
local function context()for _,a in ipairs(FindAllOf('GameStateBase')or{})do if live(a)then return a end end;error('No game state')end
local function prepare()
 if native then return end
 native=assert(package.loadlib(dir..'../../../../PalCraftMesh-v6.dll','palcraft_spawn_box'))
 if client then
  mesh=LoadAsset('/Engine/BasicShapes/Cube.Cube');assert(mesh:IsValid(),'Cube asset')
  parent=LoadAsset('/Game/Pal/Model/Prop/Architecture/Architecture_Wood/Material/MI_PalProp_Wall_Wood.MI_PalProp_Wall_Wood')
  assert(parent:IsValid(),'Wood material')
  normal=LoadAsset('/Engine/EngineMaterials/DefaultNormal.DefaultNormal')
 end
 for line in io.lines(dir..'../../../UE4SS.log')do local a=line:match('ProcessEvent address (0x%x+)');if a then process_event=tonumber(a)end end
 assert(process_event,'ProcessEvent address unavailable')
 addresses={}
 for _,name in ipairs({'BoxComponent:SetBoxExtent','PrimitiveComponent:SetCollisionEnabled','PrimitiveComponent:SetGenerateOverlapEvents','PrimitiveComponent:SetCollisionResponseToAllChannels','PrimitiveComponent:SetCollisionResponseToChannel','ActorComponent:SetIsReplicated','Actor:SetReplicates','Actor:SetReplicateMovement','Actor:SetActorHiddenInGame','Actor:K2_DestroyActor'})do addresses[#addresses+1]=address('/Script/Engine.'..name)end
 if client then addresses[1]=address('/Script/Engine.SceneComponent:SetMobility')end
end
local function material_for(id)
 if not client then return 0 end
 local texture_name=(id or 'minecraft:oak_planks'):gsub('^minecraft:',''):gsub('_stairs$',''):gsub('_slab$','')
 if texture_name=='oak'then texture_name='oak_planks'end
 if materials[texture_name]then return materials[texture_name]:GetAddress()end
 local texture_path=SHARED..'textures/'..texture_name..'.png';local f=io.open(texture_path,'rb')
 if f then f:close()else texture_path=SHARED..'textures/stone.png'end
 local ctx=context()
 local material=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,parent,FName('PalCraft_'..texture_name),0)
 assert(material:IsValid(),'Dynamic material')
 local texture=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,texture_path)
 assert(texture:IsValid(),'MC texture');texture.Filter=0
 material:SetTextureParameterValue(FName('Base Texture'),texture)
 if normal and normal:IsValid()then material:SetTextureParameterValue(FName('Normal Map'),normal)end
 material:SetScalarParameterValue(FName('Roughness Add'),0.6)
 materials[texture_name]=material;return material:GetAddress()
end
local function invoke(action,actor,x,y,z,bounds,id)
 prepare();local ctx=context():GetAddress()
 if not world_address then world_address=ctx end;assert(ctx==world_address,'World changed')
 local b=bounds or FULL[1]
 local p={O.X+(x+(b[1]+b[4])*.5)*100,O.Y-(z+(b[3]+b[6])*.5)*100,O.Z+(y-64+(b[2]+b[5])*.5)*100}
 local fields={ctx,address('/Script/Engine.Default__GameplayStatics'),address(client and '/Script/Engine.StaticMeshActor'or'/Script/Engine.TriggerBox'),address('/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass'),address('/Script/Engine.GameplayStatics:FinishSpawningActor')}
 local material=action==0 and material_for(id)or 0
 local f=assert(io.open(ROOT..'palcraft-spawn-request.bin','wb'))
 f:write(string.pack('<c8I8I8I8I8I8','PALCMSH6',table.unpack(fields)))
 f:write(string.pack('<dddI8I8I8',p[1],p[2],p[3],action,actor or 0,process_event))
 f:write(string.pack('<'..string.rep('I8',10),table.unpack(addresses)))
 f:write(string.pack('<I8I8I8I8ddd',client and mesh:GetAddress()or 0,material,address('/Script/Engine.StaticMeshComponent:SetStaticMesh'),address('/Script/Engine.PrimitiveComponent:SetMaterial'),b[4]-b[1],b[6]-b[3],b[5]-b[2]))
 f:close();native()
 f=assert(io.open(ROOT..'palcraft-spawn-result.json','rb'));local result=J.decode(f:read('*a'));f:close()
 assert(result.ok,'Native block: '..tostring(result.stage));return tonumber(result.actor)
end
local function key(x,y,z)return('%d:%d:%d'):format(x,y,z)end
local function apply(kind,x,y,z,geometry)
 local k=key(x,y,z);local previous=M.actors[k]
 local signature=kind=='set'and J.encode(geometry or {id='minecraft:oak_planks',boxes=FULL})or nil
 if previous and signature==previous.signature then return end
 if previous then for _,a in ipairs(previous.handles)do invoke(1,a,x,y,z)end;if previous.model then invoke(1,previous.model,x,y,z)end;M.actors[k]=nil end
 if kind=='set'then
  local entry={handles={},signature=signature,id=geometry and geometry.id or'minecraft:oak_planks'};M.actors[k]=entry
  if models and geometry then entry.model,entry.model_status=models.spawn(context(),O,geometry,x,y,z)end
  for _,b in ipairs(geometry and geometry.boxes or FULL)do entry.handles[#entry.handles+1]=invoke(client and(minecraft_renderer or entry.model)and 3 or 0,nil,x,y,z,b,entry.id)end
 end
 M.changes=M.changes+1
end
local function update_items()
 if not client or minecraft_renderer then return end
 local f=io.open(SHARED..'drops.json','rb');local data
 if f then local ok,r=pcall(J.decode,f:read('*a'));f:close();if ok and os.time()-(r.unix or 0)<3 then data=r end end
 local wanted={}
 for _,d in ipairs(data and data.items or{})do
  local key=tostring(d.id);wanted[key]=true;local entry=M.items[key]
  if not entry then
   local h=invoke(0,nil,d.x,d.y,d.z,{-0.15,0.1,-0.15,0.15,0.4,0.15},d.item)
   local actor;for _,a in ipairs(FindAllOf('StaticMeshActor')or{})do if live(a)and a:GetAddress()==h then actor=a;break end end
   assert(live(actor),'Dropped item actor unavailable');actor:SetActorEnableCollision(false)
   entry={handle=h,actor=actor,item=d.item};M.items[key]=entry
  end
  entry.actor:K2_SetActorLocation({X=O.X+d.x*100,Y=O.Y-d.z*100,Z=O.Z+(d.y-64+.3)*100},false,{},true)
  entry.actor:K2_SetActorRotation({Pitch=0,Yaw=(os.clock()*60)%360,Roll=0},false)
 end
 for k,v in pairs(M.items)do if not wanted[k]then if live(v.actor)then v.actor:K2_DestroyActor()end;M.items[k]=nil end end
end
function M.status()
 local n,shapes,drops,model_count=0,0,0,0;local types,unconverted={},{};for _ in pairs(M.items)do drops=drops+1 end
 for _,a in pairs(M.actors)do n=n+1;shapes=shapes+#a.handles;types[a.id]=(types[a.id]or 0)+1;if a.model then model_count=model_count+1 elseif client then unconverted[a.id]=a.model_status or'basic_mesh'end end
 return {running=M.running,error=M.error,blocks=n,shapes=shapes,models=model_count,unconverted=unconverted,drops=drops,types=types,pending=#M.queue,changes=M.changes,offset=M.offset,side=client and'client'or'server',render=client and'native_unreal_mesh'or'collision',version=6,origin=O}
end
function M.stop()
 M.running=false;for _,d in pairs(M.items)do if live(d.actor)then d.actor:K2_DestroyActor()end end;M.items={};for _,a in pairs(M.actors)do for _,h in ipairs(a.handles)do invoke(1,h,0,64,0)end;if a.model then invoke(1,a.model,0,64,0)end end;M.actors={};return M.status()
end
function M.abandon()M.running=false;M.actors={};M.items={}end
local tick
tick=function()
 if not M.running then return end
 local ok,e=pcall(function()
  if client and world_address and context():GetAddress()~=world_address then M.abandon();return end
  if not M.cleaned then
   M.cleaned=true;local owner=context():GetAddress()
   for _,a in ipairs(FindAllOf(client and 'StaticMeshActor'or'TriggerBox')or{})do
    if live(a)then
     local o=a:GetOwner();local p=a:K2_GetActorLocation()
     if live(o)and o:GetAddress()==owner and math.abs(p.X-O.X)<6400 and math.abs(p.Y-O.Y)<6400 then invoke(1,a:GetAddress(),0,64,0)end
    end
   end
  end
  local f=io.open(EVENT_PATH,'rb')
  if f then f:seek('set',M.offset);M.pending=M.pending..f:read('*a');M.offset=f:seek();f:close()end
  while true do
   local last=M.pending:find('\n',1,true);if not last then break end
   local line=M.pending:sub(1,last-1);M.pending=M.pending:sub(last+1)
   if #line>0 then local row=J.decode(line)
    if row.t=='blocks'then
     local geometry={};for _,g in ipairs(row.geometry or{})do geometry[key(table.unpack(g.at))]=g end
     for _,kind in ipairs({'clear','set'})do local a=row[kind]or{};for i=1,#a,3 do M.queue[#M.queue+1]={kind,a[i],a[i+1],a[i+2],geometry[key(a[i],a[i+1],a[i+2])]}end end
    end
   end
  end
  M.item_tick=(M.item_tick or 0)+1;if client and M.item_tick%4==0 then update_items()end
  for _=1,math.min(4,#M.queue)do local q=table.remove(M.queue,1);apply(table.unpack(q))end
 end)
 if not ok then M.error=tostring(e);M.running=false end
 write('palcraft-collision-status.json',M.status())
 if M.running then ExecuteInGameThreadWithDelay(50,tick)end
end
ExecuteInGameThreadWithDelay(500,tick)
return M
