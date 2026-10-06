-- Physical body contact over the existing MC reducer. No world reader or engine calls.
-- Positive-volume capsule/AABB intersection is analytic; rounded-cap submerged volume
-- uses exact circle/rectangle areas plus bounded one-dimensional quadrature.
local M={version=1}
local pi=math.pi
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
local function copy(t)local r={};for k,v in pairs(t or{})do r[k]=v end;return r end
local function gap(n,a,b)return math.max(a-n,0,n-b)end
local function overlaps(a,b)
 return a[1]<b[4]and a[4]>b[1]and a[2]<b[5]and a[5]>b[2]and a[3]<b[6]and a[6]>b[3]
end
function M.body(pose)
 local p=assert(pose.feet);local h=assert(pose.height)
 for i=1,3 do assert(finite(p[i]),'Finite physical MC body position required')end
 assert(finite(h)and h>0 and h<=16,'Physical body height required')
 if pose.shape=='aabb'then
  local b=assert(pose.bounds);for i=1,6 do assert(finite(b[i]),'Finite body AABB required')end
  for i=1,3 do assert(b[i]<b[i+3],'Positive body AABB extent required')end
  return{shape='aabb',bounds=b,feet=p,height=h,volume=(b[4]-b[1])*(b[5]-b[2])*(b[6]-b[3])}
 end
 local r=assert(pose.radius,'True scaled Pal capsule radius required')
 assert(finite(r)and r>0 and r<=h*.5,'Valid physical capsule radius required')
 return{shape='capsule',bounds={p[1]-r,p[2],p[3]-r,p[1]+r,p[2]+h,p[3]+r},feet=p,
  height=h,radius=r,axis_bottom=p[2]+r,axis_top=p[2]+h-r,
  volume=pi*r*r*(h-2*r)+4*pi*r*r*r/3}
end
function M.intersects(body,b)
 if not overlaps(body.bounds,b)then return false end
 if body.shape=='aabb'then return true end
 local p=body.feet;local dx,dz=gap(p[1],b[1],b[4]),gap(p[3],b[3],b[6])
 local dy=math.max(b[2]-body.axis_top,0,body.axis_bottom-b[5])
 return dx*dx+dy*dy+dz*dz<body.radius*body.radius -- Tangency is dry.
end
local function radius_at(body,y)
 local r=body.radius;local d=math.max(body.axis_bottom-y,0,y-body.axis_top)
 return d<r and math.sqrt(math.max(0,r*r-d*d))or 0
end
local function quadrant(x,z,r)
 x=math.min(math.abs(x),r);z=math.min(math.abs(z),r)
 if x==0 or z==0 then return 0 end
 if x*x+z*z<=r*r then return x*z end
 local a=math.sqrt(math.max(0,r*r-z*z))
 local function integral(t)return .5*(t*math.sqrt(math.max(0,r*r-t*t))+r*r*math.asin(clamp(t/r,-1,1)))end
 return z*math.min(x,a)+(x>a and integral(x)-integral(a)or 0)
end
function M.circle_rectangle(r,x0,z0,x1,z1)
 if r<=0 or x0>=x1 or z0>=z1 then return 0 end
 if gap(0,x0,x1)^2+gap(0,z0,z1)^2>=r*r then return 0 end
 if x0<=-r and x1>=r and z0<=-r and z1>=r then return pi*r*r end
 if math.max(x0*x0,x1*x1)+math.max(z0*z0,z1*z1)<=r*r then return(x1-x0)*(z1-z0)end
 local function f(x,z)return(x<0 and-1 or 1)*(z<0 and-1 or 1)*quadrant(x,z,r)end
 return clamp(f(x1,z1)-f(x0,z1)-f(x1,z0)+f(x0,z0),0,pi*r*r)
end
function M.section(body,b,y)
 if y<b[2]or y>b[5]then return 0 end
 if body.shape=='aabb'then
  if y<body.bounds[2]or y>body.bounds[5]then return 0 end
  return math.max(0,math.min(b[4],body.bounds[4])-math.max(b[1],body.bounds[1]))
   *math.max(0,math.min(b[6],body.bounds[6])-math.max(b[3],body.bounds[3]))
 end
 local p=body.feet;return M.circle_rectangle(radius_at(body,y),b[1]-p[1],b[3]-p[3],b[4]-p[1],b[6]-p[3])
end
-- Exact full-footprint capsule volume below a flat MC level.
function M.below(body,y)
 local b=body.bounds
 if body.shape=='aabb'then return(b[4]-b[1])*(b[6]-b[3])*clamp(y-b[2],0,b[5]-b[2])end
 local r,h=body.radius,body.height;local d=clamp(y-body.feet[2],0,h)
 local function cap(u)return pi*(r*u*u-u*u*u/3)end
 if d<=r then return cap(d)end
 if d>=h-r then return body.volume-cap(h-d)end
 return 2*pi*r*r*r/3+pi*r*r*(d-r)
