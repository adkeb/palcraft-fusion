-- Pure local regression using the completed production plan's projected layout.
-- No remote calls; this is not a fresh server snapshot.
local S='work/palworld-live/bridge/PalLiveBridge/Scripts/'
local O,J=dofile(S..'organize.lua'),dofile(S..'json.lua')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return J.decode(s,{max_bytes=8388608,max_depth=64})end
local function clone(v)if type(v)~='table'then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local ZERO='00000000-0000-0000-0000-000000000000'
for _,name in ipairs({'oldbase','newbase','thirdbase'})do
 local p=read('work/palworld-live/lab/production-'..name..'-plan.json')
 local r=read('work/palworld-live/lab/production-'..name..'-before.json')
 local t={chests={}};local payloads={};local by={}
 for _,v in ipairs(p.stacks)do payloads[v.token]=v.content end
 for _,c in ipairs(r.chests)do by[c.id]=c end
 for _,c in ipairs(p.containers)do
  t.chests[#t.chests+1]={container_id=c.id,base_id=p.base_id,group_id=p.group_id,type=c.type,expected_capacity=c.capacity,map=c.map,world=c.world}
  local chest=assert(by[c.id]);chest.slots={}
  for i=0,c.capacity-1 do chest.slots[i+1]={container_id=c.id,index=i,slot_id_index=i,item='None',count=0,empty=true,dynamicGuid=ZERO,dynamicWorldGuid=ZERO,corruption=0,corruptionKind='GetCorruptionProgressRate'}end
  for _,s in ipairs(c.slots)do
   local slot=clone(assert(payloads[s.token]));slot.container_id=c.id;slot.index=s.index;slot.slot_id_index=s.index;slot.empty=false;chest.slots[s.index+1]=slot
  end
 end
 local opts={base_id=p.base_id,policy='category',require_live_ownership=true}
 local refined,e=O.plan(r,t,opts);assert(refined,e and e.code..': '..e.message)
 local proof,err=O.simulate(r,t,opts,refined);assert(proof,err and err.message)
 assert(refined.stack_count==p.stack_count and refined.capacity==p.capacity and refined.empty_slots==p.empty_slots)
 if name=='oldbase'then
  local medicine,food,raw
  for _,c in ipairs(refined.containers)do
   local categories={};for _,v in ipairs(c.categories)do categories[v.id]=v.stacks end
   if categories.medicine then medicine=c;assert(categories.food_seeds and not categories.raw)end
   if c.id:sub(1,8)=='22b8e5da'then raw=c end
   if c.id:sub(1,8)=='f0935c8c'then food=c end
  end
  assert(medicine and food==medicine and raw and not raw.mixed)
  assert(food.used==19 and food.free==5 and raw.used==1 and raw.free==9)
  print('PASS projected production old base: medicine joins food (19/24); raw wood box becomes pure (1/10); '..refined.operation_count..' moves; 201 full-identity stacks conserved')
 elseif name=='newbase'then
  for _,c in ipairs(refined.containers)do
   for _,slot in ipairs(c.slots)do if slot.item=='Charcoal'then assert(slot.count==40 and slot.category=='processed' and not c.mixed)end end
   assert(not c.mixed,'New base now fits five categories into five dedicated boxes')
  end
  print('PASS projected production newbase: Charcoal40 joins processed materials; all 5 boxes pure; '..refined.operation_count..' moves; 18 stacks conserved')
 else
  assert(refined.operation_count==0,'Already sorted unrelated base should remain unchanged')
  print('PASS projected production '..name..': unchanged, '..refined.stack_count..' stacks')
 end
end
