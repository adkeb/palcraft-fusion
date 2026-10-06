-- Pure, shared travel protocol and bounded physical-region allocation. No Unreal calls.
local M={version=1};local Registry={};Registry.__index=Registry
local function finite(x)return type(x)=='number'and x==x and x~=math.huge and x~=-math.huge end
local function integer(x)return finite(x)and x==math.floor(x)end
local function text(x)return type(x)=='string'and #x>0 and #x<=512 end
local function uuid(x)return type(x)=='string'and x:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil end
function M.copy(x)
 if type(x)~='table'then return x end;local out={};for k,v in pairs(x)do out[k]=M.copy(v)end;return out
end
function M.vector(x)
 if type(x)~='table'or #x~=3 then return false end
 for i=1,3 do if not finite(x[i])then return false end end;return true
end
function M.ue(x)return type(x)=='table'and finite(x.X)and finite(x.Y)and finite(x.Z)end
function M.bounds(x)
 if type(x)~='table'or #x~=6 then return false end
 for i=1,6 do if not finite(x[i])then return false end end
 return x[1]<x[4]and x[2]<x[5]and x[3]<x[6]
end
function M.contains(b,p,margin)
 if not M.bounds(b)or not M.ue(p)then return false end;local m=margin or 0
 return p.X>=b[1]+m and p.Y>=b[2]+m and p.Z>=b[3]+m and p.X<=b[4]-m and p.Y<=b[5]-m and p.Z<=b[6]-m
end
function M.covers(a,b)
 if not M.bounds(a)or not M.bounds(b)then return false end
 for i=1,3 do if a[i]>b[i]or a[i+3]<b[i+3]then return false end end;return true
end
function M.distance(a,b)
 if not M.ue(a)or not M.ue(b)then return math.huge end
 return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)
end
function M.binding(b)
 return type(b)=='table'and uuid(b.mc_uuid)and uuid(b.pal_uid)and uuid(b.session_id)and text(b.mc_epoch)
  and integer(b.generation)and b.generation>=1 and text(b.world_id)and text(b.server_session_id)
end
function M.same_binding(a,b)
 return M.binding(a)and M.binding(b)and a.mc_uuid==b.mc_uuid and a.pal_uid==b.pal_uid
  and a.session_id==b.session_id and a.generation==b.generation and a.mc_epoch==b.mc_epoch
  and a.world_id==b.world_id and a.server_session_id==b.server_session_id
end
function M.identity(b)
 assert(M.binding(b),'authenticated_binding_required');local r={}
 for _,k in ipairs({'mc_uuid','pal_uid','session_id','generation','mc_epoch','world_id','server_session_id'})do r[k]=b[k]end;return r
end
function M.envelope(row)
 return type(row)=='table'and row.t=='travel'and row.v==1 and text(row.tx)and text(row.phase)
  and uuid(row.player)and uuid(row.pal_uid)and uuid(row.session_id)and text(row.mc_epoch)
  and integer(row.session_generation)and row.session_generation>=1 and text(row.world_id)
  and text(row.server_session_id)and text(row.world_session)and text(row.dim)and integer(row.view)and row.view>=1
end
function M.matches(row,tx,binding)
 return M.envelope(row)and row.tx==tx.tx and row.player==binding.mc_uuid and row.pal_uid==binding.pal_uid
  and row.session_id==binding.session_id and row.session_generation==binding.generation and row.mc_epoch==binding.mc_epoch
  and row.world_id==binding.world_id and row.server_session_id==binding.server_session_id
  and row.world_session==tx.world_session and row.dim==tx.dim and row.view==tx.view
end
function M.message(tx,phase,extra)
 local b=tx.binding;local out={t='travel',v=1,phase=phase,tx=tx.tx,player=b.mc_uuid,pal_uid=b.pal_uid,
  session_id=b.session_id,session_generation=b.generation,mc_epoch=b.mc_epoch,
  world_id=b.world_id,server_session_id=b.server_session_id,world_session=tx.world_session,dim=tx.dim,view=tx.view}
 for k,v in pairs(extra or{})do out[k]=M.copy(v)end;return out
