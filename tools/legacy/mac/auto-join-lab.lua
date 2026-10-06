local tries=0
local function join()
 tries=tries+1
 for _,w in ipairs(FindAllOf('UserWidget')or{})do
  if w:IsValid()and w:GetFullName():match('^WBP_TitleMenu_C /Engine/Transient')then
   w['BndEvt__WBP_TitleMenu_WBP_Title_MenuButton_StartMultiGame_K2Node_ComponentBoundEvent_2_OnClicked__DelegateSignature'](w)
   ExecuteInGameThreadWithDelay(2000,function()
    for _,j in ipairs(FindAllOf('PalUIJoinGameBase')or{})do
     if j:IsValid()and j:GetFullName():find('/Engine/Transient',1,true)then j:ConnectServerByAddress('127.0.0.1',8321);break end
    end
   end)
   return
  end
 end
 if tries<30 then ExecuteInGameThreadWithDelay(1000,join)end
end
ExecuteInGameThreadWithDelay(1000,join)
return {stage='waiting_for_title_menu',target='127.0.0.1:8321'}
