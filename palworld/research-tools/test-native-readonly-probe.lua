local real_dofile=dofile
local base='work/palworld-live/'
local J=real_dofile(base..'bridge/PalLiveBridge/Scripts/json.lua')
local R=real_dofile(base..'bridge/PalLiveBridge/Scripts/readers.lua')
local run=assert(loadfile(base..'lab/native-readonly-probe.lua'))
local files,loaded,mode={},0,'ok'
local function object(name,address,outer)
 local o={};function o:IsValid()return true end;function o:GetFullName()return name end
 function o:GetAddress()return address end;function o:GetOuter()return outer end
 function o:GetClass()return {GetAddress=function()return address+256 end}end
 return o
end
local manager=object('manager',0x400000)
local account=object('account',0x500000,manager)
account.InventoryData=object('inventory',0x600000,account)
account.TechnologyData=object('technology',0x700000,account)
account.IndividualHandle={GetIndividualID=function()return {PlayerUId={A=0xd8178a9d,B=0,C=0,D=0}}end}
function FindAllOf(c)
 if c=='PalItemContainerManager'then return {object('context',0x800000)}end
 if c=='PalPlayerAccount'then return mode=='no_accounts'and{}or{account}end
 error(c)
end
function StaticFindObject(c)
 if c=='/Script/Pal.Default__PalUtility'then return {GetPlayerManager=function()return manager end}end
 if c=='/Script/Engine.Default__KismetGuidLibrary'then return {NewGuid=function()return{A=1,B=2,C=3,D=4}end}end
 error(c)
end
function IsInGameThread()return mode~='wrong_thread'end
local function threadid(s)return{ToString=function()return s end}end
function GetGameThreadId()
 return threadid(mode=='bad_thread_format'and'0x4d2'or mode=='zero_thread'and'0'or mode=='overflow_thread'and'4294967296'or'1234')
end
function GetCurrentThreadId()return threadid(mode=='thread_mismatch'and'1235'or'1234')end
function ExecuteWithDelay(_,fn)fn()end
function ExecuteInGameThread(fn)fn()end
debug.getinfo=function()return {source='@D:/PalworldServer-LAN/BridgeLab/Scripts/main.lua'}end
dofile=function(p)
 if p:match('json.lua$')then return J end;if p:match('readers.lua$')then return R end;error(p)
end
os.time=function()return 2000000000 end
os.remove=function(p)files[p]=nil;return true end
os.rename=function(a,b)assert(files[a]);files[b]=files[a];files[a]=nil;return true end
io.open=function(p,m)
 if m=='wb'then return{write=function(_,s)files[p]=s;return true end,close=function()return true end}end
 if not files[p]then return nil end
 return{read=function()return files[p]end,close=function()return true end}
end
package.loadlib=function(path,symbol)
 assert(path=='D:/PalworldServer-LAN/BridgeLab/Scripts/pal_native_readonly_v2.dll')
 assert(symbol=='pal_native_readonly_v2')
 if mode=='missing_dll'then return nil,'DLL unavailable'end
 return function()
  loaded=loaded+1
  local data=assert(files['D:/PalworldServer-LAN/BridgeLab/rpc/native-readonly.request.bin'])
  assert(#data==112)
  local magic,v,n,t,pad,expiry,mgr,cls,pos=string.unpack('<c8I4I4I4I4I8I8I8',data)
  assert(magic=='PLNRO001'and v==1 and n==1 and t==1234 and pad==0 and expiry==2000000015)
  assert(mgr==0x400000 and cls==0x400100 and pos==49)
  local a,ac,tech,inv,A,B,C,D=string.unpack('<I8I8I8I8I4I4I4I4',data,65)
  assert(a==0x500000 and ac==0x500100 and tech==0x700000 and inv==0x600000 and A==0xd8178a9d and B==0 and C==0 and D==0)
  files['D:/PalworldServer-LAN/BridgeLab/rpc/native-readonly.result.json']=J.encode{
   read_only=true,not_a_builder=true,native_probe_version=1,ok=true,game_thread_id=1234,
   nonce=mode=='stale'and'bad'or'00000001000000020000000300000004',
   accounts={{player_uid_hex='000000000000400080000000000000fe',ok=true,native_lookup_same_account=true,account_outer_chain_matches=true}}}
 end
end
local function test(m,success,expected_calls)
 mode=m;files={};loaded=0;run()
 local result=J.decode(assert(files['D:/PalworldServer-LAN/BridgeLab/rpc/native-readonly-probe.json']))
 assert(result.ok==success and loaded==expected_calls,m)
end
test('ok',true,1)
test('stale',false,1)
test('missing_dll',false,0)
test('wrong_thread',false,0)
test('no_accounts',false,0)
test('bad_thread_format',false,0)
test('zero_thread',false,0)
test('overflow_thread',false,0)
test('thread_mismatch',false,0)
print('9 Lua/native wire and closed-failure checks passed')
