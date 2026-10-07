-- Native teleport/mode reset boundaries are simulated; no live game operations.
local root=assert(arg[1]);local report=assert(arg[2])
local function object(id,name)
 local o={id=id,name=name};function o:IsValid()return true end
 function o:GetAddress()return self.id end;function o:GetFullName()return self.name end;return o
end
local movement=object(1,'FixtureMovement');movement.MovementMode=1;movement.CustomMovementMode=0;movement.stops=0;movement.disables=0
function movement:StopMovementImmediately()self.stops=self.stops+1;self.velocity=0 end
function movement:DisableMovement()self.disables=self.disables+1;self.MovementMode=0 end
function movement:SetMovementMode(mode,custom)self.MovementMode=mode;self.CustomMovementMode=custom end
local pawn=object(2,'FixturePawn');pawn.CharacterMovement=movement;pawn.position={X=1,Y=2,Z=3}
pawn.CapsuleComponent={GetScaledCapsuleHalfHeight=function()return 88 end}
function pawn:HasAuthority()return true end;function pawn:K2_GetActorLocation()return self.position end
local pc=object(3,'FixturePC');pc.Pawn=pawn;pc.moves=0;pc.looks=0
function pc:HasAuthority()return true end;function pc:GetControlRotation()return{Yaw=0,Pitch=0,Roll=0}end
function pc:SetIgnoreMoveInput(v)self.moves=self.moves+(v and 1 or -1)end
function pc:SetIgnoreLookInput(v)self.looks=self.looks+(v and 1 or -1)end
StaticFindObject=function()return{IsValid=function()return true end,Teleport=function(_,p,target)
 p.position={X=target.X,Y=target.Y,Z=target.Z};p.CharacterMovement.MovementMode=1;return true
end}end
local P={ue=function()return true end,quaternion=function(v)return v end,mc_rotation=function(y,p)return{Yaw=y,Pitch=p,Roll=0}end,
 distance=function(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)end,
 same_binding=function()return true end,registry=function()return{save=function()return{}end,retain=function()end}end}
local config={teleport_api='pal_utility',position_tolerance_cm=50,replication_timeout_ms=15000}
local function actor(path)return dofile(path).new{protocol=P,config=config,game_thread=function()return true end}end
local old=actor(root..'/base/server/actor.lua');local oldlock=old.hold(pc,true)
assert(movement.MovementMode==0);assert(old.teleport(pc,{X=1,Y=2,Z=3},{Yaw=0,Pitch=0,Roll=0}))
assert(oldlock.disabled and movement.MovementMode==1,'Original held mode reset must reproduce')
old.release(oldlock);assert(pc.moves==0 and pc.looks==0 and movement.MovementMode==1)
local api=actor(root..'/source/server/actor.lua');local lock=api.hold(pc,true)
local server=dofile(root..'/source/server/travel.lua').new{protocol=P,config=config,actor=api,
 resolve=function()return{pc=pc,mc_uuid='fixture',pal_uid='fixture'}end,
 send=function()return true end,journal={load=function()return{}end,save=function()return true end},
 view={activate=function()return true end},game_thread=function()return true end}
server._resolve=function()return{pc=pc,mc_uuid='fixture',pal_uid='fixture'}end
api.safety=function()return true end;server._send=function()return true end
server.now=10;server.world_session='fixture-world'
local tx={binding={mc_uuid='fixture'},_pc=pc,_pawn_address=pawn:GetAddress(),_lock=lock,
 _ticket={},phase='preparing',world_session=server.world_session,mapping={},target_pawn={X=1,Y=2,Z=3},yaw=0,pitch=0,
 source={snapshot={position={X=1,Y=2,Z=3}}}}
server:_move(tx);assert(tx.phase=='committed'and movement.MovementMode==0 and lock.disabled)
assert(pc.moves==1 and pc.looks==1,'No extra ignore-input stack entries')
movement.MovementMode=1;movement.velocity=1;tx.phase='recovery_required'
server:_progress(tx);assert(movement.MovementMode==0 and movement.velocity==0)
assert(pc.moves==1 and pc.looks==1,'Maintain must retain the same stack entries')
local count=movement.disables;server:_progress(tx);assert(movement.disables==count,'Already disabled mode remains untouched')
api.release(lock);assert(movement.MovementMode==1 and pc.moves==0 and pc.looks==0)
local clientlock=api.hold(pc,false);movement.MovementMode=1;assert(api.maintain_hold(clientlock));assert(movement.MovementMode==1);api.release(clientlock)
local stale=api.hold(pc,true);local replacement=object(4,'FixtureReplacement');replacement.CharacterMovement=object(5,'FixtureReplacementMovement');replacement.CharacterMovement.MovementMode=1
pc.Pawn=replacement;local ok,why=api.maintain_hold(stale);assert(ok==false and why=='owned_travel_hold_possession_changed')
assert(replacement.CharacterMovement.MovementMode==1);pc.Pawn=pawn;api.release(stale)
assert(pc.moves==0 and pc.looks==0 and movement.MovementMode==1)
local f=assert(io.open(report,'wb'));f:write([[{"schema":1,"passed":true,"cases":["original_native_reset_reproduced_and_normal_move_reasserts_owned_hold","pending_recovery_maintains_disable_without_extra_input_stack_and_release_restores","client_hold_does_not_disable_and_replacement_pawn_not_modified"],"native_teleport_reset_simulated":true,"current_game_or_state_modified":false,"actual_next14_travel_complete_verified":false}]]);f:close()
print('PASS: three owned travel hold lifecycle cases; simulated native boundary only')
