-- One narrow authenticated-cache/texture/reader fixture; no MC or render startup.
local dir='work/minecraft-fusion/entity-visuals/lua/'
local Blob=dofile(dir..'capture_blob.lua');local Factory=dofile(dir..'entity_capture_cache.lua')
local Json=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
assert(Blob.sha256('')=='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
assert(Blob.sha256('abc')=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
local png64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jV2kAAAAASUVORK5CYII='
local png=Blob.base64(png64);local sha=Blob.sha256(png)
local fence={mc_uuid='player',world_session='world',dim='minecraft:overworld',view=1,mapping='origin'}
local count=0
local cache=Factory.new({root='work/minecraft-fusion/entity-visuals/cache-fixture',json=Json,current_view=function()return{fence=fence,bounds={0,0,0,10,10,10}}end,
 verify_host_session=function(h)return h=='existing-connection'end,verify_actor=function(row,actor)return actor=='actual-exact-actor'end,
 now_ms=function()return 1000 end,send_binding=function(request)assert(request.t=='entity_visual_view');count=count+1 end})
assert(cache.tick_binding());assert(count==1)
local function event(t)local p={};for k,v in pairs(fence)do p[k]=v end;p.t=t;p.schema=1;p.source='minecraft:entity_renderer_capture_v1';p.read_only=true;p.host_session='existing-connection';p.producer='mc-process';p.epoch=1;p.seq=1;p.created_ms=1000;return p end
local asset=event('entity_visual_asset');asset.resource='minecraft:textures/entity/creeper/creeper.png';asset.sha256=sha;asset.bytes=#png;asset.index=0;asset.chunks=1;asset.base64=png64
assert(cache.accept(asset))
local frame={id='mc:creature',dimension=fence.dim,source='actual_entity_renderer_submit',space='minecraft_entity_origin_world_orientation'}
local message=event('entity_visual_cache');message.seq=2;message.complete=true;message.rows={{id=frame.id,dimension=fence.dim,available=true,frame=frame,captured_ms=1000,textures={[asset.resource]={sha256=sha,bytes=#png}}}}
assert(cache.accept(message))
local row={id=frame.id,dimension=fence.dim};local returned,scope=cache.read_visual(row)
assert(returned==frame and cache.verify_visual(returned,scope,row,'actual-exact-actor'))
assert(cache.resolve_texture(asset.resource):find(sha,1,true))
message.host_session='other';local ok,why=cache.accept(message);assert(not ok and why=='capture_host_session_mismatch')
-- Actual chunk envelope authenticates outside the serialized manifest.
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(s)
 local out={}
 for i=1,#s,3 do
  local a,b,c=s:byte(i,i+2);local n=(a<<16)|((b or 0)<<8)|(c or 0)
  out[#out+1]=alphabet:sub((n>>18&63)+1,(n>>18&63)+1)..alphabet:sub((n>>12&63)+1,(n>>12&63)+1)
   ..(b and alphabet:sub((n>>6&63)+1,(n>>6&63)+1)or'=')..(c and alphabet:sub((n&63)+1,(n&63)+1)or'=')
 end
 return table.concat(out)
end
message.host_session=nil;message.seq=3
local raw=Json.encode(message);local split=math.floor(#raw/2);local hash=Blob.sha256(raw)
for i=0,1 do
 local part=event('entity_visual_cache_chunk');part.seq=4+i;part.sha256=hash;part.bytes=#raw;part.chunks=2;part.index=i
 part.base64=base64(i==0 and raw:sub(1,split)or raw:sub(split+1))
 assert(cache.accept(part))
end
returned,scope=cache.read_visual(row)
assert(scope.host_session=='existing-connection'and cache.verify_visual(returned,scope,row,'actual-exact-actor'))
assert(cache.seq==3)
print('{"status":"passed","fixture":"authenticated host/view -> PNG hash cache -> direct/chunked exact entity reader","runtime_graphics_verified":false}')