end
local function integrate(f,a,b,tolerance)
 local c=(a+b)*.5;local fa,fc,fb=f(a),f(c),f(b);local evaluations=3
 local function solve(a,b,fa,fc,fb,whole,eps,depth)
  local c=(a+b)*.5;local l,r=(a+c)*.5,(c+b)*.5;local fl,fr=f(l),f(r);evaluations=evaluations+2
  local left=(c-a)*(fa+4*fl+fc)/6;local right=(b-c)*(fc+4*fr+fb)/6
  local delta=left+right-whole
  if depth==0 or math.abs(delta)<=15*eps then return math.max(0,left+right+delta/15),math.abs(delta)/15 end
  local lv,le=solve(a,c,fa,fl,fc,left,eps*.5,depth-1)
  local rv,re=solve(c,b,fc,fr,fb,right,eps*.5,depth-1)
  return lv+rv,le+re
 end
 local value,error=solve(a,b,fa,fc,fb,(b-a)*(fa+4*fc+fb)/6,tolerance,6)
 return value,error,evaluations
end
function M.volume(body,b,tolerance)
 if not M.intersects(body,b)then return 0,0,0 end
 local bounds=body.bounds;local lo,hi=math.max(bounds[2],b[2]),math.min(bounds[5],b[5])
 if body.shape=='aabb'then return M.section(body,b,(lo+hi)*.5)*(hi-lo),0,0,hi end
 if b[1]<=bounds[1]and b[4]>=bounds[4]and b[3]<=bounds[3]and b[6]>=bounds[6]then
  return M.below(body,hi)-M.below(body,lo),0,0,hi
 end
 local p,r=body.feet,body.radius;local horizontal=gap(p[1],b[1],b[4])^2+gap(p[3],b[3],b[6])^2
 local cap=math.sqrt(math.max(0,r*r-horizontal))
 lo=math.max(lo,body.axis_bottom-cap);hi=math.min(hi,body.axis_top+cap)
 local cuts={lo,hi};for _,y in ipairs({body.axis_bottom,body.axis_top})do if y>lo and y<hi then cuts[#cuts+1]=y end end
 table.sort(cuts);local value,error,evaluations=0,0,0
 for i=1,#cuts-1 do
  local v,e,n=integrate(function(y)return M.section(body,b,y)end,cuts[i],cuts[i+1],(tolerance or body.volume*1e-6)/(#cuts-1))
  value=value+v;error=error+e;evaluations=evaluations+n
 end
 return value,error,evaluations,hi
end
function M.support(body,b)
 local p=body.feet
 if body.shape=='aabb'then
  local lo,hi={},{ };for i=1,3 do lo[i]=math.max(body.bounds[i],b[i]);hi[i]=math.min(body.bounds[i+3],b[i+3])end
  return{(lo[1]+hi[1])*.5,(lo[2]+hi[2])*.5,(lo[3]+hi[3])*.5}
 end
 local dx,dz=gap(p[1],b[1],b[4]),gap(p[3],b[3],b[6])
 local dy=math.max(b[2]-body.axis_top,0,body.axis_bottom-b[5])
 local d2=dx*dx+dy*dy+dz*dz
 local slack=math.max(body.radius-math.sqrt(d2),(body.radius*body.radius-d2)/(2*body.radius))
 local q={};local center={p[1],(body.axis_bottom+body.axis_top)*.5,p[3]}
 for i=1,3 do local inset=math.min((b[i+3]-b[i])*.25,slack*.25);q[i]=clamp(center[i],b[i]+inset,b[i+3]-inset)end
 return q
end
local Contacts={};Contacts.__index=Contacts
function M.new(o)
 assert(o and o.world and o.volume_boxes and o.column_driver,'Physical contact dependencies required')
 local column=o.column_driver.new{world=o.world,require_committed=o.require_committed~=false,max_surface_cells=o.max_surface_cells}
 assert(column.surface_at,'World-owner public surface_at API required')
 return setmetatable({options=o,column=column,contacts={},samples=0,transitions=0,unknown=0},Contacts)
end
function Contacts:_emit(name,value)local f=self.options[name];if f then f(value)end end
function Contacts:_proof(dim,b,player)
 if self.options.require_committed==false then return{ready=true}end
 local w=self.options.world;assert(w.region_status,'Committed MC shape proof required')
 local fence=tostring(w.session)..':'..tostring(w.seq)
 if fence~=self.proof_fence then self.proofs={};self.proof_fence=fence;self.proof_count=0 end
 local k=dim..':'..tostring(player)..':'..table.concat(b,':');local proof=self.proofs[k]
 if not proof then
  proof=w:region_status(dim,b,player)
  if self.proof_count>=1024 then self.proofs={};self.proof_count=0 end
  self.proofs[k]=proof;self.proof_count=self.proof_count+1
 end
 return proof
end
function Contacts:_surface(pose,fluid,q)
 local p=copy(pose);p.contact_y=q[2]
 local surface,known,reason=self.column:surface_at(p,fluid,q[1],q[3])
 -- Refine the existing column result using exact collision ceilings within
 -- waterlogged cells; the original fluid height/family/proof remains authority.
 local world=self.options.world;local x,z=math.floor(q[1]),math.floor(q[3])
 for n=0,(self.options.max_surface_cells or self.column.options.max_surface_cells or 64)-1 do
  local y=fluid.at[2]+n
  if known and y>=surface then break end
  if not self:_proof(pose.dim,{x,y,z,x+1,y+1,z+1},pose.player).ready then break end
  local g=world:get(pose.dim,x,y,z);local f=g and g.fluid
  local same=f and((fluid.family and f.family)and fluid.family==f.family or(not(fluid.family and f.family)and f.kind==fluid.kind))
  if not same then break end
  local start=n==0 and q[2]or y;local ceiling
  if f.waterlogged then for _,b in ipairs(g.boxes or{})do
   local lx,lz=q[1]-x,q[3]-z
   if lx>=b[1]and lx<b[4]and lz>=b[3]and lz<b[6]and y+b[5]>start and y+b[2]<y+f.height then
    ceiling=math.min(ceiling or math.huge,math.max(start,y+b[2]))
   end
  end end
  if ceiling then return ceiling,true,'waterlogged_solid_boundary' end
  if f.height<1 then break end
 end
 return surface,known,reason
end
function Contacts:sample(id,pose)
 assert(type(id)=='string'and type(pose.dim)=='string','Physical participant identity/dimension required')
 local world=self.options.world;local body=M.body(pose);local bb=body.bounds
 local bounds={math.floor(bb[1]),math.floor(bb[2]),math.floor(bb[3]),math.ceil(bb[4]),math.ceil(bb[5]),math.ceil(bb[6])}
 local function unknown(reason,proof)
  self.unknown=self.unknown+1;local c={id=id,dim=pose.dim,world_session=world.session,view=pose.view,
   known=false,reason=reason,proof=proof,shape=body.shape,bounds=bb};self:_emit('on_unknown',c);return c
 end
 if pose.world_session and pose.world_session~=world.session then return unknown('stale_world_session')end
 local whole=self:_proof(pose.dim,bounds,pose.player)
 local cells={}
 for y=bounds[2],bounds[5]-1 do for z=bounds[3],bounds[6]-1 do for x=bounds[1],bounds[4]-1 do
  local cell={x,y,z,x+1,y+1,z+1}
  if M.intersects(body,cell)then
   if not whole.ready then local proof=self:_proof(pose.dim,cell,pose.player);if not proof.ready then return unknown(proof.reason,proof)end end
   cells[#cells+1]={x,y,z}
  end
 end end end
 local groups={};local tests,evaluations,error=0,0,0;local waist=pose.feet[2]+body.height*.5
 for _,at in ipairs(cells)do local g=world:get(pose.dim,at[1],at[2],at[3]);local fluid=g and g.fluid
  if fluid and fluid.kind~='none'and(fluid.height or 0)>0 then
   local v=copy(fluid);v.at=at;v.solid_boxes=g.boxes
   for _,b in ipairs(self.options.volume_boxes(v))do
    tests=tests+1
    if M.intersects(body,b)then
     local volume,estimate,n,contact_top=M.volume(body,b,body.volume*(self.options.volume_tolerance or 1e-6)/math.max(1,#cells))
     error=error+estimate;evaluations=evaluations+n
     local group=groups[fluid.kind]
     if not group then group={kind=fluid.kind,volume=0,flow={0,0,0},body_area=0,all_surfaces_known=true,parts=0,waterlogged=false,max_part_volume=-1};groups[fluid.kind]=group end
     local q=M.support(body,b);local point=world:fluid_at(pose.dim,q[1],q[2],q[3])
     local surface,known,reason
     if point then surface,known,reason=self:_surface(pose,point,q)
     else known=false;reason='subprecision_contact_support' end
     group.parts=group.parts+1;group.volume=group.volume+volume;group.contact_top=math.max(group.contact_top or-math.huge,contact_top)
     if waist>=b[2]and waist<b[5]then group.body_area=group.body_area+M.section(body,b,waist)end
     group.waterlogged=group.waterlogged or fluid.waterlogged==true
     group.all_surfaces_known=group.all_surfaces_known and known;group.max_surface=known and math.max(group.max_surface or-math.huge,surface)or group.max_surface
     if not known then group.surface_reason=reason end
     if volume>group.max_part_volume then group.max_part_volume=volume;group.surface=surface;group.anchor=q;group.at=at end
     for i=1,3 do local flow=(fluid.flow and fluid.flow[i])or 0;assert(finite(flow),'Finite MC flow required');group.flow[i]=group.flow[i]+flow*volume end
    end
   end
  end
 end
 local dominant;local kinds={};local wet_volume=0
 for kind,g in pairs(groups)do
  g.fraction=clamp(g.volume/body.volume,0,1);wet_volume=wet_volume+g.volume
  if g.volume>0 then for i=1,3 do g.flow[i]=g.flow[i]/g.volume end end
  kinds[kind]={volume=g.volume,fraction=g.fraction,parts=g.parts,surface_known=g.all_surfaces_known,max_surface=g.max_surface,flow=g.flow}
  if not dominant or g.volume>dominant.volume or(g.volume==dominant.volume and kind<dominant.kind)then dominant=g end
 end
 local surface_known=dominant and dominant.all_surfaces_known or false
 local surface=surface_known and dominant.surface or nil
 local denominator=surface and M.below(body,surface)or body.volume
 local coverage=dominant and denominator>0 and clamp(dominant.volume/denominator,0,1)or 0
 local depth=dominant and clamp((dominant.contact_top-pose.feet[2])/.4,0,1)or 0
 local flow_weight=coverage*depth
 local eye=world:fluid_at(pose.dim,pose.feet[1],pose.feet[2]+(pose.eye_height or body.height*.9),pose.feet[3])
 local c={id=id,dim=pose.dim,world_session=world.session,view=pose.view or world.view,known=true,feet=copy(pose.feet),
  kind=dominant and dominant.kind or'none',wet=dominant~=nil,body=dominant and dominant.body_area>0 or false,
  submerged=eye~=nil,swimming=groups.water and groups.water.fraction>=(self.options.swim_fraction or .45)or false,
  flow=dominant and dominant.flow or{0,0,0},flow_weight=flow_weight,flow_coverage=coverage,flow_depth_factor=depth,
  waterlogged=dominant and dominant.waterlogged or false,
  surface=surface,surface_known=surface_known,surface_reason=dominant and dominant.surface_reason or nil,
  max_surface=dominant and dominant.max_surface or nil,immersion=dominant and dominant.fraction or 0,
  query_surface_known=not groups.water or groups.water.all_surfaces_known,
  query_max_surface=groups.water and groups.water.max_surface or nil,
  wet_fraction=clamp(wet_volume/body.volume,0,1),kinds=kinds,lava=groups.lava~=nil,
  shape=body.shape,bounds=copy(bb),radius=body.radius,body_volume=body.volume,body_volume_in_fluid=wet_volume,
  shape_overlap='analytic_positive_volume',volume_method='analytic_circle_rectangle_adaptive_vertical',
  volume_error_estimate=error,quadrature_evaluations=evaluations,cells_tested=#cells,boxes_tested=tests,
  contact_anchor=dominant and dominant.anchor or nil,simulation='minecraft',native_damage=false}
 local previous=self.contacts[id]
 local changed=not previous or previous.kind~=c.kind or previous.dim~=c.dim or previous.world_session~=c.world_session
 if changed then
  if previous and previous.wet then self:_emit('on_exit',previous);self.transitions=self.transitions+1 end
  if c.wet then self:_emit('on_enter',c);self.transitions=self.transitions+1 end
 end
 if not previous or previous.swimming~=c.swimming then self:_emit('on_swimming',c)end
 if c.wet then self:_emit('on_flow',c)end
 self.contacts[id]=c;self.samples=self.samples+1;self:_emit('on_update',c);return c
end
function Contacts:remove(id)
 local previous=self.contacts[id];if not previous then return end
 if previous.wet then self:_emit('on_exit',previous)end
 if previous.swimming then self:_emit('on_swimming',{id=id,dim=previous.dim,kind='none',wet=false,swimming=false,native_damage=false})end
 self.contacts[id]=nil
end
function Contacts:status()
 local wet,swimming=0,0;for _,c in pairs(self.contacts)do if c.wet then wet=wet+1 end;if c.swimming then swimming=swimming+1 end end
 return{samples=self.samples,transitions=self.transitions,unknown=self.unknown,wet=wet,swimming=swimming,
  contact_sampling='physical_capsule_or_aabb',native_adapter_attached=self.options.on_swimming~=nil,
  authoritative_native_swimming_verified=false}
end
return M
