-- One tiny field/resource passthrough fixture; no engine or graphics acceptance.
local dir='work/minecraft-fusion/entity-visuals/capture-shader-inputs/lua/'
local C=dofile(dir..'captured_entity_visuals.lua')
C.configure{root='/verified-cache/',texture_index={},resolve_texture=function(id)return'/verified-cache/'..id..'.png'end}
local vertices={}
for i=1,4 do vertices[i]={i,2,3,0,1,0,.25,.75,1,.5,.25,.8,i,10,160,240}end
local frame={source='actual_entity_renderer_submit',space='minecraft_entity_origin_world_orientation',schema=2,
 shader_textures={Sampler1={resource='overlay',sha256='overlay-hash'},Sampler2={resource='lightmap',sha256='light-hash'}},
 batches={{textures={Sampler0='skin'},vertices=vertices,primitive='QUADS',uv1_written_vertices=4,uv2_written_vertices=4,
 capture_blend={v=1,source='actual_render_pipeline',mode='translucent',light_mode='sample_lightmap',coverage={alpha_cutout='none'}},
 shader_inputs={available=true,ColorModulator={.8,.7,.6,1},cardinal_lighting={available=true,Light0_Direction={0,1,0}}}}}}
local groups,extra=assert(C.capture(frame));local g=groups[1]
assert(#g.vertices==4 and #g.vertices[1]==8 and #g.vertex_colors==4)
assert(g.overlay_uvs[4][1]==4 and g.overlay_uvs[4][2]==10 and g.light_uvs[4][1]==160 and g.light_uvs[4][2]==240)
assert(g.mc_sampler_paths.Sampler1=='/verified-cache/overlay.png'and g.mc_sampler_paths.Sampler2=='/verified-cache/lightmap.png')
assert(g.mc_shader_inputs.dynamic_transforms.ColorModulator[1]==.8 and g.alpha_mode=='translucent'and not g.additive_material_required)
assert(#extra.missing_textures==0)
print('{"status":"passed","fixture":"UV16 -> native group original integer arrays, resources and typed route","runtime_graphics_verified":false}')
