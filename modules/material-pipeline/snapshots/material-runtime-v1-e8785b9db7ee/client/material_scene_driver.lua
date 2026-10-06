-- Runs on the companion's existing tick. Missing colors retain their scene key;
-- a current authenticated reply invalidates only that scene's renderer work.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Runtime=dofile(dir..'material_runtime_binding.lua')
local M={version=1}
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
local function same(a,b)return a and b and a.mc_uuid==b.mc_uuid and a.world_session==b.world_session and a.dim==b.dim and a.view==b.view end
local function key(block,water)return('%s:%d:%d:%d:%s:%s:%s'):format(block.dim,block.x,block.y,block.z,block.id,tostring(block.state or''),water and'water'or'block')end
function M.new(options)
 assert(type(options.retry_scene)=='function','Existing scene retry callback required')
 local runtime=Runtime.new(options)
 local scenes,requests={},{};local serial=0;local now=0
 local stats={queries=0,replies=0,resumed=0,rejected=0,expired=0}
 local api={runtime=runtime,scope=nil}
 function api:bind_material_scope(scope)
  if same(self.scope,scope)then return false end
  local previous=self.scope;local retry={}
  runtime:bind(scope);self.scope=copy(scope)
  -- Queued geometry may predate initial binding, but belongs only to this MC
  -- world/dimension. Sent work from an older view must never resume new actors.
  for id in pairs(requests)do runtime:cancel(id)end;requests={}
  for k,s in pairs(scenes)do
   if s.scope and not same(s.scope,scope)or s.block.dim~=scope.dim then
    if previous and previous.world_session==scope.world_session and s.block.dim==scope.dim then retry[s.scene_key]=s.block end
    scenes[k]=nil
   else s.scope=copy(scope);s.request_id=nil;s.attempts=0 end
  end
  for scene_key,block in pairs(retry)do options.retry_scene(scene_key,block)end
  return true
 end
 function api:prepare(scene_key,block,groups)
  assert(type(scene_key)=='string'and type(block)=='table'and type(groups)=='table','Actual material scene required')
  assert(block.dim and block.id and math.tointeger(block.x)and math.tointeger(block.y)and math.tointeger(block.z),'Authoritative material block required')
  for k,s in pairs(scenes)do
   local b=s.block
   if b.dim==block.dim and b.x==block.x and b.y==block.y and b.z==block.z and(b.id~=block.id or b.state~=block.state)then scenes[k]=nil end
  end
  local out,needed={},{}
  for i,g in ipairs(groups)do
   local colored,why=runtime:color_group(g,block)
   if colored then out[i]=copy(colored);out[i].authoritative_block=block
   else
    assert(why=='actual_block_tint_pending',why)
    out[i]=copy(g);out[i].authoritative_block=block;out[i].material_pending=true
    local water=g.tint_role=='water';local k=key(block,water)
    local s=needed[k]or{block=copy(block),water=water,indices={},scene_key=scene_key,groups=groups}
    s.indices[g.tint]=true;needed[k]=s
   end
  end
  for k,n in pairs(needed)do
   local old=scenes[k]
   if not old or old.scene_key~=scene_key then serial=serial+1;n.token=serial;n.attempts=0;n.scope=self.scope and copy(self.scope);scenes[k]=n
   else old.groups=groups;for index in pairs(n.indices)do old.indices[index]=true end end
  end
  return out,next(needed)and'actual_block_tint_pending'or nil
 end
 function api:flush(seconds)
  now=seconds or now
  if not self.scope then return false,'material_scope_pending'end
  for id,r in pairs(requests)do if now-r.sent_at>=(options.reply_timeout_seconds or 2)then
   runtime:cancel(id);requests[id]=nil;stats.expired=stats.expired+1
   for _,s in ipairs(r.scenes)do if scenes[s.key]==s.entry then s.entry.request_id=nil end end
  end end
  local keys={};for k,s in pairs(scenes)do
   if not s.request_id and same(s.scope,self.scope)and s.attempts<(options.max_query_attempts or 3)then keys[#keys+1]=k end
  end;table.sort(keys)
  if #keys==0 then return true end
  local rows,selected={},{}
  for i=1,math.min(32,#keys)do
   local k=keys[i];local s=scenes[k];local b=s.block;local indices={}
   for index in pairs(s.indices)do indices[#indices+1]=index end;table.sort(indices)
   assert(#indices<=16,'Small tint index limit required')
   rows[#rows+1]={id=b.id,x=b.x,y=b.y,z=b.z,key=b.state or'',properties=b.properties,indices=indices,tint_role=s.water and'water'or nil}
   selected[#selected+1]={key=k,entry=s,token=s.token}
  end
  local id,why=runtime:request(rows);if not id then return false,why end
  for _,s in ipairs(selected)do s.entry.request_id=id;s.entry.attempts=s.entry.attempts+1 end
  requests[id]={scenes=selected,sent_at=now};stats.queries=stats.queries+1;return true
 end
 function api:accept_material_tint(reply)
  local r=type(reply)=='table'and requests[reply.request_id]
  if not r then stats.rejected=stats.rejected+1;return false,'unsolicited_tint_reply'end
  local ok,why=runtime:accept(reply);if not ok then stats.rejected=stats.rejected+1;return false,why end
  requests[reply.request_id]=nil;stats.replies=stats.replies+1
  local resume={}
  for _,s in ipairs(r.scenes)do
   local e=scenes[s.key]
   if e==s.entry and e.token==s.token and same(e.scope,self.scope)then
    scenes[s.key]=nil;resume[e.scene_key]=e.block
   end
  end
  for scene_key,block in pairs(resume)do
   assert(options.retry_scene(scene_key,block)~=false,'Existing material scene retry failed');stats.resumed=stats.resumed+1
  end
  return true
 end
 function api:resolve(ctx,group,asset_root)
  return runtime:resolve(ctx,group,asset_root,group.authoritative_block or group.material_block)
 end
 function api:tick(seconds)
  local ok,why=self:flush(seconds);local played,reason=runtime:tick(seconds)
  return ok and played,why or reason
 end
 function api:cancel_block(block)
  for k,s in pairs(scenes)do if s.block.dim==block.dim and s.block.x==block.x and s.block.y==block.y and s.block.z==block.z then scenes[k]=nil end end
 end
 function api:reset()runtime:reset();scenes={};requests={};self.scope=nil end
 function api:status()
  local pending=0;for _ in pairs(scenes)do pending=pending+1 end
  return{version=1,scope=self.scope,pending_material_scenes=pending,stats=copy(stats),runtime=runtime:status(),engine_verified=false}
 end
 return api
end
return M
