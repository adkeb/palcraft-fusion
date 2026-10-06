-- Complete next-candidate bootstrap. No automatic registration on module load.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Profiles=dofile(dir..'material_profiles.lua')
local EntityVisuals=dofile(dir..'entity_visuals_v3.lua')
local EntityPose=dofile(dir..'entity_pose_adapter_v3.lua')
local EntityAdapter=dofile(dir..'entity_native_visuals.lua')
local M={version=1}
function M.new(o)
 local Models,J,root=assert(o.models),assert(o.json),assert(o.bridge_root)
 local entity_root=root..'entity-assets-v3/'
 EntityVisuals.configure({json=J,root=entity_root})
 local instances,handlers={},{};local sign_worker,sign_handler;local api={phase='source_candidate_unverified'}
 local function resolver(ctx,group,asset_root)
  for _,entry in ipairs(handlers)do if entry.accept(group)then return entry.resolve(ctx,group,asset_root)end end
  local instance=instances[asset_root]
  if not instance then
   local opts={json=J,asset_root=asset_root,bridge_root=root,bake_library=dir..'../../../../PalCraftMaterial-v1.dll'}
   if asset_root==entity_root then
    opts.import_texture=function(context,path)
     local skin=path:gsub('/textures/','/skins/',1)
     return StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(context,skin)
    end
   else opts.pixel_index=o.pixel_index_for_root and o.pixel_index_for_root(asset_root)end
   instance=Profiles.new(opts);instances[asset_root]=instance
  end
  local candidate=group
  if group.block_entity and group.alpha_mode=='cutout'then
   -- Keep rigid lids/locks out of the Foliage WPO shader. The Paper2D
   -- masked surface is an explicit unlit candidate, pending actual probes.
   candidate={};for k,v in pairs(group)do candidate[k]=v end;candidate.shade=false
  end
  local value,why=instance:resolve(ctx,candidate);assert(value,'Native profile: '..tostring(why));return value
 end
 -- No shader acceptance is fabricated here. This resolver implements candidate
 -- bindings; validated capabilities are supplied only after actual lease probes.
 Models.set_material_provider(resolver,o.validated_material_capabilities or{})
 api.entity_renderer=EntityAdapter.new({models=Models,visuals=EntityVisuals,pose=EntityPose,
  origin=o.origin,context=o.context,asset_root=entity_root})
 function api.add_material_handler(accept,resolve)
  assert(type(accept)=='function'and type(resolve)=='function','Material dispatch functions required')
  local entry={accept=accept,resolve=resolve};table.insert(handlers,1,entry);return entry
 end
 function api.attach_signs(options)
  assert(not sign_worker,'Sign consumer already installed')
  local sign_dir=dir..'signtext/'
  local Materials=dofile(sign_dir..'materials.lua')
  local Renderer=dofile(sign_dir..'native.lua')
  local Consumer=dofile(sign_dir..'consumer.lua')
  local Scene=dofile(sign_dir..'scene.lua')
  local material=Materials.new({root=root..'sign-text-v1/',allow_candidate=options.allow_candidate==true,
   profiles=options.profiles,verified_profiles=options.verified_profiles})
  local scene=Scene.per_block({json=J,companion=assert(o.companion),confirmed_view=assert(options.confirmed_view),
   visible_bounds=options.visible_bounds,model_live=options.model_live})
  sign_worker=Consumer.new({json=J,root=root..'sign-text-v1/',renderer=Renderer.new({models=Models,materials=material}),
   send_binding=assert(options.send_binding),block_at=scene.block_at,view_provider=scene.view_provider})
  sign_handler=api.add_material_handler(function(g)return g.text_plane==true end,function(ctx,g)return material:resolve(ctx,g)end)
  api.sign_materials=material;api.sign_worker=sign_worker;return sign_worker
 end
 function api.detach_signs(context_alive)
  if not sign_worker then return true end
  sign_worker:stop(context_alive~=false)
  if api.sign_materials then api.sign_materials:reset()end
  for i=#handlers,1,-1 do if handlers[i]==sign_handler then table.remove(handlers,i)end end
  sign_worker=nil;sign_handler=nil;api.sign_worker=nil;api.sign_materials=nil;api.last_sign_seconds=nil
  return true
 end
 function api.on_lifecycle(event)Models.block_event(event)end
 function api.tick(delta_seconds,seconds)
  local elapsed=api.last_seconds and math.max(0,seconds-api.last_seconds)or delta_seconds;api.last_seconds=seconds
  Models.tick_animations(elapsed)
  for _,instance in pairs(instances)do local ok,why=instance:tick(seconds);assert(ok,why)end
  if sign_worker and(not api.last_sign_seconds or seconds-api.last_sign_seconds>=.25)then
   api.last_sign_seconds=seconds;sign_worker:tick(o.context(),true)
  end
 end
 function api.stop()api.detach_signs(true);api.entity_renderer.stop();for _,instance in pairs(instances)do instance:reset()end;instances={}end
 function api.status()
  local profiles={};for path,p in pairs(instances)do profiles[path]=p:status()end
  return{version=1,phase=api.phase,profiles=profiles,sign_text=sign_worker and sign_worker:status(),entity_visual=api.entity_renderer.status(),actual_shader_verified=false}
 end
 return api
end
return M
