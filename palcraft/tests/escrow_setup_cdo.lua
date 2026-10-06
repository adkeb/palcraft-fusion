-- One narrow regression: actual escrow_setup closures, CDO static libraries.
-- No native process/RPC/file mutation. Unrelated build/fee/work paths are not tested.
local path=assert(arg[1]);local f=assert(io.open(path,'rb'));local code=f:read('*a');f:close()
local canonical='@D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/escrow_setup.lua'
local function g(n)return string.format('00000000-0000-0000-0000-%012x',n)end
local function gid(n)return {A=0,B=0,C=0,D=n}end
local function object(name,fields)
 fields=fields or{};function fields:IsValid()return true end;function fields:GetFullName()return name end;return fields
end
local function up(fn,name)
 for i=1,60 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==name then return v,i end end
 error('Actual module upvalue not found: '..name)
end
local op={paid_cost_observed=true,candidate={model_id=g(2)},before={player_uid=g(1)},status='awaiting_normal_work'}
local commits,calls=0,0
local store={latest=function()return op end,append=function(_,row)op=row;commits=commits+1 end}
local R={guid_to_string=function(v)return g(v.D)end,guid_from_string=function(v)return gid(tonumber(v:sub(-12),16))end}
local guidlib=object('/Script/Engine.Default__KismetGuidLibrary',{NewGuid=function()return gid(4)end})
local systemlib=object('/Script/Engine.Default__KismetSystemLibrary',{})
function systemlib:LineTraceSingle(pawn,start,finish,channel,complex,ignore,draw,hit)
 assert(channel==0 and draw==0);hit.bBlockingHit=true;hit.bStartPenetrating=false
 hit.ImpactPoint={X=start.X,Y=start.Y,Z=10};hit.ImpactNormal={X=0,Y=0,Z=1};return true
end
local work=object('Live.Work',{GetWorkId=function()return gid(3)end,OwnerMapObjectModelId=gid(2),
 GetCurrentWorkAmount=function()return 10 end,GetRequiredWorkAmount=function()return 1000 end})
local process=object('Live.BuildProcess',{IsCompleted=function()return false end,GetWorkProgress=function()return work end})
local model=object('Live.Model',{BuildPlayerUId=gid(1),BuildProcess=process})
local manager=object('Live.MapObjectManager',{FindModel=function()return model end})
local utility=object('/Script/Pal.Default__PalUtility',{GetWorkProgressManager=function()return{GetWork=function()return work end}end})
local pawn=object('Live.Player',{K2_GetActorLocation=function()return{X=0,Y=0,Z=100}end})
local transmitter=object('Live.PlayerTransmitter',{})
local component=object('Live.WorkComponent',{GetOwner=function()return transmitter end})
function component:RequestStartPlayerWork_ToServer(request,id)assert(id.D==3);calls=calls+1 end
function transmitter:GetWorkProgress()return component end
local env=setmetatable({IsInGameThread=function()return true end,
 StaticFindObject=function(name)return assert(({['/Script/Engine.Default__KismetGuidLibrary']=guidlib,
  ['/Script/Engine.Default__KismetSystemLibrary']=systemlib,['/Script/Pal.Default__PalUtility']=utility})[name])end,
 FindAllOf=function(class)assert(class=='PalMapObjectManager');return{manager}end,
 dofile=function(name)assert(name:match('exchange_store.lua$'));return{new=function()return store end,native_commit=function()return function()end end}end},{__index=_G})
local M=assert(load(code,canonical,'t',env))()
local api=M.new{json={array=function(v)return v or{}end},readers=R,root='fixture/',durable_dll='fixture',allow_build=true}
local fresh=up(api.preview,'freshid');assert(fresh()==g(4),'Real freshid must accept the valid Guid CDO')
local site=up(api.preview,'site');local ground=up(site,'ground')
local point=ground({pawn=pawn},123,456);assert(point.x==123 and point.y==456 and point.z==10,'Real ground must accept SystemLibrary CDO')
local context,ctx_index=up(api.start_work,'context');local live=up(context,'live')
assert(not live(guidlib)and not live(systemlib)and not live(utility),'Instance filter must still reject CDOs')
assert(live(pawn)and live(model),'Real instances must remain usable')
debug.setupvalue(api.start_work,ctx_index,function()return{player_uid=g(1)},{pawn=pawn,transmitter=transmitter}end)
api.observe=function()return op end
api.start_work(g(5))
assert(calls==1 and commits==1 and op.work_request.required==1000 and op.work_request.before==10,'Real start_work must accept PalUtility CDO without changing work amount')
print('PASS actual setup module: Guid/System/Pal utility CDO accepted; live instance CDO rejection retained; no work progress write')
