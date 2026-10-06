-- Exact reflected SDK signatures, thread affinity, authority and owned input-lock lifecycle.
local root=assert(arg[1]);local P=dofile(root..'/travel/protocol.lua');local c=dofile(root..'/travel/config.lua')
local A=dofile(root..'/travel/actor.lua');local count=0;local checks={}
local function check(name,f)f();count=count+1;checks[#checks+1]=name end
local next_id=0
local function object(name,t)
 next_id=next_id+1;t=t or{};t.address=next_id;t.valid=true;t.name=name
 function t:IsValid()return self.valid end
 function t:GetAddress()return self.address end
 function t:GetFullName()return self.name end
 return t
end
local world=object('World');local settings=object('WorldSettings',{KillZ=-10000,bEnableWorldBoundsChecks=true})
world.PersistentLevel=object('PersistentLevel')
function settings:GetWorld()return world end
function settings:GetOuter()return world.PersistentLevel end
local decoy_settings
local saved_objects={};local game_thread=true;local authority=true;local player_uid='pal-one'
local capsule=object('Capsule');function capsule:GetScaledCapsuleHalfHeight()return 80 end
local movement=object('Movement',{MovementMode=1,CustomMovementMode=2,MaxWalkSpeed=430,JumpZVelocity=420})
function movement:StopMovementImmediately()self.stopped=true end
function movement:DisableMovement()self.MovementMode=0 end
function movement:SetMovementMode(m,custom)self.MovementMode=m;self.CustomMovementMode=custom end
local pawn=object('PalPlayerCharacter',{CharacterMovement=movement,CapsuleComponent=capsule,position={X=0,Y=0,Z=0},inventory={Wood=13},health=91})
function pawn:HasAuthority()return authority end
function pawn:K2_GetActorLocation()return P.copy(self.position)end
local pc=object('PalPlayerController',{Pawn=pawn,move=2,look=3})
function pc:HasAuthority()return authority end
function pc:GetWorld()return world end
function pc:SetIgnoreMoveInput(v)self.move=self.move+(v and 1 or-1)end
function pc:SetIgnoreLookInput(v)self.look=self.look+(v and 1 or-1)end
function pc:GetControlRotation()return{Yaw=20,Pitch=5,Roll=0}end
local library=object('Default__PalUtility');local native_calls=0
function library:Teleport(target,location,quaternion,no_check,around_check)
 assert(target==pawn and no_check==false and around_check==false,'Exact PalUtility reflected call')
 assert(type(quaternion.W)=='number');local norm=0;for _,k in ipairs({'X','Y','Z','W'})do norm=norm+quaternion[k]^2 end
 assert(math.abs(norm-1)<1e-10,'Unit FQuat required');native_calls=native_calls+1
 if self.reject then return false end;pawn.position=P.copy(location);return true
end
function StaticFindObject(path)assert(path=='/Script/Pal.Default__PalUtility');return library end
function FindAllOf(class)
 if class=='WorldSettings'then return decoy_settings and{decoy_settings,settings}or{settings}elseif class=='PalMapObject'then return saved_objects end
 error('Unexpected scene mutation/discovery: '..class)
end
local api=A.new{protocol=P,config=c,game_thread=function()return game_thread end,
 verify_identity=function(_,binding)return binding.pal_uid==player_uid,'pal_uid_mismatch'end}
local binding={pal_uid=player_uid};local registry=P.registry(c)
local mapping=assert(registry:acquire('world','minecraft:the_nether',{0,64,0},'one'))
local target=P.to_ue(mapping,{0,64,0});target.Z=target.Z+80
check('server_authority_pal_utility_fquat_bool_bool_and_measured_location',function()
 assert(api.safety(pc,mapping,target,binding));local ok,at=api.teleport(pc,target,P.mc_rotation(30,10))
 assert(ok and P.distance(at,target)==0 and native_calls==1)
 assert(pawn.health==91 and pawn.inventory.Wood==13 and movement.MaxWalkSpeed==430 and movement.JumpZVelocity==420)
end)
check('native_false_return_is_not_success',function()
 library.reject=true;local ok,why=api.teleport(pc,target,{Yaw=0,Pitch=0,Roll=0})
 assert(not ok and why=='pal_utility_teleport_rejected');library.reject=nil
end)
check('exact_owned_input_lock_balancing_and_movement_restore',function()
 local lock=api.hold(pc,true);assert(pc.move==3 and pc.look==4 and movement.MovementMode==0)
 api.release(lock);api.release(lock);assert(pc.move==2 and pc.look==3 and movement.MovementMode==1 and movement.CustomMovementMode==2)
end)
check('client_holds_input_but_never_disables_or_teleports_its_pawn',function()
 local before=native_calls;local lock=api.hold(pc,false);assert(movement.MovementMode==1)
 api.release(lock);assert(native_calls==before and pc.move==2 and pc.look==3)
end)
check('replacement_pawn_movement_not_changed_by_old_lock_release',function()
 local lock=api.hold(pc,true);local replacement=object('Replacement',{CharacterMovement=object('NewMove',{MovementMode=2})})
 pc.Pawn=replacement;api.release(lock);assert(replacement.CharacterMovement.MovementMode==2 and pc.move==2 and pc.look==3)
 pc.Pawn=pawn;movement.MovementMode=1
end)
check('kill_z_bounds_and_saved_pal_objects_block_unsafe_region',function()
 settings.KillZ=target.Z;local ok,why=api.safety(pc,mapping,target,binding);assert(not ok and why=='pal_kill_z');settings.KillZ=-10000
 ok,why=api.safety(pc,mapping,{X=99999999,Y=0,Z=0},binding);assert(not ok and why=='pal_world_or_region_bounds')
 local object_in_region=object('SavedPalMapObject')
 function object_in_region:GetWorld()return world end
 function object_in_region:K2_GetActorLocation()return P.copy(target)end
 saved_objects={object_in_region};ok,why=api.safety(pc,mapping,target,binding);assert(not ok and why=='saved_pal_map_object_in_region');saved_objects={}
end)
check('wrong_identity_and_non_authority_cannot_move',function()
 assert(api.valid(pc,{pal_uid='other'},true)==false);authority=false
 assert(api.valid(pc,binding,true)==false and not pcall(api.teleport,pc,target,{Yaw=0,Pitch=0,Roll=0}));authority=true
end)
check('asynchronous_unreal_calls_rejected',function()
 game_thread=false;assert(not pcall(api.snapshot,pc)and not pcall(api.teleport,pc,target,{Yaw=0,Pitch=0,Roll=0}));game_thread=true
end)
check('streaming_pending_is_real_error_not_noop_success',function()
 local guarded=A.new{protocol=P,config=c,game_thread=function()return true end,
  verify_identity=function()return true end,streaming_ready=function()return false,'pal_streaming_cells_pending'end}
 local ok,why=guarded.safety(pc,mapping,target,binding);assert(not ok and why=='pal_streaming_cells_pending')
end)
check('persistent_world_settings_selected_among_actual_streamed_tile_settings',function()
 decoy_settings=object('TileWorldSettings',{KillZ=1000000,bEnableWorldBoundsChecks=true})
 function decoy_settings:GetWorld()return world end
 local tile_level=object('StreamedTileLevel');function decoy_settings:GetOuter()return tile_level end
 local exact=A.new{protocol=P,config=c,game_thread=function()return true end,verify_identity=function()return true end}
 local ok,detail=exact.safety(pc,mapping,target,binding);assert(ok and detail.kill_z==-10000)
 decoy_settings=nil
end)
io.write('{"test":"dimension_travel_actor","passed":'..count..',"live_unreal_verified":false}\n')
