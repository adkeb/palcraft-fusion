-- Real MC drops/projectiles: visual-only, no inventory, pickup or damage calls.
local M={};local config,cache,textures={}, {},nil
local function resource(s)return s:find(':',1,true)and s or'minecraft:'..s end
local function read(path)
 if cache[path]~=nil then return cache[path]~=false and cache[path]or nil end
 local f=io.open(config.root..path,'rb');if not f then cache[path]=false;return nil end
 local value=config.json.decode(f:read('*a'));f:close();cache[path]=value;return value
end
function M.configure(o)config=o;cache={};if config.root:sub(-1)~='/'then config.root=config.root..'/'end;textures=read('textures.json')end
local function f(v)return string.unpack('<f',string.pack('<f',v))end
local function mcSin(v)
 local n=v*10430.378350470453;n=(n<0 and math.ceil(n)or math.floor(n))&65535
 return f(math.sin(n*math.pi*2/65536))
end
local function axis(p,name,a)
 local q={p[1],p[2],p[3]};local c,s=math.cos(a),math.sin(a)
 if name=='x'then q[2],q[3]=c*p[2]-s*p[3],s*p[2]+c*p[3]
 elseif name=='y'then q[1],q[3]=c*p[1]+s*p[3],-s*p[1]+c*p[3]
 else q[1],q[2]=c*p[1]-s*p[2],s*p[1]+c*p[2]end
 return q
