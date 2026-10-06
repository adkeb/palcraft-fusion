-- Route from the actual producer blend equation/coverage. Never infer from eyes.
local M={version=1}
function M.apply(group,batch)
 local b=batch.capture_blend
 if type(b)~='table'or b.v~=1 or b.source~='actual_render_pipeline'then
  group.material_binding_reason='actual_capture_blend_metadata_required';return false,group.material_binding_reason
 end
 group.capture_blend=b
 group.additive_material_required=nil
 local coverage=b.coverage or{}
 if coverage.dissolve==true then group.material_binding_reason='capture_dissolve_shader_required';return false,group.material_binding_reason end
 if b.mode=='additive'then group.alpha_mode='additive';group.additive_material_required=true
 elseif b.mode=='translucent'then group.alpha_mode='translucent'
 elseif b.mode=='opaque'then group.alpha_mode=coverage.alpha_cutout~='none'and coverage.alpha_cutout~=nil and'cutout'or'opaque'
 else group.material_binding_reason='capture_blend_'..tostring(b.mode)..'_not_implemented';return false,group.material_binding_reason end
 group.light_emission=b.light_mode=='emissive_no_lightmap'and 15 or 0
 group.material_binding_reason=nil
 return true
end
return M
