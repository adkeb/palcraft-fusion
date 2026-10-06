local client=assert(arg[1]);local J=dofile(arg[2])
local function object(fields)
 fields=fields or{};function fields:IsValid()return true end;function fields:GetAddress()return 1 end;return fields
end
local texture=object();local parent=object({MaterialDomain=0})
function parent:GetBlendMode()return 0 end
function parent:GetBaseMaterial()return self end
local imports={};local function mid()
 local m=object({textures={}})
 function m:K2_GetTextureParameterValue()return texture end
 function m:SetTextureParameterValue(key,value)self.textures[key]=value end
 function m:SetScalarParameterValue()end
 return m
end
function LoadAsset()return parent end
function FName(value)return value end
function IsInGameThread()return true end
function StaticFindObject()
 return{CreateDynamicMaterialInstance=function()return mid()end,
 ImportFileAsTexture2D=function(_,ctx,path)imports[#imports+1]=path;return object({path=path})end,
 GetTimeSeconds=function()return 0 end}
end
local resolver
local Models={version=5,set_material_provider=function(fn,caps)resolver=fn;assert(caps.opaque and caps.cutout and caps.tint)end}
local Pipeline=dofile(client..'/native_visual_pipeline.lua')
local worker=Pipeline.new({models=Models,json=J,bridge_root='D:/PalworldServer-LAN/PalCraft-Dev/bridge/',origin={X=0,Y=0,Z=0},context=function()return object()end})
local root='D:/PalworldServer-LAN/PalCraft-Dev/bridge/models-v4-761ddea057ce/'
local group={texture='minecraft:block/oak_planks',alpha_mode='opaque',tint=-1,shade=true,light_emission=0}
local value=resolver(object(),group,root)
assert(value and value.material:IsValid()and value.texture:IsValid())
assert(imports[1]==root..'textures/minecraft/block/oak_planks.png','Actual dispatcher root forwarding lost')
assert(value.material.textures['Base Texture']==value.texture)
assert(worker.status().actual_shader_verified==false)
print('{"ok":true,"checks":4,"actual_pipeline_and_material_modules":true,"opaque_no_tint_no_scope_runnable":true,"asset_root_forwarded":true,"engine_calls":false}')