end
function M.event(row,e)
 if type(row)~='table'or row.t~='blocks'or row.v~=2 or not text(row.session)or not integer(row.seq)or row.seq<1 then return false,'world_envelope' end
 if type(e)~='table'or e.op~='player_view'or not uuid(e.player)or not text(e.to)or row.dim~=e.to
  or not integer(e.view)or e.view<1 or not M.vector(e.pos)or not finite(e.yaw)or not finite(e.pitch)then return false,'player_view' end
 for i=1,3 do if math.abs(e.pos[i])>30000000 then return false,'mc_bounds' end end
 if e.from~=nil and not text(e.from)then return false,'source_dimension'end
 if e.reason~='join'and e.reason~='dimension_change'and e.reason~='respawn'and e.reason~='teleport'
  and e.reason~='reconnect'and e.reason~='rebase'and e.reason~='rollback'then return false,'transition_reason'end
 return true
end
function M.to_ue(mapping,pos)
 assert(M.mapping(mapping)and M.vector(pos),'invalid_coordinate_mapping')
 local o,s=mapping.origin,mapping.scale
 return{X=o.X+s*pos[1],Y=o.Y-s*pos[3],Z=o.Z+s*(pos[2]-mapping.y_origin)}
end
function M.to_mc(mapping,pos)
 assert(M.mapping(mapping)and M.ue(pos),'invalid_coordinate_mapping');local o,s=mapping.origin,mapping.scale
 return{(pos.X-o.X)/s,mapping.y_origin+(pos.Z-o.Z)/s,-(pos.Y-o.Y)/s}
end
function M.mapping(m)
 return type(m)=='table'and text(m.region_id)and text(m.world_session)and text(m.dim)
  and M.ue(m.origin)and M.ue(m.center)and M.vector(m.mc_anchor)and finite(m.scale)and m.scale>0
  and finite(m.y_origin)and M.bounds(m.region_bounds)
end
function M.mc_rotation(yaw,pitch)return{Yaw=-90-yaw,Pitch=-pitch,Roll=0}end
function M.quaternion(r)
 -- Unreal FRotator::Quaternion convention: intrinsic yaw(Z), pitch(Y), roll(X).
 local p,y,w=r.Pitch*math.pi/360,r.Yaw*math.pi/360,(r.Roll or 0)*math.pi/360
 local sp,cp,sy,cy,sr,cr=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(w),math.cos(w)
 return{X=cr*sp*sy-sr*cp*cy,Y=-cr*sp*cy-sr*cp*sy,Z=cr*cp*sy-sr*sp*cy,W=cr*cp*cy+sr*sp*sy}
end
function M.ready(proof,req,mode)
 if type(proof)~='table'then return false,'readiness_missing'end
 if proof.ready~=true or proof.world_session~=req.world_session or proof.dim~=req.dim or proof.view~=req.view
  or proof.region_id~=req.mapping.region_id or not integer(proof.generation)or proof.generation<1
  or(req.generation~=nil and proof.generation~=req.generation)then return false,'readiness_fence'end
 if proof.coverage_complete~=true or not M.covers(proof.covered_bounds,req.required_bounds)
  or proof.snapshots_pending~=0 or proof.collision_pending~=0 or proof.collision_committed~=true
  or not integer(proof.revision)or proof.revision<0 then return false,'collision_or_snapshot_pending'end
 if type(proof.errors)~='table'or next(proof.errors)~=nil then return false,'renderer_errors'end
 if mode=='client'and(proof.visual_pending~=0 or proof.visual_committed~=true)then return false,'visual_pending'end
 return true
end
-- Bootstrap callers supply a finite cap. Pending alone is not progress. Only
-- current ticket evidence may renew preparation; readiness and ACK stay intact.
function M.initial_prepare_lease(tx,proof,req,now,timeout,mode)
 if not finite(tx.initial_prepare_limit)or not finite(tx.initial_prepare_started)
  or now<tx.initial_prepare_started or now>=tx.initial_prepare_limit then return false end
 if type(proof)~='table'or proof.world_session~=req.world_session or proof.dim~=req.dim or proof.view~=req.view
  or proof.region_id~=req.mapping.region_id or proof.generation~=req.generation
  or not integer(proof.revision)or proof.revision<0 or type(proof.errors)~='table'or next(proof.errors)~=nil
  or not integer(proof.snapshots_pending)or proof.snapshots_pending<0
  or not integer(proof.collision_pending)or proof.collision_pending<0
  or(mode=='client'and(not integer(proof.visual_pending)or proof.visual_pending<0))then return false end
 local sample={revision=proof.revision,snapshots=proof.snapshots_pending,collision=proof.collision_pending,
  visual=mode=='client'and proof.visual_pending or 0,coverage=proof.coverage_complete==true}
 local old=tx._initial_prepare_progress
 local progress=not old and(sample.revision>0 or sample.snapshots>0 or sample.collision>0 or sample.visual>0 or sample.coverage)
  or old and(sample.revision>old.revision or sample.snapshots~=old.snapshots or sample.collision<old.collision
   or sample.visual<old.visual or sample.coverage and not old.coverage)
 if progress then tx._initial_prepare_progress_at=now end
 tx._initial_prepare_progress=sample
 if now<tx.deadline then return false end
 local ready=M.ready(proof,req,mode)
 if ready or tx._initial_prepare_progress_at and now-tx._initial_prepare_progress_at<timeout then
  tx.deadline=math.min(tx.initial_prepare_limit,now+timeout)
  tx.initial_prepare_extensions=(tx.initial_prepare_extensions or 0)+1
  return true
 end
 return false
