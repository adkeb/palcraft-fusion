-- Delayed candidate renderer binding. A missing pipeline returns nil; the
-- observer keeps its explicit pending state and the real Pal visual remains.
local M={}
function M.new(getter)
 return{
  spawn=function(row,actor)
   local renderer=getter();if not renderer then return nil end
   local handle,why=renderer.spawn(row,actor);if not handle then return nil,why end
   return{renderer=renderer,handle=handle}
  end,
  update=function(binding,row,actor)
   local renderer=getter()
   if renderer~=binding.renderer then
    if binding.renderer and binding.handle then binding.renderer.remove(binding.handle)end
    binding.renderer=renderer;binding.handle=nil
   end
   if not renderer then return false,'capture_consumer_not_attached'end
   if not binding.handle then binding.handle=renderer.spawn(row,actor)end
   if not binding.handle then return false,'authenticated_capture_pending'end
   return renderer.update(binding.handle,row,actor)
  end,
  remove=function(binding,context_alive)
   if binding.renderer and binding.handle then return binding.renderer.remove(binding.handle,context_alive)end
  end,
 }
end
return M
