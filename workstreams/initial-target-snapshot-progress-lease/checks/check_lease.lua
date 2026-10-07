-- Four bounded pure-source fixtures. All proof/clock data are synthetic; no Game calls.
local root=assert(arg[1],'delta root required')
local P=dofile(root..'/source/server/travel/protocol.lua')
local C=dofile(root..'/source/client/travel/protocol.lua')
local O=dofile(root..'/base/server/travel/protocol.lua')
local function id(n)return('00000000-0000-0000-0000-%012d'):format(n)end
local function fresh(complete)
 local req={player=id(1),world_session='synthetic-world',dim='minecraft:overworld',view=1,generation=1,
  session_id=id(2),session_generation=1,mc_epoch='synthetic-epoch',mapping={region_id='synthetic-region'},
  required_bounds={-63,51,-55,66,99,74}}
 local ticket={id='synthetic-ticket',generation=1}
 local tx={tx='synthetic-tx',_ticket=ticket,deadline=30,initial_prepare_started=0,initial_prepare_limit=180}
 local proof={world_session=req.world_session,dim=req.dim,view=req.view,region_id=req.mapping.region_id,
  generation=1,renderer_generation=1,session_generation=1,revision=0,snapshots_pending=2,
  collision_pending=0,visual_pending=0,coverage_complete=false,ready=false,
  errors={complete and'authoritative_snapshot_pending'or'companion_bootstrap_pending'},
  companion_bootstrap={ticket_id=ticket.id,world_session=req.world_session,dim=req.dim,view=req.view,
   region_id=req.mapping.region_id,generation=1,player=req.player,session_id=req.session_id,
   session_generation=1,mc_epoch=req.mc_epoch,base_seq=10,total=4,scanned=complete and 4 or 1,completed=complete}}
 return tx,proof,req
end
local names={}
local function check(name,body)body();names[#names+1]=name;print('PASS '..name)end
local function same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
check('completed_bootstrap_authoritative_pending_count_decreases_extend_same_lease',function()
 for _,mode in ipairs({'server','client'})do
  local tx,p,r=fresh(true);local module=mode=='server'and P or C;local original=P.copy(tx)
  assert(not module.initial_prepare_lease(tx,p,r,0,30,mode))
  p.snapshots_pending=1
  assert(module.initial_prepare_lease(tx,p,r,30,30,mode));assert(tx.deadline==60 and tx.initial_prepare_extensions==1)
  assert(tx._ticket.id==original._ticket.id and tx.tx==original.tx and same(r.required_bounds,{-63,51,-55,66,99,74}))
  assert(p.ready==false and p.coverage_complete==false and module.ready(p,r,mode)==false)
  local before,oldproof,oldreq=fresh(true);oldproof.snapshots_pending=1
  assert(not O.initial_prepare_lease(before,oldproof,oldreq,30,30,mode))
 end
end)
check('no_progress_zero_pending_incompatible_error_and_finite_cap_cannot_renew',function()
 local tx,p,r=fresh(true);assert(not P.initial_prepare_lease(tx,p,r,0,30,'server'))
 assert(not P.initial_prepare_lease(tx,p,r,30,30,'server'));assert(tx.deadline==30)
 for _,bad in ipairs({'zero','error','cap'})do
  tx,p,r=fresh(true);p.revision=50
  if bad=='zero'then p.snapshots_pending=0 end
  if bad=='error'then p.errors={'native_commit_error'}end
  assert(not P.initial_prepare_lease(tx,p,r,bad=='cap'and 180 or 30,30,'server'));assert(tx.deadline==30)
 end
end)
check('stale_native_generation_or_other_owned_ticket_tuple_cannot_renew',function()
 for _,bad in ipairs({'generation','ticket','session'})do
  local tx,p,r=fresh(true);p.revision=50
  if bad=='generation'then p.renderer_generation=2 end
  if bad=='ticket'then p.companion_bootstrap.ticket_id='old-ticket'end
  if bad=='session'then p.companion_bootstrap.session_id=id(9)end
  assert(not P.initial_prepare_lease(tx,p,r,30,30,'server'));assert(tx.deadline==30)
 end
end)
check('original_bootstrap_progress_and_consistency_rules_remain_exact',function()
 local nt,np,nr=fresh(false);local ot,op,orr=fresh(false)
 assert(P.initial_prepare_lease(nt,np,nr,0,30,'server')==O.initial_prepare_lease(ot,op,orr,0,30,'server'))
 np.companion_bootstrap.scanned=2;op.companion_bootstrap.scanned=2
 assert(P.initial_prepare_lease(nt,np,nr,30,30,'server')==O.initial_prepare_lease(ot,op,orr,30,30,'server'))
 assert(same(nt,ot))
 local tx,p,r=fresh(true);p.errors={'companion_bootstrap_pending'}
 assert(not P.initial_prepare_lease(tx,p,r,30,30,'server')and not O.initial_prepare_lease(P.copy(tx),P.copy(p),r,30,30,'server'))
 tx,p,r=fresh(false);assert(not P.initial_prepare_lease(tx,p,r,0,30,'server'))
 p.errors={'companion_bootstrap_pending','authoritative_snapshot_pending'};p.snapshots_pending=1
 assert(not P.initial_prepare_lease(tx,p,r,30,30,'server')) -- No bootstrap advance; count alone cannot fake bootstrap progress.
end)
assert(#names==4);print('RESULT 4 PASS; synthetic-only; no Game/runtime/ACK proof')
