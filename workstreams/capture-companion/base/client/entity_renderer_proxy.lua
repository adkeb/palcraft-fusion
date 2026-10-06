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
  update=function(binding,row,actor)return binding.renderer.update(binding.handle,row,actor)end,
  remove=function(binding)return binding.renderer.remove(binding.handle)end,
 }
end
return M
