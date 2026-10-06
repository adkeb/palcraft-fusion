-- Minecraft blockstate/model assets rendered as real UE procedural meshes.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local J=dofile(dir..'json.lua')
local ROOT='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local ASSETS=ROOT..'models/'
local M={};local cache,materials={},{};local native,pe,parent,normal
local function resource(id)return id:find(':',1,true)and id or'minecraft:'..id end
local function asset(kind,id)
 local path=kind..'/'..resource(id):gsub(':','/')..'.json'
 if cache[path]then return cache[path]end
 local f=io.open(ASSETS..path,'rb');if not f then return nil end
 local v=J.decode(f:read('*a'));f:close();cache[path]=v;return v
end
local function matches(condition,props)
 if not condition then return true end
 if condition.OR then for _,v in ipairs(condition.OR)do if matches(v,props)then return true end end;return false end
 if condition.AND then for _,v in ipairs(condition.AND)do if not matches(v,props)then return false end end;return true end
 for k,v in pairs(condition)do
  local found=false;local value=tostring(v);local negate=value:sub(1,1)=='!';if negate then value=value:sub(2)end
  for option in value:gmatch('[^|]+')do if props[k]==option then found=true end end
  if found==negate then return false end
 end;return true
end
local function rotate(p,spec,point)
 local x,y,z=p[1],p[2],p[3];if point then x=x-.5;y=y-.5;z=z-.5 end
 local a=math.rad(-(spec.x or 0));y,z=math.cos(a)*y-math.sin(a)*z,math.sin(a)*y+math.cos(a)*z
 a=math.rad(-(spec.y or 0));x,z=math.cos(a)*x+math.sin(a)*z,-math.sin(a)*x+math.cos(a)*z
 if point then x=x+.5;y=y+.5;z=z+.5 end;return{x,y,z}
end
local basis={down={{1,0,0},{0,0,-1}},up={{1,0,0},{0,0,1}},north={{-1,0,0},{0,-1,0}},south={{1,0,0},{0,-1,0}},west={{0,0,1},{0,-1,0}},east={{0,0,-1},{0,-1,0}}}
local function dot(a,b)return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]end
local function uvlock(uv,face,spec,n)
 if not spec.uvlock then return uv end
 local target=math.abs(n[2])>.9 and(n[2]>0 and'up'or'down')or(math.abs(n[1])>.9 and(n[1]>0 and'east'or'west')or(n[3]>0 and'south'or'north'))
 local u,v=rotate(basis[face.direction][1],spec),rotate(basis[face.direction][2],spec)
 local a,b=uv[1]-.5,uv[2]-.5
 return{.5+dot(u,basis[target][1])*a+dot(v,basis[target][1])*b,.5+dot(u,basis[target][2])*a+dot(v,basis[target][2])*b}
