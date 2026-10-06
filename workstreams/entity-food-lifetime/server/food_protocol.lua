-- A completed vanilla MC consume pays for one native Pal use. No item credit or direct HP/stomach writes.
local F={}
local function finite(n)return type(n)=='number'and n==n and n~=math.huge and n~=-math.huge end
function F.fingerprint(q)
 local s=q.player_session or{}
 return table.concat({tostring(q.session),tostring(q.source_epoch),tostring(q.target_epoch),tostring(q.source),tostring(q.target),
  tostring(q.item),tostring(q.before_count),tostring(q.after_count),tostring(q.nutrition),tostring(q.saturation),tostring(q.effects_json),
  tostring(s.session_id),tostring(s.generation)},'|')
end
function F.validate(q,o)
 local P=o.protocol
 assert(q.v==1 and q.t=='entity_consume'and q.authority=='mc_server','Food authority envelope required')
 assert(P.uuid(q.id)and q.session==o.session and q.source_epoch==o.source_epoch()and q.target_epoch==o.epoch,'Stale food authority')
 assert(P.entity_id(q.source)and q.source:sub(1,3)=='mc:'and P.entity_id(q.target)and q.target:sub(1,4)=='pal:','Food actor identities required')
 assert(type(q.item)=='string'and q.item:match('^[%w_.%-]+:[%w_./%-]+$')and #q.item<=128,'Food item identifier required')
 assert(type(q.before_count)=='number'and q.before_count%1==0 and q.before_count>=1 and q.before_count<=99,'Invalid before stack')
 assert(q.after_count==q.before_count-1 and q.consumed_count==1 and q.vanilla_completed==true and q.creative~=true,'One paid vanilla consume required')
 assert(finite(q.nutrition)and q.nutrition>=0 and q.nutrition<=20 and finite(q.saturation)and q.saturation>=0 and q.saturation<=40,'Food properties range')
 assert(type(q.effects)=='table'and #q.effects<=16 and type(q.effects_json)=='string'and #q.effects_json<=8192,'Food effects bounds')
 for _,e in ipairs(q.effects)do assert(type(e.id)=='string'and e.id:match('^[%w_.%-]+:[%w_./%-]+$')and finite(e.duration)and e.duration>=1 and e.duration<=72000 and e.duration%1==0 and finite(e.amplifier)and e.amplifier>=0 and e.amplifier<=10 and e.amplifier%1==0,'Food effect range')end
 assert(q.player_session and q.player_session.mc_uuid==q.source:sub(4),'Verified food source session required')
end
function F.new(o)
 assert(o.read and o.write and o.apply and o.protocol,'Food durable apply adapter required')
 local M={applied=0,pending=0,rejected=0}
 function M.consume(q)
  assert(o.protocol.uuid(q.id),'Food event UUID required')
  local file='pal-food-result-'..q.id..'.json';local prior=o.read(file);local fp=F.fingerprint(q)
  if prior then return prior.fingerprint==fp and prior or{v=1,t='food_result',id=q.id,ok=false,status='id_conflict'}end
  local ok,why=pcall(F.validate,q,o)
  local r={v=1,t='food_result',id=q.id,session=o.session,epoch=o.epoch,source=q.source,target=q.target,item=q.item,fingerprint=fp,ok=false,paid_mc_count=1,native_items_credited=0}
  if not ok then r.status='rejected';r.error=tostring(why);M.rejected=M.rejected+1;o.write(file,r);return r end
  r.status='in_flight';o.write(file,r)
  local applied,result=pcall(o.apply,q)
  if not applied then r.status='needs_recovery_paid_not_fed';r.error=tostring(result);M.pending=M.pending+1
  else
   assert(type(result)=='table','Observed native food result required');for k,v in pairs(result)do r[k]=v end
   r.ok=result.ok==true;r.status=result.status or(r.ok and'applied'or'pending_native_effect_confirmation')
   if r.ok then M.applied=M.applied+1 else M.pending=M.pending+1 end
  end
  o.write(file,r);return r -- uncertain result never repeats native use or consumes another MC stack
 end
 return M
end
return F
