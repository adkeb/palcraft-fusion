-- v3 escrow adapter. The exchange owner supplies its durable lease/receipt store.
-- No native call is made until a real ordinary chest, an exclusive lease and a
-- runtime verified daily-access policy have been checked. The initial policy is
-- an out-of-base chest, ordinary inventory/interaction filtering and exclusion
-- from bridge AI sorting. Hidden actors alone are insufficient. Game thread.
local M={version=1,protocol=3,runtime_verified=false}
local SOURCE_PATH=debug.getinfo(1,'S').source:lower():gsub('\\','/')
local ZERO='00000000-0000-0000-0000-000000000000'
local ALLOWED={Wood=true,Stone=true,Coal=true,Charcoal=true}
local FENCES={'player_open','pal_transport','craft_consume','ai_organize','restart'}
local function uuid(v)
 return type(v)=='string'and #v==36 and v:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil
end
local function integer(n,a,b)return type(n)=='number'and n==n and n%1==0 and n>=a and n<=b end
local function require_(v,s)assert(v,s);return v end
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function canon(v)
 if type(v)~='table'then return type(v)..':'..tostring(v)end
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={};for _,k in ipairs(keys)do out[#out+1]=canon(k)..'='..canon(v[k])end
 return '{'..table.concat(out,';')..'}'
end
local function same(a,b)return canon(a)==canon(b)end
local function copy(v)
 if type(v)~='table'then return v end
 local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out
end
local function identity(q)
 require_(type(q)=='table'and q.protocol==3 and uuid(q.id),'Escrow requires a v3 transaction UUID')
 for _,k in ipairs({'mc_uid','player_uid'})do require_(uuid(q[k]),'Bound '..k..' UUID required')end
 require_(type(q.mc_world)=='string'and #q.mc_world>0,'Bound MC world required')
 require_(ALLOWED[q.item]and integer(q.count,1,64),'Allowed ordinary material and quantity 1..64 required')
 require_(q.action=='debit'or q.action=='credit','Pal debit/credit direction required')
 require_(type(q.fingerprint)=='string'and #q.fingerprint==64 and q.fingerprint:match('^%x+$'),'Fingerprint required')
 local out={};for _,k in ipairs({'protocol','id','mc_uid','player_uid','mc_world','item','count','action','fingerprint'})do out[k]=q[k]end
 return out
end
local function ordinary(ref)
 require_(type(ref)=='table'and uuid(ref.container_id)and integer(ref.slot,0,999)and integer(ref.count,0,2147483647),'Invalid slot snapshot')
 if ref.count==0 then require_(ref.item=='','Empty slot must have no item')
 else require_(ALLOWED[ref.item]and ref.dynamic_guid==ZERO and ref.dynamic_world==ZERO,'Only nondynamic exchange material is allowed')end
 return ref
end
local function empty(cid,index)return {container_id=cid,slot=index,count=0,item=''}end
local function full(row,n)return {container_id=row.container_id,slot=row.slot,count=n,item=row.tx.item,dynamic_guid=ZERO,dynamic_world=ZERO}end
function M.witness_matches(row,w)
 if type(w)~='table'or w.protocol~=3 or w.durable~=true or w.same_level_counterpart~=true then return false end
 if w.id~=row.owner_tx or w.fingerprint~=row.tx.fingerprint or w.lease_generation~=row.generation or w.lease_revision~=row.revision then return false end
 if w.container_id~=row.container_id or w.slot~=row.slot or w.stage~=row.status or not same(w.expected_after,row.expected_after)then return false end
 return type(w.save_sha256)=='string'and #w.save_sha256==64 and w.save_sha256:match('^%x+$')~=nil
end

-- Real reflected backend: resolves registered model -> no-force concrete -> module
-- -> canonical container on EVERY call, matching the validated storage reader.
function M.game_backend(R,credit,scope)
 local standalone=scope and scope.mode=='standalone'
 if standalone then
  local expected=assert(scope.scripts_dir):lower():gsub('\\','/'):gsub('/+$','')..'/'
  require_(SOURCE_PATH:match('^@(.*[/])')==expected,'Standalone escrow source differs from selected private Scripts directory')
 else require_(SOURCE_PATH:find('@d:/palworldserver-lan/bridgelab/',1,true)==1,'Escrow runtime backend is BridgeLab-only')end
 local Authority=standalone and dofile(assert(scope.scripts_dir):gsub('/?$','/')..'standalone_authority.lua')or nil
 local function actual_authority()
  if standalone then
   local found
   for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do if live(pc)and pc:HasAuthority()and R.guid_to_string(pc:GetPlayerUId())==scope.pal_uid then require_(not found,'Ambiguous standalone host');found=pc end end
   return Authority.read(found,scope.world_directory)
  end
 end
 local function one(class)
  local out;for _,o in ipairs(FindAllOf(class)or{})do if live(o)then require_(not out,'Ambiguous '..class);out=o end end
  return require_(out,class..' unavailable')
 end
 local function guid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
 local function container(cid)
  return require_(one('PalItemContainerManager'):GetContainer({ID=R.guid_from_string(cid)}),'Container unavailable')
 end
 local function slot(ref)
  local c=container(ref.container_id);require_(live(c)and ref.slot>=0 and ref.slot<c:Num(),'Slot unavailable')
  local s=c:Get(ref.slot);require_(live(s),'Slot unavailable');return s
 end
 local function snapshot(ref)
  local s=slot(ref);local id=s:GetSlotId();require_(guid(id.ContainerId.ID)==ref.container_id and id.SlotIndex==ref.slot,'Slot identity changed')
  local n=s:GetStackCount();local out=empty(ref.container_id,ref.slot);out.count=n
  if n>0 then local item=s:GetItemId();out.item=item.StaticId:ToString();out.dynamic_guid=guid(item.DynamicId.LocalIdInCreatedWorld);out.dynamic_world=guid(item.DynamicId.CreatedWorldId)end
  return out
 end
 local function component()
  local out;for _,t in ipairs(FindAllOf('PalNetworkTransmitter')or{})do
   if live(t)and t:HasAuthority()then local o=t:GetOwner()
    if live(o)and o:GetFullName():find('BP_PalGameStateInGame',1,true)then require_(not out,'Ambiguous item authority');out=t:GetItem()end
   end
  end
  return require_(live(out)and out,'Global item authority unavailable')
 end
 local b={slot=snapshot}
 function b.chest(candidate)
  actual_authority()
  local model=one('PalMapObjectManager'):FindModel(R.guid_from_string(candidate.model_id));require_(live(model),'Escrow model missing')
  local concrete=model:GetConcreteModel(false);require_(live(concrete),'Escrow concrete unavailable')
  require_(guid(concrete:GetModelInstanceId())==candidate.model_id,'Escrow model identity changed')
  require_(guid(concrete:GetInstanceId())==candidate.concrete_id,'Escrow concrete identity changed')
  require_(concrete:TryGetMapObjectId():ToString()==candidate.type,'Escrow ordinary type changed')
  local module=concrete:GetItemContainerModule();require_(live(module),'Escrow container module missing')
  require_(guid(module:GetContainerId().ID)==candidate.container_id,'Escrow container binding changed')
  local c=container(candidate.container_id);local linked=module:GetContainer()
  require_(live(c)and live(linked)and c:GetFullName()==linked:GetFullName(),'Escrow canonical container mismatch')
  require_(c.bIsGuildChestContainer==false and c:Num()==candidate.capacity,'Escrow capacity/type changed')
  require_(guid(concrete:GetBaseCampIdBelongTo())==candidate.base_id,'Escrow base changed')
  if candidate.base_id~=ZERO then
   local base=concrete:GetBaseCampModelBelongTo();require_(live(base)and base:IsAvailable(),'Escrow base unavailable')
   require_(guid(base:GetId())==candidate.base_id and guid(base:GetGroupIdBelongTo())==candidate.guild_id,'Escrow guild/base changed')
  else require_(guid(model.GroupIdBelongTo)==candidate.guild_id,'Escrow guild changed')end
  require_(live(model.BuildProcess)and model.BuildProcess:IsCompleted(),'Escrow construction incomplete')
  local hp=model:GetHP();require_(type(hp)=='table'and hp.CurrentValue>0,'Escrow destroyed or HP unavailable')
  local pos=concrete:GetTransform().Translation
  require_(type(pos)=='table'and pos.X==candidate.position.x and pos.Y==candidate.position.y and pos.Z==candidate.position.z,'Escrow moved since enrollment')
  local slots={};for i=0,c:Num()-1 do slots[#slots+1]=snapshot({container_id=candidate.container_id,slot=i})end
  local actor=concrete:GetActor();require_(live(actor),'Escrow Actor unavailable')
  local access={actor_name=actor:GetFullName(),private_locked=model:IsLockedPrivate()==true,players={}}
  if candidate.service_uid then access.private_locked_by_service=model:IsLockedPrivateBy(R.guid_from_string(candidate.service_uid))==true end
  for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do if live(pc)and pc:HasAuthority()then
   local uid=guid(pc:GetPlayerUId());access.players[#access.players+1]={uid=uid,private_denied=model:IsLockedPrivateByNot(R.guid_from_string(uid))==true}
  end end
  return {candidate=copy(candidate),slots=slots,access=access}
 end
 function b.move(request_id,to,froms)
  actual_authority()
  local args={};for _,s in ipairs(froms)do args[#args+1]={SlotId=slot(s.before):GetSlotId(),Num=s.n}end
  component():RequestMove_ToServer(R.guid_from_string(request_id),slot(to):GetSlotId(),args)
 end
 function b.dispose(request_id,ref,n)
  actual_authority()
  component():RequestDispose_ToServer(R.guid_from_string(request_id),{SlotId=slot(ref):GetSlotId(),Num=n})
 end
 function b.bag(owner,cid)
  actual_authority()
  local found
  for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do if live(pc)and pc:HasAuthority()and guid(pc:GetPlayerUId())==owner then
   require_(not found,'Ambiguous recipient');found=pc:GetPalPlayerState():GetInventoryData()
  end end
  require_(live(found),'Recipient must be connected')
  require_(guid(found.MyInventoryInfo.CommonContainerId.ID)==cid,'Recipient bag identity changed')
  local c=container(cid);local out={};for i=0,c:Num()-1 do
   local s=c:Get(i);out[#out+1]={before=snapshot({container_id=cid,slot=i}),max_stack=s:GetMaxStack()}
  end;return out
 end
 if credit then
  b.credit_verified=credit.runtime_verified==true
  b.credit_candidate=credit.lab_candidate==true
  function b.credit(row,request_id,n)
   actual_authority()
   require_(credit.runtime_verified==true or credit.lab_candidate==true,'An explicit Lab permit is required for the produce-only candidate')
   local utility=StaticFindObject('/Script/Pal.Default__PalItemUtility');require_(utility and utility:IsValid(),'Item descriptor utility unavailable')
   -- This UI/local descriptor is neither an inventory nor a persistent container.
   -- Only the engine's validated produce transaction writes the REAL escrow slot.
   local descriptor=utility:CreateLocalItemSlot(one('PalItemContainerManager'),FName(row.tx.item),n)
   require_(live(descriptor)and descriptor:GetStackCount()==n,'Local ordinary item descriptor unavailable')
   local item=descriptor:GetItemId();require_(item.StaticId:ToString()==row.tx.item and guid(item.DynamicId.CreatedWorldId)==ZERO and guid(item.DynamicId.LocalIdInCreatedWorld)==ZERO,'Descriptor is not the bound ordinary material')
   local s=slot({container_id=row.container_id,slot=row.slot});local manager=one('PalItemContainerManager')
   local function pg(g)return string.pack('<I4I4I4I4',g.A%4294967296,g.B%4294967296,g.C%4294967296,g.D%4294967296)end
   local function bytes(hex)require_(#hex==64 and hex:match('^%x+$'),'SHA256 required');return (hex:gsub('%x%x',function(x)return string.char(tonumber(x,16))end))end
   local proof=require_(credit.permit(row,request_id),'Saved MC debit permit unavailable')
   require_(type(proof.mc_receipt_sha256)=='string'and proof.native_request_id==request_id,'Credit permit identity mismatch')
   local thread_id=tonumber(GetGameThreadId():ToString());require_(integer(thread_id,1,4294967295),'Game thread ID unavailable')
   local wire=string.pack('<c8I4I4I4I4I8I8I8','PLESCR01',1,1,thread_id,0,os.time()+15,manager:GetAddress(),manager:GetClass():GetAddress())..
    pg(R.guid_from_string(request_id))..string.pack('<I8I8I8I8',s:GetAddress(),s:GetClass():GetAddress(),descriptor:GetAddress(),descriptor:GetClass():GetAddress())..
    pg(s:GetSlotId().ContainerId.ID)..string.pack('<i4i4',row.slot,n)..pg(R.guid_from_string(row.tx.id))..string.pack('<I8',row.generation)..bytes(row.tx.fingerprint)..bytes(proof.mc_receipt_sha256)
   require_(#wire==208,'Credit wire ABI mismatch')
   local rpc=standalone and assert(scope.rpc_root)or'D:/PalworldServer-LAN/BridgeLab/rpc/'
   if standalone then require_(rpc:gsub('\\','/'):gsub('/+$',''):lower()==assert(os.getenv('PALCRAFT_RPC_ROOT')):gsub('\\','/'):gsub('/+$',''):lower(),'Credit RPC root differs from trusted startup mapping')end
   local p=rpc:gsub('\\','/'):gsub('/?$','/')..'escrow-credit.request.bin'
   local f=assert(io.open(p,'wb'));assert(f:write(wire));assert(f:flush());assert(f:close())
   local fn,why=package.loadlib(credit.dll_path,'palcraft_escrow_credit_v1');require_(fn,why or'Credit DLL unavailable');fn()
   -- Caller uses the real escrow read-back. Native JSON/logs are audit evidence,
   -- never a substitute for the subsequent installed Level.sav witness.
  end
 end
 return b
end

-- Only ordinary reflected inventory RPCs and interaction queries are filtered.
-- UE4SS RegisterHook does NOT cancel void functions. Invalidating their slot /
-- container parameter makes the game's normal pre-mutation validator refuse the
-- request. RemoteUnrealParam:set supports these struct/array types in 2281fa31.
-- Still a live Lab candidate: RPC dispatch, Froms conversion and UI getter routing
-- must be challenged in game before runtime_verified=true is recorded.
function M.rpc_guard(o)
 require_(o and o.readers and type(o.current)=='function','RPC guard requires current lease lookup')
 local R=o.readers;local register=o.register or RegisterHook
 local unreg=o.unregister or UnregisterHook
 local invalid={ContainerId={ID=R.guid_from_string(ZERO)},SlotIndex=-1}
 local installed,actors,permit,broken={}, {},nil,nil
 local counters={move_blocked=0,dispose_blocked=0,drop_blocked=0,interaction_blocked=0,bridge_allowed=0}
 local function reserved(cid)
  local row=o.current(cid);return row and row.status~='released'and row or nil
 end
 local function cid(v)return R.guid_to_string(v.ID)end
 local function slotcid(v)return cid(v.ContainerId)end
 local function list(param)
  local v=param:get();local out={}
  if type(v)=='table'then for _,e in ipairs(v)do out[#out+1]=e end
  else v:ForEach(function(_,e)out[#out+1]=e:get()end)end
  return out
 end
 local function touched(to,froms)
  local ids={};if to and reserved(to)then ids[to]=true end
  for _,s in ipairs(froms or{})do local id=slotcid(s.SlotId);if reserved(id)then ids[id]=true end end
  return ids,next(ids)~=nil
 end
 local function own(ids,request,kind)
  if not permit or permit.kind~=kind or not request then return false end
  if R.guid_to_string(request:get())~=permit.request_id then return false end
  for id in pairs(ids)do if id~=permit.container_id then return false end end
  counters.bridge_allowed=counters.bridge_allowed+1;return true
 end
 local function set(param,value)
  local ok,why=pcall(function()param:set(value)end)
  if not ok then broken=tostring(why);error('Escrow RPC filter failed to set parameter: '..broken)end
 end
 local hooks={
  ['/Script/Pal.PalNetworkItemComponent:RequestMove_ToServer']=function(_,request,to,froms)
   local ids,hit=touched(slotcid(to:get()),list(froms));if hit and not own(ids,request,'move')then set(to,copy(invalid));counters.move_blocked=counters.move_blocked+1 end
  end,
  ['/Script/Pal.PalNetworkItemComponent:RequestMoveToContainer_ToServer']=function(_,request,to,froms)
   local _,hit=touched(cid(to:get()),list(froms));if hit then set(to,{ID=R.guid_from_string(ZERO)});counters.move_blocked=counters.move_blocked+1 end
  end,
  ['/Script/Pal.PalNetworkItemComponent:RequestSwap_ToServer']=function(_,_,a,b)
   if reserved(slotcid(a:get()))or reserved(slotcid(b:get()))then set(a,copy(invalid));counters.move_blocked=counters.move_blocked+1 end
  end,
  ['/Script/Pal.PalNetworkItemComponent:RequestDispose_ToServer']=function(_,request,info)
   local s=info:get();local ids,hit=touched(nil,{s})
   if hit and not own(ids,request,'dispose')then set(info,{SlotId=copy(invalid),Num=0});counters.dispose_blocked=counters.dispose_blocked+1 end
  end,
  ['/Script/Pal.PalNetworkItemComponent:RequestDrop_ToServer']=function(_,froms)
   local _,hit=touched(nil,list(froms));if hit then set(froms,{});counters.drop_blocked=counters.drop_blocked+1 end
  end,
  ['/Script/Pal.PalInteractiveInterface:IsEnableTriggerInteract']=function(context)
   local obj=context:get();local name=obj:GetFullName();local id=actors[name]
   if not id then local ok,owner=pcall(function()return obj:GetOwner()end);if ok and live(owner)then id=actors[owner:GetFullName()]end end
   if id and reserved(id)then counters.interaction_blocked=counters.interaction_blocked+1;return false end
  end
 }
 -- Normal bag quick-stack calls can reach native manager Move directly, without
 -- the reflected item RPC above. Bind their ToContainerId parameter as well.
 for _,name in ipairs({'RequestFillSlotToTargetContainerFromInventory_SlotExcepts_ToServer','RequestFillSlotToTargetContainerFromInventory_ToServer'})do
  local path='/Script/Pal.PalPlayerInventoryData:'..name
  if o.available==nil or o.available(path)then hooks[path]=function(_,to)if reserved(cid(to:get()))then set(to,{ID=R.guid_from_string(ZERO)});counters.move_blocked=counters.move_blocked+1 end end end
 end
 local api={}
 function api.install()
  if next(installed)then return not broken end
  require_(type(register)=='function','UE4SS hook registration unavailable')
  for path,fn in pairs(hooks)do
   local ok,a,b=pcall(register,path,function(...)
    local ok,r=pcall(fn,...);if not ok then broken=tostring(r);error(r)end;return r
   end)
   if not ok or type(a)~='number'or type(b)~='number'then broken=tostring(a or'Invalid hook IDs');return false end
   installed[path]={a,b}
  end
  return true
 end
 function api.refresh(row,actor_name)require_(type(actor_name)=='string','Actual escrow Actor name required');actors[actor_name]=row.container_id end
 function api.inspect()return {installed=next(installed)~=nil and not broken,error=broken,counters=copy(counters)}end
 function api.with_permit(row,key,fn)
  require_(not permit and not broken,'Escrow RPC guard is unavailable/reentrant')
  local op=require_(row.operations[key],'Durable native intent required for bridge permit')
  permit={container_id=row.container_id,request_id=op.request_id,kind=key=='dispose'and'dispose'or'move'}
  local ok,r=pcall(fn);permit=nil;if not ok then error(r)end;return r
 end
 function api.close()
  require_(type(unreg)=='function','Hook removal unavailable')
  for path,ids in pairs(installed)do unreg(path,ids[1],ids[2])end;installed={};actors={};permit=nil
 end
 return api
end

-- Concrete initial policy; no native interception/anti-cheat subsystem required.
-- Normal current-player/guild ownership; nobody needs to disconnect or create an
-- account. Enroll after the three normal gameplay challenges and a saved restart.
-- `excluded` is shared by bridge organizers and exchange source discovery; the
-- integration owner must install that actual exclusion before enabling claims.
function M.daily_guard(o)
 require_(o and o.backend and o.readers and type(o.excluded)=='function','Daily guard dependencies required')
 local evidence=o.evidence or {runtime_verified=false}
 local api={}
 function api.inspect(row)
  local c=row.candidate;local snap=o.backend.chest(c)
  require_(c.base_id==ZERO,'Daily escrow must be out of base')
  local bases=o.readers.bases();require_(bases.ok==true,'Base-range census unavailable')
  for _,b in ipairs(bases.bases or{})do
   require_(b.ok==true and type(b.range)=='number'and b.position,'An unreadable base prevents range exclusion')
   local dx,dy=c.position.x-b.position.x,c.position.y-b.position.y
   require_(dx*dx+dy*dy>(b.range+(o.margin_cm or 1000))^2,'A base supply/transport range overlaps escrow')
  end
  require_(o.excluded(c.container_id,c.model_id)==true,'Escrow is still a normal bridge organizer/source target')
  if o.rpc then
   require_(o.rpc.install()==true,'Escrow ordinary RPC hooks could not be installed')
   o.rpc.refresh(row,snap.access.actor_name);require_(o.rpc.inspect().installed,'Escrow RPC hook has failed')
  end
  if evidence.runtime_verified then
   require_(o.rpc~=nil,'Verified daily policy requires the tested ordinary RPC filter')
   require_(evidence.container_id==c.container_id and evidence.model_id==c.model_id,'Daily isolation evidence belongs to another chest')
  end
  local out={active=true,runtime_verified=evidence.runtime_verified==true,lab_candidate=o.lab_candidate==true,epoch=o.epoch,
   owner_tx=row.owner_tx,generation=row.generation,container_id=c.container_id,
   scope=o.rpc and'ordinary_inventory_rpc_and_interaction_out_of_base'or'out_of_base_ai_exclusion_and_change_detection_only'}
  for _,name in ipairs(FENCES)do out[name]=evidence[name]==true end
  return out
 end
 function api.with_permit(row,key,fn)api.inspect(row);if o.rpc then return o.rpc.with_permit(row,key,fn)end;return fn()end
 return api
end

function M.new(o)
 require_(type(o)=='table'and type(o.epoch)=='string'and o.store and o.backend,'Lease store/backend/epoch required')
 for _,k in ipairs({'get','get_tx','cas'})do require_(type(o.store[k])=='function','Durable lease store '..k..' required')end
 require_(o.guard and type(o.guard.inspect)=='function'and type(o.guard.with_permit)=='function','Server guard required')
 require_(type(o.authorize)=='function'and type(o.accept_witness)=='function','MC receipt and save witness validators required')
 require_(type(o.request_id)=='function','Stable native request ID provider required')
 local c=copy(o.candidate);require_(type(c)=='table','One enrolled ordinary chest required')
 for _,k in ipairs({'container_id','model_id','concrete_id','base_id','guild_id'})do require_(uuid(c[k]),'Candidate '..k..' required')end
 require_((c.type=='ItemChest'or c.type=='ItemChest_02')and integer(c.capacity,1,1000)and type(c.position)=='table','Ordinary chest metadata required')
 require_(c.enrollment_save_sha256 and #c.enrollment_save_sha256==64,'Paid construction enrollment save evidence required')
 local now=o.now or os.time
 local function thread()require_(o.test_mode==true or IsInGameThread(),'Escrow requires game thread')end
 local function persist(row)
  local expected=row.revision or 0;row.revision=expected+1;row.updated_unix=now()
  require_(o.store.cas(c.container_id,expected,copy(row))==true,'Durable lease CAS failed; no native call allowed')
  return row
 end
 local function current(lease)
  thread();local row=require_(o.store.get(c.container_id),'Escrow lease missing')
  require_(same(row.tx,lease.tx)and row.generation==lease.generation and row.owner_tx==lease.owner_tx,'Stale/foreign escrow lease')
  require_(same(row.candidate,c)and row.container_id==lease.container_id and row.slot==lease.slot,'Escrow binding changed')
  return copy(row)
 end
 local function guarded(row)
  require_(row.status~='released','Escrow lease is terminal')
  local snapshot=o.backend.chest(c)
  for _,s in ipairs(snapshot.slots)do require_(s.slot==row.slot or s.count==0,'Unexpected material in another reserved chest slot')end
  local g=o.guard.inspect(copy(row))
  require_(type(g)=='table'and(g.runtime_verified==true or(o.lab_candidate==true and g.lab_candidate==true))and g.active==true and g.epoch==o.epoch,'Escrow access isolation is not verified; an explicit Lab candidate lease is required for pilot work')
  require_(g.owner_tx==row.owner_tx and g.generation==row.generation and g.container_id==row.container_id,'Escrow fence lease changed')
  if g.runtime_verified then for _,name in ipairs(FENCES)do require_(g[name]==true,'Escrow isolation missing '..name)end end
  return g
 end
 local function slot_now(row)
  guarded(row);return ordinary(o.backend.slot({container_id=row.container_id,slot=row.slot}))
 end
 local function intent(row,key,before,after,details)
  require_(not row.operations[key],'Escrow native operation was already attempted; reconcile instead of replay')
  local attempt=row.next_attempt and row.next_attempt[key]or 1
  require_(integer(attempt,1,1000000),'Native attempt counter invalid')
  local request_id=require_(o.request_id(copy(row),key,attempt),'Stable native request UUID required')
  require_(uuid(request_id),'Stable native request UUID required')
  for _,past in ipairs(row.operation_history and row.operation_history[key]or{})do require_(past.request_id~=request_id,'Rearmed operation requires a new native RequestID')end
  row.operations[key]={request_id=request_id,before=copy(before),expected_after=copy(after),details=copy(details),epoch=o.epoch,
   boot_id=o.boot_id,attempt=attempt,attempted_unix=now(),attempted=true,observed=false}
  return persist(row)
 end
 local function observe(row,key)
  local op=row.operations[key];local actual=slot_now(row)
  if not same(actual,op.expected_after)then
   local reason='Escrow outcome differs from intended exact slot; preserve lease and native intent'
   if row.status~='needs_recovery'or row.reason~=reason then row.status='needs_recovery';row.reason=reason;persist(row)end;return row
  end
  op.observed=true;op.after=actual;row.expected_after=actual;row.status=actual.count==0 and'empty'or'full'
  row.save_after_unix=now()+1;row.reason=nil;return persist(row)
 end
 local api={}
 function api.claim(tx,binding)
  thread();local q=identity(tx)
  require_(type(binding)=='table'and binding.owner_uid==q.player_uid and binding.guild_id==c.guild_id and binding.base_id==(c.source_base_id or c.base_id),'Escrow owner/guild/base binding mismatch')
  local old=o.store.get_tx(q.id)
  if old then require_(same(old.tx,q),'Transaction ID cannot be reused');return current(old)end
  old=o.store.get(c.container_id)
  require_(not old or old.status=='released','Escrow chest belongs to an in-flight transaction')
  local snapshot=o.backend.chest(c)
  for _,s in ipairs(snapshot.slots)do require_(s.count==0,'Enrolled escrow must be an entirely empty chest')end
  local row={protocol=3,tx=q,owner_tx=q.id,container_id=c.container_id,slot=0,
   candidate=copy(c),generation=old and old.generation+1 or 1,revision=old and old.revision or 0,
   status='claimed',binding=copy(binding),operations={},epoch=o.epoch,
   assurance=o.lab_candidate==true and'lab_candidate'or'verified_daily_policy'}
  persist(row) -- Persistent reservation precedes guard acquisition and any materials.
  require_(o.guard.acquire==nil or o.guard.acquire(copy(row))==true,'Escrow reservation retained; guard acquisition failed')
  guarded(row);return row
 end
 function api.read(lease)local row=current(lease);return slot_now(row),row end
 function api.moveIn(lease,froms,n)
  local row=current(lease);require_(row.tx.action=='debit'and n==row.tx.count,'Import quantity/direction mismatch')
  if row.operations.moveIn then return api.reconcile(row,'moveIn')end
  require_(row.status=='claimed','Escrow import is out of order')
  local before=slot_now(row);require_(before.count==0,'Escrow is not empty')
  require_(type(froms)=='table'and #froms>0,'Real source slots required')
  local actuals,total,seen={},0,{}
  for _,s in ipairs(froms)do
   local actual=ordinary(o.backend.slot(s.before));local key=actual.container_id..':'..actual.slot
   require_(actual.container_id~=row.container_id and not seen[key],'Duplicate or escrow source');seen[key]=true
   require_(same(actual,s.before)and actual.item==row.tx.item and integer(s.n,1,actual.count),'Source changed before Move')
   require_(o.authorize('source',copy(row),copy(actual))==true,'Source owner/guild/base authorization failed')
   total=total+s.n;actuals[#actuals+1]={before=actual,n=s.n}
  end
  require_(total==n,'Exact source material quantity required')
  row.status='moving_in';intent(row,'moveIn',before,full(row,n),actuals)
  o.guard.with_permit(copy(row),'moveIn',function()o.backend.move(row.operations.moveIn.request_id,before,actuals)end)
  return observe(row,'moveIn')
 end
 function api.ensureCredit(lease,receipt,n)
  local row=current(lease);require_(row.tx.action=='credit'and n==row.tx.count,'Export quantity/direction mismatch')
  if row.operations.credit then return api.reconcile(row,'credit')end
  require_(row.status=='claimed','Escrow credit is out of order');local before=slot_now(row);require_(before.count==0,'Escrow is not empty')
  require_(o.authorize('mc_debit',copy(row),copy(receipt))==true,'Saved MC debit receipt required before escrow credit')
  require_(type(o.backend.credit)=='function'and(o.backend.credit_verified==true or(o.lab_candidate==true and o.backend.credit_candidate==true)),'Direct escrow produce helper needs Lab verification or an explicit Lab pilot permit')
  row.mc_debit_receipt=copy(receipt);row.status='crediting';intent(row,'credit',before,full(row,n),{receipt=receipt})
  o.guard.with_permit(copy(row),'credit',function()o.backend.credit(copy(row),row.operations.credit.request_id,n)end)
  return observe(row,'credit')
 end
 function api.acceptWitness(lease,w)
  local row=current(lease);require_(same(slot_now(row),row.expected_after),'Escrow changed since witnessed stage')
  require_(row.status=='full'or row.status=='empty','Save witness is out of order')
  require_(M.witness_matches(row,w),'Escrow witness identity/generation/stage mismatch')
  require_(o.accept_witness(copy(row),copy(w))==true,'Installed Level save / generation / stage witness mismatch')
  local receipt=copy(w);receipt.lease_record=nil
  -- Full selected-row snapshots stay in the external immutable receipt file.
  -- Never nest that snapshot back into the row that future receipts will copy.
  if row.status=='full'then row.full_witness=receipt;row.status='full_saved'
  else row.empty_witness=receipt;row.status='empty_saved'end
  return persist(row)
 end
 function api.dispose(lease,receipt,n)
  local row=current(lease);require_(row.tx.action=='debit'and n==row.tx.count,'Import disposal quantity/direction mismatch')
  if row.operations.dispose then return api.reconcile(row,'dispose')end
  require_(row.status=='full_saved','Full escrow save witness required before disposal')
  require_(o.authorize('mc_credit',copy(row),copy(receipt))==true,'Saved MC credit receipt required before disposal')
  local before=slot_now(row);require_(same(before,full(row,n)),'Escrow material changed before disposal')
  row.mc_credit_receipt=copy(receipt);row.status='disposing';intent(row,'dispose',before,empty(row.container_id,row.slot),{receipt=receipt})
  o.guard.with_permit(copy(row),'dispose',function()o.backend.dispose(row.operations.dispose.request_id,before,n)end)
  return observe(row,'dispose')
 end
 function api.deliver(lease,bag_id,n)
  local row=current(lease);require_(row.tx.action=='credit'and n==row.tx.count and uuid(bag_id),'Export delivery binding mismatch')
  if row.operations.deliver then return api.reconcile(row,'deliver')end
  require_(row.status=='full_saved','Full escrow save witness required before delivery')
  local before=slot_now(row);require_(same(before,full(row,n)),'Escrow material changed before delivery')
  -- One explicit target keeps this native Move atomic. The owner can expose a
  -- normal wait-for-space state when only fragmented bag capacity is available.
  local target
  for _,s in ipairs(o.backend.bag(row.tx.player_uid,bag_id))do
   local r=s.before
   if r.count==0 or(r.item==row.tx.item and r.dynamic_guid==ZERO and r.dynamic_world==ZERO and s.max_stack-r.count>=n)then target=ordinary(r);break end
  end
  if not target then row.reason='Recipient has no slot with room for this stack';return persist(row)end
  require_(target.container_id~=row.container_id,'Escrow cannot deliver to itself')
  row.recipient_container_id=bag_id;row.status='delivering';intent(row,'deliver',before,empty(row.container_id,row.slot),{to=target,n=n})
  o.guard.with_permit(copy(row),'deliver',function()o.backend.move(row.operations.deliver.request_id,target,{{before=before,n=n}})end)
  return observe(row,'deliver')
 end
 function api.reconcile(lease,key)
  local row=current(lease);local op=require_(row.operations[key],'No recorded native intent')
  if op.observed then return row end
  -- Exclusive escrow, recorded empty/full precondition, native atomic Move and
  -- a current server guard allow its own afterimage to prove the effect. Never
  -- infer success from the changing source/bag total, and never call native again.
  return observe(row,key)
 end
 function api.rearm(lease,key,proof)
  if type(key)=='table'and proof==nil then proof=key;key=proof.operation end
  local row=current(lease);local op=require_(row.operations[key],'Rearm requires an existing native intent')
  require_((key=='moveIn'or key=='credit'or key=='dispose'or key=='deliver')and op.attempted==true,'A recorded native operation is required')
  local has_durable_after=(key=='moveIn'or key=='credit')and row.full_witness or row.empty_witness
  require_(not has_durable_after,'A witnessed native effect cannot be rearmed or rolled back')
  require_(row.status=='needs_recovery'or row.status=='moving_in'or row.status=='crediting'or row.status=='disposing'or row.status=='delivering'or
   ((key=='moveIn'or key=='credit')and row.status=='full')or((key=='dispose'or key=='deliver')and row.status=='empty'),'Rearm phase is out of order')
  require_(uuid(o.boot_id)and uuid(op.boot_id)and o.boot_id~=op.boot_id and o.epoch~=op.epoch,'A real changed Pal boot identity is required; mod reload is insufficient')
  require_(type(proof)=='table'and proof.protocol==3 and proof.kind=='escrow_rearm_after_world_rehydrate','Installed-world rehydration proof required')
  for k,v in pairs({id=row.owner_tx,fingerprint=row.tx.fingerprint,container_id=row.container_id,slot=row.slot,
   lease_generation=row.generation,lease_revision=row.revision,operation=key,previous_attempt=op.attempt or 1,
   previous_request_id=op.request_id,previous_observed=op.observed==true,from_epoch=op.epoch,to_epoch=o.epoch,from_boot_id=op.boot_id,to_boot_id=o.boot_id})do require_(proof[k]==v,'Rearm proof mismatch: '..k)end
  require_(uuid(proof.proof_id)and proof.full_world_rehydrated==true,'Fresh complete-world proof ID required')
  require_(type(proof.loaded_level_sha256)=='string'and #proof.loaded_level_sha256==64 and proof.loaded_level_sha256:match('^%x+$')and
   proof.installed_level_sha256==proof.loaded_level_sha256,'Loaded/installed Level hashes differ')
  require_(type(proof.boot_certificate_sha256)=='string'and #proof.boot_certificate_sha256==64 and proof.boot_certificate_sha256:match('^%x+$'),'Trusted boot certificate SHA256 required')
  require_(integer(proof.checkpoint_mtime_ns,1,10000000000000000000),'Checkpoint time required')
  require_(type(op.attempted_unix)=='number'and proof.checkpoint_mtime_ns<=op.attempted_unix*1000000000,'Restored checkpoint must predate the attempted effect')
  require_(same(proof.saved_before,op.before)and same(slot_now(row),op.before),'Installed and live escrow must exactly match its recorded beforeimage')
  local counterparts={}
  if key=='moveIn'then for _,s in ipairs(op.details)do counterparts[#counterparts+1]=s.before end
  elseif key=='deliver'then counterparts[1]=op.details.to end
  require_(same(proof.counterpart_before,counterparts),'Restored source/bag slots differ from recorded native beforeimages')
  for _,used in ipairs(row.rearm_proofs or{})do require_(used.id~=proof.proof_id,'Rehydration proof already consumed')end
  require_(o.authorize('rehydrate',copy(row),copy(proof))==true,'Owner must verify actual new process and the exact full-world loaded checkpoint; booleans/mtime/one empty slot are insufficient')
  row.operation_history=row.operation_history or{};row.operation_history[key]=row.operation_history[key]or{}
  row.operation_history[key][#row.operation_history[key]+1]=copy(op)
  row.rearm_proofs=row.rearm_proofs or{};row.rearm_proofs[#row.rearm_proofs+1]={id=proof.proof_id,operation=key,
   previous_attempt=op.attempt or 1,to_boot_id=o.boot_id,boot_certificate_sha256=proof.boot_certificate_sha256,installed_level_sha256=proof.installed_level_sha256}
  row.next_attempt=row.next_attempt or{};row.next_attempt[key]=(op.attempt or 1)+1;row.operations[key]=nil
  row.status=(key=='moveIn'or key=='credit')and'claimed'or'full_saved'
  row.expected_after=copy(op.before);row.reason=nil;row.save_after_unix=nil;row.epoch=o.epoch
  return persist(row) -- no native operation, permit creation, grant or removal here
 end
 function api.release(lease,terminal)
  local row=current(lease);if row.status=='released'then return row end
  require_(row.status=='empty_saved'and row.empty_witness,'Empty installed-save witness required before release')
  require_(slot_now(row).count==0,'Escrow refilled before release')
  require_(type(terminal)=='table'and terminal.protocol==3 and terminal.id==row.owner_tx and terminal.fingerprint==row.tx.fingerprint and
   terminal.lease_generation==row.generation and terminal.state=='completed'and terminal.escrow_empty_durable==true,'Matching v3 empty-durable terminal receipt required')
  require_(o.authorize('terminal',copy(row),copy(terminal))==true,'Terminal v3 coordinator receipt required')
  row.terminal_receipt=copy(terminal);row.status='released';persist(row)
  -- A crash here leaves a harmless fence; the lease tombstone is authoritative.
  if o.guard.release then o.guard.release(copy(row))end
  return row
 end
 return api
end
return M
