-- Stable dispatcher. Newly initiated exchanges use v3; existing v2 records remain recoverable.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local test=rawget(_G,'PALCRAFT_EXCHANGE_TEST');local legacy,worker
local M={protocol=3}
function M.new(options)
 local o=options or(test and test.v3)or{};local engine=dofile(dir..'exchange_v3.lua').new(o)
 local J=o.json or(test and(test.json or dofile(test.json_path)))or dofile(dir..'json.lua')
 local root=(o.root or(test and test.root)or assert(os.getenv('PALCRAFT_EXCHANGE_ROOT'))):gsub('\\','/'):gsub('/+$','')..'/'
 local api={protocol=3,engine=engine}
 function api.handle(q)
  if q.protocol==2 then legacy=legacy or dofile(dir..'exchange_v2.lua');return legacy.handle(q)end
  return engine.handle(q)
 end
 function api.tick()
  local f=io.open(root..'request.json','rb');if not f then return end;local raw=f:read('*a');f:close();local q=J.decode(raw)
  if q.protocol==2 then legacy=legacy or dofile(dir..'exchange_v2.lua');return legacy.tick()end
  return engine.tick()
 end
 function api.stop()return engine.stop()end
 return api
end
function M.handle(q)
 if q.protocol==2 then legacy=legacy or dofile(dir..'exchange_v2.lua');return legacy.handle(q)end
 worker=worker or M.new();return worker.handle(q)
end
function M.tick()
 if worker then return worker.tick()end
 local J=test and(test.json or dofile(test.json_path))or dofile(dir..'json.lua')
 local root=test and test.root or ((os.getenv('PALCRAFT_EXCHANGE_ROOT')or'D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange'):gsub('\\','/'):gsub('/+$','')..'/')
 local f=io.open(root..'request.json','rb');if not f then return end;local raw=f:read('*a');f:close();local q=J.decode(raw)
 if q.protocol==2 then legacy=legacy or dofile(dir..'exchange_v2.lua');return legacy.tick()end
 worker=worker or M.new();return worker.tick()
end
function M.stop()if worker then worker.stop();worker=nil end end
return M
