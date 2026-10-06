-- v2 survival exchange. Native calls are attempted once; durable save witnesses release MC.
-- Pal JSON revisions are immutable: no remove-before-rename window in the authoritative WAL.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local test=rawget(_G,'PALCRAFT_EXCHANGE_TEST')
if not test then assert(dir:gsub('\\','/'):lower():find('d:/palworldserver-lan/bridgelab/',1,true),'BridgeLab only')end
local J=test and(test.json or dofile(test.json_path))or dofile(dir..'json.lua')
local R=test and test.readers or dofile(dir..'readers.lua')
local ROOT=test and test.root or 'D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange/'
local allowed={Wood=true,Stone=true,Coal=true,Charcoal=true}
local identity={'protocol','id','mc_uid','player_uid','mc_world','item','count','action','fingerprint'}
local epoch=test and test.epoch or (tostring(os.time())..':'..tostring({}))
local function fault(point,row)if test and test.fault then test.fault(point,row)end end
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function exists(p)local f=io.open(p,'rb');if not f then return false end;f:close();return true end
local function read(p)
 local f=io.open(p,'rb');if not f then return nil end
 local s=f:read('*a');f:close();return J.decode(s)
end
local function create(p,v)
 assert(not exists(p),'Immutable journal revision already exists')
 local f=assert(io.open(p..'.tmp','wb'));assert(f:write(J.encode(v)));assert(f:flush());assert(f:close())
 assert(os.rename(p..'.tmp',p));fault('wal:'..tostring(v.status or v.event),v)
end
local function mailbox(p,v)
 local f=assert(io.open(p..'.tmp','wb'));assert(f:write(J.encode(v)));assert(f:flush());assert(f:close())
 -- Mailbox loss is recoverable from immutable WAL, unlike loss of an authoritative record.
 os.remove(p);assert(os.rename(p..'.tmp',p))
end
local cache={}
local function latest(prefix)
 local row=cache[prefix];local seq=row and row.revision or 0
 while exists(prefix..string.format('.r%06d.json',seq+1))do
  seq=seq+1;row=assert(read(prefix..string.format('.r%06d.json',seq)))
  assert(row.revision==seq,'Journal revision is corrupt')
 end
 if row then cache[prefix]=row end;return row
end
local function append(prefix,row)
 local previous=latest(prefix);row.revision=(previous and previous.revision or 0)+1
 row.updated_unix=os.time();create(prefix..string.format('.r%06d.json',row.revision),row);cache[prefix]=row
