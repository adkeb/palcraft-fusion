-- Real Minecraft rig/skin geometry. Authority, placement and damage stay external.
local M={};local config,cache={},{}
local function resource(s)return s:find(':',1,true)and s or'minecraft:'..s end
local function clone(v)local r={};for k,x in pairs(v)do r[k]=x end;return r end
local function f32(v)return string.unpack('<f',string.pack('<f',v))end
local function mcTrig(value,offset)
 -- Mth SIN is a 65536-entry float sine table; evaluate its selected entry.
 local n=value*10430.378350470453+(offset or 0)
 n=(n<0 and math.ceil(n)or math.floor(n))&65535
 return f32(math.sin(n*math.pi*2/65536))
end
local function mcSin(v)return mcTrig(v,0)end
local function mcCos(v)return mcTrig(v,16384)end
function M.configure(settings)config=settings;cache={};if config.root:sub(-1)~='/'then config.root=config.root..'/'end end
function M.rig(kind)
 kind=resource(kind);if cache[kind]then return cache[kind]end
 local f=io.open(config.root..'rigs/'..kind:gsub(':','/')..'.json','rb')
 if not f then return nil,'unsupported_minecraft_entity_model' end
 local rig=config.json.decode(f:read('*a'));f:close();cache[kind]=rig;return rig
end
function M.pose(rig,state)
 local s=state or{};local result={}
 for _,part in ipairs(rig.parts)do result[part.id]=clone(part.rest)end
 if s.parts then for id,p in pairs(s.parts)do result[id]=clone(p)end;return result end
 local head=result['/head'];head[4]=math.rad(s.head_pitch or 0);head[5]=math.rad(s.head_yaw or 0)
 local phase=f32(f32(s.walk_pos or 0)*f32(.6662));local speed=f32(s.walk_speed or 0)
 local a=f32(f32(mcCos(phase)*f32(1.4))*speed)
 local b=f32(f32(mcCos(f32(phase+f32(math.pi)))*f32(1.4))*speed)
 if rig.kind=='minecraft:pig'then
  result['/right_hind_leg'][4]=a;result['/left_hind_leg'][4]=b
  result['/right_front_leg'][4]=b;result['/left_front_leg'][4]=a
 elseif rig.kind=='minecraft:creeper'then
  -- The actual CreeperModel fields bind opposite left/right named parts.
  result['/right_hind_leg'][4]=b;result['/left_hind_leg'][4]=a
  result['/right_front_leg'][4]=a;result['/left_front_leg'][4]=b
 elseif rig.kind=='minecraft:zombie'then
  result['/right_leg'][4]=a/(s.speed_value or 1)
  result['/left_leg'][4]=b/(s.speed_value or 1)
  result['/right_leg'][5]=.005;result['/right_leg'][6]=.005
  result['/left_leg'][5]=-.005;result['/left_leg'][6]=-.005
  local swing=s.attack_time or 0;local a=mcSin(f32(swing*f32(math.pi)));local b=mcSin(f32((1-(1-swing)^2)*f32(math.pi)))
  local base=-math.pi/(s.aggressive and 1.5 or 2.25);local pitch=base+a*1.2-b*.4;local yaw=.1-a*.6
  local age=s.age or 0;local bobX=mcSin(f32(age*f32(.067)))*.05;local bobZ=mcCos(f32(age*f32(.09)))*.05+.05
  result['/right_arm'][4]=pitch+bobX;result['/right_arm'][5]=-yaw;result['/right_arm'][6]=bobZ
  result['/left_arm'][4]=pitch-bobX;result['/left_arm'][5]=yaw;result['/left_arm'][6]=-bobZ
  -- Vanilla's currentSwing twists body/arm pivots before ZombieArms overrides
  -- arm rotations; pose samples/default scalar path omit it unless supplied.
  if s.current_swing and swing>0 then
   local twist=mcSin(f32(math.sqrt(swing)*f32(math.pi*2)))*.2*(s.swing_arm=='left'and -1 or 1)
   result['/body'][5]=twist
   result['/right_arm'][1]=-mcCos(twist)*5/16;result['/right_arm'][3]=mcSin(twist)*5/16
   result['/left_arm'][1]=mcCos(twist)*5/16;result['/left_arm'][3]=-mcSin(twist)*5/16
  end
 end
 return result
end
local function localTransform(p)
 local x,y,z=p[4],p[5],p[6]
 local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
 return{cz*cy*p[7],(cz*sy*sx-sz*cx)*p[8],(cz*sy*cx+sz*sx)*p[9],
        sz*cy*p[7],(sz*sy*sx+cz*cx)*p[8],(sz*sy*cx-cz*sx)*p[9],
        -sy*p[7],cy*sx*p[8],cy*cx*p[9],p[1],p[2],p[3]}
