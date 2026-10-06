-- New authority-branch regressions only. No game, RPC or timer fixtures.
local Module=assert(arg[1])
local function object(name,fields)
 fields=fields or{};fields.IsValid=function()return true end;fields.GetFullName=function()return name end;return fields
end
local WORLD='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
local game=object('ActualFixtureGameState',{HasAuthority=function()return true end,GetWorldSaveDirectoryName=function()return WORLD end,ServerSessionId=''})
local pc=object('ActualFixturePC',{HasAuthority=function()return true end,IsLocalController=function()return true end})
local settings={bIsMultiplay=false}
local native={standalone=true,dedicated=false,multiplayer=false,mode='fixture:standalone'}
local players={pc}
local system=object('Default__KismetSystemLibrary',{IsStandalone=function()return native.standalone end,IsDedicatedServer=function()return native.dedicated end})
local pal=object('Default__PalUtility',{GetOptionSubsystem=function()return subsystem end,IsMultiplayer=function()return native.multiplayer end,GetNetMode=function()return native.mode end})
local subsystem=object('FixtureOptionSubsystem',{OptionWorldSettings=settings})
local gameplay=object('Default__GameplayStatics',{GetGameState=function()return game end})
function StaticFindObject(path)
 if path:find('KismetSystemLibrary',1,true)then return system end
 if path:find('GameplayStatics',1,true)then return gameplay end
 return pal
end
function IsInGameThread()return true end
function FindAllOf()return players end
local A=dofile(Module);local passed=0
local function check(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function refuses(fn)assert(not pcall(fn),'Expected actual-scope rejection')end
check('local-authority-nil-socket-native-singleplayer',function()
 local r=A.read(pc,WORLD);assert(r.local_controller and r.has_authority and not r.net_connection_present and r.engine_is_standalone)
end)
check('network-branch-still-requires-real-socket',function()
 refuses(function()A.connected(pc)end);pc.NetConnection=object('FixtureNetConnection');A.connected(pc);pc.NetConnection=nil
end)
check('world-off-local-listen-records-real-mode-without-faking-standalone',function()
 native.standalone=false;native.multiplayer=true;native.mode='fixture:internal-listen'
 local r=A.read(pc,WORLD);assert(not r.engine_is_standalone and r.pal_is_multiplayer and r.world_multiplayer_enabled==false)
 native.standalone=true;native.multiplayer=false
end)
check('multiplayer-world-option-not-waived',function()
 settings.bIsMultiplay=true;refuses(function()A.read(pc,WORLD)end);settings.bIsMultiplay=false
end)
check('dedicated-authority-not-a-singleplayer-host',function()
 native.dedicated=true;refuses(function()A.read(pc,WORLD)end);native.dedicated=false
end)
check('client-or-nonlocal-controller-not-a-host',function()
 pc.HasAuthority=function()return false end;refuses(function()A.read(pc,WORLD)end);pc.HasAuthority=function()return true end
 pc.IsLocalController=function()return false end;refuses(function()A.read(pc,WORLD)end);pc.IsLocalController=function()return true end
end)
check('other-current-world-network-player-not-hidden',function()
 local other=object('OtherPC',{HasAuthority=function()return true end,IsLocalController=function()return false end,NetConnection=object('OtherConnection')})
 players={pc,other};refuses(function()A.read(pc,WORLD)end);players={pc}
end)
check('runtime-world-and-native-return-shape-must-match',function()
 refuses(function()A.read(pc,'00000000000000000000000000000000')end)
 native.standalone=nil;refuses(function()A.read(pc,WORLD)end);native.standalone=true
end)
print('RESULT '..passed)
