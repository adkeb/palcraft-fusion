-- Next candidate: two saved escrow phases, genuine source moves and saved MC receipts.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local E=dofile(dir..'exchange_escrow.lua');local Store=dofile(dir..'exchange_store.lua')
local identity={'protocol','id','mc_uid','player_uid','mc_world','item','count','action','fingerprint'}
local allowed={Wood=true,Stone=true,Coal=true,Charcoal=true}
local ZERO='00000000-0000-0000-0000-000000000000'
local function same(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function match(a,b)for _,k in ipairs(identity)do if a[k]~=b[k]then return false end end;return true end
local function copy(q)local r={};for _,k in ipairs(identity)do r[k]=q[k]end;return r end
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function request_id(lease,key,attempt)
 local code=assert(({moveIn=1,credit=2,deliver=3,dispose=4})[key]);attempt=attempt or(lease.operations[key]and lease.operations[key].attempt)or(lease.next_attempt and lease.next_attempt[key])or 1
 local id=lease.owner_tx;local value=(tonumber(id:sub(-8),16)+lease.generation*4096+attempt*16+code)%4294967296
 return id:sub(1,-9)..string.format('%08x',value)
end
local M={protocol=3,request_id=request_id}
function M.new(opts)
 local test=rawget(_G,'PALCRAFT_EXCHANGE_TEST');local o=opts or(test and test.v3)or{}
 local J=o.json or(test and(test.json or dofile(test.json_path)))or dofile(dir..'json.lua')
 local R=o.readers or(test and test.readers)or dofile(dir..'readers.lua')
 local ROOT=o.root or(test and test.root)or os.getenv('PALCRAFT_EXCHANGE_ROOT')
 assert(ROOT,'Trusted startup exchange root is required');ROOT=ROOT:gsub('\\','/'):gsub('/+$','')..'/'
 local function read(p)local f=io.open(p,'rb');if not f then return nil end;local b=f:read('*a');f:close();return assert(J.decode(b))end
 local function mailbox(p,v)local f=assert(io.open(p..'.tmp','wb'));assert(f:write(J.encode(v)));assert(f:flush());assert(f:close());os.remove(p);assert(os.rename(p..'.tmp',p))end
 local config=o.config or assert(read(ROOT..'escrow-config.json'),'One real paid escrow enrollment is required')
 assert(config.protocol==3 and config.candidate,'Escrow enrollment protocol3 required')
 local c=config.candidate
 local standalone=config.runtime_scope and config.runtime_scope.mode=='standalone'
 local boot=o.boot_certificate or(not standalone and read(ROOT..'escrow-boot-certificate.json'))
 local binding=standalone and assert(read(ROOT..'escrow-client-process-binding.json'),'Actual standalone client process binding required')or nil
 if standalone then assert(binding.world_directory==config.runtime_scope.world_directory and binding.pal_uid==config.runtime_scope.pal_uid,'Standalone process binding belongs to another host/world')end
 local boot_id=o.boot_id or(binding and binding.boot_id)or(boot and boot.boot_id)
 local epoch=o.epoch or(binding and binding.epoch)or(test and test.epoch)or(boot and boot.epoch)or(tostring(os.time())..':'..tostring({}))
 if not test then assert(type(boot_id)=='string'and #boot_id==36 and boot_id:match('^[%x%-]+$'),'The lifecycle owner must bind this actual Pal process boot UUID')end
 local registry=rawget(_G,'PalCraftEscrowExclusions')or{containers={},models={}}
 registry.containers[c.container_id]=true;registry.models[c.model_id]=true
 registry.is_reserved=function(cid,mid)return registry.containers[cid]==true or registry.models[mid]==true end
 _G.PalCraftEscrowExclusions=registry
 local function excluded(cid,mid)return registry.is_reserved(cid,mid)end
 local function guid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
local function context(uid)
 if test then return test.context(uid)end
 for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do
  if live(pc)and pc:HasAuthority()and guid(pc:GetPlayerUId())==uid then
   local inv=pc:GetPalPlayerState():GetInventoryData();assert(live(inv),'Player inventory unavailable')
   local im;for _,o in ipairs(FindAllOf('PalItemContainerManager')or{})do if live(o)then assert(not im,'Ambiguous item manager');im=o end end
   assert(live(im),'Item manager unavailable')
   local bag=im:GetContainer({ID=R.guid_from_string(guid(inv.MyInventoryInfo.CommonContainerId.ID))});assert(live(bag),'Player bag unavailable')
   return inv,bag,pc,im
  end
 end
 error('Player must be connected to BridgeLab; transaction remains reserved')
end
local function sources(bag,pc,im,include_base)
 if test then return test.sources(bag,pc,im,include_base)end
 local containers={bag};local seen={[guid(bag:GetId().ID)]=true};local base_id
 if include_base then
  local guild=pc:GetPalPlayerState().GuildBelongTo;assert(live(pc.Pawn),'Player pawn unavailable');local pos=pc.Pawn:K2_GetActorLocation()
  if live(guild)and guild:HasGuildPermission(pc:GetPlayerUId(),4)then
   local group=guid(guild:GetId())
   for _,b in ipairs(R.bases().bases or{})do
    if b.group_id==group and b.available and(b.position.x-pos.X)^2+(b.position.y-pos.Y)^2<=(b.range or 3500)^2 then base_id=b.id;break end
   end
   if base_id then
    local d=dofile(dir..'discovery.lua').discover({group_id=group});assert(d.ok,'Base containers unavailable')
    table.sort(d.targets.chests,function(a,b)return a.container_id<b.container_id end)
    for _,t in ipairs(d.targets.chests)do
     if t.base_id==base_id and not seen[t.container_id]and not excluded(t.container_id,t.model_id)then
      local c=im:GetContainer({ID=R.guid_from_string(t.container_id)})
      if live(c)then
       -- Existing reader verifies ordinary type, current base/guild and actual container binding.
       local check=R.chests({chests={t}},{include_items=false,require_snapshot_ownership=true})
       assert(check.ok,'Base container ownership could not be confirmed')
       containers[#containers+1]=c;seen[t.container_id]=true
      end
     end
    end
   end
  end
 end
 return containers,base_id
end
local function slot_data(s)
 local sid=s:GetSlotId();local n=s:GetStackCount();local iid=s:GetItemId()
 local out={container_id=guid(sid.ContainerId.ID),slot=sid.SlotIndex,count=n,item=n>0 and iid.StaticId:ToString()or''}
 assert(type(n)=='number'and n%1==0 and n>=0,'Invalid slot quantity')
 if n>0 then out.dynamic_guid=guid(iid.DynamicId.LocalIdInCreatedWorld);out.dynamic_world=guid(iid.DynamicId.CreatedWorldId)end
 return out
end
local function snapshot(containers)
 local out=J.array();for _,c in ipairs(containers)do for i=0,c:Num()-1 do out[#out+1]=slot_data(c:Get(i))end end;return out
end
local function count(containers,item)local n=0;for _,s in ipairs(snapshot(containers))do if s.item==item then n=n+s.count end end;return n end
 local commit=o.commit or Store.native_commit(ROOT,assert(config.durable_dll,'Durable WAL DLL path required'))
 local store=Store.new{root=ROOT,json=J,commit=commit,containers={c.container_id},fault=test and test.fault}
 local function attempt(lease,key)return (lease.operations[key]and lease.operations[key].attempt)or(lease.next_attempt and lease.next_attempt[key])or 1 end
 local credit={dll_path=config.credit_dll,runtime_verified=config.credit_verified==true,lab_candidate=config.lab_candidate==true,
  permit=function(lease,id)
   local proof=assert(read(ROOT..'escrow-credit-proof-'..lease.owner_tx..'-g'..lease.generation..'-a'..attempt(lease,'credit')..'.json'),'Actual saved MC debit permit is pending')
   assert(proof.native_request_id==id and proof.lease_generation==lease.generation,'Saved MC debit permit is stale');return proof
  end}
 local backend=o.backend or E.game_backend(R,credit,config.runtime_scope)
 local prior_fence=rawget(_G,'PalCraftEscrowFence')
 if prior_fence then assert(prior_fence.root==ROOT,'A different escrow root already owns RPC fences')end
 local rpc=o.rpc or (prior_fence and prior_fence.rpc)or(not test and E.rpc_guard{readers=R,current=store.get})
 if rpc then _G.PalCraftEscrowFence={root=ROOT,rpc=rpc}end
 local guard=o.guard or E.daily_guard{backend=backend,readers=R,excluded=excluded,rpc=rpc,epoch=epoch,
  evidence=config.isolation_evidence,lab_candidate=config.lab_candidate==true}
 local function saved_mc(kind,lease)
  local mc=read(ROOT..'mc-'..lease.owner_tx..'.json');if not mc or not match(mc,lease.tx)then return nil end
  local leg=kind=='mc_debit'and'debit'or'credit'
  if mc['mc_'..leg..'_durable']~=true or not mc['mc_'..leg..'_receipt']then return nil end
  local proof=read(ROOT..'escrow-mc-'..leg..'-proof-'..lease.owner_tx..'-g'..lease.generation..'.json')
  if not proof or proof.protocol~=3 or proof.id~=lease.owner_tx or proof.fingerprint~=lease.tx.fingerprint or
   proof.lease_generation~=lease.generation or proof.leg~=leg or proof.durable~=true or not same(proof.mc_receipt,mc['mc_'..leg..'_receipt'])then return nil end
  return proof
 end
 local function authorize(kind,lease,value)
  if o.authorize then return o.authorize(kind,lease,value)end
  if kind=='rehydrate'then
   local trusted=read(ROOT..'escrow-rearm-'..lease.owner_tx..'-g'..lease.generation..'-'..value.operation..'-a'..value.previous_attempt..'.json')
   return boot and boot.runtime_verified==true and boot.full_world_rehydrated==true and value.to_boot_id==boot_id and same(trusted,value)
  elseif kind=='terminal'then
   local mc=read(ROOT..'mc-'..lease.owner_tx..'.json');return mc and match(mc,lease.tx)and mc.state=='completed'and
    mc.escrow_empty_durable==true and mc.lease_generation==lease.generation and same(mc,value)
  elseif kind=='mc_debit'or kind=='mc_credit'then local proof=saved_mc(kind,lease);return proof and same(value,proof)
  elseif kind=='source'then
   if excluded(value.container_id)then return false end
   local _,bag,pc,im=context(lease.tx.player_uid);local valid=sources(bag,pc,im,true)
   for _,container in ipairs(valid)do if guid(container:GetId().ID)==value.container_id then return true end end
  end
  return false
 end
 local adapter=E.new{epoch=epoch,boot_id=boot_id,store=store,backend=backend,guard=guard,candidate=c,test_mode=test~=nil,
  lab_candidate=config.lab_candidate==true,authorize=authorize,request_id=request_id,
  accept_witness=function(lease,w)
   local saved=read(ROOT..'escrow-witness-'..lease.owner_tx..'-g'..lease.generation..'-'..lease.status..'.json')
   return same(saved,w)and same(w.lease_record,lease)and (not config.level_path or saved.save_path:gsub('\\','/'):lower()==config.level_path:gsub('\\','/'):lower())
  end}
 local api={store=store,adapter=adapter,exclusions=registry,running=true}
 local function emit(q,lease,status,reason)
  local row=copy(q);row.lease=lease;row.status=status or lease.status;row.ok=false;row.error=reason or lease.reason
  row.effect_attempted=next(lease.operations)~=nil;row.lease_generation=lease.generation
  if lease.status=='released'then row.ok=true;row.released=true;row.durable=true;row.escrow_empty_durable=true;row.error=nil end
  local previous=store.latest('pal-'..q.id)
  if not previous or not same(previous.lease,lease)or previous.status~=row.status or previous.error~=row.error then store.append('pal-'..q.id,row)else row=previous end
  return row
 end
 function api.handle(q)
  assert(IsInGameThread(),'Game thread required');assert(q.protocol==3,'Exchange v3 required')
  assert(type(q.id)=='string'and #q.id==36 and q.id:match('^[%x%-]+$'),'Transaction UUID required')
  local players=assert(read(ROOT..'players.json'));assert(players[q.mc_uid]==q.player_uid,'MC/Pal binding mismatch')
  local inv,bag,pc,im=context(q.player_uid);local containers,base=sources(bag,pc,im,q.action~='credit')
  if q.action=='snapshot'then local out=copy(q);out.ok=true;out.counts={};out.bag_counts={};out.base_id=base
   for item in pairs(allowed)do out.counts[item]=count(containers,item);out.bag_counts[item]=count({bag},item)end;return out
  end
  local mc=assert(read(ROOT..'mc-'..q.id..'.json'),'Durable MC intent required');assert(match(mc,q),'Durable MC identity mismatch')
  assert(mc.state=='waiting_pal'or mc.state=='waiting_pal_cleanup'or mc.state=='completed','MC phase is not ready')
  local prior=store.get_tx(q.id);if prior then assert(match(prior.tx,q),'Transaction payload reuse rejected')end
  local active=store.latest('pal-active')
  if active and active.event=='begin'and active.id~=q.id then local out=copy(q);out.status='busy';out.ok=false;out.error='另一笔材料仍在 escrow 中';return out end
  local current=store.get(c.container_id)
  if not prior and not test then
   local guild=pc:GetPalPlayerState().GuildBelongTo
   if not live(guild)or guid(guild:GetId())~=c.guild_id or not guild:HasGuildPermission(pc:GetPlayerUId(),4)then
    local out=copy(q);out.status='rejected';out.ok=false;out.error='当前公会没有已登记的材料中转箱';store.append('pal-'..q.id,out);return out
   end
  end
  if not prior and current and current.status~='released'then local out=copy(q);out.status='busy';out.ok=false;out.error='材料中转箱已保留';return out end
  if not prior and q.action=='debit'and count(containers,q.item)<q.count then
   local out=copy(q);out.status='rejected';out.ok=false;out.error='背包和当前基地材料不足';store.append('pal-'..q.id,out);return out
  end
  if not active or active.event~='begin'then store.append('pal-active',{event='begin',id=q.id})end
  local lease=prior or adapter.claim(q,{owner_uid=q.player_uid,guild_id=c.guild_id,base_id=c.source_base_id or c.base_id})
  if lease.status=='released'then
   local out=emit(q,lease,'completed');out.ok=true;out.released=true;out.durable=true;out.escrow_empty_durable=true
   if active and active.event=='begin'then store.append('pal-active',{event='end',id=q.id})end;return out
  end
  if lease.status=='claimed'then
   if q.action=='debit'then
    local froms={};local left=q.count
    for _,ref in ipairs(snapshot(containers))do if ref.item==q.item and left>0 and ref.dynamic_world==ZERO and ref.dynamic_guid==ZERO then
     local n=math.min(left,ref.count);froms[#froms+1]={before=ref,n=n};left=left-n end end
    if left>0 then return emit(q,lease,'claimed','原料暂不足，恢复真实库存后自动继续')end
    lease=adapter.moveIn(lease,froms,q.count)
   else local proof=saved_mc('mc_debit',lease);local permit=read(ROOT..'escrow-credit-proof-'..lease.owner_tx..'-g'..lease.generation..'-a'..attempt(lease,'credit')..'.json')
    if not proof or not permit then return emit(q,lease,'claimed','等待实际 MC 扣料收据和一次性产出许可')end
    lease=adapter.ensureCredit(lease,proof,q.count)
   end
  end
  local restart_pending=false
  if lease.status=='moving_in'or lease.status=='crediting'or lease.status=='disposing'or lease.status=='delivering'or lease.status=='needs_recovery'or lease.status=='full'or lease.status=='empty'then
   local key=({moving_in='moveIn',crediting='credit',disposing='dispose',delivering='deliver',
    full=q.action=='debit'and'moveIn'or'credit',empty=q.action=='debit'and'dispose'or'deliver'})[lease.status]
   if not key then for _,k in ipairs({'moveIn','credit','dispose','deliver'})do
    local op=lease.operations[k];local durable=(k=='moveIn'or k=='credit')and lease.full_witness or lease.empty_witness
    if op and not durable then key=k;break end
   end end
   local op=key and lease.operations[key]
   local durable=key and ((key=='moveIn'or key=='credit')and lease.full_witness or lease.empty_witness)
   if op and not durable then
    restart_pending=boot_id~=nil and op.boot_id~=nil and op.boot_id~=boot_id and op.epoch~=epoch
    local proof=read(ROOT..'escrow-rearm-'..lease.owner_tx..'-g'..lease.generation..'-'..key..'-a'..(lease.operations[key].attempt or 1)..'.json')
    if restart_pending and proof and proof.lease_revision==lease.revision and proof.to_boot_id==boot_id and proof.to_epoch==epoch then
     lease=adapter.rearm(lease,key,proof);restart_pending=false
    elseif not op.observed then lease=adapter.reconcile(lease,key)end
   end
  end
  if lease.status=='full'or lease.status=='empty'then
   local w=read(ROOT..'escrow-witness-'..lease.owner_tx..'-g'..lease.generation..'-'..lease.status..'.json')
   if w and E.witness_matches(lease,w)then lease=adapter.acceptWitness(lease,w)
   else
    if restart_pending then return emit(q,lease,lease.status,'等待新进程原 checkpoint 核验，保留存档与中转材料')end
    mailbox(ROOT..'save-request.json',{protocol=3,id=q.id,fingerprint=q.fingerprint,lease_generation=lease.generation,lease_revision=lease.revision,stage=lease.status,not_before_unix=lease.save_after_unix});return emit(q,lease,lease.status,'等待中转箱实际存档确认')
   end
  end
  if lease.status=='full_saved'then
   if q.action=='debit'then local proof=saved_mc('mc_credit',lease);if proof then lease=adapter.dispose(lease,proof,q.count)else return emit(q,lease,'full_saved','中转原料已落盘，等待 MC 真实入包收据')end
   else lease=adapter.deliver(lease,guid(bag:GetId().ID),q.count)end
  end
  if lease.status=='empty_saved'and mc.state=='completed'and mc.escrow_empty_durable==true then lease=adapter.release(lease,mc)end
  lease=assert(store.get(c.container_id)) -- Emit the exact installed durable row, including timestamps.
  if lease.status=='released'then
   local out=emit(q,lease,'completed');out.ok=true;out.released=true;out.durable=true;out.escrow_empty_durable=true
   store.append('pal-active',{event='end',id=q.id});return out
  end
  return emit(q,lease)
 end
 local last=0
 function api.tick()
  if os.time()==last then return end;last=os.time();local q=read(ROOT..'request.json');if not q or q.protocol~=3 or type(q.id)~='string'or #q.id~=36 or not q.id:match('^[%x%-]+$')then return end
  local ok,row=pcall(api.handle,q);if not ok then local reason=tostring(row);row=copy(q);row.ok=false;row.status='pending';row.error=reason end
  mailbox(ROOT..'result-'..q.id..'.json',row)
 end
 function api.stop()
  local held=store.get(c.container_id)
  if rpc and (not held or held.status=='released')then rpc.close();_G.PalCraftEscrowFence=nil else api.held_fence=rpc~=nil end
  api.running=false
 end
 -- Restore the exclusive guard before admitting normal RPCs after a boot.
 local held=store.get(c.container_id);if held and held.status~='released'then guard.inspect(held)end
 return api
end
return M