end
function M.request(tx,mode)
 return{player=tx.binding.mc_uuid,world_session=tx.world_session,dim=tx.dim,view=tx.view,
  session_generation=tx.binding.generation,session_id=tx.binding.session_id,mc_epoch=tx.binding.mc_epoch,
  mapping=M.copy(tx.mapping),required_bounds=M.copy(tx.required_bounds),mode=mode,tx=tx.tx}
end
function M.camera_commit(frame,tx,host_scope)
 if type(frame)~='table'or frame.schema~=1 or frame.ready~=true or not text(frame.source_epoch)
  or not integer(frame.source_frame)or frame.source_frame<1 or not integer(frame.source_generation)or frame.source_generation<1
  or not integer(frame.origin_generation)or frame.origin_generation<1 or not integer(frame.origin_frame)
  or frame.source_frame<=frame.origin_frame then return false,'target_camera_frame_pending'end
 if frame.world_session~=tx.world_session or frame.dim~=tx.dim or frame.view~=tx.view then return false,'camera_world_view_mismatch'end
 local h=frame.host_scope
 if type(h)~='table'or not text(h.session_id)or not integer(h.generation)or h.generation<1
  or h.mc_uuid~=tx.binding.mc_uuid or h.pal_uid~=tx.binding.pal_uid or h.world_id~=tx.binding.world_id
  or h.server_session_id~=tx.binding.server_session_id then return false,'camera_host_identity_mismatch'end
 if host_scope then for _,k in ipairs({'session_id','generation','mc_uuid','pal_uid','world_id','server_session_id'})do
  if h[k]~=host_scope[k]then return false,'camera_host_generation_mismatch'end
 end end
 return true
end
local function overlap(a,b)
 for i=1,3 do if a[i+3]<=b[i]or b[i+3]<=a[i]then return false end end;return true
