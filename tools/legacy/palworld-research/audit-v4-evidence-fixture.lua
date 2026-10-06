-- Independent reviewer: run the ACTUAL host evidence function with real local
-- evidence fixtures. No UE, timers, game calls, or remote/filesystem writes.
local root='work/palworld-live/'
local J=dofile(root..'bridge/PalLiveBridge/Scripts/json.lua')
local Core=dofile(root..'lab/hook-free-rebuild-v4-core.lua')
local function readlocal(path)
    local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s
end
local source=readlocal(root..'lab/hook-free-rebuild-v4.lua')
local lab='D:/PalworldServer-LAN/BridgeLab/'
local dir=lab..'Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'
local rpc=lab..'rpc/'
local checkpoint=readlocal(root..'lab/hook-free-rebuild-v4-checkpoint.json')
local cfg={mode='execute',nonce='00000000-0000-4000-8000-000000000022',
    supersedes_failed_operation='00000000-0000-4000-8000-000000000017',
    backup_evidence_sha256=Core.sha256(checkpoint),expires_unix=os.time()+120}
local files={
    [rpc..'hook-free-rebuild-v4-arm.json']=J.encode(cfg),
    [rpc..'normal-rebuild-once.intent.json']=readlocal(root..'lab/rebuild-crash-20261004/intent.json'),
    [rpc..'hook-free-rebuild-v4-recovery-evidence.json']=readlocal(root..'lab/rebuild-crash-20261004/last-save-state-summary.json'),
    [rpc..'hook-free-rebuild-v4-checkpoint.json']=checkpoint,
    [rpc..'normal-rebuild-nearby-baseline.json']=readlocal(root..'lab/client-manual-nearby-saved-buildings.json'),
}
local captured,game_calls,timer_calls=nil,0,0
local env=setmetatable({}, {__index=_G})
env.io={open=function(path,mode)
    if mode=='rb' then
        local value=files[path];if not value then return nil,'not found' end
        return {read=function(_,n)return n=='*a'and value or value:sub(1,n)end,close=function()return true end}
    end
    assert(mode=='ab' and path:match('%.trace%.jsonl$'),'unexpected attempted file write: '..path)
    return {write=function()return true end,flush=function()return true end,close=function()return true end}
end}
env.dofile=function(path)
    if path==dir..'json.lua'then return J end
    if path==dir..'hook-free-rebuild-v4-core.lua'then
        return {sha256=Core.sha256,new=function(deps,arm)captured=deps;assert(arm.nonce==cfg.nonce);return{report={}}end}
    end
    if path==dir..'targets.lua'then return dofile(root..'bridge/PalLiveBridge/Scripts/targets.lua')end
    assert(path==dir..'readers.lua' or path==dir..'build.lua' or path==dir..'normal-rebuild-materials.lua'
        or path==dir..'full-observer-readonly-v3-core.lua' or path==dir..'registered-model-details-core.lua',path)
    return {}
end
env.ExecuteInGameThread=function()timer_calls=timer_calls+1 end
env.LoopAsync=function()timer_calls=timer_calls+1 end
env.IsInGameThread=function()return false end
env.FindAllOf=function()game_calls=game_calls+1;error('unexpected UE access')end
env.StaticFindObject=env.FindAllOf
env.FName=env.FindAllOf
assert(load(source,'@'..dir..'hook-free-rebuild-v4.lua','t',env))()
assert(captured,'actual host dependencies not captured')
local result=captured.verify_evidence()
assert(result.old_intent_sha256=='70bbd8cb31fe0d7326db4983cfeee20682e39bc584cd648de1695616a060c2d5')
assert(result.fresh_backup.file_count==97)
assert(result.fresh_backup.level_sha256=='01e4c81ffb2b8511380e8ca645108d33d5cd5ba3b0ae921e6679f94bef9ec53d')
assert(game_calls==0 and timer_calls==2,'unexpected game call or callback execution')
local manifest=J.decode(checkpoint)
local totallevels,main=0,0
for _,f in ipairs(manifest.files)do
    local path=f.path:gsub('\\','/')
    if path:match('/Level%.sav$')then totallevels=totallevels+1 end
    if path=='SaveGames/0/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/Level.sav'then main=main+1 end
end
assert(totallevels==11 and main==1,'actual fixture cardinality differs')
files[rpc..'hook-free-rebuild-v4-checkpoint.json']=checkpoint..' '
assert(not pcall(captured.verify_evidence),'mutated checkpoint bytes accepted')
files[rpc..'hook-free-rebuild-v4-checkpoint.json']=checkpoint
files[rpc..'normal-rebuild-once.intent.json']=files[rpc..'normal-rebuild-once.intent.json']..' '
assert(not pcall(captured.verify_evidence),'mutated old intent accepted')
assert(game_calls==0)
print('PASS actual v4 host evidence with real 97-file/11-Level fixture; exactly one main Level selected; checkpoint/old-intent byte tampering rejected; zero UE calls')
