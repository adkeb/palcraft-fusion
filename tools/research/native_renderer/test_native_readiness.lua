local Readiness=dofile(arg[1]..'/native_readiness.lua')
local address=10
local context={IsValid=function()return true end,GetAddress=function()return address end,IsA=function()return true end,HasAuthority=function()return true end}
local texture={IsValid=function()return true end}
local material={IsValid=function()return true end,GetBlendMode=function()return 0 end,K2_GetTextureParameterValue=function()return texture end}
local cube={IsValid=function()return true end,GetFullName=function()return'StaticMesh /Engine/BasicShapes/Cube.Cube'end}
local solid={StaticMesh=cube,K2_GetComponentRotation=function()return{Pitch=0,Yaw=0,Roll=0}end,IsValid=function()return true end,IsA=function()return true end,K2_GetComponentScale=function()return{X=1,Y=1,Z=1}end,GetCollisionEnabled=function()return 3 end,
 GetGenerateOverlapEvents=function()return false end,GetCollisionResponseToChannel=function(_,c)return(c==14 or c==19 or c==25)and 0 or 2 end,
 K2_LineTraceComponent=function()return true end}
local visual={K2_GetComponentRotation=function()return{Pitch=0,Yaw=0,Roll=0}end,K2_GetComponentScale=function()return{X=1,Y=1,Z=1}end,IsVisible=function()return true end,IsValid=function()return true end,IsA=function()return true end,GetAddress=function()return 31 end,GetCollisionEnabled=function()return 0 end,
 GetCollisionResponseToChannel=function()return 0 end,GetNumSections=function()return 1 end,GetMaterial=function()return material end}
local actor={IsValid=function()return true end,GetAddress=function()return 20 end,GetOwner=function()return context end,RootComponent=solid,
 K2_GetActorLocation=function()return{X=150,Y=-50,Z=250}end}
local model={IsValid=function()return true end,GetAddress=function()return 30 end,GetOwner=function()return context end,RootComponent=visual,bHidden=false,
 K2_GetActorLocation=function()return{X=100,Y=0,Z=200}end}
local g={id='minecraft:oak_planks',state='',at={0,64,0},boxes={{0,0,0,1,1,1}},visible=true,render_kind='block'}
local entry={handles={20},model=30,model_component=31}
local companion={origin={X=100,Y=0,Z=200},actors={['0:64:0']=entry},context=function()return context end,
 status=function()return{side='client'}end,models={version=3,geometry=function()return{{alpha_mode='opaque',tint=-1}}end}}
local objects={actor,model};local thread=true
local verify=Readiness.new({companion=companion,find_all=function()return objects end,in_game_thread=function()return thread end,fname=function(x)return x end,now=function()return 1 end})
local expected={{key='0:64:0',geometry=g,entry=entry}}
local tests=0
local function pass()local r=verify({},expected,'client');assert(r.collision_verified and r.visual_verified and r.evidence.body_queries==1);tests=tests+1 end
local function fail()local r=verify({},expected,'client');assert(not r.collision_verified and not r.visual_verified and r.error);tests=tests+1 end
pass()
thread=false;fail();thread=true
objects={actor};fail();objects={actor,model}
address=12;local original=actor.GetOwner;actor.GetOwner=function()return{IsValid=function()return true end,GetAddress=function()return 10 end}end;fail();address=10;actor.GetOwner=original
original=solid.GetCollisionResponseToChannel;solid.GetCollisionResponseToChannel=function()return 2 end;fail();solid.GetCollisionResponseToChannel=original
original=solid.K2_LineTraceComponent;solid.K2_LineTraceComponent=function()return false end;fail();solid.K2_LineTraceComponent=original
original=solid.K2_GetComponentScale;solid.K2_GetComponentScale=function()return{X=1,Y=1,Z=.5}end;fail();solid.K2_GetComponentScale=original
original=solid.K2_GetComponentRotation;solid.K2_GetComponentRotation=function()return{Pitch=0,Yaw=90,Roll=0}end;fail();solid.K2_GetComponentRotation=original
model.bHidden=true;fail();model.bHidden=false
original=material.K2_GetTextureParameterValue;material.K2_GetTextureParameterValue=function()return nil end;fail();material.K2_GetTextureParameterValue=original
original=material.GetBlendMode;material.GetBlendMode=function()return 1 end;fail();material.GetBlendMode=original
companion.models.version=4;fail();companion.models.version=3
original=companion.models.geometry;companion.models.geometry=function()return{{alpha_mode='cutout'}}end;fail();companion.models.geometry=original
pass()
print('{"ok":true,"tests":'..tests..',"actual_engine_invoked":false,"native_readiness_not_live_verified":true,"missing_actor_texture_body_and_caps_rejected":true}')