end
function M.registry(config,saved)
 assert(config.version==1 and config.scale>0 and config.page_blocks>0 and M.bounds(config.world_bounds),'travel_config')
 local self=setmetatable({config=config,regions=M.copy(saved and saved.regions or{}),refs={}},Registry)
 -- Validate physical pool spacing before a transaction can allocate it.
 local pool={};for dim,d in pairs(config.dimensions)do for i,slot in ipairs(config.slots)do
  local h=config.region_half_width_cm;local c={X=d.center.X+slot[1],Y=d.center.Y+slot[2],Z=d.center.Z}
  local b={c.X-h,c.Y-h,c.Z+config.scale*(d.min_y-config.y_origin),c.X+h,c.Y+h,c.Z+config.scale*(d.max_y-config.y_origin)}
  assert(M.contains(config.world_bounds,{X=b[1],Y=b[2],Z=b[3]})and M.contains(config.world_bounds,{X=b[4],Y=b[5],Z=b[6]}),'pool_outside_world_bounds')
  for _,prior in ipairs(pool)do assert(not overlap(b,prior.bounds),'physical_region_overlap:'..dim..':'..i)end
  pool[#pool+1]={bounds=b}
 end end
 return self
end
function Registry:acquire(world_session,dim,pos,owner)
 local c=self.config;local d=c.dimensions[dim];if not d then return nil,'unsupported_dimension'end
 if dim=='minecraft:overworld'then
  local o=c.home_origin;local w=c.world_bounds;local r=c.radius_blocks;local pad=c.region_vertical_padding_cm or 500
  local native_bounds={w[1],w[2],o.Z+c.scale*(d.min_y-c.y_origin)-pad,w[4],w[5],o.Z+c.scale*(d.max_y-c.y_origin)+pad}
  local low={X=o.X+c.scale*(math.floor(pos[1])-r),Y=o.Y-c.scale*(math.floor(pos[3])+r+1),Z=o.Z+c.scale*(pos[2]-c.y_origin)}
  local high={X=o.X+c.scale*(math.floor(pos[1])+r+1),Y=o.Y-c.scale*(math.floor(pos[3])-r),Z=low.Z}
  if M.contains(native_bounds,low)and M.contains(native_bounds,high)then
   local id=world_session..'/'..dim..'/native'
   local mapping={region_id=id,world_session=world_session,dim=dim,slot=0,native_overworld=true,
    page_size=c.native_overworld_window_size or 32000,window_size=c.native_overworld_window_size or 32000,
    mc_anchor={0,c.y_origin,0},center=M.copy(o),origin=M.copy(o),scale=c.scale,y_origin=c.y_origin,
    profile=d.profile,region_bounds=native_bounds}
   self.regions[id]=mapping;self.refs[id]=self.refs[id]or{};self.refs[id][owner]=true;return M.copy(mapping)
  end
 end
 local page=c.page_blocks;local ax=math.floor((pos[1]+page/2)/page)*page;local az=math.floor((pos[3]+page/2)/page)*page
 local id=world_session..'/'..dim..'/'..ax..'/'..az;local mapping=self.regions[id]
 if not mapping then
  local slot=0;local center
  do
   local occupied={};for region,r in pairs(self.regions)do if r.dim==dim and r.slot>0 then
    if next(self.refs[region]or{})~=nil or(self.can_recycle and self.can_recycle(r)~=true)then occupied[r.slot]=true end
   end end
   for i in ipairs(c.slots)do if not occupied[i]then slot=i;break end end
   if slot==0 then return nil,'physical_region_capacity'end
   -- Only an unoccupied region may be recycled. Its caller must release its last native ticket first.
   local expired={};for old,r in pairs(self.regions)do if r.dim==dim and r.slot==slot then expired[#expired+1]=old end end
   for _,old in ipairs(expired)do self.regions[old]=nil;self.refs[old]=nil end
   center={X=d.center.X+c.slots[slot][1],Y=d.center.Y+c.slots[slot][2],Z=d.center.Z}
  end
  local h=c.region_half_width_cm
  mapping={region_id=id,world_session=world_session,dim=dim,slot=slot,page_size=page,window_size=c.window_size or page,
   mc_anchor={ax,c.y_origin,az},center=center,
   origin={X=center.X-c.scale*ax,Y=center.Y+c.scale*az,Z=center.Z},scale=c.scale,y_origin=c.y_origin,
   profile=d.profile,region_bounds={center.X-h,center.Y-h,center.Z+c.scale*(d.min_y-c.y_origin)-(c.region_vertical_padding_cm or 500),
    center.X+h,center.Y+h,center.Z+c.scale*(d.max_y-c.y_origin)+(c.region_vertical_padding_cm or 500)}}
  if dim=='minecraft:overworld'then mapping.auxiliary_pending=true end
  self.regions[id]=mapping
 end
 self.refs[id]=self.refs[id]or{};self.refs[id][owner]=true;return M.copy(mapping)
end
function Registry:retain(mapping,owner)
 assert(M.mapping(mapping),'mapping_required');self.regions[mapping.region_id]=M.copy(mapping)
 self.refs[mapping.region_id]=self.refs[mapping.region_id]or{};self.refs[mapping.region_id][owner]=true
end
function Registry:release(mapping,owner)
 local refs=mapping and self.refs[mapping.region_id];if refs then refs[owner]=nil end
end
function Registry:save()return{regions=M.copy(self.regions)}end
function Registry:required(mapping,pos)
 local r=self.config.radius_blocks;local d=self.config.dimensions[mapping.dim]
 local bounds={math.floor(pos[1])-r,math.max(d.min_y,math.floor(pos[2])-(self.config.below_blocks or 16)),math.floor(pos[3])-r,
  math.floor(pos[1])+r+1,math.min(d.max_y,math.floor(pos[2])+(self.config.above_blocks or 32)),math.floor(pos[3])+r+1}
 local lo=M.to_ue(mapping,{bounds[1],bounds[2],bounds[3]});local hi=M.to_ue(mapping,{bounds[4],bounds[5],bounds[6]})
 if not M.contains(mapping.region_bounds,lo)or not M.contains(mapping.region_bounds,hi)then return nil,'required_window_outside_region'end
 return bounds
end
return M
