-- Inert factory for the existing game-thread loop. It owns no timer, network,
-- font, sign editing input or screen overlay. Only accepted world blocks render.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local G=dofile(dir..'geometry.lua');local M={version=1};local Worker={};Worker.__index=Worker
function M.binding_request(fence,bounds)
 G.fence(fence);assert(type(bounds)=='table'and #bounds==6,'Native view exclusive bounds required')
 for i=1,3 do assert(math.tointeger(bounds[i])and math.tointeger(bounds[i+3])and bounds[i]<bounds[i+3],'Native view bounds invalid')end
 return{t='sign_text_view',op='bind',world_session=fence.world_session,dim=fence.dim,view=fence.view,
  mapping=fence.mapping,mc_uuid=fence.mc_uuid,bounds={table.unpack(bounds)}}
end
function M.new(o)
 assert(o and o.json and o.renderer and type(o.block_at)=='function','JSON/native renderer/committed block lookup required')
 return setmetatable({o=o,views={},last_seen=0,last_seq=-1,stats={created=0,updated=0,removed=0,rejected=0},running=true},Worker)
end
local function same(a,b)
 if not G.same_geometry(a,b)then return false end
 for _,side in ipairs({'front','back'})do if a[side].image.sha256~=b[side].image.sha256 or a[side].image.alpha_mode~=b[side].image.alpha_mode then return false end end
 return a.id==b.id and a.state_key==b.state_key
end
function Worker:_thread()if IsInGameThread then assert(IsInGameThread(),'Sign consumer requires game thread')end end
function Worker:_clock()return(self.o.now_ms or function()return os.time()*1000 end)()end
function Worker:bind(fence,context_alive,bounds)
 self:_thread();local key=G.fence(fence)
 if key~=self.fence_key then self:reset('world_view_changed',context_alive);self.fence=fence;self.fence_key=key end
 if bounds and self.o.send_binding then self.o.send_binding(M.binding_request(fence,bounds))end
 return true
end
function Worker:_remove(key,context_alive)
 local v=self.views[key];if not v then return end
 self.o.renderer:remove(v.handle,context_alive);self.views[key]=nil;self.stats.removed=self.stats.removed+1
end
function Worker:reset(reason,context_alive)
 self:_thread();local keys={};for key in pairs(self.views)do keys[#keys+1]=key end
 for _,key in ipairs(keys)do self:_remove(key,context_alive)end
 self.last_seq=-1;self.producer=nil;self.producer_epoch=nil;self.last_seen=0;self.fence=nil;self.fence_key=nil;self.reason=reason
end
function Worker:_block(row)
 local block,committed=self.o.block_at(self.fence.dim,row.at)
 return committed==true and type(block)=='table'and block.id==row.id and block.state==row.state_key
  and block.visible~=false and block.mirror~=false
end
function Worker:_sign(row)
 local block,committed=self.o.block_at(self.fence.dim,row.at)
 local belongs=type(block)=='table'and type(block.id)=='string'and block.id:match('_sign$')
  and block.visible~=false and block.mirror~=false
 return block,committed,belongs
end
function Worker:_visible(v,visible)
 if v.visible~=visible then self.o.renderer:set_visible(v.handle,visible);v.visible=visible end
end
function Worker:prune(context_alive)
 self:_thread();local keys={}
 for key,v in pairs(self.views)do
  if not self.fence then keys[#keys+1]=key
  else
   local block,committed,belongs=self:_sign(v.row)
   if not belongs then keys[#keys+1]=key
   elseif committed~=true or block.id~=v.row.id or block.state~=v.row.state_key then self:_visible(v,false)end
  end
 end
 for _,key in ipairs(keys)do self:_remove(key,context_alive)end
end
function Worker:apply(snapshot,ctx,origin)
 self:_thread();if not self.fence then return false,'view_unbound'end
 local now=self:_clock()
 local ok,why=pcall(function()
  assert(type(snapshot)=='table'and snapshot.schema==1 and snapshot.t=='sign_text','Text snapshot schema invalid')
  assert(G.fence(snapshot)==self.fence_key,'Text view/identity fence mismatch')
  assert(type(snapshot.created_ms)=='number'and now-snapshot.created_ms<=5000 and now-snapshot.created_ms>=-5000,'Text snapshot stale')
  assert(snapshot.complete==true and type(snapshot.rows)=='table'and #snapshot.rows<=1024,'Incomplete text replacement')
  assert(type(snapshot.producer)=='string'and #snapshot.producer>0 and math.tointeger(snapshot.epoch)and snapshot.epoch>=0
   and math.tointeger(snapshot.seq)and snapshot.seq>=0,'Text producer sequence invalid')
  local seen={}
  for _,row in ipairs(snapshot.rows)do G.validate_row(row);local key=G.key(snapshot.dim,row.at);assert(not seen[key],'Duplicate text block');seen[key]=true end
 end)
 if not ok then self.stats.rejected=self.stats.rejected+1;self.error=tostring(why);return false,self.error end
 if self.retired_producers and self.retired_producers[snapshot.producer]then return false,'retired_producer'end
 if self.producer==snapshot.producer and snapshot.epoch<self.producer_epoch then return false,'stale_producer_epoch'end
 if self.producer==snapshot.producer and self.producer_epoch==snapshot.epoch and snapshot.seq<=self.last_seq then return false,'stale_sequence'end
 if self.producer and(self.producer~=snapshot.producer or self.producer_epoch~=snapshot.epoch)then
  if self.producer~=snapshot.producer then
   self.retired_producers=self.retired_producers or{};self.retired_order=self.retired_order or{}
   self.retired_producers[self.producer]=true;self.retired_order[#self.retired_order+1]=self.producer
   if #self.retired_order>32 then self.retired_producers[table.remove(self.retired_order,1)]=nil end
  end
  local expected=self.fence;self:reset('producer_replaced',true);self.fence=expected;self.fence_key=G.fence(expected)
 end
 self.producer=snapshot.producer;self.producer_epoch=snapshot.epoch
 local targets,present={},{}
 if snapshot.available==true then for _,row in ipairs(snapshot.rows)do
  local key=G.key(snapshot.dim,row.at);present[key]=row;if self:_block(row)then targets[key]=row end
 end end
 local rendered,failure=pcall(function()
 local retired={};for key in pairs(self.views)do if not present[key]then retired[#retired+1]=key end end
 for _,key in ipairs(retired)do self:_remove(key,true)end
 for key,row in pairs(targets)do
  local old=self.views[key]
  if not old then
   local handle=self.o.renderer:create(ctx,origin,row,self.fence);self.views[key]={handle=handle,row=row,visible=true};self.stats.created=self.stats.created+1
  elseif not same(old.row,row)then
   self.o.renderer:update(old.handle,row);old.row=row;self.stats.updated=self.stats.updated+1
  end
  self:_visible(self.views[key],true)
 end
 for key in pairs(present)do if not targets[key]and self.views[key]then self:_visible(self.views[key],false)end end
 end)
 if not rendered then self.error=tostring(failure);self.stats.rejected=self.stats.rejected+1;return false,self.error end
 self.last_seq=snapshot.seq;self.last_seen=now;self.error=nil;self.reason=nil;return true
end
function Worker:poll(ctx,origin,context_alive)
 self:_thread();if not self.running then return false,'stopped'end;self:prune(context_alive)
 if self.last_seen>0 and self:_clock()-self.last_seen>5000 then
  local fence=self.fence;self:reset('producer_timeout',context_alive);self.fence=fence;self.fence_key=fence and G.fence(fence)
 end
 local read=self.o.read or function()
  local f=io.open(assert(self.o.root):gsub('[\\/]+$','')..'/snapshot.json','rb');if not f then return nil end
  local raw=f:read(4194305);f:close();assert(#raw<=4194304,'Text snapshot byte limit');return self.o.json.decode(raw)
 end
 local ok,value=pcall(read)
 if not ok then self.error=tostring(value);return false,self.error end
 if value then return self:apply(value,ctx,origin)end
 return false,'awaiting_text_snapshot'
end
-- Either a normal per-block scene provider or a travel region provider may
-- return this same shape. No travel feature/ticket is required by the worker.
function Worker:tick(ctx,context_alive)
 self:_thread();local provider=assert(self.o.view_provider,'Current native scene provider required')
 local view=provider(ctx)
 if not view then self:reset('native_view_unavailable',context_alive);return false,'native_view_unavailable'end
 local key=G.fence(view.fence);local changed=key~=self.fence_key
 local bounds=view.bounds;assert(type(bounds)=='table'and #bounds==6,'Current native scope required')
 if not changed then for i=1,6 do if not self.bound_bounds or self.bound_bounds[i]~=bounds[i]then changed=true;break end end end
 if changed then
  self:bind(view.fence,context_alive)
  self.bound_bounds={table.unpack(bounds)}
  if self.o.send_binding then self.o.send_binding(M.binding_request(view.fence,bounds))end
 end
 return self:poll(ctx,assert(view.origin,'Current native mapping origin required'),context_alive)
end
function Worker:unload_chunk(dim,cx,cz,context_alive)
 self:_thread();local keys={}
 for key,v in pairs(self.views)do if self.fence and self.fence.dim==dim and v.row.at[1]//16==cx and v.row.at[3]//16==cz then keys[#keys+1]=key end end
 for _,key in ipairs(keys)do self:_remove(key,context_alive)end
end
function Worker:stop(context_alive)self:reset('stopped',context_alive);self.running=false end
function Worker:status()
 local count=0;for _ in pairs(self.views)do count=count+1 end
 return{version=1,running=self.running,signs=count,fence=self.fence,producer=self.producer,epoch=self.producer_epoch,
  seq=self.last_seq,last_seen_ms=self.last_seen,stats=self.stats,error=self.error,reason=self.reason,runtime_verified=false}
end
return M