end
local function point(m,p)return{m[1]*p[1]+m[2]*p[2]+m[3]*p[3]+m[10],m[4]*p[1]+m[5]*p[2]+m[6]*p[3]+m[11],m[7]*p[1]+m[8]*p[2]+m[9]*p[3]+m[12]}end
local function multiply(a,b)
 local r={}
 for row=0,2 do for col=0,2 do r[row*3+col+1]=a[row*3+1]*b[col+1]+a[row*3+2]*b[col+4]+a[row*3+3]*b[col+7]end end
 local t=point(a,{b[10],b[11],b[12]});r[10]=t[1];r[11]=t[2];r[12]=t[3];return r
end
local function normal(m,n)
 -- Cofactors are inverse-transpose up to determinant; normalize afterward.
 local r={(m[5]*m[9]-m[6]*m[8])*n[1]+(m[6]*m[7]-m[4]*m[9])*n[2]+(m[4]*m[8]-m[5]*m[7])*n[3],
          (m[3]*m[8]-m[2]*m[9])*n[1]+(m[1]*m[9]-m[3]*m[7])*n[2]+(m[2]*m[7]-m[1]*m[8])*n[3],
          (m[2]*m[6]-m[3]*m[5])*n[1]+(m[3]*m[4]-m[1]*m[6])*n[2]+(m[1]*m[5]-m[2]*m[4])*n[3]}
 local length=math.sqrt(r[1]^2+r[2]^2+r[3]^2);return{r[1]/length,r[2]/length,r[3]/length}
end
local function bodyEffects(kind,s)
 local effect={scale_xz=1,scale_y=1,red_overlay=s.hurt==true or(s.death_time or 0)>0,white_overlay=0,
  death_roll=math.min(1,math.sqrt(math.max(0,((s.death_time or 0)-1)/20*1.6)))*math.pi/2}
 if kind=='minecraft:creeper'then
  local f=s.swelling or 0;local pulse=1+mcSin(f32(f*100))*f*.01;local eased=math.max(0,math.min(1,f))^4
  effect.scale_xz=(1+eased*.4)*pulse;effect.scale_y=(1+eased*.1)/pulse
  effect.white_overlay=math.floor(f*10)%2~=0 and math.max(.5,math.min(1,f))or 0
 end
 return effect
end
function M.geometry(kind,state)
 local rig,why=M.rig(kind);if not rig then return nil,why end
 local s=state or{};local poses=M.pose(rig,s);local matrices={};local visible={}
 local effects=bodyEffects(rig.kind,s)
 local g={texture=rig.texture,texture_path=config.root..rig.skin_path,alpha_mode=rig.alpha_mode,tint=-1,shade=true,light_emission=0,
  part='entity',entity_visual=true,collision=false,kind=rig.kind,vertices={},indices={},face_ranges={},pose=poses,render_effects=effects}
 local size=s.scale or 1;local scaleXZ=effects.scale_xz*size;local scaleY=effects.scale_y*size
 local ca,sa=math.cos(-effects.death_roll),math.sin(-effects.death_roll)
 for _,part in ipairs(rig.parts)do
  local m=localTransform(poses[part.id]);local parent=part.parent and matrices[part.parent]
  if parent then m=multiply(parent,m)end;matrices[part.id]=m
  visible[part.id]=part.visible~=false and(not part.parent or visible[part.parent]~=false)
  if visible[part.id]and not part.skip_draw then for _,face in ipairs(part.faces)do
   local first=#g.vertices;local n=normal(m,face.normal)
   local nx,ny,nz=-n[3]/scaleXZ,n[1]/scaleXZ,-n[2]/scaleY
   local length=math.sqrt(nx*nx+ny*ny+nz*nz);nx,ny,nz=nx/length,ny/length,nz/length
   ny,nz=ca*ny-sa*nz,sa*ny+ca*nz
   for _,v in ipairs(face.vertices)do
    local p=point(m,v);local x,y,z=-p[3]*100*scaleXZ,p[1]*100*scaleXZ,(rig.renderer_model_y_offset-p[2])*100*scaleY
    y,z=ca*y-sa*z,sa*y+ca*z
    g.vertices[#g.vertices+1]={x,y,z,nx,ny,nz,v[4],v[5]}
   end
   for _,i in ipairs({0,2,1,0,3,2})do g.indices[#g.indices+1]=first+i end
   g.face_ranges[#g.face_ranges+1]={first_vertex=first,part=part.id}
  end end
 end
 return{g},effects
end
M.body_effects=bodyEffects
return M
