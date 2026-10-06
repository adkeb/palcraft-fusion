-- Uses only the native owner's published models-v5 lifetime API. The caller
-- routes text_plane material requests to this instance's materials:resolve.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local G=dofile(dir..'geometry.lua');local M={version=1};local Native={};Native.__index=Native
function M.new(o)
 assert(o and o.models and o.materials,'Models-v5 and text material resolver required')
 assert((o.models.version or 0)>=5 and o.models.update_groups and o.models.release_model,'Fixed topology/lifetime APIs required')
 return setmetatable({o=o,handles={},stats={created=0,updated=0,removed=0}},Native)
end
function Native:_thread()if IsInGameThread then assert(IsInGameThread(),'Native text requires game thread')end end
function Native:create(ctx,origin,row,fence)
 self:_thread();local groups=G.groups(row,fence.dim,self.o.materials.root,self.o)
 local prepared=self.o.materials:prepare_groups(ctx,groups);self.o.materials:commit_groups(prepared)
 local actor,component,token
 local ok,why=pcall(function()actor,component,token=self.o.models.spawn_groups(ctx,origin,groups,row.at,{hidden=true})end)
 if not ok or not actor then self.o.materials:release(groups[1].sign_key,ctx:GetAddress());error(why or'Native text actor unavailable')end
 assert(math.tointeger(token)and token>0 and component,'Native-v5 text lifetime token required')
 local h={actor=actor,component=component,native_id=token,context=ctx:GetAddress(),ctx=ctx,row=row,groups=groups,alive=true,
  fence=fence,key=groups[1].sign_key,materials=prepared}
 self.handles[actor]=h
 local visible,reason=pcall(self.o.models.set_visible,actor,true)
 if not visible then self:remove(h,true);error(reason)end
 self.stats.created=self.stats.created+1;return h
end
function Native:_component(h)
 if h.component_object and h.component_object:IsValid()then return h.component_object end
 for _,component in ipairs(FindAllOf('ProceduralMeshComponent')or{})do
  if component:IsValid()and component:GetAddress()==h.component then
   local actor=component:GetOwner()
   assert(actor and actor:IsValid()and actor:GetAddress()==h.actor,'Text component lifetime changed')
   h.component_object=component;return component
  end
 end
 error('Text component unavailable')
end
function Native:update(h,row)
 self:_thread();assert(h.alive and self.handles[h.actor]==h and h.ctx:IsValid(),'Stale text actor')
 local groups=G.groups(row,h.fence.dim,self.o.materials.root,self.o)
 local prepared=self.o.materials:prepare_groups(h.ctx,groups)
 if not G.same_geometry(h.row,row)then self.o.models.update_groups(h.actor,groups)end
 self.o.materials:commit_groups(prepared,function(index,material)
  if self.o.set_section_material then self.o.set_section_material(h,index,material)
  else self:_component(h):SetMaterial(index,material)end
 end)
 h.row=row;h.groups=groups;h.materials=prepared;self.stats.updated=self.stats.updated+1;return h
end
function Native:remove(h,context_alive)
 self:_thread();if not h or not h.alive then return true end
 assert(self.handles[h.actor]==h,'Unknown text actor')
 -- false means release native lifetime records without dereferencing dead UE
 -- actors. The world's ordinary models reset subsequently abandons its context.
 self.o.models.release_model(h.actor,context_alive~=false)
 self.o.materials:release(h.key,h.context);h.alive=false;self.handles[h.actor]=nil;self.stats.removed=self.stats.removed+1;return true
end
function Native:set_visible(h,visible)
 self:_thread();assert(h.alive and self.handles[h.actor]==h,'Stale text actor')
 return self.o.models.set_visible(h.actor,visible)
end
function Native:status()return{version=1,stats=self.stats,runtime_verified=false}end
return M
