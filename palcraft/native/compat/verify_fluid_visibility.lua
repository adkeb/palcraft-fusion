local F=dofile('work/minecraft-fusion/palcraft/client/fluid_geometry_v2.lua')
local fluid={kind='minecraft:water',flow={0,0,0},surface={corners={north_west=1,north_east=1,south_west=1,south_east=1},
 visual_epsilon=.001,contact_height=.8888889,face_visibility={up=true,down=false,north=false,south=true,west=true,east=false},
 face_unknown={'west'}}}
local groups=assert(F.geometry(fluid))
local faces={};local vertices=0
for _,g in ipairs(groups)do
 assert(g.collision==false and g.face_unknown[1]=='west')
 vertices=vertices+#g.vertices
 for _,face in ipairs(g.face_ranges)do faces[face.direction]=true end
end
assert(vertices==12 and faces.up and faces.south and faces.west)
assert(not faces.down and not faces.north and not faces.east)
local custom=assert(F.geometry(fluid,{sides={south={overlay=true,bottom_height=.25}}}))
local overlay=false;for _,g in ipairs(custom)do if g.texture=='minecraft:block/water_overlay'then overlay=true end end
assert(overlay)
assert(fluid.surface.face_visibility.north==false)
print('{"status":"passed","fixture":"exact fluid face mask + unknown-neighbor preservation + explicit overlay","night_low_power":true}')
