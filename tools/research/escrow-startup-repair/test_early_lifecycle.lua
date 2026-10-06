-- One targeted lifecycle regression, not engine/API certification.
local M=dofile(arg[1]);local J=dofile(arg[2]);local ROOT=arg[3]
local BOOT='aaaaaaaa-aaaa-4aaa-8aaa-000000000001'
local CID='11111111-1111-4111-8111-111111111111'
local function object(name,fields,address)
 fields=fields or{};fields.IsValid=function()return true end
 fields.GetFullName=function()return name end;fields.GetAddress=function()return address or 100 end
 return fields
end
local function guid(s)
 s=s:gsub('-','');return{A=tonumber(s:sub(1,8),16),B=tonumber(s:sub(9,16),16),C=tonumber(s:sub(17,24),16),D=tonumber(s:sub(25,32),16)}
end
local R={guid_from_string=guid,guid_to_string=function(g)
 local s=string.format('%08x%08x%08x%08x',g.A,g.B,g.C,g.D)
 return s:sub(1,8)..'-'..s:sub(9,12)..'-'..s:sub(13,16)..'-'..s:sub(17,20)..'-'..s:sub(21)
end}
local raw=string.pack('<i4i4i4',0,1,5)..'Wood\0'..string.rep('\0',32)
local bytes={};for i=1,#raw do bytes[i]=raw:byte(i)end
local map={ForEach=function(_,fn)
 fn({get=function()return{ID=guid(CID)}end},{get=function()return{SlotNum=1,Slots={{RawData=bytes}}}end})
end}
local game_time=setmetatable({GameDateTimeTicks=1,RealDateTimeTicks=123456789012345678},
 {__index=function(_,key)error('Native PalGameTimeSaveData has no reflected field '..key)end})
local save=object('PalWorldSaveGame /Engine/Transient.ActualLoaderFixture',
 {Version=100,Revision=102999,Timestamp={},worldSaveData={ItemContainerSaveData=map,GameTimeSaveData=game_time}},300)
save.GetClass=function()return object('Class /Script/Pal.PalWorldSaveGame')end
local loaded_flag=false;local loaded=save
local manager=object('PalSaveGameManager /Engine/Transient.ActualManagerFixture',{
 IsLoadedWorldData=function()return loaded_flag end,GetLoadedWorldSaveData=function()return loaded end,
 bIsUseBackupSaveData=false,WorldSaveDataLoadFailedDirectoryName=''},200)
manager.LoadedWorldSaveData=save
local game=object('PalGameStateInGame /Game/Pal/Maps/MainWorld_5.World',{
 HasAuthority=function()return true end,GetWorldSaveDirectoryName=function()return'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'end,
 GetWorldName=function()return'World'end,ServerSessionId='fixture-no-runtime-certificate'})
local date=object('KismetMathLibrary /Script/Engine.Default__KismetMathLibrary',{
 GetYear=function()return 2026 end,GetMonth=function()return 10 end,GetDay=function()return 6 end,
 GetHour=function()return 3 end,GetMinute=function()return 0 end,GetSecond=function()return 0 end,
 GetMillisecond=function()return 100 end})
local utility=object('PalUtility /Script/Pal.Default__PalUtility',{IsAllLevelLoaded=function()return true end})
function FindAllOf(class)
 if class=='PalSaveGameManager'then return{manager}end
 if class=='PalGameStateInGame'then return{game}end
 if class=='PalItemContainerManager'then return{object('ItemContainerManager')}end
 return{}
end
function StaticFindObject(path)return path:find('KismetMathLibrary',1,true)and date or utility end
local queued
function ExecuteInGameThreadAfterFrames(frames,fn)assert(frames==1 and not queued);queued=fn end
local function step()local fn=assert(queued);queued=nil;fn()end
local function write(path,value)local f=assert(io.open(path,'wb'));f:write(J.encode(value));f:close()end
write(ROOT..'/escrow-boot-prelaunch.json',{protocol=3,kind='palworld_prelaunch_checkpoint',boot_id=BOOT,
 epoch='pal-boot:'..BOOT,targets={slot_refs={}}})
write(ROOT..'/rpc/escrow-boot-process-'..BOOT:gsub('-','')..'.json',{
 protocol=3,pid=1234,boot_hex=BOOT:gsub('-',''),fixture_only=true})
local api=M.new{json=J,readers=R,root=ROOT,rpc_root=ROOT..'/rpc',test_mode=true}
api.start_early();step();assert(queued and not api.status().loader_captured)
loaded_flag=true;step();assert(not queued and api.status().loader_captured)
-- The engine releases both its getter result and pointer before late dispatch.
loaded=nil;manager.LoadedWorldSaveData=nil;manager.bIsUseBackupSaveData=true
local state=api.tick();assert(state.observed and not api.ready(),J.encode(state))
local f=assert(io.open(ROOT..'/bootstrap/'..BOOT..'/loaded.json','rb'))
local report=J.decode(f:read('*a'));f:close()
assert(report.header.real_date_time_ticks=='123456789012345678')
assert(report.containers[1].slots[1].item=='Wood'and report.containers[1].slots[1].count==1)
assert(report.loader_observation.save_class=='Class /Script/Pal.PalWorldSaveGame')
assert(report.all_levels_loaded and report.loaded_world_data and report.uses_backup==true)
assert(report.loader_observation.uses_backup_at_capture==false)
assert(not api.ready(),'Fixture must never issue a runtime certificate')
print('PASS one targeted early-copy -> released loader -> late-world readiness lifecycle; strict real GameTime Int64 shape and raw backup values preserved; not real engine evidence')
