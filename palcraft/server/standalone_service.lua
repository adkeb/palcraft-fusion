-- Existing in-process game-thread lifecycle port: real process identity and
-- normal Save/Autosave API requests. Never fabricates a Level witness.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={}
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function root(p)return assert(p):gsub('\\','/'):gsub('/+$','')..'/'end
function M.new(o)
 local s,J,R=assert(o.scope),assert(o.json),assert(o.readers)
 assert(s.mode=='standalone','Explicit configured singleplayer scope required')
 local ROOT,RPC=root(s.exchange_root),root(s.rpc_root)
 assert(ROOT:lower()==root(os.getenv('PALCRAFT_EXCHANGE_ROOT')):lower(),'Trusted WAL root differs')
 assert(RPC:lower()==root(os.getenv('PALCRAFT_RPC_ROOT')):lower(),'Trusted RPC root differs')
 local Store=dofile(dir..'exchange_store.lua')
 local store=Store.new{root=ROOT,json=J,containers={},commit=Store.native_commit(ROOT,assert(o.durable_dll))}
 local Authority=dofile(dir..'standalone_authority.lua')
 local identity,why=package.loadlib(assert(o.credit_dll),'palcraft_escrow_client_identity_v1');assert(identity,why)
 local function read(p)local f=io.open(p,'rb');if not f then return end;local v=J.decode(f:read('*a'));f:close();return v end
 local function write(p,v)local f=assert(io.open(p..'.tmp','wb'));assert(f:write(J.encode(v)));assert(f:flush());assert(f:close());os.remove(p);assert(os.rename(p..'.tmp',p))end
 local function context()
  local found
  for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do
   if live(pc)and pc:HasAuthority()and R.guid_to_string(pc:GetPlayerUId())==s.pal_uid then assert(not found,'Ambiguous local host');found=pc end
  end
  return assert(found,'Actual local host is unavailable'),Authority.read(found,s.world_directory)
 end
 local api={ready=false}
 function api.tick()
  assert(IsInGameThread(),'Existing game thread required')
  local pc,a=context();identity()
  local p=assert(read(RPC..'escrow-client-process.json'),'Actual client native identity unavailable')
  assert(p.kind=='palworld_client_process_identity'and p.native_code_matched==true and p.read_only==true and p.executable_sha256=='e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837','Unmatched client identity')
  assert(p.pid>0 and os.time()-p.observed_unix>=-1 and os.time()-p.observed_unix<=2,'Stale client identity')
  local ticks=assert(tonumber(p.process_created_filetime));assert(math.type(ticks)=='integer','Exact native FILETIME required')
  -- Deterministic actual-process binding: reloads retain the same identity.
  -- This is not a UID allocation or full-world rehydration certificate.
  local boot=R.guid_to_string({A=p.pid,B=(ticks>>32)&0xffffffff,C=ticks&0xffffffff,D=assert(tonumber(s.world_directory:sub(-8),16))})
  local prefix='pal-client-process-'..boot
  local b=store.latest(prefix)
  if not b then
   b={protocol=3,kind='palworld_client_process_binding',boot_id=boot,epoch='pal-client:'..boot,
    pid=p.pid,process_created_filetime=p.process_created_filetime,executable_sha256=p.executable_sha256,
    world_directory=a.world_directory,pal_uid=s.pal_uid}
   store.append(prefix,b);b=assert(store.latest(prefix))
  end
  assert(b.pid==p.pid and b.process_created_filetime==p.process_created_filetime and b.world_directory==a.world_directory and b.pal_uid==s.pal_uid,'Process binding mismatch')
  local pointer=ROOT..'escrow-client-process-binding.json';local old=read(pointer)
  if not old or old.boot_id~=b.boot_id then write(pointer,b)end
  api.binding=b;api.ready=true
  local command=read(ROOT..'escrow-client-save-command.json')
  if not command then return api end
  assert(command.protocol==3 and command.world_directory==a.world_directory and command.pal_uid==s.pal_uid and type(command.id)=='string'and#command.id==36 and command.id:match('^[%x%-]+$'),'Save request scope differs')
  local save_prefix='pal-client-save-'..command.id
  if store.latest(save_prefix)then return api end -- Never repeat an uncertain request under this ID.
  local lib=StaticFindObject('/Script/Pal.Default__PalUtility');assert(lib and lib:IsValid())
  local manager=lib:GetSaveGameManager(pc);assert(live(manager),'Actual singleplayer SaveGameManager unavailable')
  if manager:IsWorldAutoSaving()then return api end
  local row={protocol=3,id=command.id,status='normal_save_intent',world_directory=a.world_directory,pal_uid=s.pal_uid,boot_id=boot}
  store.append(save_prefix,row)
  local ok,error=pcall(function()manager:StartWorldDataAutoSave();manager:StartLocalWorldDataAutoSave()end)
  row.status=ok and'normal_save_requested'or'save_request_uncertain';row.error=not ok and tostring(error)or nil
  store.append(save_prefix,row)
  -- A requested save is not a durability receipt. Only the real parsed installed
  -- Level containing the exact escrow phase/counterpart can advance the v3 WAL.
  return api
 end
 return api
end
return M
