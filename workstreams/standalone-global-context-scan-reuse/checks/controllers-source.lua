local function player_controllers()
  if realm then
   local proof=current_authority(gs);local pc=proof.pc
   assert(live(pc)and pc:HasAuthority()and guid(pc:GetPlayerUId())==proof.host_uid
    and live(pc.Pawn)and live(proof.pawn)and pc.Pawn:GetAddress()==proof.pawn:GetAddress(),'Actual standalone player controller changed')
   return{pc}
  end
  return FindAllOf('PalPlayerController')or{}
 end
 return player_controllers
