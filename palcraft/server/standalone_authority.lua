-- Read actual local-world authority. No RPC, flags, actors or save writes.
-- Steam offline and a missing NetConnection are not authority evidence.
local M={}
local function valid(o)return o and o:IsValid()end
local function live(o)return valid(o)and not o:GetFullName():find('Default__',1,true)end
local function text(v)return type(v)=='string'and v or v:ToString()end
local function library(path)local o=StaticFindObject(path);assert(valid(o),'Native library unavailable: '..path);return o end
function M.connected(pc)
 assert(live(pc)and pc:HasAuthority(),'Actual authority player controller required')
 assert(live(pc.NetConnection),'Selected real player is not connected')
end
function M.read(pc,expected_world)
 assert(IsInGameThread(),'Existing game thread required')
 assert(live(pc)and pc:HasAuthority()and pc:IsLocalController(),'Actual local authority player controller required')
 assert(type(expected_world)=='string'and #expected_world==32 and expected_world:match('^%x+$'),'Actual loaded test-world directory required')
 local system=library('/Script/Engine.Default__KismetSystemLibrary')
 local pal=library('/Script/Pal.Default__PalUtility')
 local gameplay=library('/Script/Engine.Default__GameplayStatics')
 local game=gameplay:GetGameState(pc)
 assert(live(game)and game:HasAuthority(),'Current local authority game state required')
 local world=text(game:GetWorldSaveDirectoryName()):upper()
 assert(world==expected_world:upper(),'Actual local world differs from runtime-selected test world')
 local subsystem=pal:GetOptionSubsystem(pc)
 assert(live(subsystem)and subsystem:GetWorld():GetAddress()==pc:GetWorld():GetAddress(),'Actual world option subsystem differs')
 local options=subsystem.OptionWorldSettings
 assert(options and options.bIsMultiplay==false,'Loaded world multiplayer option must actually be off')
 local dedicated=system:IsDedicatedServer(pc)
 assert(dedicated==false,'Dedicated server is outside current singleplayer scope')
 local engine_single=system:IsStandalone(pc)
 local pal_multi=pal:IsMultiplayer(pc)
 assert(type(engine_single)=='boolean'and type(pal_multi)=='boolean','Native network-mode observation unavailable')
 -- A game may implement its singleplayer world with an internal listen host.
 -- Record its real engine mode; authorize the actual local/world-off state,
 -- rather than inventing NM_Standalone or treating IsMultiplayer as a UI flag.
 local remote=0
 for _,other in ipairs(FindAllOf('PalPlayerController')or{})do
  if live(other)and other:HasAuthority()and not other:IsLocalController()and live(other.NetConnection)then
   local state=gameplay:GetGameState(other)
   if live(state)and state:GetFullName()==game:GetFullName()then remote=remote+1 end
  end
 end
 assert(remote==0,'A remote possessed player is outside current singleplayer scope')
 return {mode='standalone',world_directory=world,game_state_object=game:GetFullName(),
  server_session_id=text(game.ServerSessionId),local_controller=true,has_authority=true,
  world_multiplayer_enabled=false,dedicated_server=false,remote_connected_players=remote,
  engine_is_standalone=engine_single,pal_is_multiplayer=pal_multi,
  native_net_mode=text(pal:GetNetMode(pc)),net_connection_present=live(pc.NetConnection)==true}
end
return M
