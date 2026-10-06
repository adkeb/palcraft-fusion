local G=dofile('work/minecraft-fusion/palcraft/client/model_geometry_v3.lua')
local J=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
local Timeline=dofile('work/minecraft-fusion/palcraft/client/texture_timeline.lua')
local ROOT='work/minecraft-fusion/model-compat/v3/assets/'
G.configure({json=J,root=ROOT})
local checks=0;local maxPosition,maxNormal=0,0
local function check(v,message)assert(v,message);checks=checks+1 end
local function read(path)local f=assert(io.open(path,'rb'));local value=J.decode(f:read('*a'));f:close();return value end
local oracle={}
for line in io.lines('work/minecraft-fusion/model-compat/v3/vanilla-entity.ndjson')do
 local row=J.decode(line)
 if row.type=='face'and(row.family=='shulker'or row.family=='chest')then
  local key=row.family..':'..row.variant..':'..row.input
  oracle[key]=oracle[key]or{};local parts=oracle[key]
  parts[row.part]=parts[row.part]or{};parts[row.part][#parts[row.part]+1]=row
 end
end
local motionCases=0
for key,parts in pairs(oracle)do
 local family,variant,value=key:match('([^:]+):([^:]+):([^:]+)');local input=tonumber(value)
 local block,state
 if family=='shulker'then block='minecraft:shulker_box';state='facing='..variant
 else block='minecraft:chest';state='facing=south,type='..variant end
 local static=assert(G.geometry(block,state,0,64,0))
 local original=static[1].vertices[1][1]
 local animated=assert(G.geometry(block,state,0,64,0,{open_progress=input}))
 check(static[1].vertices[1][1]==original,'Static cached geometry is immutable')
 for _,group in ipairs(animated)do
  local faces=assert(parts[group.part],group.part)
  check(#group.vertices==#faces*4,'Same original model topology')
  for i,face in ipairs(faces)do for j,v in ipairs(face.vertices)do
   local actual=group.vertices[(i-1)*4+j]
   local expected={v[1]*100,-v[3]*100,v[2]*100,face.normal[1],-face.normal[3],face.normal[2],v[4],v[5]}
   for k=1,8 do
    local error=math.abs(actual[k]-expected[k]);if k<=3 then maxPosition=math.max(maxPosition,error)elseif k<=6 then maxNormal=math.max(maxNormal,error)end
    check(error<(k<=3 and .0003 or .000001),family..'/'..variant..'/'..input..' MC motion position/normal/UV: '..k..' error '..error)
   end
  end end
 end
 motionCases=motionCases+1
end
local colors={'','black','blue','brown','cyan','gray','green','light_blue','light_gray','lime','magenta','orange','pink','purple','red','white','yellow'}
local staticCases=0
for _,color in ipairs(colors)do for _,direction in ipairs({'up','down','north','south','east','west'})do
 local name=(color~=''and color..'_'or'')..'shulker_box'
 local groups,why=G.geometry('minecraft:'..name,'facing='..direction,0,64,0)
 check(groups~=nil,'Colored shulker '..tostring(why));check(#groups==2,'Separate original base and lid')
 check(groups[1].animation_clip~=nil,'Animation clip available')
 staticCases=staticCases+1
end end
for _,facing in ipairs({'north','south','east','west'})do
 local groups=G.geometry('minecraft:decorated_pot','facing='..facing,0,64,0)
 check(groups and #groups==7,'Original decorated pot neck/top/bottom/4 sides')
 local decorated=G.geometry('minecraft:decorated_pot','facing='..facing,0,64,0,{decorations={front='minecraft:entity/decorated_pot/archer_pottery_pattern'}})
 local found=false;for _,group in ipairs(decorated)do if group.part=='/front'then found=group.texture=='minecraft:entity/decorated_pot/archer_pottery_pattern'end end
 check(found,'Decorated pot original side sprite')
 staticCases=staticCases+1
end
local metadata=read(ROOT..'textures/minecraft/block/lava_still.json')
local sample=Timeline.sample(metadata,0)
check(sample.index==metadata.animation.frames[1].index,'First original animation frame')
local period=0;for _,frame in ipairs(metadata.animation.frames)do period=period+frame.time end
check(Timeline.sample(metadata,period/20).index==sample.index,'Animation wraps at exact vanilla tick duration')
local elapsed=metadata.animation.frames[1].time/20
check(Timeline.sample(metadata,elapsed).index==metadata.animation.frames[2].index,'Frame changes at MC tick boundary')
local text=read(ROOT..'text_layouts/minecraft/signs.json')
check(#text.layouts==40,'Original front/back text poses for all sign variants')
for _,layout in ipairs(text.layouts)do check(#layout.front==16 and #layout.back==16,'Sign pose matrix dimensions')end
local result={status='passed',checks=checks,motion_cases=motionCases,static_entity_cases=staticCases,
 max_motion_position_error_cm=maxPosition,max_motion_normal_error=maxNormal,sign_layouts=40,
 verified_against='Actual Minecraft model setupAnim/ModelPart.visit output'}
local f=assert(io.open('work/minecraft-fusion/model-compat/v3/entity-verification.json','wb'));f:write(J.encode(result));f:close();print(J.encode(result))
