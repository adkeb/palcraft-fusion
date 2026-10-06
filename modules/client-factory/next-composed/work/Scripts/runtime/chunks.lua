-- One real consumer composition; the companion keeps its sole reducer/journal/timer.
local M={version=2}
function M.new(o)
 assert(o and o.client_dir and o.companion and o.initial_view,'Real companion and confirmed initial view required')
 local dir=o.client_dir:gsub('\\','/'):gsub('/?$','/')
 return dofile(dir..'companion_chunk_bridge.lua').compose(o)
end
return M
