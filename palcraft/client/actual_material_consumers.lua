-- Thin actual-color/material dispatcher for the next renderer candidate. It
-- registers nothing on load; runtime owns request transport and verified caps.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Tint=dofile(dir..'biome_tint_consumer.lua')
local Profiles=dofile(dir..'material_profiles.lua')
local Widget=dofile(dir..'widget_surface_materials.lua')
local M={version=1}
function M.new(options)
 local self={tints=Tint.new(),profiles={},widgets={}}
 local function profile(root)
  if not self.profiles[root]then local o={};for k,v in pairs(options)do o[k]=v end;o.asset_root=root
   if options.pixel_index_for_root then o.pixel_index=options.pixel_index_for_root(root)end
   self.profiles[root]=Profiles.new(o)
  end
  return self.profiles[root]
 end
 local function widget(root)
  if not self.widgets[root]then local o={};for k,v in pairs(options)do o[k]=v end;o.asset_root=root;o.proof=options.widget_proof
   o.tint_texture=function(original,color,group)
    local prefix=root:gsub('[\\/]+$','')..'/'
    if original:sub(1,#prefix)~=prefix then return nil end
    return profile(root):_bake(original:sub(#prefix+1),color)
   end
   self.widgets[root]=Widget.new(o)
  end
  return self.widgets[root]
 end
 function self:bind(scope)self.tints:bind(scope)end
 function self:accept(reply)return self.tints:accept(reply)end
 function self:resolve(ctx,group,root,block)
  local colored,why=self.tints:apply(group,block)
  if not colored then return nil,why end
  if colored.alpha_mode=='translucent'then return widget(root):resolve(ctx,colored)end
  return profile(root):resolve(ctx,colored,block)
 end
 function self:tick(seconds)for _,p in pairs(self.profiles)do local ok,why=p:tick(seconds);if not ok then return nil,why end end;return true end
 function self:reset()
  for _,p in pairs(self.profiles)do p:reset()end;for _,p in pairs(self.widgets)do p:reset()end
  self.profiles={};self.widgets={};self.tints=Tint.new()
 end
 return self
end
return M
