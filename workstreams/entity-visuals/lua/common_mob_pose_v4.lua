-- Direct scalar pose rules from actual MC26.3 model setupAnim implementations.
local M={}
local function f(v)return string.unpack('<f',string.pack('<f',v))end
local function trig(v,offset)
 local n=v*10430.378350470453+(offset or 0);n=(n<0 and math.ceil(n)or math.floor(n))&65535
 return f(math.sin(n*math.pi*2/65536))
end
local function sin(v)return trig(v,0)end
local function cos(v)return trig(v,16384)end
local supported={['minecraft:skeleton']=true,['minecraft:spider']=true,['minecraft:cow']=true,
 ['minecraft:sheep']=true,['minecraft:sheep_wool']=true,['minecraft:chicken']=true,['minecraft:enderman']=true}
function M.supports(kind)return supported[kind]==true end
function M.pose(rig,s)
 s=s or{};local out={}
 for _,p in ipairs(rig.parts)do local c={};for i,v in ipairs(p.rest)do c[i]=v end;out[p.id]=c end
 if s.parts then for id,p in pairs(s.parts)do out[id]=p end;return out end
 local head=out['/head'];if head then head[4]=math.rad(s.head_pitch or 0);head[5]=math.rad(s.head_yaw or 0)end
 local phase=f(f(s.walk_pos or 0)*f(.6662));local speed=f(s.walk_speed or 0)
 local a=f(f(cos(phase)*f(1.4))*speed);local b=f(f(cos(f(phase+f(math.pi)))*f(1.4))*speed)
 local kind=rig.kind
 if kind=='minecraft:cow'or kind=='minecraft:sheep'or kind=='minecraft:sheep_wool'then
  out['/right_hind_leg'][4]=a;out['/left_hind_leg'][4]=b
  out['/right_front_leg'][4]=b;out['/left_front_leg'][4]=a
  if kind~='minecraft:cow'then
   head[2]=head[2]+(s.head_eat_position or 0)*9/16*(s.age_scale or 1)
   head[4]=s.head_eat_angle or math.rad(s.head_pitch or 0)
  end
 elseif kind=='minecraft:chicken'then
  out['/right_leg'][4]=a;out['/left_leg'][4]=b
  local wing=f(f(sin(s.flap or 0)+1)*(s.flap_speed or 0))
  out['/right_wing'][6]=wing;out['/left_wing'][6]=-wing
 elseif kind=='minecraft:spider'then
  local names={'hind','middle_hind','middle_front','front'};local offsets={0,math.pi,math.pi/2,math.pi*1.5}
  for i,name in ipairs(names)do
   local yaw=f(f(-f(cos(f(f(phase*2)+f(offsets[i])))*f(.4)))*speed)
   local roll=f(math.abs(f(sin(f(phase+f(offsets[i])))*f(.4)))*speed)
   local r,l=out['/right_'..name..'_leg'],out['/left_'..name..'_leg']
   r[5]=r[5]+yaw;l[5]=l[5]-yaw;r[6]=r[6]+roll;l[6]=l[6]-roll
  end
 else
  local right,left=out['/right_arm'],out['/left_arm']
  out['/right_leg'][4]=a/(s.speed_value or 1);out['/left_leg'][4]=b/(s.speed_value or 1)
  out['/right_leg'][5]=.005;out['/right_leg'][6]=.005;out['/left_leg'][5]=-.005;out['/left_leg'][6]=-.005
  right[4]=f(cos(f(phase+f(math.pi)))*speed);left[4]=f(cos(phase)*speed)
  right[5]=0;left[5]=0
  local age=s.age or 0;local bx=sin(f(age*f(.067)))*.05;local bz=cos(f(age*f(.09)))*.05+.05
  right[4]=right[4]+bx;left[4]=left[4]-bx;right[6]=bz;left[6]=-bz
  if kind=='minecraft:skeleton'and s.aggressive and not s.holding_bow then
   local swing=s.attack_time or 0;local u=sin(f(swing*f(math.pi)));local v=sin(f((1-(1-swing)^2)*f(math.pi)))
   local pitch=-math.pi/2-u*1.2+v*.4;local yaw=.1-u*.6
   right[4]=pitch+bx;left[4]=pitch-bx;right[5]=-yaw;left[5]=yaw
  elseif kind=='minecraft:enderman'then
   right[4]=math.max(-.4,math.min(.4,right[4]*.5));left[4]=math.max(-.4,math.min(.4,left[4]*.5))
   out['/right_leg'][4]=math.max(-.4,math.min(.4,out['/right_leg'][4]*.5))
   out['/left_leg'][4]=math.max(-.4,math.min(.4,out['/left_leg'][4]*.5))
   if s.carrying then right[4]=-.5;left[4]=-.5;right[6]=.05;left[6]=-.05 end
   if s.creepy then head[2]=head[2]-5/16;out['/head/hat'][2]=out['/head/hat'][2]+5/16 end
  end
 end
 return out
end
return M
