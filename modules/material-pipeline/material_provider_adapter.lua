-- Integration adapter only. It registers no callbacks or capabilities on load.
-- Native/runtime owner calls install after recording actual shader probe results.
local M={}
function M.install(renderer,Profiles,options,validated)
 assert(renderer.set_material_provider and type(validated)=='table','Renderer/validated capabilities required')
 local instances={}
 renderer.set_material_provider(function(ctx,group,asset_root)
  local instance=instances[asset_root]
  if not instance then
   local config={};for k,v in pairs(options)do config[k]=v end
   config.asset_root=asset_root
   if options.pixel_index_for_root then config.pixel_index=options.pixel_index_for_root(asset_root)end
   instance=Profiles.new(config);instances[asset_root]=instance
  end
  local value,why=instance:resolve(ctx,group)
  assert(value,'Native material rejected: '..tostring(why))
  return value
 end,validated)
 return{
  tick=function(seconds)
   for _,instance in pairs(instances)do local ok,why=instance:tick(seconds);assert(ok,why)end
  end,
  reset=function()for _,instance in pairs(instances)do instance:reset()end;instances={}end,
  status=function()local result={};for root,instance in pairs(instances)do result[root]=instance:status()end;return result end
 }
end
return M
