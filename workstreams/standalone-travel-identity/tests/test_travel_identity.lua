-- Actual source callback only; no engine, consumer, reader, RPC or ACK.
local f=assert(io.open(assert(arg[1])));local s=f:read('*a');f:close()
local code=assert(s:match('options.travel.verify_identity=(function%(pc,b,authority%).-\n   end)'))
local pc={};local proof={host_uid='host',world_id='world',server_session_id='standalone:actual-life'}
local valid,world=true,true;local actual=proof
local o={local_realm={current=function()return actual end,
 validate=function(_,p,x)return valid and p==actual and x==pc end,
 same_world=function(_,x,p)return world and x==pc and p==actual end}}
local verify=assert(load('return '..code,'actual_SP_travel_identity','t',setmetatable({o=o},{__index=_G})))()
local b={pal_uid=proof.host_uid,world_id=proof.world_id,server_session_id=proof.server_session_id};local n=0
local function check(v)assert(v);n=n+1 end
check(verify(pc,b,true)==true)
check(verify(pc,b,false)==false)
check(verify(pc,nil,true)==false)
actual=nil;check(verify(pc,b,true)==false);actual=proof
valid=false;check(verify(pc,b,true)==false);valid=true
world=false;check(verify(pc,b,true)==false);world=true
check(verify({},b,true)==false)
for _,k in ipairs({'pal_uid','world_id','server_session_id'})do local old=b[k];b[k]='other';check(verify(pc,b,true)==false);b[k]=old end
print('PASS '..n..' actual callback checks; no game/RPC/ACK')
