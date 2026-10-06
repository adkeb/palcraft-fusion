-- Engine-independent protocol and attempt-once combat journal. Clients cannot be an authority.
local P={VERSION=1,MAX_ENTITIES=512,MAX_DAMAGE=10000}
function P.uuid(s)return type(s)=='string'and #s==36 and s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil and s==s:lower()end
function P.token(s)return type(s)=='string'and #s>0 and #s<=128 and not s:find('[^%w_.:%-]')end
function P.entity_id(s)
 if type(s)~='string'then return false end
 if s:sub(1,3)=='mc:'then return P.uuid(s:sub(4))end
 if s:sub(1,4)=='pal:'then local a,b=s:sub(5):match('^([^/]+)/([^/]+)$');return P.uuid(a)and P.uuid(b)end
 return false
end
function P.finite(n)return type(n)=='number'and n==n and n~=math.huge and n~=-math.huge end
local function safe(q,k)assert(P.token(q[k]),'Invalid '..k);return q[k]end
function P.validate_hit(q,session,epoch,source_epoch,authority)
 assert(type(q)=='table'and q.v==1 and q.t=='entity_damage'and q.authority==authority,'Invalid authority envelope')
 assert(P.uuid(q.id),'Invalid event ID')
 assert(safe(q,'session')==session,'Stale session')
 assert(safe(q,'target_epoch')==epoch,'Stale target epoch')
 assert(safe(q,'source_epoch')==source_epoch,'Stale source epoch')
 assert(P.entity_id(q.source)and P.entity_id(q.target),'Invalid entity ID')
 assert(authority~='mc_server'or(q.source:sub(1,3)=='mc:'and q.target:sub(1,4)=='pal:'),'Wrong authority direction')
 assert(P.finite(q.amount)and q.amount>0 and q.amount<=P.MAX_DAMAGE,'Invalid damage')
 assert(type(q.kind)=='string'and #q.kind<=96 and #q.kind>0 and not q.kind:find('[^%w_:./%-]'),'Invalid damage kind')
 return true
end
-- Include all combat semantics; reusing an ID for a different attacker/amount is a conflict, not another hit.
function P.fingerprint(q)
 return table.concat({tostring(q.session),tostring(q.target_epoch),tostring(q.source_epoch),tostring(q.target),tostring(q.source),P.finite(q.amount)and('%.17g'):format(q.amount)or tostring(q.amount),tostring(q.kind),
  tostring(q.environment==true),tostring(q.source_player==true),tostring(q.source_proxy==true),q.player_session and tostring(q.player_session.session_id)or'',
  q.player_session and tostring(q.player_session.generation)or''},'|')
end
function P.validate_snapshot(q,session,now)
 assert(type(q)=='table'and q.v==1 and q.t=='entity_snapshot'and q.authority=='mc_server','Invalid MC authority snapshot')
 assert(safe(q,'session')==session and P.token(q.epoch),'Stale MC session')
 assert(P.finite(q.unix)and now-q.unix<=3 and now-q.unix>=-5,'Stale MC snapshot')
 assert(type(q.revision)=='number'and q.revision>=0 and q.revision%1==0,'Invalid revision')
 assert(type(q.entities)=='table'and #q.entities<=P.MAX_ENTITIES,'Entity limit')
 local seen={}
 for _,r in ipairs(q.entities)do
  assert(P.entity_id(r.id)and r.id:sub(1,3)=='mc:'and not seen[r.id],'Invalid or duplicate MC identity');seen[r.id]=true
  assert(type(r.kind)=='string'and #r.kind<=128,'Invalid entity kind')
  for _,k in ipairs({'x','y','z','yaw','width','height'})do assert(P.finite(r[k]),'Invalid '..k)end
  assert(math.abs(r.x)<=29999900 and math.abs(r.z)<=29999900 and math.abs(r.y)<=100000,'Entity outside bridge bounds')
  assert(r.width>0 and r.width<=64 and r.height>0 and r.height<=64,'Invalid entity dimensions')
  if r.category=='mob'then assert(P.finite(r.hp)and P.finite(r.max_hp)and r.hp>=0 and r.max_hp>0,'Invalid health')end
 end
 return true
end
function P.new(o)
 assert(P.token(o.session)and P.token(o.epoch),'Server authority required')
 assert(type(o.read)=='function'and type(o.write)=='function'and type(o.apply)=='function','Durable storage and native apply required')
 local M={session=o.session,epoch=o.epoch,source_epoch=nil,revision=-1,applied=0,rejected=0,uncertain=0}
 function M.snapshot(q)
  P.validate_snapshot(q,M.session,o.now())
  if M.source_epoch==q.epoch and q.revision<=M.revision then return false end
  local changed=M.source_epoch~=q.epoch
  M.source_epoch=q.epoch;M.revision=q.revision
  return true,changed
 end
 function M.hit(q)
  local path='pal-result-'..tostring(q.id)..'.json'
  assert(P.uuid(q.id),'Invalid event path')
  local prior=o.read(path)
  if prior then
   if prior.fingerprint~=P.fingerprint(q)then return {v=1,t='entity_result',id=q.id,ok=false,status='id_conflict'}end
   return prior -- in_flight/native_error stay uncertain forever; no automatic native retry
  end
  local valid,why=pcall(P.validate_hit,q,M.session,M.epoch,M.source_epoch,'mc_server')
  if not valid then
   M.rejected=M.rejected+1
   local r={v=1,t='entity_result',id=q.id,ok=false,status='rejected',error=tostring(why),fingerprint=P.fingerprint(q)}
   o.write(path,r);return r
  end
  local r={v=1,t='entity_result',id=q.id,session=M.session,epoch=M.epoch,ok=false,status='in_flight',fingerprint=P.fingerprint(q),drop_owner='palworld'}
  o.write(path,r) -- durability is mandatory before any native mutation
  local ok,result=pcall(o.apply,q)
  if not ok then r.status='native_error';r.error=tostring(result);M.uncertain=M.uncertain+1
  else
   assert(type(result)=='table','Native result required')
   for k,v in pairs(result)do r[k]=v end
   r.ok=result.ok==true;r.status=result.status or(r.ok and'applied'or'pending_native_confirmation')
   if r.ok then M.applied=M.applied+1 else M.uncertain=M.uncertain+1 end
  end
  o.write(path,r);return r
 end
 return M
end
return P
