-- Complete next-candidate bootstrap. No automatic registration on module load.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Profiles=dofile(dir..'material_profiles.lua')
local ActualMaterials=dofile(dir..'actual_material_consumers.lua')
local Additive=dofile(dir..'capture_additive_materials.lua')
local M={version=1}
function M.new(o)
 local Models,J,root=assert(o.models),assert(o.json),assert(o.bridge_root)
 local entity_root=root..'entity-assets-v3/'
 local capture_root=root..'entity-capture-v1/textures/'
 local instances,handlers={},{};local material_scope;local sign_worker,sign_handler,capture_worker;local api={phase='source_candidate_unverified'}
 local additive_descriptor=o.capture_additive_descriptor
 if not additive_descriptor then
  local file=io.open(root..'capture-additive-v1/profile.json','rb')
  if file then additive_descriptor=J.decode(file:read('*a'));file:close()end
 end
 local additive=Additive.new({asset_root=capture_root,descriptor=additive_descriptor})
 local function resolver(ctx,group,asset_root)
  if group.additive_material_required then
   local value,why=additive:resolve(ctx,group);assert(value,'Actual additive pending: '..tostring(why));return value
  end
  for _,entry in ipairs(handlers)do if entry.accept(group)then return entry.resolve(ctx,group,asset_root)end end
  local instance=instances[asset_root]
  if not instance then
   local opts={json=J,asset_root=asset_root,bridge_root=root,bake_library=dir..'../../../../PalCraftMaterial-v1.dll'}
   if asset_root==entity_root then
    opts.import_texture=function(context,path)
     local skin=path:gsub('/textures/','/skins/',1)
     return StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(context,skin)
    end
   else opts.pixel_index_for_root=o.pixel_index_for_root end
   opts.widget_proof=o.widget_proof or{parent_asset='/Engine/EngineMaterials/Widget3DPassThrough_Translucent.Widget3DPassThrough_Translucent',
    static_uv0_alpha_clear=true,capture_evidence=o.static_material_capture or'native_renderer/evidence/material-three/opaque-cutout-glass-actual.png',
    intermediate_alpha=false,overlap_sorting=false}
   instance=ActualMaterials.new(opts);if material_scope then instance:bind(material_scope)end;instances[asset_root]=instance
  end
  local candidate=group
  if(group.block_entity or group.actual_renderer_capture)and group.alpha_mode=='cutout'then
   -- Keep rigid lids/locks out of the Foliage WPO shader. The Paper2D
   -- masked surface is an explicit unlit candidate, pending actual probes.
   candidate={};for k,v in pairs(group)do candidate[k]=v end;candidate.shade=false
  end
  local value,why=instance:resolve(ctx,candidate,asset_root,group.authoritative_block);assert(value,'Native profile: '..tostring(why));return value
 end
 -- No shader acceptance is fabricated here. This resolver implements candidate
 -- bindings; validated capabilities are supplied only after actual lease probes.
 Models.set_material_provider(resolver,{opaque=true,cutout=true,translucent=true,tint=true,animation=true,dynamic=true})
 function api.bind_material_scope(scope)
  material_scope=scope;for _,instance in pairs(instances)do instance:bind(scope)end
 end
 function api.accept_material_tint(reply)
  local result=true;for _,instance in pairs(instances)do local ok=instance:accept(reply);result=result and ok~=false end;return result
 end
 function api.add_material_handler(accept,resolve)
  assert(type(accept)=='function'and type(resolve)=='function','Material dispatch functions required')
  local entry={accept=accept,resolve=resolve};table.insert(handlers,1,entry);return entry
 end
 function api.remove_material_handler(entry)
  for i=#handlers,1,-1 do if handlers[i]==entry then table.remove(handlers,i);return true end end
  return false
 end
 function api.attach_capture(options)
  assert(not capture_worker,'Capture consumer already installed')
  assert(Models.version>=6,'Captured vertex RGBA requires the actual Models6 adapter')
  local Capture=dofile(dir..'capture/capture_runtime_binding.lua')
  local Native=dofile(dir..'capture/captured_native_consumer.lua')
  -- Test the real resolver/import path before hiding any replicated body.
  -- A successful profile binding is runnable; shader fidelity remains unverified.
  local function material_supported(group)
   if group.actual_renderer_capture~=true or group.material_root~=capture_root then return false,'capture_material_root_mismatch'end
   if group.material_binding_reason then return false,group.material_binding_reason end
   local ok,value=pcall(resolver,o.context(),group,capture_root)
   if not ok then return false,tostring(value)end
   return value~=nil
  end
  capture_worker=Capture.new({json=J,png_root=capture_root,models=Models,native_consumer=Native,
   current_view=assert(options.current_view),verify_host_session=assert(options.verify_host_session),
   verify_actor=assert(options.verify_actor),now_ms=options.now_ms,send_binding=assert(options.send_binding),
   material_supported=material_supported,origin=function()
    local view=assert(options.current_view(),'Committed capture origin unavailable');return assert(view.origin)
   end,context=assert(o.context)})
  api.capture_worker=capture_worker;api.capture_renderer=capture_worker.renderer;api.entity_renderer=capture_worker.renderer
  return capture_worker
 end
 function api.receive_capture(row)
  if not capture_worker then return false,'capture_consumer_not_attached'end
  local ok,accepted,reason=pcall(capture_worker.receive,row)
  api.capture_reply_status={accepted=ok and accepted==true,reason=ok and reason or tostring(accepted),t=row.t}
  return ok and accepted==true,api.capture_reply_status.reason
 end
 function api.detach_capture(context_alive)
  if not capture_worker then return true end
  capture_worker.stop(context_alive~=false);capture_worker=nil
  api.capture_worker=nil;api.capture_renderer=nil;api.entity_renderer=nil;api.capture_reply_status=nil
  local instance=instances[capture_root];if instance then instance:reset();instances[capture_root]=nil end
  return true
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
   send_binding=assert(options.send_binding),block_at=options.block_at or scene.block_at,view_provider=options.view_provider or scene.view_provider})
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
 function api.on_lifecycle(event)
  Models.block_event(event)
  if capture_worker then capture_worker.on_lifecycle(event)end
 end
 function api.tick(delta_seconds,seconds)
  local elapsed=api.last_seconds and math.max(0,seconds-api.last_seconds)or delta_seconds;api.last_seconds=seconds
  Models.tick_animations(elapsed)
  for _,instance in pairs(instances)do local ok,why=instance:tick(seconds);assert(ok,why)end
  if capture_worker then capture_worker.tick()end
  if sign_worker and(not api.last_sign_seconds or seconds-api.last_sign_seconds>=.25)then
   api.last_sign_seconds=seconds;sign_worker:tick(o.context(),true)
  end
 end
 function api.stop(context_alive)
  api.detach_signs(context_alive);api.detach_capture(context_alive)
  additive:reset();for _,instance in pairs(instances)do instance:reset()end;instances={};api.last_seconds=nil
 end
 function api.status()
  local profiles={};for path,p in pairs(instances)do profiles[path]={actual_shader_verified=false,runnable_consumer='actual_material_consumers_v1'}end
  return{version=1,phase=api.phase,profiles=profiles,sign_text=sign_worker and sign_worker:status(),
   entity_visual=capture_worker and capture_worker.status()or{phase='capture_not_attached'},
   capture_reply=api.capture_reply_status,material_runtime=api.material_runtime and api.material_runtime.status(),actual_shader_verified=false}
 end
 return api
end
return M