end
local function pal_prefix(id)return ROOT..'pal-'..id end
local function save(row)append(pal_prefix(row.id),row)end
local function copy(q)local row={};for _,k in ipairs(identity)do row[k]=q[k]end;return row end
local function match(a,b)for _,k in ipairs(identity)do if a[k]~=b[k]then return false end end;return true end
local function guid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D})end
local function validate(q)
 assert(type(q)=='table'and q.protocol==2,'Exchange protocol v2 required; old incomplete transactions must be audited')
 assert(type(q.id)=='string'and #q.id==36 and q.id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'Transaction ID required')
 assert(type(q.mc_uid)=='string'and type(q.player_uid)=='string'and type(q.mc_world)=='string','Bound player/world identity required')
 assert(type(q.fingerprint)=='string'and #q.fingerprint==64 and q.fingerprint:match('^%x+$'),'Transaction fingerprint required')
 local identities=assert(read(ROOT..'players.json'),'Player binding unavailable')
 assert(identities[q.mc_uid]==q.player_uid,'MC/Pal player binding mismatch')
 if q.action=='snapshot'then assert(q.count==0 and q.item=='','Invalid balance request');return end
 assert(q.action=='debit'or q.action=='credit','Unknown exchange action')
 assert(allowed[q.item],'Unknown exchange material')
 assert(type(q.count)=='number'and q.count%1==0 and q.count>0 and q.count<=64,'Quantity must be 1..64')
end
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
     if t.base_id==base_id and not seen[t.container_id]then
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
local function component()
 if test then return test.component()end
 for _,t in ipairs(FindAllOf('PalNetworkTransmitter')or{})do
  if live(t)and t:HasAuthority()then local o=t:GetOwner();if live(o)and o:GetFullName():find('BP_PalGameStateInGame',1,true)then return t:GetItem()end end
 end
 error('Item authority unavailable')
end
local function active()
 local row=latest(ROOT..'pal-active');return row and row.event=='begin'and row.id or nil
end
local function release(id)
 if active()==id then append(ROOT..'pal-active',{event='end',id=id})end
end
local function acquire(q)
 local id=active()
 if id and id~=q.id then
  local old=latest(pal_prefix(id))
  if old and(old.status=='completed'or old.status=='rejected')then release(id);id=nil end
 end
 if id and id~=q.id then
  local out=copy(q);out.ok=false;out.status='busy';out.error='另一笔材料交易尚未确认：'..id;return out
 end
 if not id then append(ROOT..'pal-active',{event='begin',id=q.id})end
end
local function hold(row,text)
 if row.status~='needs_recovery'or row.error~=text then row.status='needs_recovery';row.error=text;row.ok=false;save(row)end
 return row
end
local save_requests={}
local function request_save(pc,row)
 if test then return test.request_save(row)end
 if os.time()-(save_requests[row.id]or 0)<3 then return end;save_requests[row.id]=os.time()
 -- The watcher requests immediate REST/save after this barrier. StartWorldDataAutoSave's
 -- timer semantics and save-complete delegates have not been runtime verified here.
 mailbox(ROOT..'save-request.json',{protocol=2,id=row.id,fingerprint=row.fingerprint,
  pal_revision=row.revision,not_before_unix=row.save_after_unix,kind='bridgelab_rest_save'})
end
local function witness(row)
 local w=read(ROOT..'witness-'..row.id..'.json')
 if not w then return false end
 return row.effect_observed==true and w.protocol==2 and w.id==row.id and w.fingerprint==row.fingerprint and
  w.pal_revision==row.revision and w.durable==true and type(w.save_sha256)=='string'and #w.save_sha256==64 and
  J.encode(w.expected_after)==J.encode(row.expected_after)
end
local function find_slot(im,ref)
 local c=im:GetContainer({ID=R.guid_from_string(ref.container_id)});assert(live(c),'Planned container is unavailable')
 assert(ref.slot>=0 and ref.slot<c:Num(),'Planned slot is unavailable');return c:Get(ref.slot)
end
local M={}
function M.handle(q)
 assert(IsInGameThread(),'Game thread required');validate(q)
 local old=latest(pal_prefix(q.id))
 if old then assert(match(old,q),'Transaction ID cannot be reused with another payload')end
 if not old and exists(ROOT..'pal-'..q.id..'.json')then
  local out=copy(q);out.ok=false;out.status='needs_recovery';out.error='旧版帕鲁记录没有落盘收据，已隔离';return out
 end
 if old and(old.status=='completed'or old.status=='rejected')then release(old.id);return old end
 if q.action~='snapshot'then local busy=acquire(q);if busy then return busy end end
 local inv,bag,pc,im=context(q.player_uid)
 local containers,base_id=sources(bag,pc,im,q.action~='credit')
 if q.action=='snapshot'then
  local out=copy(q);out.ok=true;out.counts={};out.bag_counts={};out.base_id=base_id
  for item in pairs(allowed)do out.counts[item]=count(containers,item);out.bag_counts[item]=count({bag},item)end;return out
 end
 local row=old
 if not row then
  local mc=assert(read(ROOT..'mc-'..q.id..'.json'),'Durable MC coordinator intent required')
  assert(match(mc,q)and mc.state=='waiting_pal','MC coordinator intent mismatch')
  assert(q.action~='credit'or mc.mc_debit_durable==true,'Durable MC source debit required before Pal credit')
  row=copy(q);row.ok=false;row.status='prepared';row.base_id=base_id;row.scope=q.action=='debit'and'backpack_then_current_guild_base'or'backpack'
  row.before=count(containers,q.item);row.before_slots=snapshot(containers);row.steps=J.array();row.epoch=epoch
  if q.action=='debit'then
   if row.before<q.count then row.status='rejected';row.error='背包和当前基地材料不足';save(row);release(row.id);return row end
   local remaining=q.count
   for _,ref in ipairs(row.before_slots)do
    if ref.item==q.item and remaining>0 then
     local n=math.min(remaining,ref.count);row.steps[#row.steps+1]={before=ref,n=n};remaining=remaining-n
    end
   end
   assert(remaining==0,'Inventory changed')
  else
   local capacity=0
   for i=0,bag:Num()-1 do local s=bag:Get(i);local n=s:GetStackCount()
    if n==0 then capacity=capacity+q.count elseif s:GetItemId().StaticId:ToString()==q.item then capacity=capacity+s:GetMaxStack()-n end
   end
   if capacity<q.count then row.status='rejected';row.error='帕鲁背包空间不足';save(row);release(row.id);return row end
  end
  save(row)
 end
 if row.status=='needs_recovery'then return row end
 if row.status=='awaiting_pal_save'then
  if witness(row)then
   row.status='completed';row.durable=true;row.ok=true;row.error=nil;row.recovery_required=nil;row.save_witness=read(ROOT..'witness-'..row.id..'.json');save(row);release(row.id);return row
  end
  local blocked=read(ROOT..'witness-blocked-'..row.id..'.json')
  if blocked and blocked.pal_revision==row.revision and blocked.fingerprint==row.fingerprint and blocked.needs_inventory_audit==true then
   local message='材料槽在保存前已变化，交易已保留；需要核对原槽和正常搬动记录'
   if row.error~=message or not row.recovery_required then row.error=message;row.recovery_required=true;save(row)end
  end
  request_save(pc,row);return row
 end
 if row.effect_attempted and not row.effect_observed and row.action=='credit'then
  return hold(row,'帕鲁发放调用已发起但结果未确认；材料交易已保留，禁止自动重发')
 end
 if row.action=='credit'and not row.effect_attempted then
  -- Before an attempt there is no Pal effect to replay. Recheck the recipient after a restart.
  local current=snapshot({bag});local capacity=0
  for i=0,bag:Num()-1 do local s=bag:Get(i);local n=s:GetStackCount()
   if n==0 then capacity=capacity+row.count elseif s:GetItemId().StaticId:ToString()==row.item then capacity=capacity+s:GetMaxStack()-n end
  end
  if capacity<row.count then row.status='rejected';row.error='帕鲁背包空间不足';save(row);release(row.id);return row end
  if J.encode(current)~=J.encode(row.before_slots)then row.before_slots=current;row.before=count({bag},row.item);save(row)end
 end
 if row.action=='debit'then
  local eligible={};for _,c in ipairs(containers)do eligible[guid(c:GetId().ID)]=true end
  for i,step in ipairs(row.steps)do
   if not step.observed then
    if step.attempted then return hold(row,'第 '..i..' 个材料扣除调用结果不明；保留逐槽记录，禁止重复扣除')end
    if not eligible[step.before.container_id]then return hold(row,'原材料容器已不属于当前可用背包/基地，交易已保留')end
    local s=find_slot(im,step.before)
    if J.encode(slot_data(s))~=J.encode(step.before)then return hold(row,'计划扣除的原材料槽已变化，交易已保留')end
    row.status='applying';row.effect_attempted=true;step.attempted=true;step.epoch=epoch;save(row)
    local request_id=R.guid_from_string(row.id)
    -- Distinct deterministic native request IDs, in addition to the durable attempt-once guard.
    request_id.D=(request_id.D+i)%4294967296
    component():RequestDispose_ToServer(request_id,{SlotId=s:GetSlotId(),Num=step.n});fault('native:debit:'..i,row)
    local after=slot_data(s)
    if after.count~=step.before.count-step.n or(after.count>0 and after.item~=row.item)then return hold(row,'帕鲁扣除数量尚未确认，交易已保留')end
    step.after=after;step.observed=true;save(row);fault('observed:debit:'..i,row)
   end
  end
  row.expected_after=J.array();for _,step in ipairs(row.steps)do row.expected_after[#row.expected_after+1]=step.after end
 else
  row.status='applying';row.effect_attempted=true;save(row)
  inv:AddItem_ServerInternal(FName(row.item),row.count,false,0,true);fault('native:credit',row)
  local after=snapshot({bag});local total=0;row.expected_after=J.array()
  for i,ref in ipairs(after)do
   local before=row.before_slots[i]
   if J.encode(ref)~=J.encode(before)then
    if (before.count>0 and before.item~=row.item)or(ref.count>0 and ref.item~=row.item)or ref.count<before.count then return hold(row,'帕鲁发放槽与原始计划不一致，交易已保留')end
    total=total+ref.count-before.count;row.expected_after[#row.expected_after+1]=ref
   end
  end
  if total~=row.count then return hold(row,'帕鲁发放数量尚未确认，交易已保留')end
 end
 row.effect_observed=true;row.status='awaiting_pal_save';row.after=row.before+(row.action=='debit'and-row.count or row.count)
 row.save_after_unix=os.time()+1
 row.error='材料变更已确认，等待帕鲁实际存档落盘';save(row);request_save(pc,row);return row
end
local last_tick=0
function M.tick()
 if os.time()==last_tick then return end;last_tick=os.time()
 local q=read(ROOT..'request.json');if not q then return end
 if type(q.id)~='string'or #q.id~=36 or not q.id:match('^[%x%-]+$')then return end
 -- Pending results are refreshed. A previous temporary error must not permanently suppress recovery.
 local ok,r=pcall(M.handle,q)
 if not ok then local err=tostring(r);r=copy(q);r.ok=false;r.status='error';r.error=err end
 mailbox(ROOT..'result-'..q.id..'.json',r)
end
return M
