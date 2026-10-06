local F=dofile('work/minecraft-fusion/palcraft/client/fluid_geometry.lua')
local sample={kind='minecraft:water',flow={0,0,0},surface={corners={north_west=1,north_east=.75,south_west=.5,south_east=.25},
 visual_epsilon=.001,contact_height=.8888889,unknown={}}}
local groups=assert(F.geometry(sample))
assert(#groups==1 and #groups[1].vertices==4 and #groups[1].indices==6)
local g=groups[1]
assert(g.collision==false and g.fluid_visual and g.alpha_mode=='translucent'and g.tint_role=='water')
assert(math.abs(g.vertices[1][3]-99.9)<1e-9 and math.abs(g.vertices[3][3]-24.9)<1e-9)
assert(g.contact_height==sample.surface.contact_height)
assert(g.vertices[1][2]==0 and g.vertices[2][2]==-100)
local movingUV,moving=F.flow_uv(1,0)
assert(moving and #movingUV==4)
local side=assert(F.geometry(sample,{top_visible=false,sides={north={visible=true,bottom_height=.1}}}))
assert(#side==1 and #side[1].vertices==4 and side[1].face_ranges[1].direction=='north')
assert(#F.geometry(sample,{top_visible=false})==0)
local missing,why=F.geometry({kind='minecraft:water'})
assert(missing==nil and why=='missing_actual_fluid_surface')
print('{"status":"passed","cases":5,"scope":"actual surface heights/axis/no collision/explicit faces","night_low_power":true}')
