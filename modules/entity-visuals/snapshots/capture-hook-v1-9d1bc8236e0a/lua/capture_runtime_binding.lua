-- Concrete cache/provider/native renderer composition for the existing observer.
-- Runtime owns the authenticated WS dispatch and exact Actor/world view sources.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Cache=dofile(dir..'entity_capture_cache.lua')
local Captured=dofile(dir..'captured_entity_visuals.lua')
local M={}
function M.new(o)
 local cache=Cache.new({root=assert(o.png_root),current_view=assert(o.current_view),verify_host_session=assert(o.verify_host_session),
  verify_actor=o.verify_actor,now_ms=o.now_ms,send_binding=assert(o.send_binding)})
 Captured.configure({json=o.json,root=o.png_root,texture_index={},resolve_texture=cache.resolve_texture})
 local renderer=assert(o.native_consumer).new({models=assert(o.models),capture=Captured,read_visual=cache.read_visual,
  verify_visual=cache.verify_visual,material_supported=assert(o.material_supported),origin=assert(o.origin),context=assert(o.context)})
 local api={renderer=renderer,cache=cache}
 function api.receive(message)
  if message.t~='entity_visual_asset'and message.t~='entity_visual_cache'then return false,'not_capture_event'end
  return cache.accept(message)
 end
 function api.tick()return cache.tick_binding()end
 function api.stop()if renderer.stop then renderer.stop()end;cache.rows={};cache.chunks={}end
 return api
end
return M
