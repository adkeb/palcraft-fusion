-- Only SP owner selection. No native DLL, process, old suite or full body matrix.
local base=assert(arg[1]);local Core=dofile(base..'native/fluid_physics_core.lua')
local checks=0;local function check(v,name)checks=checks+1;assert(v,name)end
local m={MovementMode=1,CustomMovementMode=0,GravityScale=1,WaterPlaneZ=-1,WaterPlaneZPrev=-1,InWaterRate=0,
 enters=0,exits=0,modes=0,impulses=0}
function m:IsValid()return true end;function m:IsA()return true end;function m:IsSwimming()return self.MovementMode==4 end
function m:GetGravityZ()return-980*self.GravityScale end;function m:GetVelocity()return{X=0,Y=0,Z=0}end
function m:GetInWaterRate()return self.InWaterRate end;function m:IsEnteredWater()return self.enters>self.exits end
function m:OnEnterWater()self.enters=self.enters+1 end;function m:OnExitWater()self.exits=self.exits+1 end
function m:SetMovementMode(mode,custom)self.MovementMode=mode;self.CustomMovementMode=custom;self.modes=self.modes+1 end
function m:AddImpulse(v)self.impulses=self.impulses+1;self.impulse=v end
local actor={authority=true,CharacterMovement=m};function actor:IsValid()return true end
function actor:HasAuthority()return self.authority end;function actor:GetAddress()return 0x50100 end
actor.CapsuleComponent={IsValid=function()return true end,GetScaledCapsuleRadius=function()return 30 end,
 GetScaledCapsuleHalfHeight=function()return 90 end,K2_GetComponentLocation=function()return{X=50,Y=-50,Z=90}end}
local context={IsValid=function()return true end,GetAddress=function()return 0x50200 end}
local pc={Pawn=actor};-- No NetConnection or socket proof: native authority is real in SP.
local world={dimension='minecraft:overworld',session='sp',seq=1,
 fluid_at=function()end,fluid_volumes=function()return{}end,region_status=function()return{ready=true}end}
local shape={new=function(o)return{sample=function(self,id,pose)
 local c={id=id,dim=pose.dim,known=true,kind='water',wet=true,swimming=true,body=true,surface=.9,surface_known=true,
  immersion=.5,flow={1,0,0},flow_weight=1,query_surface_known=true,query_max_surface=.9,shape='capsule',bounds={.2,0,.2,.8,1.8,.8},radius=.3}
 o.on_update(c);return c end,remove=function()end}end}
local column={new=function()end}
local native_calls={new=0,replace=0,reset=0}
local function fake_native()
 native_calls.new=native_calls.new+1
 return{replace=function()native_calls.replace=native_calls.replace+1 end,
 reset=function()native_calls.reset=native_calls.reset+1 end,status=function()return{actors=0}end}
end
Core.Native.new=fake_native
local function options(side)
 return{side=side,origin={X=0,Y=0,Z=0,y_origin=0},world=world,contact_driver=column,shape_contact_driver=shape,
  game_thread=function()return true end,resolve_context=function()return context end,
  resolve_participants=function()return{{id=side..':same_pawn',actor=actor,dim=world.dimension}}end}
end
local client=Core.new(options('client'));local server=Core.new(options('server'))
check(native_calls.new==0,'Neither construction initializes process-wide native state before owner selection')
client:tick(1000,{pc=pc});server:tick(1000,{pc=pc})
check(native_calls.new==1 and native_calls.replace==1,'Only the authoritative server worker constructs and commits a physical batch')
check(m.enters==1 and m.modes==1 and m.GravityScale==0,'Same SP Pawn enters water through exactly one physical worker')
client:tick(1050,{pc=pc});server:tick(1050,{pc=pc})
check(m.impulses==1 and m.modes==2,'Client observation creates no second flow or swimming update')
local status=client:status()
check(status.observer_only and status.ownership=='authority_observer'and not status.native.initialized,'Client status truthfully reports authority-owner observation without native initialization')
client:stop('client_stopped',{context_alive=true})
check(m.exits==0 and m.GravityScale==0 and native_calls.reset==0,'Stopping the observer does not restore gravity or reset the authority native batch')
server:stop('server_stopped',{context_alive=true})
check(m.exits==1 and m.GravityScale==1 and native_calls.reset==1,'Stopping the sole owner restores water fields and native resources once')
-- An empty client resolver in SP must not silently replace/abandon shared native state.
local empty_options=options('client');empty_options.resolve_participants=function()return{}end
local empty=Core.new(empty_options);local before=native_calls.new
empty:tick(1100,{pc=pc});empty:stop('empty_observer',{context_alive=true})
check(native_calls.new==before and native_calls.reset==1,'Authoritative local Pawn with zero participants remains a zero-native-call observer')
-- A separate multiplayer client replica still owns normal local prediction.
actor.authority=false;local remote=Core.new(options('client'))
remote:tick(1200,{pc=pc});remote:tick(1250,{pc=pc})
check(remote:status().ownership=='client_prediction'and not remote:status().observer_only and native_calls.new==before+1,'Non-authoritative multiplayer replica retains native client prediction')
remote:stop('remote_stopped',{context_alive=true})
actor.authority=true;local Server=dofile(base..'server/fluid_physics.lua');local selected=options('server')
selected.core=Core;selected.resolve_participants=nil
selected.entity_authority={running=true,session='sp',native={['pal:offline_real']={actor=actor,player=true}}}
local normal=Server.new(selected);normal:tick(1300,{presence={server_session_id='sp'},pc=pc})
check(normal.participants['pal:offline_real']~=nil and normal:status().ownership=='pal_authority_worker','Default server resolver accepts real standalone authority without a NetConnection')
normal:stop('default_resolver_stopped',{context_alive=true})
print('{"ok":true,"suite":"standalone_fluid_single_owner","checks":'..checks..',"native_live_calls":0,"live_sp_verified":false,"no_netconnection_required":true,"old_matrix_rerun":false}')
