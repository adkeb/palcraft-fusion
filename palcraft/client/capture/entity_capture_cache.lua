-- Actual authenticated capture consumer/cache for native's exact-Actor reader.
-- No socket, timer, world/HP mutation or second session implementation.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Blob=dofile(dir..'capture_blob.lua')
local M={}
local keys={'mc_uuid','world_session','dim','view','mapping'}
local function same(a,b)if not a or not b then return false end;for _,k in ipairs(keys)do if a[k]~=b[k]then return false end end;return true end
function M.binding_request(fence,bounds)
 return{t='entity_visual_view',op='bind',mc_uuid=fence.mc_uuid,world_session=fence.world_session,dim=fence.dim,
  view=fence.view,mapping=fence.mapping,bounds={table.unpack(bounds)}}
end
function M.new(o)
 assert(o.root and type(o.current_view)=='function'and type(o.verify_host_session)=='function','Existing authenticated view and host verifier required')
 local C={rows={},assets={},chunks={},manifests={},errors={},seq=-1,producer=nil,epoch=-1}
 local function now()return(o.now_ms or function()return os.time()*1000 end)()end
 local function accepts(p)
  local view=o.current_view();local fence=view and(view.fence or view)
  if not same(fence,p)then return nil,'capture_view_mismatch'end
  if o.verify_host_session(p.host_session,p)~=true then return nil,'capture_host_session_mismatch'end
  if p.source~='minecraft:entity_renderer_capture_v1'or p.read_only~=true then return nil,'capture_source_mismatch'end
  if type(p.created_ms)~='number'or math.abs(now()-p.created_ms)>5000 then return nil,'capture_stale'end
  return fence
 end
 function C.accept(p)
  local fence,why=accepts(p);if not fence then return nil,why end
  if p.t=='entity_visual_cache_chunk'then
   assert(o.json,'JSON decoder required for capture chunk assembly')
   assert(p.bytes>0 and p.bytes<=8*1024*1024 and p.index>=0 and p.index<p.chunks and p.chunks<=171,'Capture chunk bounds')
   local state=C.manifests[p.sha256]
   if not state then state={bytes=p.bytes,count=p.chunks,producer=p.producer,epoch=p.epoch,parts={}};C.manifests={};C.manifests[p.sha256]=state end
   if state.producer~=p.producer or state.epoch~=p.epoch or state.bytes~=p.bytes or state.count~=p.chunks then return nil,'capture_chunk_sequence_mismatch'end
   state.parts[p.index+1]=Blob.base64(p.base64)
   for i=1,state.count do if not state.parts[i]then return true,'capture_partial'end end
   local raw=table.concat(state.parts);C.manifests={}
   if #raw~=state.bytes or Blob.sha256(raw)~=p.sha256 then return nil,'capture_payload_hash_invalid'end
   local message=o.json.decode(raw)
   if message.t~='entity_visual_cache'or not same(message,p)or message.producer~=p.producer or message.epoch~=p.epoch then return nil,'capture_chunk_payload_scope_mismatch'end
   -- HostLink authenticates each outer packet; the serialized inner payload
   -- precedes respond() adding the existing connection's host_session.
   message.host_session=p.host_session
   return C.accept(message)
  elseif p.t=='entity_visual_asset'then
   assert(type(p.sha256)=='string'and #p.sha256==64 and not p.sha256:find('[^0-9a-f]'),'Asset hash')
   assert(p.bytes>0 and p.bytes<=8*1024*1024 and p.index>=0 and p.index<p.chunks and p.chunks<=171,'Asset bounds')
   local state=C.chunks[p.sha256]
   if not state then state={bytes=p.bytes,count=p.chunks,parts={},producer=p.producer,epoch=p.epoch};C.chunks[p.sha256]=state end
   if state.producer~=p.producer or state.epoch~=p.epoch or state.bytes~=p.bytes or state.count~=p.chunks then return nil,'asset_sequence_mismatch'end
   state.parts[p.index+1]=Blob.base64(p.base64)
   for i=1,state.count do if not state.parts[i]then return true,'asset_partial'end end
   local png=table.concat(state.parts);C.chunks[p.sha256]=nil
   if #png~=state.bytes or Blob.sha256(png)~=p.sha256 or png:sub(1,8)~='\137PNG\13\10\26\10'then return nil,'asset_pixel_hash_invalid'end
   local root=o.root:gsub('[\\/]+$','');local path=root..'/'..p.sha256..'.png';local temporary=path..'.pending'
   local existing=io.open(path,'rb')
   if existing then local old=existing:read('*a');existing:close();assert(Blob.sha256(old)==p.sha256,'Existing cached PNG changed')
   else local f=assert(io.open(temporary,'wb'));f:write(png);f:close();assert(os.rename(temporary,path))end
   C.assets[p.sha256]=path;return true,'asset_committed'
  elseif p.t=='entity_visual_cache'then
   if p.complete~=true then return nil,'capture_manifest_incomplete'end
   if C.producer==p.producer and(p.epoch<C.epoch or p.epoch==C.epoch and p.seq<=C.seq)then return nil,'capture_old_sequence'end
   if C.producer~=p.producer or C.epoch~=p.epoch then C.rows={};C.errors={}end
   C.producer,C.epoch,C.seq=p.producer,p.epoch,p.seq;local rows={}
   for _,r in ipairs(p.available~=false and(p.rows or{})or{})do
    if r.available==true and r.frame and r.dimension==fence.dim then
     local complete=true;local sources={}
     for resource,pixels in pairs(r.textures or{})do local path=C.assets[pixels.sha256];if not path then complete=false;break end;sources[resource]=path end
     if complete then rows[r.id]={frame=r.frame,scope=p,created_ms=r.captured_ms,textures=sources};C.errors[r.id]=nil
     else C.errors[r.id]='capture_png_transfer_pending'end
    else C.errors[r.id]=r.error or r.resource_errors or'capture_renderer_pending'end
   end
   C.rows=rows;C.error=p.error;return true,p.available==false and'capture_unavailable'or'capture_cache_committed'
  end
  return nil,'other_capture_event'
 end
 function C.read_visual(row)
  local entry=C.rows[row.id]
  if not entry then return nil,C.errors[row.id]or'capture_pending'end
  return entry.frame,entry.scope
 end
 function C.verify_visual(frame,scope,row,actor)
  local fence,why=accepts(scope);if not fence then return nil,why end
  local entry=C.rows[row.id]
  if not entry or entry.frame~=frame or frame.id~=row.id or frame.dimension~=row.dimension or row.dimension~=fence.dim then return nil,'capture_entity_binding_mismatch'end
  if now()-(entry.created_ms or 0)>5000 then return nil,'capture_pose_stale'end
  if o.verify_actor and o.verify_actor(row,actor)~=true then return nil,'capture_actor_binding_mismatch'end
  return true
 end
 function C.resolve_texture(resource)
  for _,entry in pairs(C.rows)do if entry.textures[resource]then return entry.textures[resource]end end
  return nil,'capture_texture_unavailable'
 end
 function C.reset()
  C.rows={};C.errors={};C.chunks={};C.manifests={};C.bound=nil;C.bounds=nil;C.error=nil
 end
 function C.stop(context_alive)
  local view=context_alive~=false and o.current_view();local fence=view and(view.fence or view)
  if same(C.bound,fence)and C.bounds then
   local request=M.binding_request(fence,C.bounds);request.op='unbind';o.send_binding(request)
  end
  C.reset();C.assets={}
 end
 function C.tick_binding()
  local view=o.current_view();if not view then C.reset();return nil,'capture_view_unavailable'end
  local fence=view.fence or view;local changed=not same(C.bound,fence)
  if not changed and view.bounds then for i=1,6 do if not C.bounds or C.bounds[i]~=view.bounds[i]then changed=true;break end end end
  if changed then
   C.rows={};C.errors={};C.chunks={};C.manifests={};C.bound=nil;C.bounds=nil
   if not view.bounds or #view.bounds~=6 then return nil,'capture_bounds_unavailable'end
   local bounds={table.unpack(view.bounds)}
   local ok,why=o.send_binding(M.binding_request(fence,bounds))
   if ok~=true then C.last_binding_error=why or'capture_bind_not_queued';return nil,C.last_binding_error end
   C.bound={};for _,k in ipairs(keys)do C.bound[k]=fence[k]end;C.bounds=bounds;C.last_binding_error=nil
  end
  return true
 end
 return C
end
return M
