-- Durable delegate for the existing immutable Pal WAL. One game-thread authority.
local M={protocol=3}
local function canon(v)
 if type(v)~='table'then return type(v)..':'..tostring(v)end
 local keys,out={},{};for k in pairs(v)do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 for _,k in ipairs(keys)do out[#out+1]=canon(k)..'='..canon(v[k])end;return '{'..table.concat(out,';')..'}'
end
local function copy(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=copy(x)end;return t end
function M.new(o)
 local root,J=assert(o.root),assert(o.json);assert(type(o.commit)=='function','Actual durable WAL delegate required')
 local function read(name)local f=io.open(root..name,'rb');if not f then return nil end;local b=f:read('*a');f:close();return assert(J.decode(b))end
 local function write(name,row)
  local f=assert(io.open(root..name..'.tmp','wb'));assert(f:write(J.encode(row)));assert(f:flush());assert(f:close());if name=='escrow-leases-current.pending.json'then os.remove(root..name)end;assert(os.rename(root..name..'.tmp',root..name))
 end
 local function committed(name,row)local receipt=read(name:gsub('%.json$','.durable.json'));return receipt and canon(row)==canon(receipt)end
 local function latest(prefix,all)
  local row,chain=nil,{};local n=1
  while true do
   local name=prefix..string.format('.r%06d.json',n);local nextrow=read(name);if not nextrow then break end
   assert(nextrow.revision==n,'Corrupt exchange WAL revision')
   if not committed(name,nextrow)then break end
   row=nextrow;chain[#chain+1]=row;n=n+1
  end
  return all and chain or row
 end
 local function stage(name,row)
  local draft=read(name)
  if draft then
   local a,b=copy(draft),copy(row);a.updated_unix=nil;b.updated_unix=nil
   if canon(a)==canon(b)then row.updated_unix=draft.updated_unix;return row end
   assert(not committed(name,draft),'Committed immutable revision cannot change')
   -- No durable receipt means CAS could never have returned permission for a
   -- native call. Keep the tentative image as forced audit, then safely rebase
   -- this uncommitted slot after a real process change or lawful source move.
   if draft.tx then assert(canon(draft.tx)==canon(row.tx)and draft.owner_tx==row.owner_tx and draft.generation==row.generation and canon(draft.candidate)==canon(row.candidate),'Tentative lease identity changed')end
   local index=1;local archive
   repeat archive=name:gsub('%.json$',string.format('.unconfirmed%06d.json',index));index=index+1 until not read(archive)
   assert(os.rename(root..name,root..archive));o.commit(archive);assert(committed(archive,draft),'Tentative audit durability pending')
  end
  write(name,row);return row
 end
 local api={}
 function api.latest(prefix)return latest(prefix)end
 function api.append(prefix,row)
  local old=latest(prefix);row.revision=(old and old.revision or 0)+1;row.updated_unix=os.time()
  local name=prefix..string.format('.r%06d.json',row.revision);stage(name,row)
  o.commit(name);assert(committed(name,row),'WAL durable commit pending');if o.fault then o.fault('wal:'..tostring(row.status or row.event),row)end
 end
 function api.get(cid)return latest('escrow-'..cid)end
 function api.get_tx(id)
  for _,cid in ipairs(o.containers)do for _,row in ipairs(latest('escrow-'..cid,true))do if row.owner_tx==id then api._tx=row end end end
  local row=api._tx;api._tx=nil;return row
 end
 function api.cas(cid,expected,row)
  local old=api.get(cid);if (old and old.revision or 0)~=expected then return false end
  assert(row.container_id==cid and row.revision==expected+1,'Lease CAS identity/revision mismatch')
  local name='escrow-'..cid..string.format('.r%06d.json',row.revision);row=stage(name,row)
  local current=read('escrow-leases-current.json')or{protocol=3,revision=0,leases={}}
  current.revision=current.revision+1;current.leases[cid]=row;write('escrow-leases-current.pending.json',current)
  o.commit(name,'escrow-leases-current.pending.json','escrow-leases-current.json')
  assert(committed(name,row),'Lease durable commit pending')
  local installed=assert(read('escrow-leases-current.json'),'Lease CURRENT unavailable');assert(canon(installed.leases[cid])==canon(row),'Lease CURRENT is not durably installed')
  if o.fault then o.fault('lease:'..row.status,row)end;return true
 end
 return api
end
function M.native_commit(root,dll)
 local fn,why=package.loadlib(assert(dll),'palcraft_exchange_commit_v3');assert(fn,why)
 local env=assert(os.getenv('PALCRAFT_EXCHANGE_ROOT'),'Installer must bind PALCRAFT_EXCHANGE_ROOT at startup')
 local function normal(p)return p:gsub('\\','/'):gsub('/+$',''):lower()end
 assert(normal(env)==normal(root),'WAL delegate root differs from trusted startup root')
 return function(revision,pending,current)
  local wire=string.pack('<c8I4c128c128c128','PLWAL003',3,revision,pending or'',current or'');assert(#wire==396)
  local f=assert(io.open(root..'durable-request.bin','wb'));assert(f:write(wire));assert(f:flush());assert(f:close());fn()
 end
end
return M
