-- Actual per-block MC colors, fenced by the authenticated world view. No default
-- biome green is inferred. Apply before chunk material grouping.
local M={version=1}
local function poskey(row,water)return string.format('%d,%d,%d:%s:%s:%s',row.x,row.y,row.z,row.id,tostring(row.key or row.state or''),water and'water'or'block')end
local function same(a,b)return a and b and a.mc_uuid==b.mc_uuid and a.world_session==b.world_session and a.dim==b.dim and a.view==b.view end
function M.new()
 local self={scope=nil,colors={},applied=0,rejected=0}
 function self:bind(scope)
  assert(type(scope)=='table'and scope.mc_uuid and scope.world_session and scope.dim and math.tointeger(scope.view),'Tint scope required')
  if not same(self.scope,scope)then
   self.scope={mc_uuid=scope.mc_uuid,world_session=scope.world_session,dim=scope.dim,view=scope.view};self.colors={}
  end
 end
 function self:accept(reply)
  if not same(self.scope,reply)or reply.source~='minecraft:material_tint_v1'or reply.read_only~=true then
   self.rejected=self.rejected+1;return false,'wrong_tint_source_or_scope'
  end
  assert(type(reply.rows)=='table'and #reply.rows<=32,'Tint rows limit')
  local prepared={}
  for _,row in ipairs(reply.rows)do
   assert(math.tointeger(row.x)and math.tointeger(row.y)and math.tointeger(row.z)and type(row.id)=='string','Tint coordinate/id required')
   assert(row.tint_source=='minecraft:block_tint_source.colorInWorld'or row.tint_source=='minecraft:biome_water_color','Actual MC tint source required')
   local colors={}
   for index,color in pairs(row.tint_colors or{})do
    assert(math.tointeger(color)and color>=0 and color<=0xffffff,'MC RGB required')
    colors[tostring(index)]=color
   end
   prepared[poskey(row,row.tint_source=='minecraft:biome_water_color')]=colors
  end
  for key,colors in pairs(prepared)do self.colors[key]=colors end
  return true
 end
 function self:apply(group,block)
  if group.tint_rgb~=nil then assert(math.tointeger(group.tint_rgb)and group.tint_rgb>=0 and group.tint_rgb<=0xffffff,'Final MC RGB required');return group end
  if group.texture_meta and group.texture_meta.baked_diffuse_tint==true or(group.tint or-1)<0 then return group end
  assert(type(block)=='table','Tint block context required')
  local colors=self.colors[poskey(block,group.tint_role=='water')]
  local color=colors and colors[tostring(group.tint)]
  if color==nil then return nil,'actual_block_tint_pending'end
  local copy={};for k,v in pairs(group)do copy[k]=v end
  copy.tint_rgb=color;self.applied=self.applied+1
  return copy
 end
 function self:status()return{scope=self.scope,applied=self.applied,rejected=self.rejected,authority='MC BlockTintSource',world_modified=false}end
 return self
end
return M
