local G=dofile('work/minecraft-fusion/palcraft/client/model_geometry_v3.lua')
local J=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
G.configure({root='work/minecraft-fusion/model-compat/v4/assets/',json=J})
local checks,cases=0,0
local function check(v,m)assert(v,m);checks=checks+1 end
local colors={'white','orange','magenta','light_blue','yellow','lime','pink','gray','light_gray','cyan','purple','blue','brown','green','red','black'}
for _,color in ipairs(colors)do
 for _,wall in ipairs({false,true})do
  local name='minecraft:'..color..(wall and'_wall_banner'or'_banner')
  for i=1,wall and 4 or 16 do
   local state=wall and('facing='..({'north','south','east','west'})[i])or('rotation='..(i-1))
   local groups,why=G.geometry(name,state,0,64,0)
   check(groups~=nil,name..' '..tostring(why));check(#groups==(wall and 2 or 3),'Banner pole/bar/cloth parts')
   for _,g in ipairs(groups)do check(g.block_entity=='banner','Original entity groups')end
   cases=cases+1
  end
 end
end
for _,type_ in ipairs({'skeleton','wither_skeleton','zombie','creeper','dragon','piglin','player'})do
 local suffix=(type_=='skeleton'or type_=='wither_skeleton')and'_skull'or'_head'
 for _,wall in ipairs({false,true})do
  local name='minecraft:'..type_..(wall and suffix:gsub('_','_wall_',1)or suffix)
  for i=1,wall and 4 or 16 do
   local state=wall and('facing='..({'north','south','east','west'})[i])or('rotation='..(i-1))
   local groups,why=G.geometry(name,state,0,64,0)
   check(groups and #groups>0,name..' '..tostring(why))
   for _,g in ipairs(groups)do for _,v in ipairs(g.vertices)do for _,n in ipairs(v)do check(n==n and math.abs(n)<1000,'Finite original head mesh')end end end
   cases=cases+1
  end
 end
end
local conduit=G.geometry('minecraft:conduit','waterlogged=true',0,64,0)
check(conduit and #conduit==1 and conduit[1].block_entity=='conduit','Original inactive conduit shell')
local result={status='passed',static_decor_cases=cases+1,checks=checks,
 remaining='Head powered animation/player profiles, banner patterns/wave, active conduit effects and copper statues remain pending'}
local f=assert(io.open('work/minecraft-fusion/model-compat/v4/decor-verification.json','wb'));f:write(J.encode(result));f:close();print(J.encode(result))
