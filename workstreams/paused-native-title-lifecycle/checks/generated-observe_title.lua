assert(IsInGameThread(),'Owned game thread required')
local sp=assert(_G.PalCraftStandaloneBootstrap)
local p,epoch=assert(_G.PalCraftStandalonePermissions).process()
assert(epoch=="fixture-epoch",'Native boot changed')
local found={}
for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do if pc:IsValid() and not pc:GetFullName():find('Default__',1,true) and pc.Player:IsValid() and pc.Player:GetFullName():match('^PalLocalPlayer ') and pc:GetFullName():find('BP_PalPlayerController_Title_C',1,true) then found[#found+1]=pc end end
assert(#found==1,'Actual Title local controller pending')
return {request_id="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",token="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",process_epoch=epoch,action="observe_title",observed_unix=os.time()}
