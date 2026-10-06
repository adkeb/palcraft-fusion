-- Only parent deploys this observer. Top-level dofile from BridgeLab main.lua.
-- It captures one manual ItemChest RPC; it never initiates/changes a game action.
local source=debug.getinfo(1,'S').source
local directory=assert(source:match('^@(.*[/\\])'),'script directory unavailable')
assert(directory:lower():gsub('\\','/')=='d:/palworldserver-lan/bridgelab/pal/binaries/win64/ue4ss/mods/pallivebridge/scripts/','BridgeLab script path mismatch')
local ROOT='D:/PalworldServer-LAN/BridgeLab/rpc/'
local J=dofile(directory..'json.lua');local R=dofile(directory..'readers.lua');local T=dofile(directory..'targets.lua')
local Core=dofile(directory..'manual-build-observer-core.lua')
local function read(path,max)local f=assert(io.open(path,'rb'));local s=f:read(max+1);f:close();assert(#s<=max,'input oversized');return J.decode(s)end
local cfg=read(ROOT..'manual-build-observer-arm.json',4096)
assert(type(cfg.observation_id)=='string'and cfg.observation_id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'invalid observation id')
assert(type(cfg.target_player_uid)=='string'and R.guid_to_string(R.guid_from_string(cfg.target_player_uid))==cfg.target_player_uid,'invalid target UID')
local outfile=ROOT..'manual-build-observation-'..cfg.observation_id..'.json'
local existing=io.open(outfile,'rb');if existing then existing:close();print('[ManualBuildObserver] existing observation refuses rearm\n');return end
local context=read(ROOT..'client-context.json',65536);assert(context.ok and context.lab_only and context.read_only,'live context report invalid')
local selected;for _,p in ipairs(context.players or{})do if p.player_uid==cfg.target_player_uid then assert(not selected,'duplicate context');selected=p end end
assert(selected and selected.can_build_in_guild and selected.wood_chest_unlocked and selected.wood_chest_denied==false,'verified selected player context missing')
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function same(o,name)return live(o)and o:GetFullName()==name end
local function player_state(o,kind)
    if kind=='request'then
        if not same(o,selected.player_component)then return nil end
        local tr=o:GetOwner();assert(same(tr,selected.transmitter),'transmitter identity changed')
        local pc=tr:GetOwner();assert(same(pc,selected.controller),'controller identity changed')
        assert(R.guid_to_string(pc:GetPlayerUId())==cfg.target_player_uid,'player UID mismatch')
        local ps=pc:GetPalPlayerState();assert(same(ps,selected.player_state),'player state identity changed');return ps
    end
    if not same(o,selected.player_state)then return nil end
    local pc=o:GetPlayerController();assert(same(pc,selected.controller),'result controller changed')
    assert(R.guid_to_string(pc:GetPlayerUId())==cfg.target_player_uid,'result UID mismatch');return o
end
local function snapshot()
    assert(IsInGameThread(),'material observation requires game thread')
    local ps=StaticFindObject(selected.player_state:match('^[^ ]+ (.*)$'));assert(player_state(ps,'result'),'selected player no longer live')
    local inv=ps:GetInventoryData();assert(live(inv),'inventory unavailable')
    local result={observed_unix=os.time(),player_uid=cfg.target_player_uid,carried={},chests=J.array(),chest_totals={Wood=0,Stone=0},subset_only=true}
    for _,id in ipairs({'Wood','Stone'})do local n=inv:CountItemNum64(FName(id));assert(type(n)=='number'and n>=0 and n%1==0,'invalid carried count');result.carried[id]=n end
    local s=R.chests(T,{include_items=true,verify_ownership=true,require_snapshot_ownership=true})
    assert(s.ok and s.verified_live,'ordinary chest subset snapshot unavailable')
    for _,c in ipairs(s.chests)do local row={container_id=c.id,base_id=c.base_id_live,guild_id=c.group_id_live,counts={Wood=0,Stone=0},material_slots=J.array()}
        for _,slot in ipairs(c.slots)do if not slot.empty and(row.counts[slot.item]~=nil)then
            row.counts[slot.item]=row.counts[slot.item]+slot.count
            row.material_slots[#row.material_slots+1]={index=slot.index,item=slot.item,count=slot.count,dynamic_guid=slot.dynamicGuid,dynamic_world_guid=slot.dynamicWorldGuid}
        end end
        for _,id in ipairs({'Wood','Stone'})do result.chest_totals[id]=result.chest_totals[id]+row.counts[id]end
        result.chests[#result.chests+1]=row
    end
    return result
end
local observer=Core.start{json=J,config=cfg,now=os.time,is_game_thread=IsInGameThread,
    register=RegisterHook,unregister=UnregisterHook,match_context=function(kind,o)return player_state(o,kind)~=nil end,snapshot=snapshot,
    emit=function(report)
        report.verified_context=selected
        local f=assert(io.open(outfile..'.tmp','wb'));assert(f:write(J.encode(report,{max_bytes=1048576})));assert(f:close())
        os.remove(outfile);assert(os.rename(outfile..'.tmp',outfile))
    end,
    stop_requested=function()local f=io.open(ROOT..'manual-build-observer-stop-'..cfg.observation_id,'rb');if f then f:close();return true end;return false end}
local queued=false
LoopAsync(500,function()
    if observer.report.stopped_unix then return true end
    if not queued then queued=true;ExecuteInGameThread(function()
        local ok,e=pcall(observer.tick);queued=false
        if not ok then observer.stop('tick_error:'..tostring(e))end
    end)end
    return false
end)
print('[ManualBuildObserver] '..observer.report.status..' '..cfg.observation_id..'\n')
return observer
