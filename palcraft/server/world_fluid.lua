-- MC contact driver. The caller owns a verified authoritative native swimming adapter.
-- Fluid.new({world=reducer,on_enter,on_exit,on_update,on_swimming,on_flow,on_unknown})
-- :sample(id,{dim,feet={x,y,z},height=1.8,eye_height=1.62}), :remove(id), :status()
-- No native damage: Minecraft already owns lava/fire/drowning and the entity bridge settles it once.
local Fluid={};Fluid.__index=Fluid
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
function Fluid.new(options)
 assert(options and options.world and options.world.fluid_at,'world reducer required')
 return setmetatable({options=options,contacts={},samples=0,transitions=0,unknown=0},Fluid)
end
function Fluid:_emit(name,value)local callback=self.options[name];if callback then callback(value)end end
local function same_fluid(a,b)
 if not a or not b then return false end
 if a.family and b.family then return a.family==b.family end
 return a.kind==b.kind and(a.kind=='water'or a.kind=='lava'or a.id==b.id)
end
function Fluid:_surface(pose,fluid,x,z)
 local world=self.options.world;local y=fluid.at[2];local current=fluid
 local limit=self.options.max_surface_cells or 64
 assert(finite(limit)and limit>=1 and limit<=256 and limit==math.floor(limit),'bounded column surface limit required')
 for _=1,limit do
  local top=y+current.height
  if current.height<1 then return top,true,'fluid_surface' end
  local nextY=y+1
  if self.options.require_committed~=false and world.region_status then
   local proof=world:region_status(pose.dim,{math.floor(x),nextY,math.floor(z),math.floor(x)+1,nextY+1,math.floor(z)+1},pose.player)
   if not proof.ready then return nil,false,proof.reason end
  end
  local nextBlock=world:get(pose.dim,math.floor(x),nextY,math.floor(z))
  local nextFluid=nextBlock and nextBlock.fluid
  if not same_fluid(current,nextFluid)then return top,true,'fluid_boundary' end
  local accessible=world:fluid_at(pose.dim,x,nextY+0.001,z)
  if not accessible then return top,true,'solid_boundary' end
  y=nextY;current=accessible
 end
 return nil,false,'surface_column_limit'
end
-- Stable public helper for an authoritative capsule/AABB contact adapter using this same world proof policy.
function Fluid:surface_at(pose,fluid,x,z)return self:_surface(pose,fluid,x,z)end
function Fluid:sample(id,pose)
 assert(type(id)=='string'and type(pose)=='table'and type(pose.dim)=='string','identity and dimension required')
 local p=assert(pose.feet,'MC feet required');for i=1,3 do assert(finite(p[i]),'finite MC coordinates required')end
 local height=pose.height or 1.8;local eyeHeight=pose.eye_height or 1.62
 assert(finite(height)and height>0 and height<=16 and finite(eyeHeight)and eyeHeight>=0 and eyeHeight<=height,'valid body dimensions required')
 local world=self.options.world;local lower=world:fluid_at(pose.dim,p[1],p[2]+0.001,p[3])
 if pose.world_session and pose.world_session~=world.session then
  local unknown={id=id,dim=pose.dim,world_session=world.session,view=pose.view,known=false,reason='stale_world_session'}
  self.unknown=self.unknown+1;self:_emit('on_unknown',unknown);return unknown
 end
 if self.options.require_committed~=false and world.region_status then
  local x,y,z=math.floor(p[1]),math.floor(p[2]),math.floor(p[3])
  local proof=world:region_status(pose.dim,{x,y,z,x+1,math.floor(p[2]+height)+1,z+1},pose.player)
  if not proof.ready then local unknown={id=id,dim=pose.dim,world_session=world.session,view=pose.view,known=false,reason=proof.reason,proof=proof}
   self.unknown=self.unknown+1;self:_emit('on_unknown',unknown);return unknown
  end
 end
 local middle=world:fluid_at(pose.dim,p[1],p[2]+height*.5,p[3])
 local eye=world:fluid_at(pose.dim,p[1],p[2]+eyeHeight,p[3])
 local fluid=middle or lower or eye
 local surface,surfaceKnown,surfaceReason
 if fluid then surface,surfaceKnown,surfaceReason=self:_surface(pose,fluid,p[1],p[3])end
 local previous=self.contacts[id]
 local contact={id=id,dim=pose.dim,world_session=world.session,view=pose.view or world.view,known=true,feet=p,kind=fluid and fluid.kind or'none',
  wet=fluid~=nil,body=middle~=nil,submerged=eye~=nil,swimming=middle~=nil and middle.kind=='water',
  flow=fluid and fluid.flow or{0,0,0},waterlogged=fluid and fluid.waterlogged or false,
  surface=surface,surface_known=surfaceKnown==true,surface_reason=surfaceReason,
  volume_surface=fluid and fluid.at[2]+fluid.height or nil,
  immersion=surface and math.max(0,math.min(1,(surface-p[2])/height))or nil,
  simulation='minecraft',native_damage=false}
 local changed=not previous or previous.kind~=contact.kind or previous.dim~=contact.dim or previous.world_session~=contact.world_session
 if changed then
  if previous and previous.wet then self:_emit('on_exit',previous);self.transitions=self.transitions+1 end
  if contact.wet then self:_emit('on_enter',contact);self.transitions=self.transitions+1 end
 end
 if not previous or previous.swimming~=contact.swimming or previous.dim~=contact.dim then self:_emit('on_swimming',contact)end
 if contact.wet then self:_emit('on_flow',contact)end
 self.contacts[id]=contact;self.samples=self.samples+1;self:_emit('on_update',contact);return contact
end
function Fluid:remove(id)
 local previous=self.contacts[id];if not previous then return end
 if previous.wet then self:_emit('on_exit',previous)end
 if previous.swimming then local dry={id=id,dim=previous.dim,kind='none',wet=false,swimming=false,native_damage=false};self:_emit('on_swimming',dry)end
 self.contacts[id]=nil
end
function Fluid:status()
 local wet,swimming=0,0;for _,contact in pairs(self.contacts)do if contact.wet then wet=wet+1 end;if contact.swimming then swimming=swimming+1 end end
 return {samples=self.samples,transitions=self.transitions,unknown=self.unknown,wet=wet,swimming=swimming,
  native_adapter_attached=self.options.on_swimming~=nil,authoritative_native_swimming_verified=self.options.authoritative_native_swimming_verified==true}
end
return Fluid