end
function M.geometry(id,state,x,y,z)
 local block=asset('states',id);if not block then return nil,'missing_blockstate' end
 local props={};for k,v in(state or''):gmatch('([%w_]+)=([%w_]+)')do props[k]=v end
 local selected={};local seed=math.abs((x or 0)*73428767+(y or 0)*912931+(z or 0)*42317861)
 local function choose(spec)
  if spec[1]then local total=0;for _,v in ipairs(spec)do total=total+(v.weight or 1)end;local n=seed%total;for _,v in ipairs(spec)do n=n-(v.weight or 1);if n<0 then spec=v;break end end end
  selected[#selected+1]=spec
 end
 for key,spec in pairs(block.variants or{})do local condition={};for k,v in key:gmatch('([^=,]+)=([^,]+)')do condition[k]=v end;if matches(condition,props)then choose(spec);break end end
 for _,part in ipairs(block.multipart or{})do if matches(part.when,props)then choose(part.apply)end end
 local groups={};local count=0
 for _,spec in ipairs(selected)do
  local model=asset('models',spec.model)
  for _,face in ipairs(model and model.faces or{})do
   local g=groups[face.texture];if not g then g={texture=face.texture,vertices={},indices={}};groups[face.texture]=g end
   local first=#g.vertices;local n=rotate(face.normal,spec)
   for i,p in ipairs(face.vertices)do
    local q=rotate(p,spec,true);local uv=uvlock(face.uv[i],face,spec,n)
    g.vertices[#g.vertices+1]={q[1]*100,-q[3]*100,q[2]*100,n[1],-n[3],n[2],uv[1],uv[2]}
   end
   for _,i in ipairs({0,2,1,0,3,2})do g.indices[#g.indices+1]=first+i end;count=count+1
  end
 end
 if count==0 then return nil,'special_model_required' end
 local result={};for _,g in pairs(groups)do result[#result+1]=g end;table.sort(result,function(a,b)return a.texture<b.texture end)
 return result
end
local function address(path)local o=StaticFindObject(path);assert(o and o:IsValid(),path);return o:GetAddress()end
local function prepare()
 if native then return end
 parent=LoadAsset('/Game/Pal/Material/Prop/MI_PalPropBase.MI_PalPropBase');assert(parent:IsValid(),'Base prop material unavailable')
 normal=LoadAsset('/Engine/EngineMaterials/DefaultNormal.DefaultNormal')
 for line in io.lines(dir..'../../../UE4SS.log')do local a=line:match('ProcessEvent address (0x%x+)');if a then pe=tonumber(a)end end;assert(pe,'ProcessEvent')
 native=assert(package.loadlib(dir..'../../../../PalCraftModel-v2.dll','palcraft_create_model'))
end
local function material(ctx,name)
 if materials[name]then return materials[name]:GetAddress()end
 local m=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,parent,FName('MC_'..name:gsub('[:/]','_')),0)
 local tex=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,ASSETS..'textures/'..name:gsub(':','/')..'.png')
 assert(m:IsValid()and tex:IsValid(),'Model texture '..name);tex.Filter=0
 m:SetTextureParameterValue(FName('Base Texture'),tex)
 if normal:IsValid()then m:SetTextureParameterValue(FName('Normal Map'),normal)end
 m:SetScalarParameterValue(FName('Roughness Add'),1);m:SetScalarParameterValue(FName('ChangeColor Rate'),0)
 materials[name]=m;return m:GetAddress()
end
function M.spawn(ctx,origin,geometry,x,y,z)
 local groups,why=M.geometry(geometry.id,geometry.state,x,y,z);if not groups then return nil,why end
 prepare()
 local functions={ctx:GetAddress(),address('/Script/Engine.Default__GameplayStatics'),address('/Script/Engine.Actor'),address('/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass'),address('/Script/Engine.GameplayStatics:FinishSpawningActor'),address('/Script/ProceduralMeshComponent.ProceduralMeshComponent'),address('/Script/Engine.Actor:AddComponentByClass'),address('/Script/ProceduralMeshComponent.ProceduralMeshComponent:CreateMeshSection'),address('/Script/Engine.PrimitiveComponent:SetMaterial'),pe,address('/Script/Engine.Actor:K2_SetActorLocation')}
 local f=assert(io.open(ROOT..'model-request.bin','wb'))
 f:write(string.pack('<c8'..string.rep('I8',11),'PALCPRC2',table.unpack(functions)))
 f:write(string.pack('<dddI4I4',origin.X+x*100,origin.Y-z*100,origin.Z+(y-64)*100,#groups,0))
 for _,g in ipairs(groups)do
  f:write(string.pack('<I8I4I4',material(ctx,g.texture),#g.vertices,#g.indices))
  for _,v in ipairs(g.vertices)do f:write(string.pack('<dddddddd',table.unpack(v)))end
  for _,i in ipairs(g.indices)do f:write(string.pack('<I4',i))end
 end;f:close();native()
 f=assert(io.open(ROOT..'model-result.json','rb'));local result=J.decode(f:read('*a'));f:close();assert(result.ok,'Procedural model: '..tostring(result.stage))
 return tonumber(result.actor),tonumber(result.component)
end
return M
