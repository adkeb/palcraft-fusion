-- Narrow actual bootstrap exporter shape test; no fixture can issue a real cert.
local M=dofile(arg[1]);local J=dofile(arg[2]);local ROOT=arg[3]
local CID='11111111-1111-4111-8111-111111111111';local ZERO='00000000-0000-0000-0000-000000000000'
local BOOT='aaaaaaaa-aaaa-4aaa-8aaa-000000000001'
local function obj(name,extra)extra=extra or{};extra.IsValid=function()return true end;extra.GetFullName=function()return name end;return extra end
local function guid(s)s=s:gsub('-','');return {A=tonumber(s:sub(1,8),16),B=tonumber(s:sub(9,16),16),C=tonumber(s:sub(17,24),16),D=tonumber(s:sub(25,32),16)}end
local R={guid_to_string=function(g)local s=string.format('%08x%08x%08x%08x',g.A,g.B,g.C,g.D);return s:sub(1,8)..'-'..s:sub(9,12)..'-'..s:sub(13,16)..'-'..s:sub(17,20)..'-'..s:sub(21)end,guid_from_string=guid}
local raw=string.pack('<i4i4i4',0,1,5)..'Wood\0'..string.rep('\0',32)
local bytes={};for i=1,#raw do bytes[i]=raw:byte(i)end
local array=function(rows)return {ForEach=function(_,fn)for i,row in ipairs(rows)do fn(i-1,{get=function()return row end})end end}end
local item={StaticId={ToString=function()return'Wood'end},DynamicId={CreatedWorldId=guid(ZERO),LocalIdInCreatedWorld=guid(ZERO)}}
local slot=obj('Slot',{GetStackCount=function()return 1 end,GetItemId=function()return item end,GetSlotId=function()return {ContainerId={ID=guid(CID)},SlotIndex=0}end})
local container=obj('Container',{Num=function()return 1 end,Get=function()return slot end})
local map={ForEach=function(_,fn)fn({get=function()return {ID=guid(CID)}end},{get=function()return {SlotNum=1,Slots=array{{RawData=bytes}}}end})end}
local saved=obj('LoadedSaved',{Version=100,Revision=102999,Timestamp={},worldSaveData={ItemContainerSaveData=map,GameTimeSaveData={RawData={}}}})
local manager=obj('SaveManager',{IsLoadedWorldData=function()return true end,GetLoadedWorldSaveData=function()return saved end,bIsUseBackupSaveData=false,WorldSaveDataLoadFailedDirectoryName=''})
local game=obj('GameState',{HasAuthority=function()return true end,GetWorldSaveDirectoryName=function()return'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'end,GetWorldName=function()return'World'end,ServerSessionId='actual-shape-session'})
local im=obj('ItemManager',{GetContainer=function()return container end})
local math=obj('Math',{GetYear=function()return 2026 end,GetMonth=function()return 10 end,GetDay=function()return 6 end,GetHour=function()return 3 end,GetMinute=function()return 0 end,GetSecond=function()return 0 end,GetMillisecond=function()return 100 end})
function FindAllOf(class)return class=='PalSaveGameManager'and{manager}or class=='PalGameStateInGame'and{game}or{im}end
function StaticFindObject(path)return path:find('KismetMathLibrary',1,true)and math or obj('Utility',{IsAllLevelLoaded=function()return true end})end
local pre={protocol=3,kind='palworld_prelaunch_checkpoint',boot_id=BOOT,epoch='pal-boot:'..BOOT,targets={slot_refs={{container_id=CID,slot=0}}}}
local function write(p,v)local f=assert(io.open(p,'wb'));f:write(J.encode(v));f:close()end
write(ROOT..'/escrow-boot-prelaunch.json',pre)
write(ROOT..'/rpc/escrow-boot-process-'..BOOT:gsub('-','')..'.json',{protocol=3,pid=1234,process_created_filetime='134000000000000000',boot_hex=BOOT:gsub('-','')})
local api=M.new{json=J,readers=R,root=ROOT,rpc_root=ROOT..'/rpc',test_mode=true}
local state=api.tick();assert(state.observed and not api.ready(),J.encode(state))
local f=assert(io.open(ROOT..'/bootstrap/'..BOOT..'/loaded.json','rb'));local report=J.decode(f:read('*a'));f:close()
assert(report.header.version==100 and report.containers[1].capacity==1 and report.transaction_slots[1].count==1)
assert(report.containers[1].slots[1].item=='Wood'and report.loaded_world_data and report.all_levels_loaded and not report.uses_backup)
write(ROOT..'/escrow-boot-certificate.json',{boot_id=BOOT,runtime_verified=true})
api.tick();assert(api.ready())
print('PASS bootstrap game-thread real API exporter shape + certificate admission transition')
