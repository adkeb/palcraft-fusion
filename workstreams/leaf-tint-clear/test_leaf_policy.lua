local dir=assert(arg[1]);local Profiles=dofile(dir..'/material_profiles.lua')
local function g(extra)
 local a={texture='minecraft:block/oak_leaves',alpha_mode='cutout',tint=0,shade=true}
 for k,v in pairs(extra or{})do a[k]=v end;return a
end
local d=assert(Profiles.descriptor(g({tint_rgb=0x63924a})))
assert(d.parent_asset=='/Paper2D/MaskedUnlitSpriteMaterial.MaskedUnlitSpriteMaterial'
 and d.texture_parameter=='SpriteTexture' and d.expected_blend==1
 and d.tint_rgb==0x63924a and d.biome_rigid_cutout and d.lit==false)
local absent,why=Profiles.descriptor(g());assert(not absent and why=='minecraft_block_color_required')
d=assert(Profiles.descriptor(g({texture_meta={baked_diffuse_tint=true}})))
assert(d.tint_rgb==nil and d.biome_rigid_cutout)
d=assert(Profiles.descriptor(g({tint=-1})));assert(d.id=='cutout_foliage')
d=assert(Profiles.descriptor(g({entity_visual=true,tint_rgb=0x63924a})));assert(d.id=='cutout_foliage')
d=assert(Profiles.descriptor(g({alpha_mode='opaque',tint_rgb=0x63924a})));assert(d.id=='opaque_prop')
absent,why=Profiles.descriptor(g({alpha_mode='translucent',tint_rgb=0x63924a}))
assert(not absent and why=='translucent_parent_not_probed')
io.write('{"ok":true,"directed_policy_checks":7,"actual_biome_RGB_not_defaulted":true,"tint_bake_and_Paper_sampler_path":true,"opaque_translucent_entity_routes_preserved":true,"runtime_called":false}\n')
