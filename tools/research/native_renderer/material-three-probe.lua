local companion=assert(_G.PalCraftCollisionCompanion);local Models=assert(companion.models)
local pc;for _,p in ipairs(FindAllOf('PalPlayerController')or{})do if p:IsValid()and p.Pawn:IsValid()then pc=p;break end end
assert(pc,'No player');local ctx=companion.context();local O=companion.origin
local view=pc.PlayerCameraManager;local camera=view:GetCameraLocation();local rot=view:GetCameraRotation();local yaw=math.rad(rot.Yaw)
local forward={X=math.cos(yaw),Y=math.sin(yaw)};local right={X=-forward.Y,Y=forward.X}
local root='D:/PalworldServer-LAN/PalCraft-Dev/bridge/models-v2-7342e9820b46/textures/minecraft/block/'
local samples={
 {id='opaque',parent='/Game/Pal/Material/Prop/MI_PalPropBase.MI_PalPropBase',parameter='Base Texture',texture='oak_planks.png',blend=0},
 {id='cutout',parent='/Paper2D/MaskedUnlitSpriteMaterial.MaskedUnlitSpriteMaterial',parameter='SpriteTexture',texture='oak_leaves.png',blend=1},
 {id='translucent',parent='/Engine/EngineMaterials/Widget3DPassThrough_Translucent.Widget3DPassThrough_Translucent',parameter='SlateUI',texture='glass.png',blend=2}
}
local report={read_only_gameplay=true,no_collision=true,temporary_render_only=true,shader_visible=false,camera=camera,rotation=rot,samples={}}
local keep={actors={},materials={},textures={}};_G.PalCraftMaterialThreeProbe=keep
for i,s in ipairs(samples)do
 local row={id=s.id,parent=s.parent,parameter=s.parameter,shader_verified=false};report.samples[#report.samples+1]=row
 local parent=LoadAsset(s.parent)
 if parent and parent:IsValid()then
  row.blend=parent:GetBlendMode();local base=parent:GetBaseMaterial();row.domain=base:IsValid()and base.MaterialDomain
  if row.blend==s.blend and row.domain==0 then
   local m=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,parent,FName('MC_ShortShader_'..s.id..'_'..os.time()),0)
   local inherited=m:K2_GetTextureParameterValue(FName(s.parameter));row.inherited_texture=inherited and inherited:IsValid()or false
   local tex=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,root..s.texture)
   assert(tex:IsValid(),'Probe source texture missing');tex.Filter=0;m:SetTextureParameterValue(FName(s.parameter),tex)
   local actor,component=Models.spawn(ctx,O,{id='minecraft:oak_planks',state='Block{minecraft:oak_planks}'},0,64,0)
   local object,mesh;for _,a in ipairs(FindAllOf('Actor')or{})do if a:IsValid()and a:GetAddress()==actor then object=a;mesh=a.RootComponent;break end end
   assert(object and mesh:IsValid(),'Probe actor unavailable');assert(mesh:GetCollisionEnabled()==0,'Probe must have no collision')
   for section=0,mesh:GetNumSections()-1 do mesh:SetMaterial(section,m)end
   local offset=(i-2)*130
   local location={X=camera.X+forward.X*330+right.X*offset,Y=camera.Y+forward.Y*330+right.Y*offset,Z=camera.Z-85}
   object:K2_SetActorLocation(location,false,{},true)
   row.actor=actor;row.component=component;row.location=location;row.material=m:GetAddress();row.texture=tex:GetAddress();row.parameter_roundtrip=m:K2_GetTextureParameterValue(FName(s.parameter)):GetAddress()==tex:GetAddress()
   row.result='await_actual_game_window_capture';keep.actors[#keep.actors+1]=object;keep.materials[#keep.materials+1]=m;keep.textures[#keep.textures+1]=tex
  else row.result='wrong_blend_or_domain' end
 else row.result='parent_unavailable' end
end
return report
