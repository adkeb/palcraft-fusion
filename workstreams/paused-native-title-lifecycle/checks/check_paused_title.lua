local root=assert(arg[1])
local function read(name)local f=assert(io.open(root..'/'..name,'rb'));local s=f:read('*a');f:close();return s end
local main=read('source/client/main.lua')
local queue=assert(main:match('local function poll_client_operation%(%)%s*(.-)%s*local function run%(%)')):gsub('%s*end%s*$','')
-- The actual extracted paused branch and operation consumer run with in-memory IO.
local head=assert(main:match('local function run%(%)%s*(.-)%s*tick_count=tick_count%+1'))
local pending,result,now,paused,active_dispatch= nil,nil,10,true,0
local writes={}
local function open(name)
 if name~='client-op.lua' or not pending then return nil end
 return {read=function()return pending end,close=function()end}
end
local env={assert=assert,pcall=pcall,tostring=tostring,print=print,load=load}
local os_fixture={time=function()return now end,remove=function()pending=nil end}
env.os=os_fixture;env.open=open;env.ROOT='fixture/'
env.json=function(name,value)result=value;writes[#writes+1]={name=name,value=value}end
env.operator_paused=true
env.paused_next_ops=0
env._ENV=env
-- Use locals as production does; no native object is supplied or touched.
local consumer=assert(load('return function() '..queue..' end','original-consumer','t',env))()
env.poll_client_operation=consumer
local paused_head=assert(load('return function() '..head..' return "active" end','original-paused-head','t',env))()
pending='return {action="observe_title",title=true}'
assert(paused_head()==nil and result.ok and result.result.action=='observe_title')
now=11;pending='return {action="quit_title",quit=true}'
assert(paused_head()==nil and result.ok and result.result.action=='quit_title')
assert(#writes==2 and pending==nil)
-- Active same-callback stop must return before the original standalone tick.
local stop_tail=assert(main:match('if now>=next_ops then next_ops=now%+1000;poll_client_operation%(%)end%s*(if operator_paused then return end)%s*if standalone then'))
env.operator_paused=true
local stopped=assert(load('return function() '..stop_tail..' active_dispatch=active_dispatch+1 end','same-frame-stop','t',env))()
env.active_dispatch=0;stopped();assert(env.active_dispatch==0)
env.operator_paused=false;assert(paused_head()=='active')
-- Execute the original Python-produced return/observe/quit operations.
local order={}
env.IsInGameThread=function()return true end
env._G=env
env.PalCraftStandalonePermissions={process=function()return{},'fixture-epoch' end}
local pc={ClientReturnToMainMenu=function()order[#order+1]='return_title' end}
local proof={server_session_id='fixture-SID',world_id='fixture-world',host_uid='fixture-uid',pc=pc,
 save_manager={IsWorldAutoSaving=function()return false end}}
env.PalCraftServerFeatures={}
env.PalCraftStandaloneBootstrap={local_realm={current=function()return proof end},
 world={stop=function(f)assert(f==env.PalCraftServerFeatures);order[#order+1]='cleanup';return{stop_ok=true}end}}
assert(load(read('checks/generated-return_title.lua'),'generated-title','t',env))()
assert(table.concat(order,',')=='cleanup,return_title')
order={};env.PalCraftStandaloneBootstrap.world.stop=function()order[#order+1]='cleanup_rejected';return{stop_ok=false}end
assert(not pcall(assert(load(read('checks/generated-return_title.lua'),'generated-stop-reject','t',env))))
assert(table.concat(order,',')=='cleanup_rejected')
print('PASS 3 targeted cases: paused native-free command poll; active/resume and same-frame stop; original generated cleanup before Title with rejection')
