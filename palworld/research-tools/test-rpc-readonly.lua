local scripts='work/palworld-live/bridge/PalLiveBridge/Scripts/'
local core=scripts..'rpc-main.lua'
local J=dofile(scripts..'json.lua')
local R=dofile(scripts..'readers.lua')
local T=dofile(scripts..'targets.lua')
local f=assert(io.open('work/palworld-live/lab/audit-live-before.json','rb'))
local AUDIT=J.decode(f:read('a'),{max_bytes=8388608});f:close()
local function copy(t)return J.decode(J.encode(t,{max_bytes=8388608}),{max_bytes=8388608})end
local files, writes={},{}
local now=os.time()
local inside=false
local counter={bases=0,chests=0,guid=0}
local readers={guid_to_string=R.guid_to_string}
function readers.bases()assert(inside);counter.bases=counter.bases+1;return copy(AUDIT.bases)end
function readers.chests(targets)
 assert(inside);counter.chests=counter.chests+1
 local report=copy(AUDIT.storage);report.chests=J.array({})
 local wanted={} for _,t in ipairs(targets.chests)do wanted[t.container_id]=true end
 for _,c in ipairs(AUDIT.storage.chests)do if wanted[c.id]then report.chests[#report.chests+1]=copy(c)end end
 return report
end
local fakeos={time=function()return now end,date=os.date}
function fakeos.remove(path)files[path]=nil;return true end
function fakeos.rename(from,to)
 if files[to] then return nil,'destination exists' end
 if not files[from]then return nil,'source missing'end
 files[to]=files[from];files[from]=nil;return true
end
local fakeio={}
function fakeio.open(path,mode)
 if mode=='rb'then
  if files[path]==nil then return nil,'not found'end
  return {read=function(_,n)return files[path]:sub(1,n)end,close=function()return true end}
 elseif mode=='wb'then
  assert(path:sub(-4)=='.tmp','all writes must be temporary')
  writes[#writes+1]=path
  local data=''
  return {write=function(self,s)data=data..s;return self end,close=function()files[path]=data;return true end}
 end
 error('unexpected mode')
end
local callback
local function newenv()
 local env=setmetatable({}, {__index=_G})
 env.io=fakeio;env.os=fakeos;env.print=function()end
 env.dofile=function(path)
  if path:match('readers.lua$')then return readers end
  if path:match('targets.lua$')then return T end
  if path:match('json.lua$')then return J end
  error('unexpected path')
 end
 env.LoopAsync=function(ms,fn)assert(ms==250);callback=fn end
 env.ExecuteInGameThread=function(fn)inside=true;fn();inside=false end
 env.FindFirstOf=function(class)assert(inside);assert(class=='PalItemContainerManager');return {IsValid=function()return true end}end
 env.StaticFindObject=function(path)
  assert(inside)
  if path=='/Script/Engine.Default__KismetGuidLibrary'then
   return {IsValid=function()return true end,NewGuid=function()counter.guid=counter.guid+1;return{A=0,B=0,C=0,D=counter.guid}end}
  elseif path=='/Script/Pal.Default__PalUtility'then
   return{IsValid=function()return true end,GetDisplayVersion=function()return'v1.0.5'end}
  end
  error('unexpected object')
 end
 return env
end
assert(loadfile(core,'t',newenv()))()
now=now+16;callback()
local rpc='D:/PalworldServer-LAN/BridgeLab/rpc/'
local cap=J.decode(assert(files[rpc..'capabilities.json']))
assert(cap.capabilities['bases.list'].verified)
assert(cap.capabilities['storage.list'].verified)
assert(not cap.capabilities['storage.apply'].supported)
assert(cap.startup_error==J.null)
local instance=cap.server_instance_id
local sequence=10
local function req(method,params,deadline,extra)
 sequence=sequence+1
 local q={protocol_version=1,request_id=string.format('00000000-0000-0000-0000-%012x',sequence),
  method=method,params=params or {},deadline_utc=deadline or os.date('!%Y-%m-%dT%H:%M:%SZ',now+20)}
 for k,v in pairs(extra or{})do q[k]=v end
 local raw=J.encode(q)
 files[rpc..'request.json']=raw;callback()
 assert(files[rpc..'request.json']==nil,'queue must be cleared')
 local body=assert(files[rpc..'responses/'..q.request_id..'.json'])
 local response=J.decode(body,{max_bytes=8388608})
 assert(response.request_id==q.request_id and response.protocol_version==1)
 return response,q,raw
end
local b=req('bases.list',{})assert(b.ok and #b.result.bases==3)
local gid=AUDIT.bases.bases[1].group_id
b=req('bases.list',{guild_id=gid:upper()})assert(b.ok and #b.result.bases==3)
b=req('bases.list',{guild_id='00000000-0000-0000-0000-000000000000'})assert(b.ok and #b.result.bases==0)
local first=AUDIT.bases.bases[1].id
local s,q,raw=req('storage.list',{base_id=first})assert(s.ok and #s.result.chests==13)
assert(s.result.include_empty_containers and not s.result.coverage.automatic_discovery)
assert(s.result.server_instance_id==instance and s.result.reader_verified)
local before=counter.chests
files[rpc..'request.json']=raw;callback();assert(counter.chests==before and not files[rpc..'request.json'])
s=req('storage.list',{base_id=AUDIT.bases.bases[3].id})assert(s.ok and #s.result.chests==0 and s.result.coverage.selected_known_containers==0)
s=req('storage.list',{base_id=AUDIT.bases.bases[2].id,include_empty=false})assert(s.ok)
for _,c in ipairs(s.result.chests)do assert(c.occupied>0)end
local normal_chests=readers.chests
readers.chests=function(targets)local report=normal_chests(targets);report.ok=false;return report end
local failed=req('storage.list',{base_id=first});assert(not failed.ok and failed.error.code=='backend_unavailable')
readers.chests=normal_chests
before=counter.chests
local cases={
 {'storage.apply',{},nil,nil,'unsupported'},
 {'storage.plan',{},nil,nil,'unsupported'},
 {'storage.list',{base_id=first,include_empty='yes'},nil,nil,'invalid_request'},
 {'bases.list',{},'2026-02-30T00:00:00Z',nil,'invalid_request'},
 {'bases.list',{},'2026-10-04T00:00:00+00:00',nil,'invalid_request'},
 {'bases.list',{},os.date('!%Y-%m-%dT%H:%M:%SZ',now-1),nil,'timeout'},
 {'bases.list',{},os.date('!%Y-%m-%dT%H:%M:%SZ',now+120),nil,'invalid_request'},
 {'bases.list',{},nil,{path='ignored-not-read'},'invalid_request'},
 {'storage.list',{base_id='../../arbitrary'},nil,nil,'invalid_request'},
 {'storage.list',{base_id=first,code='error(1)'},nil,nil,'invalid_request'}
}
for _,c in ipairs(cases)do local res=req(c[1],c[2],c[3],c[4]);assert(not res.ok and res.error.code==c[5],c[5]..' expected')end
assert(counter.chests==before)
files[rpc..'request.json']='{broken';callback();assert(not files[rpc..'request.json'] and files[rpc..'last-rejected.json'])
files[rpc..'request.json']=string.rep('x',1048577);callback();assert(not files[rpc..'request.json'])
now=now+2;callback();cap=J.decode(files[rpc..'capabilities.json']);assert(cap.server_instance_id==instance)
assert(loadfile(core,'t',newenv()))();callback();cap=J.decode(files[rpc..'capabilities.json']);assert(cap.server_instance_id~=instance)
print('Read-only RPC mocks passed: 3 bases, 13/5/0 target coverage, filtering, deadlines, malformed input, allowlist, duplicate suppression, atomic response writes, game-thread-only UE access, reload UUID rotation.')
