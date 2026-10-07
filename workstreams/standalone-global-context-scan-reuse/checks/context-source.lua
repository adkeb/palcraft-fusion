local function context()
 local sp=rawget(_G,'PalCraftStandaloneBootstrap')
 if sp then
  local realm=assert(sp.local_realm,'Actual standalone realm required')
  local proof,why=realm:current()
  assert(proof and proof.mode=='standalone',why or'Actual standalone context unavailable')
  local gs,pc,world=proof.game_state,proof.pc,proof.world
  assert(live(gs)and live(pc)and live(world)and gs:HasAuthority(),'Actual standalone native context changed')
  local gs_world,pc_world=gs:GetWorld(),pc:GetWorld()
  assert(live(gs_world)and live(pc_world)and gs_world:GetAddress()==world:GetAddress()
   and pc_world:GetAddress()==world:GetAddress()and world:GetAddress()==proof.world_address,'Actual standalone context world changed')
  return gs
 end
 for _,a in ipairs(FindAllOf('GameStateBase')or{})do if live(a)then return a end end;error('No game state')
end
return context
