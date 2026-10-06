local geometry=dofile('work/minecraft-fusion/palcraft/client/model_geometry_v2.lua')
local json=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
geometry.configure({json=json,root='work/minecraft-fusion/model-compat/assets-v2/',cache_limit=16})
local checks=0
local maxUv,maxPosition=0,0
local function check(value,message)assert(value,message);checks=checks+1 end
local function near(a,b,message,tolerance)
 check(math.abs(a-b)<(tolerance or 1e-6),message..': '..tostring(a)..' vs '..tostring(b))
end
local oracle=assert(io.open('work/minecraft-fusion/palcraft/native/compat/vanilla-oracle.ndjson'))
local uvCases,randomCases=0,0
for line in oracle:lines()do
 local row=json.decode(line)
 if row.type=='uv'then
  local spec={x=row.x,y=row.y,z=row.z,uvlock=true}
  local uv=geometry.lock_uv({.13,.71},row.face,spec)
  local p=geometry.rotation({.17,.31,.73},spec,true)
  for i=1,2 do maxUv=math.max(maxUv,math.abs(uv[i]-row.uv[i]));near(uv[i],row.uv[i],'Vanilla locked UV')end
  for i=1,3 do maxPosition=math.max(maxPosition,math.abs(p[i]-row.point[i]));near(p[i],row.point[i],'Vanilla XYZ rotation')end
  uvCases=uvCases+1
 elseif row.type=='random'then
  local p=row.position;local seed=geometry.position_seed(p[1],p[2],p[3])
  check(seed==math.tointeger(tonumber(row.seed)),'Vanilla position seed')
  local random=geometry.random_source(seed)
  for i,bound in ipairs({2,3,17,1000000007})do check(random.next_int(bound)==row.samples[i],'Vanilla weighted random choice')end
  random.reset(seed);local multipartSeed=random.next_long()
  check(multipartSeed==math.tointeger(tonumber(row.multipart_seed)),'Vanilla multipart reseeding')
  random.reset(multipartSeed);check(random.next_int(19)==row.multipart_choice,'Vanilla multipart weighted choice')
  randomCases=randomCases+1
 end
end
oracle:close()
check(geometry.matches({OR={{north='true'},{west='true'}}},{north='false',west='true'}),'OR multipart')
check(geometry.matches({AND={{north='!false'},{east='true|false'}}},{north='true',east='false'}),'AND, negation and alternate values')
check(not geometry.matches({north='!true'},{north='true'}),'Rejected negated condition')

