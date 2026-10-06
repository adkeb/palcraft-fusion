local S='work/palworld-live/bridge/PalLiveBridge/Scripts/'
local M=dofile(S..'merge.lua')
local O=dofile(S..'organize.lua')
local J=dofile(S..'json.lua')
local ZERO='00000000-0000-0000-0000-000000000000'
local function guid(n)return string.format('00000000-0000-0000-0000-%012x',n)end
local BASE,GROUP=guid(9000),guid(9001)
local function clone(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=clone(x)end return t end
local function content(s)local t=clone(s);t.container_id=nil;t.index=nil;t.slot_id_index=nil;return t end
local function item(id,n,max,dynamic,timer)return{item=id,count=n,max_stack=max,dynamicGuid=dynamic or ZERO,dynamicWorldGuid=ZERO,corruption=timer or 0,corruptionKind='GetCorruptionProgressRate',empty=false}end
local function fixture(specs)
 local t={chests={}};local r={ok=true,includes_items=true,verifies_ownership=true,verified_live=true,chests={}}
 for ci,spec in ipairs(specs)do
  local id=guid(ci);local base=spec.base_id or BASE;local capacity=spec.capacity or #spec.items
  t.chests[#t.chests+1]={container_id=id,base_id=base,group_id=GROUP,type='ItemChest_02',expected_capacity=capacity}
  local c={id=id,actual_id=id,ok=true,capacity=capacity,base_id_from_snapshot=base,group_id_from_snapshot=GROUP,
   base_id_live=base,group_id_live=GROUP,type_live='ItemChest_02',container_id_from_module_live=id,is_guild_chest_live=false,
   ownership_verified_live=true,eligible_for_snapshot_plan=true,slots={}}
  r.chests[#r.chests+1]=c
  for index=0,capacity-1 do
   local s=clone((spec.items or {})[index+1])or{item='None',count=0,empty=true,dynamicGuid=ZERO,dynamicWorldGuid=ZERO,corruption=0,corruptionKind='GetCorruptionProgressRate'}
   s.container_id=id;s.index=index;s.slot_id_index=index;c.slots[#c.slots+1]=s
  end
 end
 return r,t,{base_id=BASE,policy='category',require_live_ownership=true}
end
local function index(r)local out={}for _,c in ipairs(r.chests)do for _,s in ipairs(c.slots)do out[s.container_id..':'..s.index]=s end end return out end
local function reference(r)return r.container_id..':'..r.index end
local function apply_mock(original,plan)
 local state=clone(original);local slots=index(state)
 for _,op in ipairs(plan.operations)do
  local a,b=slots[reference(op.from)],slots[reference(op.to)]
  assert(op.kind=='merge'and not a.empty and not b.empty and op.count>0)
  assert(M.canonical(content(a))==M.canonical(op.expected_source))
  assert(M.canonical(content(b))==M.canonical(op.expected_target))
  assert(a.item==b.item and a.dynamicGuid==b.dynamicGuid and a.dynamicWorldGuid==b.dynamicWorldGuid)
  assert(a.dynamicGuid==ZERO and a.dynamicWorldGuid==ZERO)
  assert(op.count<=a.count and b.count+op.count<=b.max_stack)
  local source_count=a.count-op.count;local target_count=b.count+op.count
  assert(op.expected_after.source.count==source_count and op.expected_after.target.count==target_count)
  assert(op.expected_after.target.corruption==b.corruption)
  if source_count>0 then assert(op.expected_after.source.corruption==a.corruption)end
  for _,pair in ipairs({{slot=a,after=op.expected_after.source},{slot=b,after=op.expected_after.target}})do
   local slot,after=pair.slot,pair.after;local cid,si=slot.container_id,slot.index
   for k in pairs(slot)do slot[k]=nil end
   for k,v in pairs(after)do slot[k]=clone(v)end
   slot.container_id=cid;slot.index=si;slot.slot_id_index=si
  end
 end
 local projected=index(plan.projected_snapshot)
 for key,slot in pairs(slots)do assert(M.canonical(slot)==M.canonical(projected[key]),'Projection differs from replay')end
 return state
end
local passed=0
local function test(name,fn)local ok,err=pcall(fn);if not ok then error(name..': '..tostring(err),0)end passed=passed+1;print('PASS '..name)end
local function expect(r,t,o)
 local p,e=M.plan(r,t,o);assert(p,e and e.code..': '..e.message)
 assert(p.quantity_signature and p.quantity_signature==M.canonical(p.identity_quantities_after))
 apply_mock(r,p);return p
end

test('partial fill obeys native max and preserves target food timer',function()
 local r,t,o=fixture({{items={item('Berries',8,10,nil,.8),item('Berries',7,10,nil,.2)}}})
 local p=expect(r,t,o);assert(#p.operations==1 and p.operations[1].count==2 and p.freed_slots==0)
 assert(p.operations[1].expected_after.source.count==5 and p.operations[1].expected_after.target.count==10)
end)
test('merge can free slots in a completely full base before classification',function()
 local r,t,o=fixture({{items={item('Wood',3,10),item('Wood',2,10),item('Stone',4,10)}}})
 local p=expect(r,t,o);assert(p.freed_slots==1 and p.occupied_after==2)
 local arrangement,err=O.plan(p.projected_snapshot,t,o);assert(arrangement,err and err.message)
 assert(O.simulate(p.projected_snapshot,t,o,arrangement))
end)
test('full-stack consumption produces a standard None empty slot',function()
 local r,t,o=fixture({{items={item('Wood',4,10),item('Wood',2,10)}}})
 local p=expect(r,t,o);local s=p.operations[1].expected_after.source
 assert(s.empty and s.count==0 and s.item=='None'and s.dynamicGuid==ZERO and s.dynamicWorldGuid==ZERO and s.max_stack==nil)
end)
test('same dynamic identity is preserved as separate equipment stacks',function()
 local r,t,o=fixture({{items={item('HandGun',1,10,guid(20)),item('HandGun',1,10,guid(20)),item('HandGun',1,10,guid(21))}}})
 local p=expect(r,t,o);assert(#p.operations==0 and p.dynamic_stacks_skipped==3 and p.occupied_after==3)
end)
test('nonzero dynamic world ID alone also forbids merge',function()
 local a=item('OddItem',1,10);a.dynamicWorldGuid=guid(20)
 local r,t,o=fixture({{items={a,clone(a)}}})
 local p=expect(r,t,o);assert(#p.operations==0 and p.dynamic_stacks_skipped==2)
end)
test('same static ID with inconsistent limits rejects',function()
 local r,t,o=fixture({{items={item('Wood',1,10),item('Wood',1,20)}}})
 local p,e=M.plan(r,t,o);assert(not p and e.code=='inconsistent_max_stack')
end)
test('missing native max or already overflowed stack rejects',function()
 local r,t,o=fixture({{items={item('Wood',1,nil)}}})
 local p,e=M.plan(r,t,o);assert(not p and e.code=='missing_max_stack')
 r.chests[1].slots[1].max_stack=1;r.chests[1].slots[1].count=2
 p,e=M.plan(r,t,o);assert(not p and e.code=='stack_overflow')
end)
test('different opaque metadata is not silently discarded',function()
 local a,b=item('FutureItem',1,10),item('FutureItem',1,10);a.opaque='a';b.opaque='b'
 local r,t,o=fixture({{items={a,b}}});local p=expect(r,t,o);assert(#p.operations==0)
end)
test('unknown static items can safely merge by complete identity',function()
 local r,t,o=fixture({{items={item('FutureItem',1,10),item('FutureItem',2,10)}}})
 local p=expect(r,t,o);assert(#p.operations==1 and p.freed_slots==1)
end)
test('different bases are never merged',function()
 local r,t,o=fixture({{items={item('Wood',1,10)}},{base_id=guid(9002),items={item('Wood',1,10)}}})
 local p=expect(r,t,o);assert(#p.operations==0 and p.occupied_before==1)
 assert(M.canonical(r.chests[2])==M.canonical(p.projected_snapshot.chests[2]))
end)
test('current ownership mismatch rejects',function()
 local r,t,o=fixture({{items={item('Wood',1,10)}}});r.chests[1].eligible_for_snapshot_plan=false
 local p,e=M.plan(r,t,o);assert(not p and e.code=='ownership_unverified')
end)
test('input snapshot never mutates',function()
 local r,t,o=fixture({{items={item('Wood',1,10),item('Wood',2,10)}}});local original=M.canonical(r)
 expect(r,t,o);assert(M.canonical(r)==original)
end)
test('500 random static inventories reach theoretical minimum stacks',function()
 math.randomseed(88211)
 for _=1,500 do
  local items,total={},0;local max=math.random(2,500);local n=math.random(2,30)
  for i=1,n do local count=math.random(1,max);items[i]=item('Wood',count,max);total=total+count end
  local r,t,o=fixture({{items=items}});local p=expect(r,t,o)
  assert(p.occupied_after==math.ceil(total/max)and p.freed_slots==n-p.occupied_after)
 end
end)
test('actual 18-box runtime max-stack snapshot merges then classifies',function()
 local f=assert(io.open('work/palworld-live/lab/merge-preflight.json','rb'));local r=J.decode(f:read('*a'),{max_bytes=8388608,max_depth=64}).before;f:close()
 local targets=dofile(S..'targets.lua');local bases={}
 for _,c in ipairs(r.chests)do bases[c.base_id_live]=true end
 for base in pairs(bases)do
  local o={base_id=base,policy='category',require_live_ownership=true}
  local p=expect(r,targets,o)
  local arrangement,err=O.plan(p.projected_snapshot,targets,o);assert(arrangement,err and err.code..': '..err.message)
  local proof,e=O.simulate(p.projected_snapshot,targets,o,arrangement);assert(proof,e and e.message)
  print(string.format('  base=%s stacks=%d->%d freed=%d merge_ops=%d organize_ops=%d',base,p.occupied_before,p.occupied_after,p.freed_slots,p.operation_count,arrangement.operation_count))
 end
end)
print(string.format('OK %d merge planner tests; 500 randomized inventory consolidations',passed))
