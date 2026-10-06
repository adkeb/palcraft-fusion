-- BridgeLab: one game-thread read of actual mesh components and collision data.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
assert(dir:gsub('\\','/'):lower():find('d:/palworldserver-lan/bridgelab/',1,true))
return ExecuteInGameThreadWithDelay(5000,function()
 local J=dofile(dir..'json.lua');local R=dofile(dir..'readers.lua')
 local ROOT='D:/PalworldServer-LAN/BridgeLab/rpc/'
 local out={read_only=true,observed_unix=os.time(),models=J.array(),components=J.array(),meshes={},errors=J.array()}
 local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
 local function gid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
 local function vec(v)return {X=v.X,Y=v.Y,Z=v.Z}end
 local function trans(t)return {Translation=vec(t.Translation),Rotation={X=t.Rotation.X,Y=t.Rotation.Y,Z=t.Rotation.Z,W=t.Rotation.W},Scale3D=vec(t.Scale3D)}end
 local function nearby(v)return math.abs(v.X+308100)<2600 and math.abs(v.Y-187800)<2600 and v.Z<5500 end
 local function meshdata(mesh)
  local key=mesh:GetFullName();if out.meshes[key]then return key end
  local b=mesh:GetBounds();local row={asset=key,bounds={Origin=vec(b.Origin),BoxExtent=vec(b.BoxExtent)},boxes=J.array(),convex=J.array()};out.meshes[key]=row
  local body=mesh.BodySetup
  if live(body)then
   local a=body.AggGeom
   for i=1,a.BoxElems:GetArrayNum()do local e=a.BoxElems[i];row.boxes[#row.boxes+1]={Center=vec(e.Center),Rotation={Pitch=e.Rotation.Pitch,Yaw=e.Rotation.Yaw,Roll=e.Rotation.Roll},X=e.X,Y=e.Y,Z=e.Z}end
   for i=1,a.ConvexElems:GetArrayNum()do
    local e=a.ConvexElems[i];local v={transform=trans(e.Transform),vertices=J.array()}
    for n=1,e.VertexData:GetArrayNum()do v.vertices[#v.vertices+1]=vec(e.VertexData[n])end
    row.convex[#row.convex+1]=v
   end
  end
  return key
 end
 local ok,err=pcall(function()
  local mgr;for _,m in ipairs(FindAllOf('PalMapObjectManager')or{})do if live(m)then mgr=m end end
  local f=assert(io.open(ROOT..'actual-geometry-model-ids.json','rb'));local ids=J.decode(f:read('*a'));f:close()
  local selected={};for _,id in ipairs(ids)do selected[id]=true end
  for _,id in ipairs(ids)do
   local m=mgr:FindModel(R.guid_from_string(id))
   if live(m)then out.models[#out.models+1]={id=id,build_id=m.BuildObjectId:ToString(),transform=trans(m.InitialTransformCache)}end
  end
  local seen={}
  for _,class in ipairs({'StaticMeshComponent','InstancedStaticMeshComponent','HierarchicalInstancedStaticMeshComponent'})do
   for _,comp in ipairs(FindAllOf(class)or{})do
    if live(comp)then
     local n=comp:GetFullName()
     if not seen[n]and n:find('PersistentLevel',1,true)then
      seen[n]=true
      local good,e=pcall(function()
       local mesh=comp.StaticMesh;if not live(mesh)then return end
       local owner=comp:GetOwner();if not live(owner)then return end
       local mok,model=pcall(function()return owner.MapObjectModel end)
       if not mok or not live(model)or not selected[gid(model.InstanceId)]then return end
       local count_ok,count=pcall(function()return comp:GetInstanceCount()end)
       local function add(t,index)
        if not nearby(t.Translation)then return end
        local row={component=n,mesh=meshdata(mesh),transform=trans(t),instance_index=index}
        if live(owner)then
         row.actor=owner:GetFullName()
         local mok,model=pcall(function()return owner.MapObjectModel end)
         if mok and live(model)then row.model_id=gid(model.InstanceId)end
        end
        out.components[#out.components+1]=row
       end
       if count_ok and type(count)=='number'and count>0 and count<10000 then
        for i=0,count-1 do local o={};if comp:GetInstanceTransform(i,o,true)then add(o.OutInstanceTransform or o,i)end end
       else add(comp:K2_GetComponentToWorld(),nil)end
      end)
      if not good then out.errors[#out.errors+1]={component=n,error=tostring(e)}end
     end
    end
   end
  end
 end)
 if not ok then out.error=tostring(err)end
 local f=assert(io.open(ROOT..'actual-geometry.json','wb'));f:write(J.encode(out));f:close()
end)
