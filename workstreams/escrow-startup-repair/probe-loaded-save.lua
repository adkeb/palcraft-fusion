-- One-shot server GAME THREAD probe for the runtime owner's trusted read queue.
-- Returns selected reflected state; no hooks, save/item/actor mutation or timers.
assert(IsInGameThread(),'Server game thread required')
local function valid(o)return o and o:IsValid()end
local function describe(o)
 if not o then return{present=false,valid=false}end
 if not valid(o)then return{present=true,valid=false}end
 local c=o:GetClass()
 return{present=true,valid=true,address=string.format('0x%x',o:GetAddress()),name=o:GetFullName(),
  class=valid(c)and c:GetFullName()or false}
end
local function get(fn)
 local ok,v=pcall(fn);if ok then return v end;return{error=tostring(v)}
end
local function text(v)return type(v)=='string'and v or v:ToString()end
local out={kind='palworld_loader_api_probe',read_only=true,unix=os.time(),managers={},save_objects={},init={}}
for _,m in ipairs(FindAllOf('PalSaveGameManager')or{})do
 if valid(m)and not m:GetFullName():find('Default__',1,true)then
  local row={manager=describe(m)}
  row.loaded_flag=get(function()return m:IsLoadedWorldData()end)
  row.loaded_field_flag=get(function()return m.bIsLoadedWorldSaveData end)
  row.getter=get(function()return describe(m:GetLoadedWorldSaveData())end)
  row.field=get(function()return describe(m.LoadedWorldSaveData)end)
  row.uses_backup=get(function()return m.bIsUseBackupSaveData end)
  row.failed_directory=get(function()return text(m.WorldSaveDataLoadFailedDirectoryName)end)
  out.managers[#out.managers+1]=row
 end
end
for _,s in ipairs(FindAllOf('PalWorldSaveGame')or{})do
 if valid(s)and not s:GetFullName():find('Default__',1,true)then
  local row=describe(s)
  row.version=get(function()return s.Version end);row.revision=get(function()return s.Revision end)
  out.save_objects[#out.save_objects+1]=row
 end
end
for _,i in ipairs(FindAllOf('PalGameSystemInitManagerComponent')or{})do
 if valid(i)and not i:GetFullName():find('Default__',1,true)then
  out.init[#out.init+1]={manager=describe(i),current_sequence_index=get(function()return i.CurrentSequenceIndex end),
   can_refer_to_world=get(function()return i.bCanReferToWorldObject end)}
 end
end
out.utility=describe(StaticFindObject('/Script/Pal.Default__PalUtility'))
out.date_library=describe(StaticFindObject('/Script/Engine.Default__KismetMathLibrary'))
if _G.PalCraftServerFeatures and _G.PalCraftServerFeatures.boot_observer then
 out.observer=_G.PalCraftServerFeatures.boot_observer.status()
end
return out
