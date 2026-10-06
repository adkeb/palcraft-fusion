-- Server-owned, newline-committed state journal and final-ack outbox. No UObject or service operations.
-- A production host should supply flush_file for a durable OS flush. Lua flush/close alone is process-crash recovery.
local M={}
function M.new(options)
 local J=assert(options.json,'json_required');local path=assert(options.path,'server_journal_path_required')
 local ack_path=assert(options.ack_path,'server_ack_path_required');local serial=0
 local function restore_backup(file_path)
  local f=io.open(file_path,'rb');if f then f:close();return end
  local backup=io.open(file_path..'.torn','rb');if backup then backup:close();assert(os.rename(file_path..'.torn',file_path),'journal_backup_restore_failed')end
 end
 local function rewrite(file_path,bytes)
  local temporary=file_path..'.repair';local backup=file_path..'.torn'
  local f=assert(io.open(temporary,'wb'));assert(f:write(bytes));assert(f:flush());assert(f:close())
  if options.flush_file then assert(options.flush_file(temporary)==true,'journal_os_flush_failed')end
  os.remove(backup);assert(os.rename(file_path,backup),'journal_backup_failed')
  local ok,why=os.rename(temporary,file_path)
  if not ok then os.rename(backup,file_path);error(why or'journal_repair_rename_failed')end
  if options.flush_file then assert(options.flush_file(file_path)==true,'journal_os_flush_failed')end
  os.remove(backup)
 end
 local function repair_tail(file_path)
  restore_backup(file_path);local f=io.open(file_path,'rb');if not f then return end
  local size=assert(f:seek('end'));if size==0 then f:close();return end
  f:seek('end',-1);local ending=f:read(1)
  if ending=='\n' then f:close();return end
  f:seek('set',0);local raw=assert(f:read('*a'));f:close()
  local at=1;local end_at=0
  while true do local stop=raw:find('\n',at,true);if not stop then break end;end_at=stop;at=stop+1 end
  rewrite(file_path,raw:sub(1,end_at))
 end
 local function append(file_path,row)
  repair_tail(file_path)
  local line=J.encode(row)..'\n';local f=assert(io.open(file_path,'ab'),'journal_open_failed')
  local ok,err=pcall(function()assert(f:write(line));assert(f:flush())end);local closed,close_error=f:close()
  if not ok then error(err)end;if not closed then error(close_error or'journal_close_failed')end
  if options.flush_file then assert(options.flush_file(file_path)==true,'journal_os_flush_failed')end
  return true
 end
 local api={}
 function api.load()
  restore_backup(path)
  local f=io.open(path,'rb');if not f then return nil end
  local raw=f:read('*a');f:close();local last;local at=1;local read_serial=0
  while true do
   local stop=raw:find('\n',at,true);if not stop then break end
   local line=raw:sub(at,stop-1);at=stop+1
   if #line>0 then
    local ok,row=pcall(J.decode,line);assert(ok and type(row)=='table'and row.v==1 and type(row.serial)=='number'and type(row.state)=='table','committed_journal_corrupt')
    assert(row.serial>read_serial,'journal_serial_regression');read_serial=row.serial;last=row.state
   end
  end
  -- A torn tail is not a committed record. Remove it before a future append can join two JSON objects.
  if at<=#raw then
   rewrite(path,raw:sub(1,at-1))
  end
  serial=read_serial;return last
 end
 function api.save(state)
  serial=serial+1;return append(path,{v=1,serial=serial,state=state})
 end
 function api.ack(row)
  assert(row.phase=='complete'and row.applied==true and row.authority_source=='pal_server','authoritative_final_required')
  return append(ack_path,row)
 end
 function api.status()return{path=path,ack_path=ack_path,serial=serial,durability=options.flush_file and'os_flushed'or'lua_flush_process_crash'}end
 return api
end
return M
