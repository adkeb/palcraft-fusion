-- Three bounded synthetic interleaving cases, using actual Bridge/World functions.
local work,dir=assert(arg[1]),assert(arg[2]);local J=dofile(work..'/../palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function part(s,a,b)local i=assert(s:find(a,1,true));local k=assert(s:find(b,i+1,true));return s:sub(i,k-1)end
local function key(at)return table.concat(at,':')end
local function clone(v)return J.decode(J.encode(v))end
local function inside(at,b)return at[1]>=b[1]and at[1]<b[4]and at[2]>=b[2]and at[2]<b[5]and at[3]>=b[3]and at[3]<b[6]end
local G={clone=clone,stable=function(v)return J.encode(v)end}
local source=read(dir..'/source/client/companion_chunk_bridge.lua');local Bridge={};Bridge.__index=Bridge
local code=part(source,'function Bridge:_late_snapshot_end(','function Bridge:prepare_view(')
 ..part(source,'function Bridge:_seed_one()','function Bridge:before_commit(')
 ..part(source,'function Bridge:readiness(','function Bridge:activate(')
local env=setmetatable({Bridge=Bridge,G=G,inside=inside,at_key=key,block_key=function(dim,at)return dim..':'..key(at)end},{__index=_G})
assert(load(code,'@exact-Bridge-catchup','t',env))()
local World={};World.__index=World
local world_source=read(dir..'/base/client/world_compat.lua')
assert(load(part(world_source,'function World:_snapshot_end(','function World:_lifecycle('),'@exact-authoritative-World-commit','t',
 setmetatable({World=World,key=key,inside=inside,copy=clone},{__index=_G})))()
local dim='minecraft:overworld';local player='fixture-player';local bounds={0,63,0,2,66,1}
local function fixture()
 local blocks={['1:64:0']={at={1,64,0},id='old-native'}}
 local world=setmetatable({session='fixture-world',seq=10,last_gap_seq=0,dimension=dim,snapshots={},committed_snapshots={},committed_order={},worlds={[dim]={blocks=clone(blocks)}}},World)
 function world:_world(d)return self.worlds[d]end
 function world:_callback()end
 function world:committed_snapshot(id)return self.committed_snapshots[id]end
 function world:get(d,x,y,z)return self.worlds[d].blocks[key({x,y,z})]end
 -- begin/body happened before native attach; commit occurs after it.
 world.snapshots.s={dim=dim,bounds=clone(bounds),at={0,0},player=player,begin_seq=1,replace=true,touched={},
  blocks={['0:64:0']={at={0,64,0},id='snapshot-value'}}}
 local child={generation=1,snapshots={},coverage={},chunks={{dimension=dim,blocks=clone(blocks)}},values=clone(blocks),calls=0}
 function child:apply_blocks(_,set,clear)
  self.calls=self.calls+1
  for _,at in ipairs(clear)do self.values[key(at)]=nil end
  for _,g in ipairs(set)do self.values[key(g.at)]=clone(g)end
 end
 local region={id='owned-region',dim=dim,refs=2,scheduler=child,window={-16,-100,0,16,100,16}}
 local a={id='real-ticket-1',region=region,player=player,generation=1,world_session=world.session,dim=dim,required_bounds=clone(bounds)}
 local b={id='real-ticket-2',region=region,player=player,generation=1,world_session=world.session,dim=dim,required_bounds=clone(bounds)}
 local views={generation=1,session=world.session,regions={[region.id]=region},tickets={a,b},ingests=0}
 function views:ingest()self.ingests=self.ingests+1;return true end
 function views:readiness()return{ready=true,snapshots_pending=0,errors={}}end
 local bridge=setmetatable({world=world,views=views,bootstrap={},latest={},retirements={},block_events={},installed=true,stats={rows=0,seeded_blocks=0},options={seed_blocks_per_tick=1}},Bridge)
 function bridge:_transform(row)return row end
 local life={op='snapshot_end',snapshot='s',player=player,bounds=clone(bounds)}
 local row={t='blocks',session=world.session,seq=10,dim=dim,ops={},lifecycle={life}}
 world:_snapshot_end(row,life)
 return{bridge=bridge,world=world,child=child,region=region,a=a,b=b,row=row,life=life}
end
local cases={};local function test(name,f)f();cases[#cases+1]=name end

test('missing_native_begin_body_real_end_budgeted_catchup_all_region_tickets_pending_then_real_coverage',function()
 local f=fixture();f.a._companion_bootstrap={session_id='original-session',mc_epoch='original-epoch',base_seq=3,total=1,scanned=1,completed=true}
 local original=J.encode(f.a._companion_bootstrap);assert(f.bridge:on_row(f.row,true,'applied'))
 assert(#f.bridge.bootstrap==1 and J.encode(f.a._companion_bootstrap)==original)
 assert(f.bridge:readiness(f.a).snapshots_pending==1 and f.bridge:readiness(f.b).snapshots_pending==1)
 assert(f.bridge:readiness(f.a).ready==false and#f.child.coverage==0)
 f.bridge:_seed_one();assert(#f.child.coverage==0 and f.child.calls==1)
 f.bridge:_seed_one();assert(#f.bridge.bootstrap==0 and#f.child.coverage==1 and f.region.commit_hold==nil)
 assert(J.encode(f.a._companion_bootstrap)==original)
 assert(f.child.values['0:64:0'].id=='snapshot-value'and f.child.values['1:64:0']==nil)
 assert(f.child.coverage[1].snapshot=='s'and f.child.coverage[1].seq==10 and f.child.coverage[1].source=='companion_reducer_receipt')
end)

test('queued_catchup_reads_current_values_preserves_newer_delta_and_clear_instead_of_old_snapshot',function()
 local f=fixture();f.bridge:on_row(f.row,true,'applied')
 f.world.worlds[dim].blocks['0:64:0']={at={0,64,0},id='newer-authoritative'}
 f.bridge:_seed_one();f.bridge:_seed_one();assert(f.child.values['0:64:0'].id=='newer-authoritative')
 f=fixture();f.bridge:on_row(f.row,true,'applied')
 f.world.worlds[dim].blocks['0:64:0']=nil;f.bridge:_seed_one();f.bridge:_seed_one();assert(f.child.values['0:64:0']==nil)
 f=fixture();f.bridge:on_row(f.row,true,'applied');f.bridge.latest[dim..':0:64:0']=11
 f.child.values['0:64:0']={at={0,64,0},id='original-later-delta-already-applied'}
 f.bridge:_seed_one();f.bridge:_seed_one();assert(f.child.values['0:64:0'].id=='original-later-delta-already-applied')
end)

test('wrong_noncommitted_foreign_or_repeated_receipt_ignored_native_stage_and_already_seeded_receipt_unchanged',function()
 for _,kind in ipairs({'not_committed','wrong_bounds','wrong_endseq','wrong_player','gap_floor','foreign_ticket'})do
  local f=fixture();local r=f.world.committed_snapshots.s
  if kind=='not_committed'then r.committed=false elseif kind=='wrong_bounds'then r.bounds[4]=3
  elseif kind=='wrong_endseq'then r.end_seq=9 elseif kind=='wrong_player'then r.player='other-player'
  elseif kind=='gap_floor'then f.world.last_gap_seq=11 else f.a.player='other-player';f.b.player='other-player'end
  assert(f.bridge:on_row(f.row,true,'applied')and#f.bridge.bootstrap==0 and f.bridge.error==nil)
 end
 local f=fixture();f.child.snapshots.s={};f.bridge:on_row(f.row,true,'applied');assert(#f.bridge.bootstrap==0)
 f=fixture();f.child.coverage[1]={snapshot='s',seq=10,session=f.world.session,generation=1};f.bridge:on_row(f.row,true,'applied');assert(#f.bridge.bootstrap==0)
 f=fixture();f.bridge:on_row(f.row,true,'applied');f.bridge:on_row(f.row,true,'duplicate');assert(#f.bridge.bootstrap==1)
 f.bridge:_seed_one();f.bridge:_seed_one();f.bridge:on_row(f.row,true,'applied');assert(#f.bridge.bootstrap==0 and#f.child.coverage==1)
 f=fixture();f.bridge:on_row(f.row,true,'applied');f.child.generation=2;f.bridge:_seed_one()
 assert(#f.bridge.bootstrap==0 and#f.child.coverage==0 and f.child.calls==0 and f.region.commit_hold==nil)
end)
print(J.encode{ok=true,tests=3,cases=cases,synthetic_only=true,actual_World_snapshot_commit_and_Bridge_functions=true,
 native_scheduler_apply_is_scoped_fixture_adapter=true,actual_Game_native_commit_Retry_or_ACK=false,
 original_bootstrap_identity_not_modified=true})