local samples={
 {'oak_planks',''},
 {'oak_slab','type=bottom,waterlogged=false'},
 {'oak_slab','type=top,waterlogged=false'},
 {'oak_slab','type=double,waterlogged=false'},
 {'crafting_table',''},
 {'furnace','facing=north,lit=false'},
 {'glass',''},
 {'oak_leaves','persistent=true,distance=7,waterlogged=false'},
 {'oak_fence','north=true,south=false,east=false,west=true,waterlogged=false'},
 {'rail','shape=south_east,waterlogged=false'},
 {'oak_hanging_sign','attached=false,rotation=3,waterlogged=false'},
 {'redstone_wire','east=side,west=none,north=up,south=side,power=15'},
}
for _,facing in ipairs({'north','east','south','west'})do
 for _,half in ipairs({'bottom','top'})do
  for _,shape in ipairs({'straight','inner_left','inner_right','outer_left','outer_right'})do
   samples[#samples+1]={'oak_stairs','facing='..facing..',half='..half..',shape='..shape..',waterlogged=false'}
  end
 end
end
local modelCases,faces=0,0
for _,sample in ipairs(samples)do
 local groups,why=geometry.geometry('minecraft:'..sample[1],sample[2],7,63,-15)
 check(groups~=nil,sample[1]..' geometry '..tostring(why))
 for _,group in ipairs(groups)do
  check(#group.vertices%4==0 and #group.indices==#group.vertices/4*6,'Complete quads')
  faces=faces+#group.vertices/4
  for _,i in ipairs(group.indices)do check(i>=0 and i<#group.vertices,'Valid zero-based index')end
  for _,v in ipairs(group.vertices)do
   for _,n in ipairs(v)do check(n==n and math.abs(n)<1000,'Finite bounded geometry')end
   near(v[4]*v[4]+v[5]*v[5]+v[6]*v[6],1,'Unit surface normal')
  end
 end
 modelCases=modelCases+1
end
local function bounds(groups)
 local lo,hi={math.huge,math.huge,math.huge},{-math.huge,-math.huge,-math.huge}
 for _,g in ipairs(groups)do for _,v in ipairs(g.vertices)do for i=1,3 do lo[i]=math.min(lo[i],v[i]);hi[i]=math.max(hi[i],v[i])end end end
 return lo,hi
end
local bottom=geometry.geometry('minecraft:oak_slab','type=bottom',0,64,0)
local top=geometry.geometry('minecraft:oak_slab','type=top',0,64,0)
local blo,bhi=bounds(bottom);local tlo,thi=bounds(top)
near(blo[3],0,'Bottom slab bottom');near(bhi[3],50,'Bottom slab top')
near(tlo[3],50,'Top slab bottom');near(thi[3],100,'Top slab top')
local workbench=geometry.geometry('minecraft:crafting_table','',0,64,0)
local textures={};for _,g in ipairs(workbench)do textures[g.texture]=true end
check(textures['minecraft:block/crafting_table_top'],'Workbench top texture')
check(textures['minecraft:block/crafting_table_front'],'Workbench front texture')
check(textures['minecraft:block/crafting_table_side'],'Workbench side texture')
local glass=geometry.geometry('minecraft:glass','',0,64,0)
check(glass[1].alpha_mode=='translucent','Glass transparency metadata')
local leaves=geometry.geometry('minecraft:oak_leaves','',0,64,0)
check(leaves[1].alpha_mode=='cutout' and leaves[1].tint==0,'Leaves cutout and biome tint metadata')
local visible=geometry.geometry('minecraft:oak_planks','',0,64,0,{occluded=function(face)return face=='west'end})
check(#visible[1].vertices==20,'Cull occluded adjacent face')
local empty=geometry.geometry('minecraft:oak_planks','',0,64,0,{occluded=function()return true end})
check(#empty==0,'Fully occluded block has zero sections')
local chest,why=geometry.geometry('minecraft:chest','facing=south,type=single,waterlogged=false',0,64,0)
check(chest~=nil,'Actual closed chest model '..tostring(why))
check(#chest==3,'Chest body, lid and lock separate sections')
local clo,chi=bounds(chest)
near(clo[1],6.25,'Chest minX');near(chi[1],93.75,'Chest maxX')
near(clo[2],-100,'Chest lock front');near(chi[2],-6.25,'Chest back')
near(clo[3],0,'Chest bottom');near(chi[3],87.5,'Chest lid top')
local chestKinds={'chest','trapped_chest','ender_chest','copper_chest','exposed_copper_chest','weathered_copper_chest','oxidized_copper_chest',
 'waxed_copper_chest','waxed_exposed_copper_chest','waxed_weathered_copper_chest','waxed_oxidized_copper_chest'}
local chestCases=0
for _,kind in ipairs(chestKinds)do for _,facing in ipairs({'north','south','east','west'})do
 for _,variant in ipairs(kind=='ender_chest'and{'single'}or{'single','left','right'})do
  local g,e=geometry.geometry('minecraft:'..kind,'facing='..facing..',type='..variant..',waterlogged=false',0,64,0)
  check(g~=nil,kind..'/'..facing..'/'..variant..' actual geometry '..tostring(e));check(#g==3,'Chest part sections')
  local n=0;for _,part in ipairs(g)do n=n+#part.vertices/4 end
  check(n==(variant=='single' and 18 or 15),'Exact chest polygons')
  local lo,hi=bounds(g);for i=1,3 do check(lo[i]>=-100.000001 and hi[i]<=100.000001,'Chest stays in its block')end
  chestCases=chestCases+1
 end
end end
local unsupported,reason=geometry.geometry('minecraft:shulker_box','facing=up',0,64,0)
check(unsupported==nil and reason=='special_model_required','Unimplemented dynamic entity model remains explicit')
for _,color in ipairs({'white','light_blue','light_gray'})do
 local g,e=geometry.geometry('minecraft:'..color..'_shulker_box','facing=up',0,64,0)
 check(g==nil and e=='special_model_required','Colored entity models remain explicit')
end
local air=geometry.geometry('minecraft:air','',0,64,0)
check(air and #air==0,'Air intentionally has no geometry')
local result={checks=checks,vanilla_uv_cases=uvCases,vanilla_random_cases=randomCases,
 max_uv_error=maxUv,max_position_error=maxPosition,model_cases=modelCases,chest_cases=chestCases,model_faces=faces,status='passed'}
local out=assert(io.open('work/minecraft-fusion/model-compat/geometry-verification.json','wb'));out:write(json.encode(result));out:close()
print(json.encode(result))
