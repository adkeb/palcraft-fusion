-- Path-selected skin variants for baby/climate entity rigs. Uses frozen overlay
-- math, never assumes one texture per entity kind, and never transforms vertices.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Effects=dofile(dir..'entity_material_effects.lua')
local M={version=2,overlay=Effects.overlay,creeper_progress=Effects.creeper_progress}
function M.descriptor(group,index,skin_root,overlay_root)
 assert(group.entity_visual==true and group.alpha_mode=='cutout'and(group.tint or-1)<0,'Entity cutout/untinted group required')
 skin_root=assert(skin_root,'Current private skin root required'):gsub('\\','/'):gsub('/+$','')..'/'
 local path=assert(group.texture_path,'Selected current rig skin path required'):gsub('\\','/')
 assert(path:sub(1,#skin_root)==skin_root,'Skin path outside selected entity asset root')
 local relative=path:sub(#skin_root+1)
 assert(not relative:find('..',1,true),'Invalid skin path')
 local skin=assert(index.skins_by_path[relative],'Selected baby/climate skin variants unavailable')
 local effect=Effects.overlay(group.render_effects)
 local variant=assert(skin.variants[effect.key],'Overlay variant unavailable')
 overlay_root=assert(overlay_root,'Runtime derived overlay root required'):gsub('[\\/]+$','')..'/'
 return{texture_path=overlay_root..variant,source_skin_path=relative,source_skin_sha256=skin.source_sha256,
  alpha_mode='cutout',entity_visual=true,overlay=effect,geometry_effects_already_applied=true,
  parent_requirement='precompiled Surface masked parent without foliage WPO or additional tint',
  shader_visible=false,changes_hp=false,changes_world_position=false}
end
return M