end
local function normalized(n)local length=math.sqrt(n[1]^2+n[2]^2+n[3]^2);return{n[1]/length,n[2]/length,n[3]/length}end
local function append(g,positions,normal,uv,part)
 local first=#g.vertices
 for i,p in ipairs(positions)do g.vertices[#g.vertices+1]={p[1]*100,-p[3]*100,p[2]*100,normal[1],-normal[3],normal[2],uv[i][1],uv[i][2]}end
 for _,n in ipairs({0,2,1,0,3,2})do g.indices[#g.indices+1]=first+n end
 g.face_ranges[#g.face_ranges+1]={first_vertex=first,part=part}
end
local function group(groups,texture,kind)
 if not groups[texture]then
  local info=textures[texture]
  groups[texture]={texture=texture,texture_path=info and config.root..info.path,material_root=config.root,alpha_mode='cutout',tint=-1,shade=true,
   light_emission=0,part=kind,entity_visual=true,portable_visual=true,collision=false,actor_yaw=0,
   world_orientation_baked=true,vertices={},indices={},face_ranges={}}
 end
 return groups[texture]
end
local function ordered(groups)local result={};for _,g in pairs(groups)do result[#result+1]=g end;table.sort(result,function(a,b)return a.texture<b.texture end);return result end
local function transform(p,pose,normal)
 local q={p[1],p[2],p[3]}
 for i=1,3 do q[i]=normal and q[i]/pose[6+i]or q[i]*pose[6+i]end
 q=axis(axis(axis(q,'x',pose[4]),'y',pose[5]),'z',pose[6])
 if not normal then for i=1,3 do q[i]=q[i]+pose[i]end end
 return q
end
function M.projectile(row)
 local kind=resource(row.kind);local name=kind=='minecraft:trident'and'trident'or(kind=='minecraft:arrow'or kind=='minecraft:spectral_arrow')and'arrow'or nil
 if not name then return nil,'unsupported_actual_projectile_model' end
 local rig=read('projectiles/minecraft/'..name..'.json');if not rig then return nil,'missing_projectile_rig' end
 local skin=kind=='minecraft:spectral_arrow'and'minecraft:entity/projectiles/arrow_spectral'or rig.texture
 local parts={};for _,p in ipairs(rig.parts)do parts[p.id]=p end
 local chain={};local groups={}
 local yaw=math.rad((row.yaw or 0)-90);local pitch=math.rad((row.pitch or 0)+(name=='trident'and 90 or 0))
 for _,part in ipairs(rig.parts)do
  local pose={};for i,v in ipairs(part.rest)do pose[i]=v end
  if part.id=='/'and name=='arrow'and(row.shake or 0)>0 then pose[6]=pose[6]+math.rad(-mcSin(f(row.shake*3))*row.shake)end
  local path={pose};if part.parent then for _,ancestor in ipairs(chain[part.parent])do path[#path+1]=ancestor end end;chain[part.id]=path
  for _,face in ipairs(part.faces)do
   local positions={};local uv={};local n=face.normal
   for _,p in ipairs(path)do n=transform(n,p,true)end
   n=normalized(axis(axis(n,'z',pitch),'y',yaw))
   for _,v in ipairs(face.vertices)do
    local q={v[1],v[2],v[3]};for _,p in ipairs(path)do q=transform(q,p,false)end
    positions[#positions+1]=axis(axis(q,'z',pitch),'y',yaw);uv[#uv+1]={v[4],v[5]}
   end
   append(group(groups,skin,'projectile'),positions,n,uv,part.id)
  end
 end
 local result=ordered(groups);for _,g in ipairs(result)do g.foil_pending=row.foil==true;g.kind=kind end
 return result,{actor_yaw=0,world_orientation_baked=true,shake_baked=name=='arrow',foil_material_pending=row.foil==true}
end
local function groundPoint(v,display,normal)
 local scale=display.scale or{1,1,1};local rotation=display.rotation or{0,0,0};local translation=display.translation or{0,0,0}
 local p={v[1],v[2],v[3]}
 for i=1,3 do p[i]=normal and p[i]/scale[i]or(p[i]-.5)*scale[i]end
 -- Actual ItemTransform.rotationXYZ: Z then Y then X for vertex application.
 p=axis(axis(axis(p,'z',math.rad(rotation[3])),'y',math.rad(rotation[2])),'x',math.rad(rotation[1]))
 if not normal then for i=1,3 do p[i]=p[i]+translation[i]/16 end end
 return p
end
local function amount(count)if count<=1 then return 1 elseif count<=16 then return 2 elseif count<=32 then return 3 elseif count<=48 then return 4 else return 5 end end
local function random(seed)
 local value=(math.tointeger(seed)~0x5deece66d)&0xffffffffffff
 return function()value=(value*0x5deece66d+11)&0xffffffffffff;return(value>>24)/0x1000000 end
end
function M.item(row)
 local id=resource(row.item or row.kind);local model=read('items/'..id:gsub(':','/')..'.json')
 if not model then return nil,'unsupported_actual_item_model' end
 local prepared={};local minY,minZ,maxZ=math.huge,math.huge,-math.huge
 for _,face in ipairs(model.faces)do
  local points={};for _,v in ipairs(face.vertices)do local q=groundPoint(v,model.ground,false);points[#points+1]=q;minY=math.min(minY,q[2]);minZ=math.min(minZ,q[3]);maxZ=math.max(maxZ,q[3])end
  prepared[#prepared+1]={points=points,normal=normalized(groundPoint(face.normal,model.ground,true)),uv=face.uv,texture=face.texture}
 end
 local age=row.age or 0;local offset=row.bob_offset or 0
 local bob=f(f(mcSin(f(f(age/10)+offset))*.1)+.1);local lift=bob-minY+.0625
 local spin=row.spin or f(f(age/20)+offset)
 local groups={};local count=amount(row.count or 1);local nextFloat=random(row.render_seed or 187)
 local thick=maxZ-minZ>.0625;local separation=(maxZ-minZ)*1.5
 for copy=1,count do
  local shift={0,0,thick and 0 or -separation*(count-1)/2+(copy-1)*separation}
  if copy>1 then
   if thick then for i=1,3 do shift[i]=(nextFloat()*2-1)*.15 end
   else shift[1]=(nextFloat()*2-1)*.15*.5;shift[2]=(nextFloat()*2-1)*.15*.5 end
  end
  for _,face in ipairs(prepared)do
   local positions={};for _,p in ipairs(face.points)do local q=axis({p[1]+shift[1],p[2]+shift[2],p[3]+shift[3]},'y',spin);q[2]=q[2]+lift;positions[#positions+1]=q end
   append(group(groups,face.texture,'item'),positions,axis(face.normal,'y',spin),face.uv,'copy'..copy)
  end
 end
 local result=ordered(groups);for _,g in ipairs(result)do g.item=id;g.count=row.count or 1;g.rendered_copies=count;g.pose_timing_pending=row.age==nil or row.bob_offset==nil;g.render_seed_pending=row.render_seed==nil end
 return result,{actor_yaw=0,world_orientation_baked=true,item_ground_pose_baked=true,bob=bob,spin=spin,
  pose_timing_pending=row.age==nil or row.bob_offset==nil,render_seed_pending=row.render_seed==nil}
end
function M.geometry(row)
 if row.category=='projectile'then return M.projectile(row)end
 return M.item(row)
end
return M
