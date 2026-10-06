-- Bounded adapters for the existing trusted NDJSON journals and native command.json slot.
-- No sockets, timers, new envelope, or untrusted destination selection.
local M={}
function M.tail(o)
 local json,path=assert(o.json),assert(o.path);local offset,pending=0,'';local api={}
 function api.poll(consume,max_rows)
  local file=io.open(path,'rb');if not file then return 0 end
  local size=file:seek('end')
  if size<offset then file:close();error('Committed journal truncated; restart its authority consumer')end
  file:seek('set',offset);local raw=file:read(o.read_bytes or 65536)or'';offset=file:seek();file:close()
  pending=pending..raw;assert(#pending<=(o.max_pending_bytes or 1048576),'Journal record exceeds bounded input')
  local count=0
  while count<(max_rows or 64)do
   local stop=pending:find('\n',1,true);if not stop then break end
   local line=pending:sub(1,stop-1);pending=pending:sub(stop+1)
   if #line>0 then consume(json.decode(line));count=count+1 end
  end
  return count
 end
 function api.status()return{path=path,offset=offset,partial_bytes=#pending}end
 return api
end
function M.append(o)
 local api={};local json,path=assert(o.json),assert(o.path)
 function api.send(row)
  local raw=json.encode(row)..'\n';assert(#raw<=(o.max_bytes or 65536),'Outbox record exceeds limit')
  local file=assert(io.open(path,'ab'));assert(file:write(raw));assert(file:flush());assert(file:close())
  if o.flush_file then assert(o.flush_file(path)==true,'Outbox OS flush failed')end
  return true -- queued in the existing outbox; peer readiness still requires its real response
 end
 return api
end
function M.commands(o)
 local json,path=assert(o.json),assert(o.path);local queue={};local api={}
 function api.send(row)
  assert(#queue<(o.capacity or 64),'Native command queue full')
  queue[#queue+1]=json.encode(row);return true
 end
 function api.tick()
  if #queue==0 then return end
  local existing=io.open(path,'rb');if existing then existing:close();return end
  local file=assert(io.open(path..'.pending','wb'));assert(file:write(queue[1]));assert(file:close())
  assert(os.rename(path..'.pending',path));table.remove(queue,1)
 end
 function api.reset()queue={}end
 function api.status()return{queued=#queue,path=path}end
 return api
end
return M
