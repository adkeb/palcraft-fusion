local M=dofile(arg[1])
local J=dofile(arg[2])
local ZERO='00000000-0000-0000-0000-000000000000'
local CID='00000000-0000-4000-8000-000000000016'
local SOURCE='11111111-1111-4111-8111-111111111111'
local BAG='22222222-2222-4222-8222-222222222222'
local UID='33333333-3333-4333-8333-333333333333'
local TX='44444444-4444-4444-8444-444444444444'
local BASE='55555555-5555-4555-8555-555555555555'
local GUILD='00000000-0000-4000-8000-00000000001b'
local function clone(v)return J.decode(J.encode(v))end
local function deep_same(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not deep_same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function slot(cid,i,n,item)return n==0 and{container_id=cid,slot=i,count=0,item=''}or{container_id=cid,slot=i,count=n,item=item or'Wood',dynamic_guid=ZERO,dynamic_world=ZERO}end
local function setup(direction)
 local f={rows={},txs={},calls={move=0,credit=0,dispose=0},fail=nil,occupied=false,capacity=999,now=100,epoch='one',model_exists=true,boot_n=1,reloads=0}
 f.boot_id='aaaaaaaa-aaaa-4aaa-8aaa-000000000001'
 local c={model_id='00000000-0000-4000-8000-00000000000c',concrete_id='00000000-0000-4000-8000-000000000028',container_id=CID,
  type='ItemChest',capacity=10,base_id=ZERO,source_base_id=BASE,guild_id=GUILD,position={x=100000,y=0,z=100},enrollment_save_sha256=string.rep('a',64)}
 f.candidate=c
 f.slots={[CID..':0']=slot(CID,0,0),[SOURCE..':0']=slot(SOURCE,0,50),[BAG..':0']=slot(BAG,0,0)}
 local store={}
 function store.get(cid)return f.rows[cid]and clone(f.rows[cid])end
 function store.get_tx(id)return f.txs[id]and clone(f.txs[id])end
 function store.cas(cid,rev,row)
  assert((f.rows[cid]and f.rows[cid].revision or 0)==rev)
  if f.fail=='persist'then return false end
  f.rows[cid]=clone(row);f.txs[row.owner_tx]=clone(row)
  if f.fail=='after_intent'and(row.status=='moving_in'or row.status=='crediting'or row.status=='disposing'or row.status=='delivering')then f.fail=nil;error('power cut after durable intent')end
  return true
 end
 local b={credit_verified=true}
 function b.chest(candidate)
  assert(f.model_exists,'model destroyed');assert(not f.rebound,'module points at another container');assert(not f.moved,'escrow relocated')
  return {candidate=clone(candidate),slots={clone(f.slots[CID..':0']),slot(CID,1,f.occupied and 1 or 0)}}
 end
 function b.slot(ref)return clone(assert(f.slots[ref.container_id..':'..ref.slot]))end
 function b.bag(owner,cid)assert(owner==UID and cid==BAG);return {{before=clone(f.slots[BAG..':0']),max_stack=f.capacity}}end
 function b.move(_,to,froms)
  f.calls.move=f.calls.move+1
  if f.fail=='no_effect'then return end
  for _,s in ipairs(froms)do
   local k=s.before.container_id..':'..s.before.slot;local current=f.slots[k]
   current.count=current.count-s.n;if current.count==0 then f.slots[k]=slot(current.container_id,current.slot,0)end
   local tk=to.container_id..':'..to.slot;local target=f.slots[tk]
   f.slots[tk]=slot(to.container_id,to.slot,target.count+s.n)
  end
  if f.fail=='after_native'then f.fail=nil;error('power cut after native Move')end
 end
 function b.credit(row,_,n)
  f.calls.credit=f.calls.credit+1;f.slots[CID..':0']=slot(CID,0,n)
  if f.fail=='after_native'then f.fail=nil;error('power cut after native credit')end
 end
 function b.dispose(_,_,n)
  f.calls.dispose=f.calls.dispose+1;assert(f.slots[CID..':0'].count==n);f.slots[CID..':0']=slot(CID,0,0)
  if f.fail=='after_native'then f.fail=nil;error('power cut after native disposal')end
 end
 local g={}
 function g.inspect(row)
  local out={runtime_verified=not f.isolation_lost,active=true,epoch=f.epoch,owner_tx=row.owner_tx,generation=row.generation,container_id=CID}
  for _,k in ipairs({'player_open','pal_transport','craft_consume','ai_organize','restart'})do out[k]=true end
  return out
 end
 function g.with_permit(_,_,fn)return fn()end
 local opts={test_mode=true,candidate=c,epoch=f.epoch,boot_id=f.boot_id,store=store,backend=b,guard=g,now=function()return f.now end,
  authorize=function(kind,_,proof)return kind=='source'or proof and proof.valid==true end,
  accept_witness=function(row,w)return not f.require_record or deep_same(row,w.lease_record)end,
  request_id=function(_,_,attempt)return f.request_override or('66666666-6666-4666-8666-'..string.format('%012d',attempt or 1))end}
 function f.reload(real_boot)
  f.reloads=f.reloads+1;f.epoch='reload:'..f.reloads
  if real_boot~=false then f.boot_n=f.boot_n+1;f.boot_id='aaaaaaaa-aaaa-4aaa-8aaa-'..string.format('%012d',f.boot_n)end
  opts.epoch=f.epoch;opts.boot_id=f.boot_id;f.api=M.new(opts)
 end
 f.api=M.new(opts)
 f.tx={protocol=3,id=TX,mc_uid='77777777-7777-4777-8777-777777777777',player_uid=UID,mc_world='fixture',action=direction or'debit',item='Wood',count=16,fingerprint=string.rep('b',64)}
 f.binding={owner_uid=UID,guild_id=GUILD,base_id=BASE}
 function f.claim()f.lease=f.api.claim(f.tx,f.binding);return f.lease end
 function f.import()f.lease=f.api.moveIn(f.lease,{{before=clone(f.slots[SOURCE..':0']),n=16}},16);return f.lease end
 function f.credit()f.lease=f.api.ensureCredit(f.lease,{valid=true},16);return f.lease end
 function f.witness(stage)
  local row=store.get(CID)
  local w={protocol=3,id=TX,fingerprint=f.tx.fingerprint,lease_generation=row.generation,lease_revision=row.revision,container_id=CID,
   slot=0,stage=stage,expected_after=clone(row.expected_after),durable=true,same_level_counterpart=true,save_sha256=string.rep('c',64)}
  return w
 end
 function f.saved(stage)f.lease=f.api.acceptWitness(f.lease,f.witness(stage));return f.lease end
 function f.proof(key)
  local row=store.get(CID);local op=row.operations[key];local refs={}
  if key=='moveIn'then for _,s in ipairs(op.details)do refs[#refs+1]=clone(s.before)end elseif key=='deliver'then refs[1]=clone(op.details.to)end
  return {valid=true,protocol=3,kind='escrow_rearm_after_world_rehydrate',proof_id='bbbbbbbb-bbbb-4bbb-8bbb-'..string.format('%012d',f.boot_n),
   id=TX,fingerprint=f.tx.fingerprint,container_id=CID,slot=0,lease_generation=row.generation,lease_revision=row.revision,
   operation=key,previous_attempt=op.attempt,previous_request_id=op.request_id,previous_observed=op.observed==true,from_epoch=op.epoch,to_epoch=f.epoch,
   from_boot_id=op.boot_id,to_boot_id=f.boot_id,full_world_rehydrated=true,loaded_level_sha256=string.rep('d',64),
   installed_level_sha256=string.rep('d',64),boot_certificate_sha256=string.rep('e',64),checkpoint_mtime_ns=(op.attempted_unix-1)*1000000000,
   saved_before=clone(op.before),counterpart_before=refs}
 end
 return f
end
local passed=0
local function test(name,fn)
 if arg[3]and not name:find(arg[3],1,true)then return end
 local ok,e=pcall(fn);if not ok then error(name..': '..tostring(e))end;passed=passed+1;print('PASS '..name)
end
local function refused(fn)local ok=pcall(fn);assert(not ok,'expected refusal')end
local function terminal(f)return {valid=true,protocol=3,id=f.tx.id,fingerprint=f.tx.fingerprint,lease_generation=f.lease.generation,state='completed',escrow_empty_durable=true}end
test('import two barriers and real-material conservation',function()
 local f=setup();f.claim();f.import();assert(f.slots[SOURCE..':0'].count==34 and f.slots[CID..':0'].count==16)
 refused(function()f.api.dispose(f.lease,{valid=true},16)end);f.saved('full')
 f.lease=f.api.dispose(f.lease,{valid=true},16);refused(function()f.api.release(f.lease,{valid=true})end)
 f.saved('empty');f.lease=f.api.release(f.lease,terminal(f));assert(f.lease.status=='released'and f.calls.dispose==1)
end)
test('export direct escrow never stages in bag',function()
 local f=setup('credit');f.claim();f.credit();assert(f.calls.credit==1 and f.slots[BAG..':0'].count==0)
 f.saved('full');f.lease=f.api.deliver(f.lease,BAG,16);assert(f.slots[BAG..':0'].count==16 and f.slots[CID..':0'].count==0)
 f.saved('empty');f.api.release(f.lease,terminal(f))
end)
test('source production and recipient sorting are independent of receipt',function()
 local f=setup();f.claim();f.import();f.slots[SOURCE..':0'].count=200;f.saved('full');assert(f.lease.status=='full_saved')
 local e=setup('credit');e.claim();e.credit();e.saved('full');e.lease=e.api.deliver(e.lease,BAG,16);e.slots[BAG..':0']=slot(BAG,0,0);e.saved('empty');assert(e.lease.status=='empty_saved')
end)
test('empty intent with no effect is held without replay after restart',function()
 local f=setup();f.claim();f.fail='after_intent';refused(function()f.import()end);f.reload()
 local out=f.api.reconcile(f.lease,'moveIn');assert(out.status=='needs_recovery'and f.calls.move==0)
 refused(function()f.api.claim({protocol=2},f.binding)end)
end)
test('saved native Move intent with lost response reconciles only own escrow',function()
 local f=setup();f.claim();f.fail='after_native';refused(function()f.import()end);f.slots[SOURCE..':0'].count=150;f.reload()
 f.lease=f.api.reconcile(f.lease,'moveIn');assert(f.lease.status=='full'and f.calls.move==1);f.api.reconcile(f.lease,'moveIn');assert(f.calls.move==1)
end)
test('direct credit power cut never creates a second stack',function()
 local f=setup('credit');f.claim();f.fail='after_native';refused(function()f.credit()end);f.reload();f.lease=f.api.reconcile(f.lease,'credit')
 assert(f.lease.status=='full'and f.calls.credit==1);f.api.ensureCredit(f.lease,{valid=true},16);assert(f.calls.credit==1)
end)
test('disposal power cut recovers desired empty once',function()
 local f=setup();f.claim();f.import();f.saved('full');f.fail='after_native';refused(function()f.api.dispose(f.lease,{valid=true},16)end)
 f.reload();f.lease=f.api.reconcile(f.lease,'dispose');assert(f.lease.status=='empty'and f.calls.dispose==1)
end)
test('delivery power cut tolerates lawful bag movement',function()
 local f=setup('credit');f.claim();f.credit();f.saved('full');f.fail='after_native';refused(function()f.api.deliver(f.lease,BAG,16)end)
 f.slots[BAG..':0']=slot(BAG,0,0);f.reload();f.lease=f.api.reconcile(f.lease,'deliver');assert(f.lease.status=='empty'and f.calls.move==1)
end)
test('occupied enrollment does not consume anyone materials',function()
 local f=setup();f.occupied=true;refused(function()f.claim()end);assert(f.calls.move==0 and not f.rows[CID])
end)
test('lease conflict preserves first transaction',function()
 local f=setup();f.claim();local q=clone(f.tx);q.id='88888888-8888-4888-8888-888888888888';refused(function()f.api.claim(q,f.binding)end);assert(f.rows[CID].owner_tx==TX)
end)
test('reused transaction with changed payload is refused',function()
 local f=setup();f.claim();f.tx.count=17;refused(function()f.claim()end)
end)
test('persist failure forbids native calls',function()
 local f=setup();f.claim();f.fail='persist';refused(function()f.import()end);assert(f.calls.move==0)
end)
test('material changed before Move is refused',function()
 local f=setup();f.claim();local before=clone(f.slots[SOURCE..':0']);f.slots[SOURCE..':0'].count=49
 refused(function()f.api.moveIn(f.lease,{{before=before,n=16}},16)end);assert(f.calls.move==0)
end)
test('duplicate source cannot manufacture aggregate quantity',function()
 local f=setup();f.claim();local s={before=clone(f.slots[SOURCE..':0']),n=8}
 refused(function()f.api.moveIn(f.lease,{s,s},16)end);assert(f.calls.move==0)
end)
test('destroyed, rebound, relocated containers do not acquire replacement leases',function()
 for _,key in ipairs({'model_exists','rebound','moved'})do local f=setup();f.claim();if key=='model_exists'then f[key]=false else f[key]=true end
  refused(function()f.import()end);assert(f.rows[CID].generation==1 and f.calls.move==0)
 end
end)
test('lost everyday access isolation retains lease and refuses effects',function()
 local f=setup();f.claim();f.isolation_lost=true;refused(function()f.import()end);assert(f.calls.move==0 and f.rows[CID].status=='claimed')
end)
test('MC durable receipts precede creation and disposal',function()
 local f=setup('credit');f.claim();refused(function()f.api.ensureCredit(f.lease,{valid=false},16)end);assert(f.calls.credit==0)
 local d=setup();d.claim();d.import();d.saved('full');refused(function()d.api.dispose(d.lease,{valid=false},16)end);assert(d.calls.dispose==0)
end)
test('recipient capacity waits without discarding full escrow',function()
 local f=setup('credit');f.claim();f.credit();f.saved('full');f.slots[BAG..':0']=slot(BAG,0,999);f.capacity=999
 f.lease=f.api.deliver(f.lease,BAG,16);assert(f.lease.status=='full_saved'and f.calls.move==0 and f.slots[CID..':0'].count==16)
 f.capacity=2000;f.lease=f.api.deliver(f.lease,BAG,16);assert(f.lease.status=='empty'and f.calls.move==1)
end)
test('late full witness cannot acknowledge empty or recycled generation',function()
 local f=setup();f.claim();f.import();local late=f.witness('full');f.saved('full');f.lease=f.api.dispose(f.lease,{valid=true},16)
 refused(function()f.api.acceptWitness(f.lease,late)end);f.saved('empty');local old=f.lease;f.api.release(old,terminal(f))
 f.tx.id='99999999-9999-4999-8999-999999999999';f.claim();assert(f.lease.generation==2)
 refused(function()f.api.acceptWitness(f.lease,late)end);refused(function()f.api.read(old)end)
end)
test('wrong witness revision or save digest never completes stage',function()
 for _,key in ipairs({'lease_revision','lease_generation','fingerprint','save_sha256','container_id','stage'})do
  local f=setup();f.claim();f.import();local w=f.witness('full');if type(w[key])=='number'then w[key]=w[key]+1 else w[key]='bad'end
  refused(function()f.api.acceptWitness(f.lease,w)end);assert(f.rows[CID].status=='full')
 end
end)
test('v2 terminal status never releases v3 lease',function()
 local f=setup();f.claim();f.import();f.saved('full');f.lease=f.api.dispose(f.lease,{valid=true},16);f.saved('empty')
 local receipt=terminal(f);receipt.protocol=2;refused(function()f.api.release(f.lease,receipt)end)
 receipt=terminal(f);receipt.lease_generation=0;refused(function()f.api.release(f.lease,receipt)end);assert(f.rows[CID].status=='empty_saved')
end)
test('unexpected additional occupied slot is held',function()
 local f=setup();f.claim();f.occupied=true;refused(function()f.import()end);assert(f.calls.move==0)
end)
test('no effect result retains intent and never retries',function()
 local f=setup();f.claim();f.fail='no_effect';f.import();assert(f.lease.status=='needs_recovery'and f.calls.move==1)
 f.fail=nil;f.api.moveIn(f.lease,{{before=clone(f.slots[SOURCE..':0']),n=16}},16);assert(f.calls.move==1)
end)
test('actual daily profile is enabled by successful normal gameplay evidence',function()
 local f=setup();f.claim();local access={actor_name='RealChestActor',private_locked=false,players={{private_denied=false}}}
 local evidence={runtime_verified=true,container_id=CID,model_id=f.candidate.model_id,player_open=true,pal_transport=true,craft_consume=true,ai_organize=true,restart=true}
 local rpc={install=function()return true end,refresh=function()end,inspect=function()return{installed=true}end}
 local g=M.daily_guard{rpc=rpc,backend={chest=function()return {access=access}end},epoch='one',readers={bases=function()return {ok=true,bases={{ok=true,range=3500,position={x=0,y=0,z=0}}}}end},evidence=evidence,excluded=function()return true end}
 assert(g.inspect(f.lease).runtime_verified==true)
 -- The actual owner can stay connected; ordinary inventory filtering is local
 -- to this container, independent of a private-lock owner or extra account.
 access.players[1].connected=true;assert(g.inspect(f.lease).runtime_verified==true)
end)
test('new base near an enrolled outside chest immediately stops exchange',function()
 local f=setup();f.claim();local evidence={runtime_verified=true,container_id=CID,model_id=f.candidate.model_id,player_open=true,pal_transport=true,craft_consume=true,ai_organize=true,restart=true}
 local g=M.daily_guard{backend={chest=function()return {access={private_locked_by_service=true,service_owner_connected=false,players={}}}end},epoch='one',readers={bases=function()return {ok=true,bases={{ok=true,range=3500,position={x=99000,y=0,z=0}}}}end},evidence=evidence,excluded=function()return true end}
 refused(function()g.inspect(f.lease)end)
end)
test('private lock alone without real AI exclusion does not enable escrow',function()
 local f=setup();f.claim();local evidence={runtime_verified=true,container_id=CID,model_id=f.candidate.model_id,player_open=true,pal_transport=true,craft_consume=true,ai_organize=true,restart=true}
 local g=M.daily_guard{backend={chest=function()return {access={private_locked_by_service=true,service_owner_connected=false,players={}}}end},epoch='one',readers={bases=function()return {ok=true,bases={}}end},evidence=evidence,excluded=function()return false end}
 refused(function()g.inspect(f.lease)end)
end)
test('explicit unverified Lab pilot is runnable with change-detection assurance',function()
 local f=setup();f.claim()
 local g=M.daily_guard{backend={chest=function()return {access={actor_name='RealChestActor'}}end},epoch='one',lab_candidate=true,
  readers={bases=function()return {ok=true,bases={}}end},excluded=function()return true end}
 local out=g.inspect(f.lease);assert(out.lab_candidate and not out.runtime_verified and out.scope:find('detection_only',1,true))
end)
local function rpc_fixture()
 local f=setup();f.claim();local callbacks={},nil
 local readers={guid_from_string=function(s)return {s=s}end,guid_to_string=function(g)return assert(g.s)end}
 local serial=0;local hooks={}
 local g=M.rpc_guard{readers=readers,current=function(cid)return f.rows[cid]end,
  register=function(path,fn)serial=serial+1;hooks[path]=fn;return serial,serial+100 end,
  unregister=function(path)hooks[path]=nil end}
 assert(g.install());g.refresh(f.lease,'RealChestActor')
 local function p(v)return {v=clone(v),get=function(self)return self.v end,set=function(self,x)self.v=clone(x)end}end
 local function sid(id)return {ContainerId={ID={s=id}},SlotIndex=0}end
 local function call(name,...)return assert(hooks['/Script/Pal.'..name])(...)end
 return f,g,p,sid,call
end
test('ordinary Move to and from reserved chest is blocked before game validator',function()
 local _,g,p,sid,call=rpc_fixture()
 for _,ids in ipairs({{SOURCE,CID},{CID,BAG}})do
  local to=p(sid(ids[2]));local from=p({{SlotId=sid(ids[1]),Num=16}})
  call('PalNetworkItemComponent:RequestMove_ToServer',nil,p({s=TX}),to,from)
  assert(to.v.SlotIndex==-1 and to.v.ContainerId.ID.s==ZERO and from.v[1].Num==16)
 end
 assert(g.inspect().counters.move_blocked==2)
end)
test('unrelated ordinary Move passes through unchanged',function()
 local _,g,p,sid,call=rpc_fixture();local to=p(sid(BAG));local from=p({{SlotId=sid(SOURCE),Num=16}})
 call('PalNetworkItemComponent:RequestMove_ToServer',nil,p({s=TX}),to,from)
 assert(to.v.ContainerId.ID.s==BAG and to.v.SlotIndex==0 and g.inspect().counters.move_blocked==0)
end)
test('transaction-local permit allows only recorded ordinary native RequestID',function()
 local f,g,p,sid,call=rpc_fixture();f.lease.operations.moveIn={request_id=TX,attempted=true}
 g.with_permit(f.lease,'moveIn',function()
  local to=p(sid(CID));call('PalNetworkItemComponent:RequestMove_ToServer',nil,p({s=TX}),to,p({{SlotId=sid(SOURCE),Num=16}}));assert(to.v.SlotIndex==0)
  local other=p(sid(CID));call('PalNetworkItemComponent:RequestMove_ToServer',nil,p({s=BAG}),other,p({{SlotId=sid(SOURCE),Num=16}}));assert(other.v.SlotIndex==-1)
 end)
 assert(g.inspect().counters.bridge_allowed==1)
 local to=p(sid(CID));call('PalNetworkItemComponent:RequestMove_ToServer',nil,p({s=TX}),to,p({{SlotId=sid(SOURCE),Num=16}}));assert(to.v.SlotIndex==-1)
end)
test('void-hook return is never used to cancel Drop Dispose Swap or quick stack',function()
 local _,g,p,sid,call=rpc_fixture();local info=p({SlotId=sid(CID),Num=16})
 call('PalNetworkItemComponent:RequestDispose_ToServer',nil,p({s=TX}),info);assert(info.v.Num==0 and info.v.SlotId.SlotIndex==-1)
 local drop=p({{SlotId=sid(CID),Num=16}});call('PalNetworkItemComponent:RequestDrop_ToServer',nil,drop);assert(#drop.v==0)
 local a=p(sid(CID));call('PalNetworkItemComponent:RequestSwap_ToServer',nil,p({s=TX}),a,p(sid(BAG)));assert(a.v.SlotIndex==-1)
 local to=p({ID={s=CID}});call('PalPlayerInventoryData:RequestFillSlotToTargetContainerFromInventory_ToServer',nil,to);assert(to.v.ID.s==ZERO)
 local container=p({ID={s=BAG}});call('PalNetworkItemComponent:RequestMoveToContainer_ToServer',nil,p({s=TX}),container,p({{SlotId=sid(CID),Num=16}}));assert(container.v.ID.s==ZERO)
 assert(g.inspect().counters.drop_blocked==1 and g.inspect().counters.dispose_blocked==1)
end)
test('interaction boolean is overridden only for held chest Actor',function()
 local f,g,_,_,call=rpc_fixture()
 local actor={GetFullName=function()return'RealChestActor'end,IsValid=function()return true end}
 local ctx={get=function()return {GetFullName=function()return'ChestComponent'end,GetOwner=function()return actor end}end}
 assert(call('PalInteractiveInterface:IsEnableTriggerInteract',ctx)==false)
 f.rows[CID].status='released';assert(call('PalInteractiveInterface:IsEnableTriggerInteract',ctx)==nil)
 assert(g.inspect().counters.interaction_blocked==1)
end)
test('fresh boot exact beforeimage can rearm with history and a new attempt ID',function()
 local f=setup();f.claim();f.fail='after_intent';refused(function()f.import()end);f.reload()
 local proof=f.proof('moveIn');f.lease=f.api.rearm(f.lease,proof)
 assert(f.lease.status=='claimed'and f.lease.generation==1 and f.lease.next_attempt.moveIn==2 and #f.lease.operation_history.moveIn==1 and f.calls.move==0)
 f.import();assert(f.lease.operations.moveIn.attempt==2 and f.lease.operations.moveIn.request_id~=f.lease.operation_history.moveIn[1].request_id and f.calls.move==1)
 refused(function()f.api.rearm(f.lease,'moveIn',proof)end)
end)
test('mod reload and same Pal boot cannot rearm an empty beforeimage',function()
 local f=setup();f.claim();f.fail='after_intent';refused(function()f.import()end);f.reload(false)
 refused(function()f.api.rearm(f.lease,'moveIn',f.proof('moveIn'))end);assert(f.calls.move==0 and f.rows[CID].operations.moveIn.attempt==1)
end)
test('fresh booleans or mismatched checkpoint cannot authorize replay',function()
 for _,key in ipairs({'valid','loaded_level_sha256','checkpoint_mtime_ns','lease_revision','previous_request_id','counterpart_before','saved_before'})do
  local f=setup();f.claim();f.fail='after_intent';refused(function()f.import()end);f.reload();local proof=f.proof('moveIn')
  if key=='valid'then proof.valid=false elseif key=='checkpoint_mtime_ns'then proof[key]=101000000000
  elseif key=='lease_revision'then proof[key]=proof[key]+1 elseif key=='counterpart_before'then proof[key][1].count=49
  elseif key=='saved_before'then proof[key]=slot(CID,0,1)else proof[key]='bad'end
  refused(function()f.api.rearm(f.lease,'moveIn',proof)end);assert(f.calls.move==0 and not f.rows[CID].operation_history)
 end
end)
test('a persisted afterimage reconciles and cannot be rearmed',function()
 local f=setup('credit');f.claim();f.fail='after_native';refused(function()f.credit()end);f.reload()
 refused(function()f.api.rearm(f.lease,'credit',f.proof('credit'))end);f.lease=f.api.reconcile(f.lease,'credit');assert(f.lease.status=='full'and f.calls.credit==1)
end)
test('genuine restore of unsaved credit creates only one surviving stack',function()
 local f=setup('credit');f.claim();f.fail='after_native';refused(function()f.credit()end)
 f.slots[CID..':0']=slot(CID,0,0);f.reload();f.lease=f.api.rearm(f.lease,'credit',f.proof('credit'));f.credit()
 assert(f.slots[CID..':0'].count==16 and f.calls.credit==2 and f.lease.operations.credit.attempt==2)
end)
test('restored unsaved disposal preserves the original MC credit prerequisite',function()
 local f=setup();f.claim();f.import();f.saved('full');f.fail='after_native';refused(function()f.api.dispose(f.lease,{valid=true},16)end)
 f.slots[CID..':0']=slot(CID,0,16);f.reload();f.lease=f.api.rearm(f.lease,'dispose',f.proof('dispose'))
 assert(f.lease.status=='full_saved'and f.lease.full_witness);f.lease=f.api.dispose(f.lease,{valid=true},16)
 assert(f.slots[CID..':0'].count==0 and f.calls.dispose==2)
end)
test('restored unsaved delivery retries only after matching saved bag beforeimage',function()
 local f=setup('credit');f.claim();f.credit();f.saved('full');f.fail='after_native';refused(function()f.api.deliver(f.lease,BAG,16)end)
 f.slots[CID..':0']=slot(CID,0,16);f.slots[BAG..':0']=slot(BAG,0,0);f.reload();f.lease=f.api.rearm(f.lease,'deliver',f.proof('deliver'))
 f.lease=f.api.deliver(f.lease,BAG,16);assert(f.slots[BAG..':0'].count==16 and f.calls.move==2)
end)
test('a callback that reuses old RequestID is rejected before native replay',function()
 local f=setup();f.claim();f.fail='after_intent';refused(function()f.import()end);f.request_override=f.rows[CID].operations.moveIn.request_id;f.reload()
 f.lease=f.api.rearm(f.lease,'moveIn',f.proof('moveIn'));refused(function()f.import()end);assert(f.calls.move==0)
end)
test('pending beforeimage reconciliation keeps a stable revision for proof generation',function()
 local f=setup();f.claim();f.fail='after_intent';refused(function()f.import()end);f.reload()
 f.lease=f.api.reconcile(f.lease,'moveIn');local revision=f.lease.revision
 f.lease=f.api.reconcile(f.lease,'moveIn');assert(f.lease.revision==revision)
 f.lease=f.api.rearm(f.lease,'moveIn',f.proof('moveIn'));assert(f.lease.revision==revision+1)
end)
test('a rehydration proof ID cannot be recycled across later boot attempts',function()
 local f=setup();f.claim();f.fail='after_intent';refused(function()f.import()end);f.reload()
 local first=f.proof('moveIn');f.lease=f.api.rearm(f.lease,first);f.fail='after_intent';refused(function()f.import()end);f.reload()
 local second=f.proof('moveIn');second.proof_id=first.proof_id
 refused(function()f.api.rearm(f.lease,second)end);assert(f.calls.move==0 and f.rows[CID].operations.moveIn.attempt==2)
 f.lease=f.api.rearm(f.lease,f.proof('moveIn'));assert(f.lease.next_attempt.moveIn==3 and #f.lease.operation_history.moveIn==2)
end)
test('observed but unwitnessed native effect lost at reboot can be rearmed',function()
 local f=setup('credit');f.claim();f.credit();assert(f.lease.operations.credit.observed and not f.lease.full_witness)
 f.slots[CID..':0']=slot(CID,0,0);f.reload();f.lease=f.api.rearm(f.lease,f.proof('credit'));f.credit()
 assert(f.slots[CID..':0'].count==16 and f.calls.credit==2 and f.lease.operation_history.credit[1].observed==true)
end)
test('accepted full or empty witness prevents any rearm despite restore flags',function()
 local f=setup('credit');f.claim();f.credit();f.saved('full');f.slots[CID..':0']=slot(CID,0,0);f.reload()
 refused(function()f.api.rearm(f.lease,f.proof('credit'))end);assert(f.calls.credit==1)
 local d=setup();d.claim();d.import();d.saved('full');d.lease=d.api.dispose(d.lease,{valid=true},16);d.saved('empty');d.slots[CID..':0']=slot(CID,0,16);d.reload()
 refused(function()d.api.rearm(d.lease,d.proof('dispose'))end);assert(d.calls.dispose==1)
end)
test('lease_record locks a safe rebase even if the witness tuple is unchanged',function()
 local f=setup();f.claim();f.import();f.require_record=true
 local w=f.witness('full');w.lease_record=clone(f.rows[CID]);assert(M.witness_matches(f.rows[CID],w))
 -- Simulate factory rebase of an unconfirmed current export, preserving revision.
 f.rows[CID].save_after_unix=f.rows[CID].save_after_unix+3
 assert(M.witness_matches(f.rows[CID],w));refused(function()f.api.acceptWitness(f.lease,w)end)
 assert(f.rows[CID].status=='full')
end)
test('lease_record is validated externally and omitted from compact stored receipts',function()
 local f=setup();f.claim();f.import();f.require_record=true
 local full=f.witness('full');full.lease_record=clone(f.rows[CID]);f.lease=f.api.acceptWitness(f.lease,full)
 assert(f.lease.full_witness and not f.lease.full_witness.lease_record)
 f.lease=f.api.dispose(f.lease,{valid=true},16)
 local empty=f.witness('empty');empty.lease_record=clone(f.rows[CID]);f.lease=f.api.acceptWitness(f.lease,empty)
 assert(not f.lease.empty_witness.lease_record and not f.lease.full_witness.lease_record)
end)
print('RESULT '..J.encode({passed=passed,scope='offline_adapter_fault_tests',runtime_verified=false,power_mode='night_low_power'}))
