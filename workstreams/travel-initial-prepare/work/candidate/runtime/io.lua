-- Small file adapters for the existing JSON mailboxes; not a transport or transaction WAL.
local M={}
function M.root(path)return assert(path,'Runtime directory required'):gsub('\\','/'):gsub('/?$','/')end
function M.new(json,options)
 options=options or{};local F={}
 function F.read(path)
  if options.read then return options.read(path)end
  local f=io.open(path,'rb');if not f then return nil end
  local n=f:seek('end');assert(n<=(options.max_bytes or 1048576),'Runtime mailbox too large: '..path)
  f:seek('set');local raw=f:read('*a');f:close();return json.decode(raw)
 end
 function F.write(path,value)
  if options.write then return options.write(path,value)end
  local f=assert(io.open(path..'.tmp','wb'));assert(f:write(json.encode(value)));assert(f:close())
  os.remove(path);assert(os.rename(path..'.tmp',path));return true
 end
 return F
end
return M
