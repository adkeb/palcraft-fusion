local REAL=dofile
local J=REAL('work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local RR=REAL('work/palworld-live/bridge/PalLiveBridge/Scripts/readers.lua')
local probe=assert(loadfile('work/palworld-live/lab/native-material-roundtrip.lua'))
local id={A=0x12345678,B=9,C=10,D=11};local zero={A=0,B=0,C=0,D=0}
local mode,files,calls,reads='ok',{},0,0
local base='D:/PalworldServer-LAN/BridgeLab/rpc/'
local function obj(name,addr,t)
 t=t or{};function t:IsValid()return true end;function t:GetFullName()return name end
 function t:GetAddress()return addr end;function t:GetClass()return{GetAddress=function()return addr+256 end}end;return t
end
local slot=obj('slot',0x500000,{GetMaxStack=function()return 9999 end,GetStackCount=function()return 20 end,GetSlotId=function()return{ContainerId={ID=id},SlotIndex=3}end,
 GetItemId=function()return{StaticId={ToString=function()return'Wood'end},DynamicId={CreatedWorldId=zero,LocalIdInCreatedWorld=mode=='dynamic'and id or zero}}end})
local container=obj('container',0x600000,{Get=function(_,n)assert(n==3);return slot end})
local manager=obj('manager',0x400000,{GetContainer=function(_,x)assert(x.ID.A==id.A);return container end})
local R={guid_to_string=RR.guid_to_string,guid_from_string=RR.guid_from_string}
function R.chests(_,opts)
 assert(opts.include_items and opts.verify_ownership and opts.require_snapshot_ownership);reads=reads+1
 return{ok=true,verified_live=true,chests={{id=RR.guid_to_string(id),slots={{index=3,item='Wood',count=mode=='changed'and reads>1 and 19 or 20,empty=false,dynamicGuid=RR.guid_to_string(zero),dynamicWorldGuid=RR.guid_to_string(zero)}}}}}
end
function FindAllOf(c)assert(c=='PalItemContainerManager');return{manager}end
function StaticFindObject()return{NewGuid=function()return{A=1,B=2,C=3,D=4}end}end
local function threadid()return{ToString=function()return mode=='bad_thread'and'???'or'1234'end}end
function GetGameThreadId()return threadid()end
function GetCurrentThreadId()return threadid()end
function IsInGameThread()return true end
function ExecuteWithDelay(_,f)f()end
function ExecuteInGameThread(f)f()end
debug.getinfo=function()return{source='@D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/native-material-roundtrip.lua'}end
dofile=function(p)
 if p:match('json.lua$')then return J elseif p:match('readers.lua$')then return R elseif p:match('targets.lua$')then return{}end;error(p)
end
io.open=function(p,m)
 if m=='wb'then return{write=function(_,s)files[p]=s;return true end,flush=function()return true end,close=function()return true end}end
 if not files[p]then return nil end;return{read=function()return files[p]end,close=function()return true end}
end
os.remove=function(p)files[p]=nil;return true end
os.rename=function(a,b)if files[b]then return nil,'target exists'end;files[b]=assert(files[a]);files[a]=nil;return true end
os.time=function()return 2000000000 end
local nonce='00000000-0000-4000-8000-000000000002'
package.loadlib=function(p,sym)
 assert(p=='D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/pal_native_material_roundtrip_v1.dll'and sym=='pal_native_material_roundtrip_v1')
 return function()
  calls=calls+1
  assert(files[base..'native-roundtrip.intent.json']and files[base..'native-roundtrip.before.json'])
  assert(files[base..'native-roundtrip.used-arm.json']and not files[base..'native-roundtrip.arm.json'])
  assert(#files[base..'native-roundtrip.permit.bin']==16)
  files[base..'native-roundtrip.claimed.bin']=files[base..'native-roundtrip.permit.bin'];files[base..'native-roundtrip.permit.bin']=nil
  local wire=assert(files[base..'native-roundtrip.request.bin']);assert(#wire==112)
  local magic,v,n,t,res,expiry,mp,mc=string.unpack('<c8I4I4I4I4I8I8I8',wire)
  assert(magic=='PLNRT001'and v==1 and n==1 and t==1234 and res==0 and expiry==2000000015 and mp==0x400000 and mc==0x400100)
  local sp,sc,A,B,C,D,index,num,count,pad=string.unpack('<I8I8I4I4I4I4i4i4i4I4',wire,65)
  assert(sp==0x500000 and sc==0x500100 and A==id.A and B==9 and C==10 and D==11 and index==3 and num==1 and count==20 and pad==0)
  files[base..'native-roundtrip.result.json']=J.encode{ok=true,lab_only=true,read_only=false,not_a_builder=true,native_roundtrip_version=1,
   nonce=mode=='stale'and'bad'or'00000001000000020000000300000004',consume_called=true,restore_called=true,complete_payload_restored=true,
   count_before=20,count_after_consume=19,count_after_restore=20,automatic_retry_allowed=false}
 end
end
local function setup(m)
 mode=m;files={};calls=0;reads=0
 files[base..'native-material-preview.json']=J.encode{ok=true,live_slot_unchanged=true,all_allowlisted_slot_identities_and_counts_unchanged=true,submit_called=false}
 if m~='missing_arm'then files[base..'native-roundtrip.arm.json']=J.encode{nonce=nonce,action='consume-one-wood-and-restore',expires_unix=2000000100,
  saved_backup_verified=m~='no_backup',saved_backup_reference='D:/PalworldServer-LAN/BridgeLab/Backups/test-Saved'}end
 if m=='prior_intent'then files[base..'native-roundtrip.intent.json']='prior durable intent'end
 if m=='already_claimed'then files[base..'native-roundtrip.claimed.bin']='prior claim'end
end
local function run(m,success,expected)
 setup(m);probe();local r=J.decode(assert(files[base..'native-roundtrip-probe.json']))
 assert(r.ok==success and calls==expected,m)
 if success then assert(r.all_allowlisted_slot_identities_and_counts_unchanged and r.lua_verified_native_response);probe();assert(calls==1,'reload repeated debit')end
end
run('ok',true,1);run('stale',false,1);run('changed',false,1);run('dynamic',false,0);run('bad_thread',false,0)
run('missing_arm',false,0);run('prior_intent',false,0);run('already_claimed',false,0);run('no_backup',false,0)
print('9 roundtrip Lua arming/intent/wire/conservation checks plus replay refusal passed')
