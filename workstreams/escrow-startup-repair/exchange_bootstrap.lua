-- Actual normal-startup observation. Call tick on the existing GAME THREAD,
-- before exchange mutations. No item/actor/save writes or lifecycle actions.
local SOURCE=debug.getinfo(1,'S').source:lower():gsub('\\','/')
local M={}
local function valid(o)return o and o:IsValid()end
local function live(o)return valid(o)and not o:GetFullName():find('Default__',1,true)end
local function str(v)return type(v)=='string'and v or v:ToString()end
local function exists(p)local f=io.open(p,'rb');if not f then return false end;f:close();return true end
function M.new(o)
 assert(SOURCE:find('@d:/palworldserver-lan/bridgelab/',1,true)==1 or o.test_mode,'BridgeLab bootstrap only')
 local J,R=assert(o.json),assert(o.readers);local ROOT=assert(o.root):gsub('\\','/'):gsub('/?$','/')
 local RPC=assert(o.rpc_root):gsub('\\','/'):gsub('/?$','/')
 local dir=SOURCE:match('^@(.*[/])');local state={phase='awaiting_prelaunch',ready=false,observed=false}
 local function read(p)local f=io.open(p,'rb');if not f then return nil end;local s=f:read('*a');f:close();return J.decode(s)end
 local function put(p,v)
  if exists(p)then return end
  local f=assert(io.open(p..'.tmp','wb'));assert(f:write(J.encode(v,{max_bytes=33554432,max_depth=64})));assert(f:flush());assert(f:close());assert(os.rename(p..'.tmp',p))
 end
 local function guid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
 local function one(class)
  local found;for _,v in ipairs(FindAllOf(class)or{})do if live(v)then assert(not found,'Ambiguous '..class);found=v end end
  return assert(found,class..' not loaded')
 end
 local function val(v)
  if type(v)=='number'or type(v)=='string'then return v end
  local ok,result=pcall(function()return v:get()end);return ok and result or v
 end
 local function each(array,fn)
  local ok,method=pcall(function()return array.ForEach end)
  if ok and type(method)=='function'then array:ForEach(function(i,v)fn(i,val(v))end)
  else for i,v in ipairs(array)do fn(i-1,val(v))end end
 end
 local function raw_bytes(v)
  local parts={};each(v,function(_,b)b=val(b);assert(type(b)=='number'and b>=0 and b<=255);parts[#parts+1]=string.char(b)end);return table.concat(parts)
 end
 local function guid_raw(bytes,pos)
  local a,b,c,d,nextpos=string.unpack('<I4I4I4I4',bytes,pos);return guid({A=a,B=b,C=c,D=d}),nextpos
 end
 local function saved_slot(cid,s)
  local ok,bytes=pcall(function()return raw_bytes(s.RawData)end)
  local index,count,item,world,dyn
  if ok and #bytes>=8 then
   local p;index,count,p=string.unpack('<i4i4',bytes)
   if count>0 then
    local len;len,p=string.unpack('<i4',bytes,p);assert(len>0 and len<65536,'Unsupported non-ASCII static item ID')
    item=bytes:sub(p,p+len-2);p=p+len;world,p=guid_raw(bytes,p);dyn,p=guid_raw(bytes,p)
   end
  else
   index,count=s.SlotIndex,s.StackCount
   if count>0 then local id=s.ItemId;item=str(id.StaticId);world=guid(id.DynamicId.CreatedWorldId);dyn=guid(id.DynamicId.LocalIdInCreatedWorld)end
  end
  assert(type(index)=='number'and index%1==0 and type(count)=='number'and count%1==0 and count>=0,'Loaded save slot schema unavailable')
  local r={container_id=cid,slot=index,count=count,item=count>0 and item or''}
  if count>0 then r.dynamic_world=world;r.dynamic_guid=dyn end;return r
 end
 local function loaded_containers(world)
  local out=J.array();local seen={}
  world.ItemContainerSaveData:ForEach(function(k,v)
   k,v=val(k),val(v);local cid=guid(k.ID);assert(not seen[cid],'Duplicate loaded container');seen[cid]=true
   local row={container_id=cid,capacity=v.SlotNum,slots=J.array()};assert(type(row.capacity)=='number'and row.capacity>=0)
   local slots={};each(v.Slots,function(_,s)local r=saved_slot(cid,s);assert(r.slot>=0 and r.slot<row.capacity and not slots[r.slot],'Invalid loaded sparse slot');slots[r.slot]=true;if r.count>0 then row.slots[#row.slots+1]=r end end)
   table.sort(row.slots,function(a,b)return a.slot<b.slot end);out[#out+1]=row
  end)
  table.sort(out,function(a,b)return a.container_id<b.container_id end);return out
 end
 local function actual_slots(refs)
  local manager=one('PalItemContainerManager');local out=J.array()
  for _,ref in ipairs(refs or{})do
   local c=manager:GetContainer({ID=R.guid_from_string(ref.container_id)});assert(live(c),'Transaction container not restored')
   assert(ref.slot>=0 and ref.slot<c:Num());local s=c:Get(ref.slot);assert(live(s));local sid=s:GetSlotId()
   assert(guid(sid.ContainerId.ID)==ref.container_id and sid.SlotIndex==ref.slot,'Live transaction slot differs')
   local n=s:GetStackCount();local row={container_id=ref.container_id,slot=ref.slot,count=n,item=''}
   if n>0 then local id=s:GetItemId();row.item=str(id.StaticId);row.dynamic_world=guid(id.DynamicId.CreatedWorldId);row.dynamic_guid=guid(id.DynamicId.LocalIdInCreatedWorld)end
   out[#out+1]=row
  end;return out
 end
 local function process_identity(pre)
  local hex=pre.boot_id:gsub('-','');local p=RPC..'escrow-boot-process-'..hex..'.json';local found=read(p)
  if found then return found end
  local g=R.guid_from_string(pre.boot_id);local thread=tonumber(GetGameThreadId():ToString());assert(thread and thread>0)
  local wire=string.pack('<c8I4I4I4I4I8I8I8I4I4I4I4','PLBOOT01',1,1,thread,0,os.time()+15,0,0,g.A%4294967296,g.B%4294967296,g.C%4294967296,g.D%4294967296)
  assert(#wire==64);local f=assert(io.open(RPC..'escrow-boot-process.request.bin','wb'));assert(f:write(wire));assert(f:flush());assert(f:close())
  local fn,why=package.loadlib(o.process_dll or(dir..'PalCraftEscrowBoot-v1.dll'),'palcraft_escrow_process_identity_v1');assert(fn,why);fn()
  return assert(read(p),'Actual in-process identity helper did not publish')
 end
 local captured,loader_manager
 local function capture(pre)
  if not live(loader_manager)then loader_manager=one('PalSaveGameManager')end
  local mgr=loader_manager;assert(mgr:IsLoadedWorldData()==true,'World save not loaded')
  local loaded=mgr:GetLoadedWorldSaveData();assert(live(loaded),'Loaded world save unavailable')
  local field=mgr.LoadedWorldSaveData;assert(live(field)and field:GetAddress()==loaded:GetAddress(),'Loader property and getter differ')
  local date_math=StaticFindObject('/Script/Engine.Default__KismetMathLibrary');assert(valid(date_math),'Date library unavailable')
  local date=loaded.Timestamp
  local header={version=loaded.Version,revision=loaded.Revision,timestamp=J.array{date_math:GetYear(date),date_math:GetMonth(date),date_math:GetDay(date),date_math:GetHour(date),date_math:GetMinute(date),date_math:GetSecond(date),date_math:GetMillisecond(date)}}
  local world=loaded.worldSaveData
  -- This build reflects FPalGameTimeSaveData as two Int64 properties, not
  -- RawData. Copy the actual value before the loader object is released.
  local real_ticks=val(world.GameTimeSaveData.RealDateTimeTicks)
  assert(type(real_ticks)=='number'and math.type(real_ticks)=='integer','Loaded RealDateTimeTicks Int64 unavailable')
  header.real_date_time_ticks=string.format('%d',real_ticks)
  -- Copy only plain values while the actual manager still owns this loader
  -- object. Never keep a raw save UObject/UScriptStruct across ticks or root it.
  local containers=loaded_containers(world)
  captured={boot_id=pre.boot_id,epoch=pre.epoch,header=header,containers=containers,
   process_identity=process_identity(pre),uses_backup=mgr.bIsUseBackupSaveData,
   load_failed_directory=str(mgr.WorldSaveDataLoadFailedDirectoryName),
   manager_address=string.format('0x%x',mgr:GetAddress()),
   save_address=string.format('0x%x',loaded:GetAddress()),save_object=loaded:GetFullName(),
   save_class=loaded:GetClass():GetFullName(),observed_unix=os.time()}
  state.loader_captured=true;state.loader_observed_unix=captured.observed_unix
 end
 local function sample(pre)
  if not captured or captured.boot_id~=pre.boot_id or captured.epoch~=pre.epoch then capture(pre)end
  local mgr=one('PalSaveGameManager');assert(mgr:IsLoadedWorldData()==true,'World save not loaded')
  assert(string.format('0x%x',mgr:GetAddress())==captured.manager_address,'Loaded save manager changed')
  assert(str(mgr.WorldSaveDataLoadFailedDirectoryName)==captured.load_failed_directory,'World loader failure state changed')
  local gs=one('PalGameStateInGame');assert(gs:HasAuthority(),'Server authority required')
  local utility=StaticFindObject('/Script/Pal.Default__PalUtility');assert(valid(utility),'World utility unavailable')
  assert(utility:IsAllLevelLoaded(gs)==true,'World levels not ready')
  return {protocol=3,kind='palworld_loaded_checkpoint_observation',boot_id=pre.boot_id,epoch=pre.epoch,
   observed_unix=os.time(),process_identity=captured.process_identity,loaded_world_data=mgr:IsLoadedWorldData()==true,
   all_levels_loaded=utility:IsAllLevelLoaded(gs)==true,uses_backup=mgr.bIsUseBackupSaveData,
   load_failed_directory=str(mgr.WorldSaveDataLoadFailedDirectoryName),world_directory=str(gs:GetWorldSaveDirectoryName()),
   world_name=str(gs:GetWorldName()),server_session_id=str(gs.ServerSessionId),header=captured.header,
   containers=captured.containers,transaction_slots=actual_slots(pre.targets.slot_refs),
   loader_observation={method='early_game_thread_manager_getter_and_property',observed_unix=captured.observed_unix,
    manager_address=captured.manager_address,save_address=captured.save_address,
    save_object=captured.save_object,save_class=captured.save_class,uses_backup_at_capture=captured.uses_backup}}
 end
 local api={}
 function api.start_early()
  if state.early_started then return api end
  assert(type(ExecuteInGameThreadAfterFrames)=='function','Actual frame scheduler unavailable')
  state.early_started=true;local deadline=os.time()+60
  local function step()
   if state.early_stopped or captured then state.early_sampling_active=false;return end
   state.early_sampling_active=true
   local ok,why=pcall(function()
    assert(o.test_mode or IsInGameThread(),'Game thread required')
    local pre=assert(read(ROOT..'escrow-boot-prelaunch.json'),'Stopped-boot checkpoint missing')
    assert(pre.protocol==3 and pre.kind=='palworld_prelaunch_checkpoint','Invalid stopped-boot checkpoint envelope')
    capture(pre)
   end)
   if ok then state.early_sampling_active=false;state.early_error=nil;return end
   state.early_error=tostring(why)
   if os.time()>=deadline then state.early_sampling_active=false;state.phase='early_loader_capture_missed';return end
   ExecuteInGameThreadAfterFrames(1,step)
  end
  ExecuteInGameThreadAfterFrames(1,step)
  return api
 end
 function api.stop()state.early_stopped=true;state.early_sampling_active=false end
 function api.tick()
  assert(o.test_mode or IsInGameThread(),'Game thread required')
  local pre=read(ROOT..'escrow-boot-prelaunch.json');if not pre then return state end
  assert(pre.protocol==3 and pre.kind=='palworld_prelaunch_checkpoint','Invalid stopped-boot checkpoint envelope')
  local certificate=read(ROOT..'escrow-boot-certificate.json')
  if certificate and certificate.boot_id==pre.boot_id then
   state.ready=certificate.runtime_verified==true;state.phase=state.ready and'certified'or'awaiting_finalize';return state
  end
  state.ready=false
  state.phase='awaiting_world_loader';state.boot_id=pre.boot_id
  if o.restore_fence then o.restore_fence(pre)end -- existing exchange owner guard, before sampling/admission
  local p=ROOT..'bootstrap/'..pre.boot_id..'/loaded.json'
  if not exists(p)then
   local ok,r=pcall(sample,pre)
   if not ok then state.error=tostring(r);return state end
   put(p,r);state.observed=true;state.error=nil
  end
  state.phase='awaiting_os_finalize';return state
 end
 function api.ready()return state.ready==true end
 function api.status()return state end
 return api
end
return M
