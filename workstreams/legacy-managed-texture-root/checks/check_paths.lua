-- Two bounded path fixtures, actual producer helper. No ImportFile/Game calls.
local root=assert(arg[1]);local f=assert(io.open(root..'/source/client/palcraft-collisions.lua','rb'));local s=f:read('*a');f:close()
local helper=assert(s:match('(local texture_provider,texture_provider_root.-)\nlocal function material_for'))
local BRIDGE='Z:/synthetic-owned/bridge/';local ASSET=BRIDGE..'models-v4-f00/'
local function fixture(files,status)
 local env={SHARED=BRIDGE,dir='synthetic-scripts/',J={},models={status=function()return status or{asset_root=ASSET,geometry_version=3}end},provider_calls=0}
 setmetatable(env,{__index=_G})
 env.io={open=function(path)if files[path]then return{close=function()end}end end}
 env.dofile=function(path)
  assert(path=='synthetic-scripts/model_geometry_v3.lua')
  return{configure=function(v)assert(v.root==ASSET)end,geometry=function(id,state,x,y,z)
   env.provider_calls=env.provider_calls+1;assert(id=='minecraft:oak_stairs');return{{texture='minecraft:block/oak_planks'}}
  end}
 end
 return assert(load(helper..'\nreturn legacy_texture_path','actual-source-path-helper','t',env))(),env
end
local paths={
 [ASSET..'textures/minecraft/item/stick.png']=true,[ASSET..'textures/minecraft/block/stick.png']=true,
 [ASSET..'textures/minecraft/block/torch.png']=true,[ASSET..'textures/minecraft/block/stone.png']=true,
 [ASSET..'textures/minecraft/block/oak_planks.png']=true}
local get,env=fixture(paths)
assert(get('minecraft:stick','stick')==ASSET..'textures/minecraft/item/stick.png')
assert(get('minecraft:torch','torch')==ASSET..'textures/minecraft/block/torch.png')
assert(get('minecraft:coal','coal')==ASSET..'textures/minecraft/block/stone.png')
assert(get('minecraft:oak_stairs','oak')==ASSET..'textures/minecraft/block/oak_planks.png'and env.provider_calls==1)
paths[BRIDGE..'textures/torch.png']=true;assert(get('minecraft:torch','torch')==BRIDGE..'textures/torch.png')
print('PASS existing_legacy_then_original_item_block_provider_alias_and_managed_stone_paths_selected')
local invalid=fixture({}, {})
assert(not pcall(invalid,'minecraft:torch','torch'))
assert(not pcall(get,'minecraft:../Saved','../Saved'))
local missing=fixture({})
assert(not pcall(missing,'minecraft:coal','coal'))
print('PASS missing_declared_root_missing_managed_fallback_and_invalid_resource_path_reject_without_import')
print('RESULT 2 PASS; source path fixtures only; no Game/ImportFile/asset mutation')
