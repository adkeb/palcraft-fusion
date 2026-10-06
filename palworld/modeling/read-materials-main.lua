local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
assert(dir:gsub('\\','/'):lower():find('d:/palworldserver-lan/bridgelab/',1,true))
return ExecuteInGameThreadWithDelay(5000,function()
 local J=dofile(dir..'json.lua');local root='D:/PalworldServer-LAN/BridgeLab/rpc/'
 local f=assert(io.open(root..'material-components.json','rb'));local list=J.decode(f:read('*a'));f:close()
 local out={read_only=true,components=J.array(),materials={},errors=J.array(),observed_unix=os.time()}
 local function live(o)return o and o:IsValid()end
 local function material(m)
  if not live(m)then return nil end
  local name=m:GetFullName();if out.materials[name]then return name end
  local row={name=name,scalars={},vectors={},textures={}};out.materials[name]=row
  local ok,parent=pcall(function()return m.Parent end)
  if ok and live(parent)then row.parent=material(parent)end
  pcall(function()local a=m.ScalarParameterValues;for i=1,a:GetArrayNum()do local v=a[i];row.scalars[v.ParameterInfo.Name:ToString()]=v.ParameterValue end end)
  pcall(function()local a=m.VectorParameterValues;for i=1,a:GetArrayNum()do local v=a[i];local c=v.ParameterValue;row.vectors[v.ParameterInfo.Name:ToString()]={R=c.R,G=c.G,B=c.B,A=c.A}end end)
  pcall(function()local a=m.TextureParameterValues;for i=1,a:GetArrayNum()do local v=a[i];if live(v.ParameterValue)then row.textures[v.ParameterInfo.Name:ToString()]=v.ParameterValue:GetFullName()end end end)
  return name
 end
 for _,v in ipairs(list)do
  local ok,e=pcall(function()
   local comp=StaticFindObject(assert(v.component:match('^[^ ]+ (.*)$')))
   if not live(comp)then return end
   local row={component=v.component,model_id=v.model_id,materials=J.array()}
   for i=0,comp:GetNumMaterials()-1 do row.materials[#row.materials+1]=material(comp:GetMaterial(i))end
   out.components[#out.components+1]=row
  end)
  if not ok then out.errors[#out.errors+1]={component=v.component,error=tostring(e)}end
 end
 local f=assert(io.open(root..'actual-materials.json','wb'));f:write(J.encode(out));f:close()
end)
