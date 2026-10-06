-- Actual MC renderer vertex stream -> existing native mesh groups. No kind list.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local BlendRoute=dofile(dir..'capture_blend_route.lua')
local M={};local config={};local textureIndex
function M.configure(o)
 config=o;if config.root:sub(-1)~='/'then config.root=config.root..'/'end
 if o.texture_index then textureIndex=o.texture_index
 else local f=assert(io.open(config.root..'textures.json','rb'));textureIndex=o.json.decode(f:read('*a'));f:close()end
end
local function texture(id)
 if config.resolve_texture then return config.resolve_texture(id)end
 local item=textureIndex[id];return item and config.root..item.path or nil
end
function M.capture(frame)
 if frame.source~='actual_entity_renderer_submit'or frame.space~='minecraft_entity_origin_world_orientation'then return nil,'not_original_renderer_capture' end
 local groups={};local missing={}
 for _,batch in ipairs(frame.batches or{})do
  local id=batch.textures and batch.textures.Sampler0
  local path=id and texture(id)
  if not path then missing[#missing+1]=id or'missing_Sampler0'
  else
   local g={texture=id,texture_path=path,material_root=config.root,entity_visual=true,collision=false,
    actual_renderer_capture=true,world_orientation_baked=true,actor_yaw=0,part='renderer_batch',
    renderer_source=batch.source,render_type_name=batch.render_type_name,render_order=batch.layer_order,
    alpha_mode=batch.has_blending and'translucent'or'cutout',shade=true,light_emission=0,
    mc_overlay=batch.overlay,mc_light=batch.light,vertex_colors={},vertices={},indices={},overlay_uvs={},light_uvs={},
    mc_uv1_written_vertices=batch.uv1_written_vertices,mc_uv2_written_vertices=batch.uv2_written_vertices,
    mc_shader_textures=frame.shader_textures,mc_shader_inputs={cardinal_lighting=batch.shader_inputs and batch.shader_inputs.cardinal_lighting
      or(frame.shader_inputs and frame.shader_inputs.cardinal_lighting),
     dynamic_transforms=batch.shader_inputs},mc_sampler_paths={},capture_blend=batch.capture_blend}
   for sampler,desc in pairs(frame.shader_textures or{})do
    local original=texture(desc.resource)
    if original then g.mc_sampler_paths[sampler]=original else missing[#missing+1]=desc.resource end
   end
   BlendRoute.apply(g,batch)
   for _,v in ipairs(batch.vertices)do
    g.vertices[#g.vertices+1]={v[1]*100,-v[3]*100,v[2]*100,v[4],-v[6],v[5],v[7],v[8]}
    g.vertex_colors[#g.vertex_colors+1]={v[9],v[10],v[11],v[12]}
    if #v>=16 then
     g.overlay_uvs[#g.overlay_uvs+1]={v[13],v[14]};g.light_uvs[#g.light_uvs+1]={v[15],v[16]}
    end
   end
   local count=#g.vertices;local primitive=tostring(batch.primitive)
   if primitive=='QUADS'then
    if count%4~=0 then return nil,'torn_original_quad_stream' end
    for i=0,count-1,4 do for _,n in ipairs({0,2,1,0,3,2})do g.indices[#g.indices+1]=i+n end end
   elseif primitive:find('TRIANGLE',1,true)and not primitive:find('STRIP',1,true)then
    if count%3~=0 then return nil,'torn_original_triangle_stream' end
    for i=0,count-1,3 do g.indices[#g.indices+1]=i;g.indices[#g.indices+1]=i+2;g.indices[#g.indices+1]=i+1 end
   else return nil,'unsupported_actual_primitive_'..primitive end
   groups[#groups+1]=g
  end
 end
 if #groups==0 then return nil,'no_resolved_original_renderer_batches',missing end
 return groups,{actor_yaw=0,world_orientation_baked=true,missing_textures=missing,
  unsupported_submissions=frame.unsupported_submissions,material_binding_pending=true}
end
function M.geometry(row,frame)
 frame=frame or row.visual_capture
 if not frame then return nil,'renderer_capture_not_attached' end
 if frame.id and frame.id~=row.id then return nil,'different_entity_capture' end
 if frame.dimension and frame.dimension~=row.dimension then return nil,'different_dimension_capture' end
 -- Existing authority/session/epoch binding is the observer's responsibility;
 -- this pure provider never creates a second authorization protocol.
 return M.capture(frame)
end
function M.actor_yaw()return 0 end
return M
