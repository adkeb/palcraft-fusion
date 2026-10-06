-- Concrete next-candidate material wiring. The caller supplies the existing
-- authenticated transport and renderer; this module starts no process/socket.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Consumers=dofile(dir..'actual_material_consumers.lua')
local M={version=1}
local function norm(path)return path:gsub('\\','/'):gsub('/+$','')..'/'end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
function M.new(options)
 assert(options.json and options.bridge_root and options.send_query and options.pixel_packages,'Bound material runtime options required')
 local root=norm(options.bridge_root)
 local indices={}
 local function index_for(asset_root)
  local key=norm(asset_root)
  if indices[key]then return indices[key]end
  local package=assert(options.pixel_packages[key],'Pixel sidecar package for selected immutable model root required')
  assert(package.namespace and package.namespace:match('^[%w_%-]+$')and package.index_path,'Pixel package namespace/index required')
  local f=assert(io.open(root..package.index_path,'rb'))
  local index=options.json.decode(f:read('*a'));f:close()
  assert(index.version==1 and type(index.textures)=='table','Pixel index version required')
  -- V1 utility reads only bridge/material-pixels-v1; independent immutable
  -- packages are stored below a namespace there, never replacing model assets.
  local value=copy(index);value.textures={}
  for sprite,entry in pairs(index.textures)do
   local row=copy(entry)
   assert(type(row.path)=='string'and not row.path:find('..',1,true)and row.path:sub(1,1)~='/','Pixel path required')
   row.path=package.namespace..'/'..row.path;value.textures[sprite]=row
  end
  indices[key]=value;return value
 end
 local profile_options=copy(options);profile_options.asset_root=options.initial_asset_root or root
 profile_options.pixel_index_for_root=index_for
 profile_options.bake_library=options.bake_library or'D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/PalCraftMaterial-v1.dll'
 local instance=Consumers.new(profile_options)
 local self={consumer=instance,scope=nil,request_serial=0,pending={}}
 local nonce=options.request_nonce or(tostring(self):gsub('[^%w]','')..'-'..os.time())
 function self:bind(scope)
  assert(type(scope)=='table'and scope.mc_uuid and scope.world_session and scope.dim and math.tointeger(scope.view),'Trusted local scope required')
  local changed=not self.scope or self.scope.mc_uuid~=scope.mc_uuid or self.scope.world_session~=scope.world_session or self.scope.dim~=scope.dim or self.scope.view~=scope.view
  if changed then self.pending={};self.scope=copy(scope);instance:bind(scope)end
 end
 function self:request(rows)
  assert(self.scope and type(rows)=='table'and #rows>0 and #rows<=32,'Bound scope and small tint rows required')
  self.request_serial=self.request_serial+1
  local request_id='material-tint-'..nonce..'-'..self.request_serial
  local request=copy(self.scope);request.t='material_tint_query';request.request_id=request_id;request.rows=rows
  self.pending[request_id]=rows
  local sent,why=options.send_query(request)
  if sent~=true then self.pending[request_id]=nil;return nil,why or'material_tint_transport_not_ready'end
  return request_id
 end
 function self:accept(reply)
  if type(reply)~='table'or reply.t~='material_tint'then return false,'invalid_tint_reply'end
  local requested=self.pending[reply.request_id]
  if not requested then return false,'unsolicited_tint_reply'end
  if type(reply.rows)~='table'or #reply.rows~=#requested then return false,'tint_reply_rows_mismatch'end
  for i,row in ipairs(reply.rows)do
   local request=requested[i]
   if row.id~=request.id or row.x~=request.x or row.y~=request.y or row.z~=request.z or row.key~=request.key
    or row.tint_source~=(request.tint_role=='water'and'minecraft:biome_water_color'or'minecraft:block_tint_source.colorInWorld')then
    return false,'tint_reply_row_mismatch'
   end
   for _,index in ipairs(request.indices)do if not row.tint_colors or row.tint_colors[tostring(index)]==nil then return false,'tint_reply_index_missing'end end
  end
  local called,ok,why=pcall(instance.accept,instance,reply)
  if not called then return false,'invalid_tint_reply_fields'end
  if ok then self.pending[reply.request_id]=nil end
  return ok,why
 end
 function self:cancel(request_id)self.pending[request_id]=nil end
 function self:color_group(group,block)return instance.tints:apply(group,block)end
 function self:resolve(ctx,group,asset_root,block)return instance:resolve(ctx,group,norm(asset_root),block)end
 function self:install(renderer,validated_capabilities)
  assert(renderer.set_material_provider and type(validated_capabilities)=='table','Provider-capable renderer and actual validatedcaps required')
  renderer.set_material_provider(function(ctx,group,asset_root)
   local value,why=self:resolve(ctx,group,asset_root,group.material_block)
   assert(value,'Actual material pending: '..tostring(why));return value
  end,validated_capabilities)
 end
 function self:tick(seconds)return instance:tick(seconds)end
 function self:reset()instance:reset();self.scope=nil;self.pending={}end
 function self:status()
  local n=0;for _ in pairs(self.pending)do n=n+1 end
  return{version=1,scope=self.scope,pending_queries=n,tints=instance.tints:status(),transport_owned_by_runtime=true}
 end
 return self
end
return M
