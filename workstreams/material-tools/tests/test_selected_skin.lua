local Effects=dofile(assert(arg[1])..'/client/entity_material_effects_v2.lua')
local n=0;local function check(v,why)assert(v,why);n=n+1 end
local index={skins_by_path={
 ['skins/minecraft/entity/pig/pig_temperate.png']={source_sha256='temperate',variants={white_00='temperate/base.png',red='temperate/red.png'}},
 ['skins/minecraft/entity/pig/pig_cold.png']={source_sha256='cold',variants={white_00='cold/base.png',red='cold/red.png'}}
}}
local group={entity_visual=true,alpha_mode='cutout',tint=-1,texture='same-kind-alias',
 texture_path='D:/bridge/entity-assets-v2/skins/minecraft/entity/pig/pig_cold.png',render_effects={red_overlay=true}}
local d=Effects.descriptor(group,index,'D:/bridge/entity-assets-v2/','D:/bridge/entity-overlays-v2/')
check(d.source_skin_sha256=='cold','actual selected climate skin wins kind alias')
check(d.texture_path=='D:/bridge/entity-overlays-v2/cold/red.png','overlay uses selected skin')
check(d.geometry_effects_already_applied and not d.changes_hp,'no duplicate baby scaling/death roll/HP')
local ok=pcall(Effects.descriptor,group,index,'D:/other-root/','D:/out/')
check(not ok,'wrong private asset root rejected')
print(string.format('{"status":"passed","checks":%d,"engine_calls":0,"mode":"night_low_power_light_contract"}',n))
