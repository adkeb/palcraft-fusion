-- Concrete cache/provider/native renderer composition for the existing observer.
-- Runtime owns the authenticated WS dispatch and exact Actor/world view sources.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Cache=dofile(dir..'entity_capture_cache.lua')
local Captured=dofile(dir..'captured_entity_visuals.lua')
local M={}
function M.new(o)
 local cache=Cache.new({root=assert(o.png_root),json=assert(o.json),current_view=assert(o.current_view),verify_host_session=assert(o.verify_host_session),
  verify_actor=o.verify_actor,now_ms=o.now_ms,send_binding=assert(o.send_binding)})
 Captured.configure({json=o.json,root=o.png_root,texture_index={},resolve_texture=cache.resolve_texture})
 local renderer=assert(o.native_consumer).new({models=assert(o.models),capture=Captured,read_visual=cache.read_visual,
  verify_visual=cache.verify_visual,material_supported=assert(o.material_supported),origin=assert(o.origin),context=assert(o.context)})
 local api={renderer=renderer,cache=cache}
 function api.receive(message)
  if message.t~='entity_visual_asset'and message.t~='entity_visual_cache'and message.t~='entity_visual_cache_chunk'then return false,'not_capture_event'end
  return cache.accept(message)
 end
 function api.tick()
  local ok,why=cache.tick_binding();api.reason=ok and nil or why
  if not ok then renderer.suspend()end
  return ok,why
 end
 function api.on_lifecycle(event)
  local op=event.op
  if op=='session_reset'or op=='world_unload'or op=='resync_required'or op=='player_view'or op=='chunk_unload'then
   cache.reset();renderer.suspend();api.reason='capture_lifecycle:'..op
  end
 end
 function api.stop(context_alive)
  if renderer.stop then renderer.stop(context_alive~=false)end;cache.stop(context_alive~=false);api.reason='stopped'
 end
 function api.status()
  local r=renderer.status();r.phase=api.reason or(cache.bound and'capture_bound'or'capture_view_pending')
  r.bound=cache.bound;r.cache_error=cache.error;r.binding_error=cache.last_binding_error;r.actual_shader_verified=false
  return r
 end
 return api
end
return M
