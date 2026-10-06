-- Exact original coordinates for the next reflected native section API.
-- Raw integer UV1/UV2 are retained. No guessed brightness or overlay is baked.
local M={version=1,vertex_bytes=104,uv1_semantics='original_MC_overlay_integer_xy',
 uv2_semantics='original_MC_lightmap_integer_xy',shader_verified=false}
local function coordinate(value)
 assert(type(value)=='number' and value==value and value>=0 and value<=65535 and value%1==0,
  'Original shader UV must be an integer in the native unsigned-short range')
 return value
end
local function channel(group,index,at)
 local values=index==1 and group.overlay_uvs or group.light_uvs
 local written=index==1 and group.mc_uv1_written_vertices or group.mc_uv2_written_vertices
 local blend=group.capture_blend
 local mode=blend and(index==1 and blend.overlay_mode or blend.light_mode)
 local required=group.actual_renderer_capture==true and mode~='none'
 if group.actual_renderer_capture then
  assert(type(blend)=='table' and blend.source=='actual_render_pipeline',
   'Actual shader metadata required before original UV binding')
  assert(mode~=nil and mode~='shader_specific','Shader UV consumer mode unresolved')
 end
 if required then
  assert(written==#group.vertices and type(values)=='table' and #values==#group.vertices,
   index==1 and 'Original per-vertex overlay UV incomplete' or 'Original per-vertex light UV incomplete')
 elseif values then
  assert(#values==0 or #values==#group.vertices,'Partial optional shader UV channel')
 end
 if not values or #values==0 then return nil end
 if at then
  local uv=values[at]
  assert(type(uv)=='table' and #uv==2,'Original shader UV pair required')
  coordinate(uv[1]);coordinate(uv[2]);return uv
 end
 for _,uv in ipairs(values) do
  assert(type(uv)=='table' and #uv==2,'Original shader UV pair required')
  coordinate(uv[1]);coordinate(uv[2])
 end
 return values
end
function M.validate(groups)
 for _,group in ipairs(groups) do channel(group,1);channel(group,2) end
 return true
end
function M.vertex(group,index)
 -- Validation precedes material resolution/native calls; this accessor also
 -- rejects malformed direct callers. Zero is only an unused channel placeholder.
 local a=channel(group,1,index) or {0,0}
 local b=channel(group,2,index) or {0,0}
 return coordinate(a[1]),coordinate(a[2]),coordinate(b[1]),coordinate(b[2])
end
function M.status()
 return {vertex_bytes=104,raw_uv1=true,raw_uv2=true,linear_color_api=true,
  srgb_conversion=false,actual_shader_sampling_verified=false}
end
return M
